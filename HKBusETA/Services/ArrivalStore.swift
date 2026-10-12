import Foundation
import Observation

enum ArrivalFailure: LocalizedError {
    case identityChanged
    var errorDescription: String? { L10n.t("tracking.identityChanged") }
}

extension BusTrackingTarget {
    @MainActor
    init?(app: AppState, routeKey: String, seq: Int) {
        guard let entry = app.data.entry(routeKey), entry.canonicalStops.indices.contains(seq) else { return nil }
        let stopID = entry.canonicalStops[seq]
        let metadata = app.data.mainlandMetadata(for: routeKey)
        self.init(regionID: app.region.id, providerID: app.provider.id, routeKey: routeKey,
                  route: entry.route, destination: entry.dest.name(L10n.language),
                  origin: entry.orig.name(L10n.language), serviceType: entry.serviceTypeValue,
                  operators: entry.co.sorted(), directions: entry.bound, stopID: stopID,
                  stopName: app.data.stopName(stopID, L10n.language), stopSequence: seq,
                  lineID: entry.gtfsId?.value, mode: metadata?.mode.rawValue,
                  source: metadata?.source.rawValue, language: L10n.language.rawValue)
    }

    func matches(entry: RouteEntry, providerID: String, source: String?) -> Bool {
        self.providerID == providerID && routeKey == entry.routeKey
            && serviceType == entry.serviceTypeValue && operators.sorted() == entry.co.sorted()
            && directions == entry.bound && lineID == entry.gtfsId?.value
            && entry.canonicalStops.indices.contains(stopSequence)
            && entry.canonicalStops[stopSequence] == stopID && self.source == source
    }
}

/// One observed session per exact boarding identity. Only arrival subviews read it.
@MainActor @Observable
final class ArrivalSession {
    let target: BusTrackingTarget
    private(set) var etas: [Eta] = []
    private(set) var updatedAt: Date?
    private(set) var error: String?
    private(set) var isRefreshing = false
    @ObservationIgnored private let data: DataStore
    @ObservationIgnored private var flight: Task<Void, Never>?

    init(target: BusTrackingTarget, data: DataStore) {
        self.target = target
        self.data = data
    }

    var activityState: BusArrivalState {
        guard error == nil, let updatedAt else {
            // Preserve last successful timestamp; a failed request is never a fresh prediction.
            return .unavailable(at: updatedAt ?? Date(), message: error ?? "")
        }
        if let eta = etas.first(where: { ($0.date ?? .distantPast) > Date() }), let arrival = eta.date {
            return .prediction(arrival: arrival, updatedAt: updatedAt,
                               scheduled: eta.isScheduled, message: eta.remark.name(language))
        }
        let message = etas.first?.remark.name(language) ?? L10n.t("eta.noEta")
        let cancelled = message.localizedCaseInsensitiveContains("cancel") || message.contains("取消")
        return .unavailable(at: updatedAt, message: message, cancelled: cancelled)
    }

    private var language: AppLanguage { AppLanguage(rawValue: target.language) ?? .en }

    func refresh(force: Bool = false) async {
        #if DEBUG
        if data.isPreview { return }
        #endif
        if let flight { await flight.value; return }
        if !force, let updatedAt, error == nil, Date().timeIntervalSince(updatedAt) < 20 { return }
        let task = Task { await performRefresh() }
        flight = task
        await task.value
        flight = nil
    }

    func cancel() { flight?.cancel() }

    private func performRefresh() async {
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            await data.load()
            if data.entry(target.routeKey) == nil,
               let mainland = data.provider as? any MainlandTransitProvider, let lineID = target.lineID {
                let mode = target.mode.flatMap(MainlandTransitMode.init(rawValue:)) ?? .bus
                if let payload = try await mainland.linePayload(lineID: lineID, modeHint: mode),
                   let shared = MainlandRouteAdapter.makeSharedRoute(from: payload.applying(modeHint: mode)) {
                    guard !Task.isCancelled else { return }
                    data.registerSynthetic(entry: shared.entry, stops: shared.stops, mainlandMetadata: shared.metadata)
                }
            }
            guard let entry = data.entry(target.routeKey), let db = data.db,
                  target.matches(entry: entry, providerID: data.provider.id,
                                 source: data.mainlandMetadata(for: target.routeKey)?.source.rawValue)
            else { throw ArrivalFailure.identityChanged }
            let result: [Eta]
            if let mainland = data.provider as? any MainlandTransitProvider {
                let metadata = data.mainlandMetadata(for: target.routeKey)
                guard MainlandRealtimePolicy.allowsRequest(modeHint: metadata?.mode) else {
                    throw MainlandProviderError.realtimeUnavailable(source: mainland.id)
                }
                let location = data.stop(target.stopID)?.location
                result = try await mainland.fetchEtas(
                    lineID: target.lineID ?? "", stopID: target.stopID, stopSequence: target.stopSequence,
                    latitude: location?.coordinateSystem == .wgs84 ? location?.lat : nil,
                    longitude: location?.coordinateSystem == .wgs84 ? location?.lng : nil,
                    source: metadata?.source, language: language, modeHint: metadata?.mode)
            } else if data.provider is HongKongProvider {
                result = try await HongKongETAService.fetchEtasReportingErrors(
                    entry: entry, seq: target.stopSequence, db: db, language: language)
            } else {
                result = await data.provider.fetchEtas(entry: entry, seq: target.stopSequence, db: db, language: language)
            }
            guard !Task.isCancelled else { return }
            if etas != result { etas = result }
            updatedAt = Date()
            error = nil
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else { return }
            self.error = (error as? ArrivalFailure)?.errorDescription
                ?? (data.provider is HongKongProvider ? L10n.t("arrival.networkError") : MainlandErrorPresentation.message(for: error))
        }
    }

    #if DEBUG
    func seed(etas: [Eta], updatedAt: Date, error: String? = nil) {
        self.etas = etas
        self.updatedAt = updatedAt
        self.error = error
    }
    #endif
}

@MainActor
final class ArrivalStore {
    private var sessions: [String: ArrivalSession] = [:]
    private var regionData: [String: DataStore] = [:]

    func session(for target: BusTrackingTarget, app: AppState) -> ArrivalSession? {
        if let session = sessions[target.id], session.target.language == target.language { return session }
        guard let region = RegionCatalog.region(for: target.regionID) else { return nil }
        let data: DataStore
        if app.region.id == target.regionID { data = app.data }
        else if let cached = regionData[target.regionID] { data = cached }
        else {
            data = DataStore(provider: RegionCatalog.provider(for: region))
            regionData[target.regionID] = data
        }
        guard data.provider.id == target.providerID else { return nil }
        // Bound the cache; activities and views retain the sessions they use.
        if sessions.count > 40 { sessions = sessions.filter { $0.value.isRefreshing } }
        let session = ArrivalSession(target: target, data: data)
        sessions[target.id] = session
        return session
    }

    func cancelRequests() { sessions.values.forEach { $0.cancel() } }
}
