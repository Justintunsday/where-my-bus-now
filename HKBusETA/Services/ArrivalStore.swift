import ActivityKit
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
                  source: metadata?.source.rawValue, language: L10n.language.rawValue,
                  timeZoneIdentifier: app.region.timeZone.identifier)
    }

    func matches(entry: RouteEntry, providerID: String, source: String?, mode: String?) -> Bool {
        self.providerID == providerID && routeKey == entry.routeKey
            && serviceType == entry.serviceTypeValue && operators.sorted() == entry.co.sorted()
            && directions == entry.bound && lineID == entry.gtfsId?.value
            && entry.canonicalStops.indices.contains(stopSequence)
            && entry.canonicalStops[stopSequence] == stopID && self.source == source && self.mode == mode
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
    private(set) var identityInvalid = false
    private(set) var lastSuccessfulState: BusArrivalState?
    private var isNetworkFailure = false
    @ObservationIgnored private let data: DataStore
    @ObservationIgnored private var flight: Task<Void, Never>?

    init(target: BusTrackingTarget, data: DataStore) {
        self.target = target
        self.data = data
    }

    var activityState: BusArrivalState {
        if let error {
            return .failed(previous: lastSuccessfulState, at: Date(), network: isNetworkFailure, message: error)
        }
        return lastSuccessfulState ?? .unavailable(at: updatedAt ?? Date())
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

    /// Restore the system's last received snapshot before the first foreground request.
    /// A cold-start network failure must not erase an existing activity's clock history.
    func restore(_ state: BusArrivalState) {
        guard lastSuccessfulState == nil else { return }
        lastSuccessfulState = state
        updatedAt = state.updatedAt
        if state.status == .networkError || state.status == .unavailable {
            isNetworkFailure = state.status == .networkError
            error = state.message.isEmpty
                ? BusActivityCopy.text(isNetworkFailure ? "networkError" : "unavailable", language: target.language)
                : state.message
        }
    }

    private func performRefresh() async {
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            try await data.ensureLoaded()
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
                                 source: data.mainlandMetadata(for: target.routeKey)?.source.rawValue,
                                 mode: data.mainlandMetadata(for: target.routeKey)?.mode.rawValue)
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
            let rows = result.map { item in
                BusArrivalState.reportedStatus(item.remark.name(language)) == nil ? item
                    : Eta(eta: "", remark: item.remark, dest: item.dest, co: item.co)
            }
            if etas != rows { etas = rows }
            let receivedAt = Date()
            lastSuccessfulState = makeState(result, at: receivedAt)
            updatedAt = receivedAt
            error = nil
            identityInvalid = false
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else { return }
            identityInvalid = error is ArrivalFailure
            if let urlError = error as? URLError {
                isNetworkFailure = [.notConnectedToInternet, .networkConnectionLost, .timedOut,
                    .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed].contains(urlError.code)
            } else if case CheLaileAPIError.transport = error { isNetworkFailure = true }
            else { isNetworkFailure = false }
            self.error = (error as? ArrivalFailure)?.errorDescription
                ?? (data.provider is HongKongProvider ? L10n.t("arrival.networkError") : MainlandErrorPresentation.message(for: error))
        }
    }

    private func makeState(_ result: [Eta], at date: Date) -> BusArrivalState {
        let sorted = result.filter {
            ($0.date ?? .distantPast) > date && BusArrivalState.reportedStatus($0.remark.name(language)) == nil
        }.sorted { $0.date! < $1.date! }
        let first = sorted.first
        let message = first?.remark.name(language) ?? result.first?.remark.name(language) ?? ""
        let explicit = first == nil ? result.compactMap { BusArrivalState.reportedStatus($0.remark.name(language)) }.first : nil
        var state = BusArrivalState.snapshot(arrivals: sorted.compactMap { $0.date?.timeIntervalSince1970 }, updatedAt: date,
                         scheduled: first?.isScheduled ?? false, message: message, explicitStatus: explicit,
                         previous: lastSuccessfulState)
        if first != nil, let old = lastSuccessfulState?.arrivalEpoch,
           result.contains(where: { item in
               guard let date = item.date, let status = BusArrivalState.reportedStatus(item.remark.name(language)) else { return false }
               return [.cancelled, .arrived, .departed].contains(status) && abs(date.timeIntervalSince1970 - old) < 15
           }) { state.change = .nextBus }
        return state
    }

    #if DEBUG
    func seed(etas: [Eta], updatedAt: Date, error: String? = nil) {
        self.etas = etas
        self.updatedAt = updatedAt
        self.error = error
        self.lastSuccessfulState = makeState(etas, at: updatedAt)
        self.isNetworkFailure = error != nil
    }
    #endif
}

@MainActor
final class ArrivalStore {
    private var sessions: [String: ArrivalSession] = [:]
    private var regionData: [String: DataStore] = [:]

    func session(for target: BusTrackingTarget, app: AppState) -> ArrivalSession? {
        let cacheKey = "\(target.id)|language:\(target.language)"
        if let session = sessions[cacheKey] { return session }
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
        if let activity = Activity<BusActivityAttributes>.activities.first(where: {
            $0.attributes.target.id == target.id && ($0.activityState == .active || $0.activityState == .stale)
        }) { session.restore(activity.content.state) }
        sessions[cacheKey] = session
        return session
    }

    func cancelRequests() { sessions.values.forEach { $0.cancel() } }
}
