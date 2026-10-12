import CoreLocation
import Foundation
import Observation

struct NearbyStop: Identifiable, Sendable {
    var id: String { item.id }
    let item: StopSearchItem
    let distance: CLLocationDistance
}

struct RouteSearchItem: Sendable {
    let key: String
    let routeUpper: String
    let terminalLower: String
    let co: [String]
}

struct StopSearchItem: Sendable {
    let id: String
    let haystack: String
    let nameZh: String
    let nameEn: String
    let location: StopLocation
}

struct StopRouteRef: Sendable, Hashable {
    let routeKey: String
    let seq: Int
}

struct StopAlias: Sendable, Hashable {
    let co: String
    let stopId: String
}

@MainActor
@Observable
final class DataStore {
    private(set) var db: EtaDB?
    private(set) var isLoading = false
    private(set) var isDownloading = false
    private(set) var statusText = ""
    private(set) var lastLoaded: Date?
    var errorMessage: String?

    /// Download progress in 0...1 (0 when unknown).
    private(set) var downloadProgress: Double = 0
    private(set) var downloadedBytes: Int64 = 0
    private(set) var totalBytes: Int64 = 0

    private(set) var routeSearchItems: [RouteSearchItem] = []
    private(set) var stopSearchItems: [StopSearchItem] = []
    private(set) var stopRouteIndex: [String: [StopRouteRef]] = [:]
    private(set) var directStopCompanies: [String: Set<String>] = [:]

    /// Entries synthesized at runtime by query-mode providers (for example
    /// Hosted CheLaile API data, optional AMap base data, or the legacy
    /// mainland fallback.
    private var syntheticEntries: [String: RouteEntry] = [:]
    private var syntheticStops: [String: StopEntry] = [:]
    private var syntheticMainlandMetadata: [String: MainlandRouteMetadata] = [:]

    let provider: any TransitProvider
    #if DEBUG
    private(set) var isPreview = false
    func installPreviewDatabase(_ db: EtaDB) {
        isPreview = true
        apply(Self.buildLoadedData(db))
    }
    #endif

    private let session: URLSession

    init(provider: any TransitProvider) {
        self.provider = provider
        let configuration = URLSessionConfiguration.default
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 60
        session = URLSession(configuration: configuration)
    }

    // MARK: - Cache locations

    private var cacheDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("HKBusETA", isDirectory: true).appendingPathComponent(provider.id, isDirectory: true)
    }

    private var cacheFileURL: URL { cacheDirectory.appendingPathComponent("routeFareList.min.json") }
    private var cacheMd5URL: URL { cacheDirectory.appendingPathComponent("routeFareList.md5") }

    /// Pre-1.6 cache location (before caches were namespaced by region).
    private var legacyCacheFileURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("HKBusETA", isDirectory: true).appendingPathComponent("routeFareList.min.json")
    }

    private var legacyCacheMd5URL: URL {
        legacyCacheFileURL.deletingLastPathComponent().appendingPathComponent("routeFareList.md5")
    }

    private func ensureCacheDirectory() {
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }

    /// Moves a pre-1.6 cache into the per-region directory so existing users
    /// don't re-download the full database after upgrading.
    private func migrateLegacyCacheIfNeeded() {
        guard provider.id == "hk" else { return }
        let fileManager = FileManager.default
        guard !fileManager.fileExists(atPath: cacheFileURL.path),
              fileManager.fileExists(atPath: legacyCacheFileURL.path) else { return }
        ensureCacheDirectory()
        try? fileManager.copyItem(at: legacyCacheFileURL, to: cacheFileURL)
        if fileManager.fileExists(atPath: legacyCacheMd5URL.path),
           !fileManager.fileExists(atPath: cacheMd5URL.path) {
            try? fileManager.copyItem(at: legacyCacheMd5URL, to: cacheMd5URL)
        }
    }

    // MARK: - Loading

    func load() async {
        guard db == nil, !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        // Query-mode regions have no static database to download.
        if provider.databaseURLs.isEmpty {
            db = .empty
            lastLoaded = Date()
            return
        }

        migrateLegacyCacheIfNeeded()

        if let data = try? Data(contentsOf: cacheFileURL),
           let loaded = await Self.parse(data: data) {
            apply(loaded)
        }

        await refreshIfNeeded()
    }

    func refreshIfNeeded() async {
        #if DEBUG
        if isPreview { return }
        #endif
        guard !provider.databaseURLs.isEmpty else { return }
        ensureCacheDirectory()
        migrateLegacyCacheIfNeeded()
        isDownloading = true
        statusText = L10n.t("status.checkingUpdate")
        defer {
            isDownloading = false
            statusText = ""
            downloadProgress = 0
            downloadedBytes = 0
            totalBytes = 0
        }

        let remoteMd5 = await fetchText(md5: true)
        let localMd5 = (try? String(contentsOf: cacheMd5URL, encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines)

        let needsDownload = db == nil
            || remoteMd5 == nil
            || localMd5 == nil
            || remoteMd5 != localMd5
            || !FileManager.default.fileExists(atPath: cacheFileURL.path)

        guard needsDownload else { return }

        statusText = L10n.t("status.downloading")
        guard let data = await fetchData() else {
            if db == nil {
                errorMessage = L10n.t("error.dataDownloadFailed")
            }
            return
        }

        statusText = L10n.t("status.processing")
        guard let loaded = await Self.parse(data: data) else {
            errorMessage = L10n.t("error.dataParseFailed")
            return
        }

        try? data.write(to: cacheFileURL, options: .atomic)
        if let remoteMd5 {
            try? remoteMd5.write(to: cacheMd5URL, atomically: true, encoding: .utf8)
        }
        apply(loaded)
        errorMessage = nil
    }

    private func fetchData() async -> Data? {
        for url in provider.databaseURLs {
            if let data = try? await downloadWithProgress(from: url), !data.isEmpty {
                return data
            }
        }
        return nil
    }

    /// Downloads with byte-level progress so the UI can show a percentage.
    private func downloadWithProgress(from url: URL) async throws -> Data {
        let delegate = DownloadProgressDelegate { [weak self] written, total in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.downloadedBytes = written
                self.totalBytes = total
                if total > 0 {
                    self.downloadProgress = min(Double(written) / Double(total), 1)
                }
            }
        }
        let configuration = URLSessionConfiguration.default
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 60
        let downloadSession = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
        defer { downloadSession.finishTasksAndInvalidate() }

        let (fileURL, response) = try await downloadSession.download(from: url)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw URLError(.badServerResponse)
        }
        return try Data(contentsOf: fileURL)
    }

    private func fetchText(md5: Bool) async -> String? {
        let urls = md5 ? provider.databaseMd5URLs : provider.databaseURLs
        for url in urls {
            if let (data, _) = try? await session.data(from: url),
               let text = String(data: data, encoding: .utf8) {
                let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !value.isEmpty {
                    return value
                }
            }
        }
        return nil
    }

    nonisolated private static func parse(data: Data) async -> LoadedData? {
        await Task.detached(priority: .userInitiated) {
            guard let db = try? JSONDecoder().decode(EtaDB.self, from: data) else { return nil }
            return buildLoadedData(db)
        }.value
    }

    nonisolated private static func buildLoadedData(_ db: EtaDB) -> LoadedData {
        var routeItems: [RouteSearchItem] = []
        routeItems.reserveCapacity(db.routeList.count)
        var stopRouteIndex: [String: [StopRouteRef]] = [:]
        var directStopCompanies: [String: Set<String>] = [:]

        for (key, entry) in db.routeList {
            let terminal = "\(entry.orig.en) \(entry.orig.zh) \(entry.dest.en) \(entry.dest.zh)"
            routeItems.append(
                RouteSearchItem(
                    key: key,
                    routeUpper: entry.route.uppercased(),
                    terminalLower: terminal.lowercased(),
                    co: entry.co
                )
            )
            for (co, ids) in entry.stops {
                for (seq, stopId) in ids.enumerated() {
                    stopRouteIndex[stopId, default: []].append(StopRouteRef(routeKey: key, seq: seq))
                    directStopCompanies[stopId, default: []].insert(co)
                }
            }
        }

        var stopItems: [StopSearchItem] = []
        stopItems.reserveCapacity(db.stopList.count)
        for (id, stop) in db.stopList {
            stopItems.append(
                StopSearchItem(
                    id: id,
                    haystack: "\(stop.name.zh) \(stop.name.en)".lowercased(),
                    nameZh: stop.name.zh,
                    nameEn: stop.name.en,
                    location: stop.location
                )
            )
        }

        return LoadedData(
            db: db,
            routeItems: routeItems,
            stopItems: stopItems,
            stopRouteIndex: stopRouteIndex,
            directStopCompanies: directStopCompanies
        )
    }

    private func apply(_ loaded: LoadedData) {
        db = loaded.db
        routeSearchItems = loaded.routeItems
        stopSearchItems = loaded.stopItems
        stopRouteIndex = loaded.stopRouteIndex
        directStopCompanies = loaded.directStopCompanies
        lastLoaded = Date()
    }

    // MARK: - Queries

    /// Registers a runtime-synthesized entry (query-mode providers) so the
    /// shared route / ETA screens can resolve it like a database entry.
    func registerSynthetic(
        entry: RouteEntry,
        stops: [String: StopEntry],
        mainlandMetadata: MainlandRouteMetadata? = nil
    ) {
        syntheticEntries[entry.routeKey] = entry
        for (key, value) in stops {
            syntheticStops[key] = value
        }
        if let mainlandMetadata {
            syntheticMainlandMetadata[entry.routeKey] = mainlandMetadata
        } else {
            syntheticMainlandMetadata.removeValue(forKey: entry.routeKey)
        }
    }

    func entry(_ key: String) -> RouteEntry? {
        syntheticEntries[key] ?? db?.routeList[key]
    }

    func stop(_ id: String) -> StopEntry? {
        syntheticStops[id] ?? db?.stopList[id]
    }

    func mainlandMetadata(for routeKey: String) -> MainlandRouteMetadata? {
        syntheticMainlandMetadata[routeKey]
    }

    func stopName(_ id: String, _ language: AppLanguage) -> String {
        stop(id)?.name.name(language) ?? id
    }

    /// Cross-company aliases of the same physical stop, including itself.
    func aliases(for stopId: String) -> [StopAlias] {
        guard let db else { return [] }
        var result: [StopAlias] = []
        var seen = Set<String>()
        for co in directStopCompanies[stopId] ?? [] {
            let alias = StopAlias(co: co, stopId: stopId)
            if seen.insert("\(co)|\(stopId)").inserted {
                result.append(alias)
            }
        }
        for tuple in db.stopMap[stopId] ?? [] where tuple.count >= 2 {
            let alias = StopAlias(co: tuple[0], stopId: tuple[1])
            if seen.insert("\(alias.co)|\(alias.stopId)").inserted {
                result.append(alias)
            }
        }
        if result.isEmpty {
            result.append(StopAlias(co: "", stopId: stopId))
        }
        return result
    }

    /// Route references (key + stop sequence) serving a physical stop.
    func routesAtStop(_ stopId: String) -> [StopRouteRef] {
        var refs: [StopRouteRef] = []
        var seen = Set<String>()
        for alias in aliases(for: stopId) {
            for ref in stopRouteIndex[alias.stopId] ?? [] {
                let signature = "\(ref.routeKey)|\(ref.seq)"
                if seen.insert(signature).inserted {
                    refs.append(ref)
                }
            }
        }
        return refs
    }

    func searchRoutes(query: String, filter: TransportFilter) -> [RouteSearchItem] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        // The database uses Traditional Chinese only; normalize the input so
        // Simplified Chinese queries still match.
        let normalized = ChineseConverter.traditional(trimmed)
        let upper = normalized.uppercased()
        let lower = normalized.lowercased()
        let allowed = provider.operatorIDs(for: filter)

        var scored: [(item: RouteSearchItem, score: Int)] = []
        for item in routeSearchItems {
            guard item.co.contains(where: { allowed.contains($0) }) else { continue }
            let score: Int
            if item.routeUpper == upper {
                score = 0
            } else if item.routeUpper.hasPrefix(upper) {
                score = 1
            } else if item.routeUpper.contains(upper) {
                score = 2
            } else if item.terminalLower.contains(lower) {
                score = 3
            } else {
                continue
            }
            scored.append((item, score))
        }
        scored.sort {
            if $0.score != $1.score { return $0.score < $1.score }
            return $0.item.routeUpper < $1.item.routeUpper
        }
        return scored.prefix(80).map(\.item)
    }

    func searchStops(query: String) -> [StopSearchItem] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let lower = ChineseConverter.traditional(trimmed).lowercased()
        var matches = stopSearchItems.filter { $0.haystack.contains(lower) }
        matches.sort {
            let lhs = $0.nameZh.count + $0.nameEn.count
            let rhs = $1.nameZh.count + $1.nameEn.count
            if lhs != rhs { return lhs < rhs }
            return $0.id < $1.id
        }
        return Array(matches.prefix(40))
    }

    func nearestStops(to location: CLLocation, limit: Int = 40) -> [NearbyStop] {
        var results: [NearbyStop] = []
        results.reserveCapacity(stopSearchItems.count)
        for item in stopSearchItems {
            let distance = location.distance(from: CLLocation(latitude: item.location.lat, longitude: item.location.lng))
            results.append(NearbyStop(item: item, distance: distance))
        }
        results.sort { $0.distance < $1.distance }
        return Array(results.prefix(limit))
    }

    func routeCount(at stopId: String) -> Int {
        routesAtStop(stopId).count
    }

    /// The route entry running the opposite direction, if one exists.
    func oppositeEntry(for entry: RouteEntry) -> (key: String, entry: RouteEntry)? {
        guard let db else { return nil }
        guard entry.orig.en != entry.dest.en else { return nil }
        var fallback: (key: String, entry: RouteEntry)?
        for (key, candidate) in db.routeList {
            guard key != entry.routeKey else { continue }
            guard candidate.route == entry.route else { continue }
            guard !Set(candidate.co).isDisjoint(with: Set(entry.co)) else { continue }
            guard candidate.orig.en == entry.dest.en, candidate.dest.en == entry.orig.en else { continue }
            if candidate.serviceTypeValue == entry.serviceTypeValue {
                return (key, candidate)
            }
            if fallback == nil {
                fallback = (key, candidate)
            }
        }
        return fallback
    }
}

private struct LoadedData: Sendable {
    let db: EtaDB
    let routeItems: [RouteSearchItem]
    let stopItems: [StopSearchItem]
    let stopRouteIndex: [String: [StopRouteRef]]
    let directStopCompanies: [String: Set<String>]
}

/// Reports throttled download progress (at most ~4 updates per second).
private final class DownloadProgressDelegate: NSObject, URLSessionDownloadDelegate {
    private let onProgress: (Int64, Int64) -> Void
    private var lastBytes: Int64 = 0
    private var lastReport = Date.distantPast

    init(onProgress: @escaping (Int64, Int64) -> Void) {
        self.onProgress = onProgress
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        let now = Date()
        let finished = totalBytesExpectedToWrite > 0 && totalBytesWritten >= totalBytesExpectedToWrite
        guard totalBytesWritten - lastBytes > 256 * 1024
            || now.timeIntervalSince(lastReport) > 0.25
            || finished
        else { return }
        lastBytes = totalBytesWritten
        lastReport = now
        onProgress(totalBytesWritten, totalBytesExpectedToWrite)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        // Handled by the async `download(from:)` API.
    }
}
