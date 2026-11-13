import CoreLocation
import SwiftUI

struct SearchView: View {
    @Environment(AppState.self) private var app
    @State private var query = ""
    @State private var filter: TransportFilter = .all
    @State private var routes: [TransitRouteSearchResult] = []
    @State private var stops: [StopSearchItem] = []
    @State private var mainlandLines: [MainlandLineSummary] = []
    @State private var mainlandStops: [MainlandStopSummary] = []
    @State private var mainlandError: String?
    @State private var isSearching = false
    @State private var retryID = 0
    @Namespace private var routeTransition

    init(initialQuery: String = "") {
        // A one-time entry/preview seed; subsequent text belongs to this screen.
        _query = State(initialValue: initialQuery)
    }

    private var language: AppLanguage { L10n.language }
    private var request: TransitSearchRequest {
        TransitSearchRequest(query: query.trimmingCharacters(in: .whitespacesAndNewlines),
            filter: filter, language: app.settings.language, regionID: app.region.id,
            dataRevision: app.data.lastLoaded, retryID: retryID)
    }

    var body: some View {
        NavigationStack {
            DataGate {
                content
            }
            .background(DesignTokens.background)
            .navigationTitle(L10n.t("search.title"))
            .toolbar { TransitAppToolbar() }
            .navigationDestination(for: RouteDetailTarget.self) { target in
                RouteDetailView(routeKey: target.routeKey)
                    .modifier(RouteZoomDestination(id: target.routeKey, namespace: routeTransition))
            }
            .navigationDestination(for: RouteEtaTarget.self) { target in
                RouteEtaView(routeKey: target.routeKey, seq: target.seq)
            }
            .navigationDestination(for: StopTarget.self) { target in
                StopEtaView(stopId: target.stopId)
            }
            .navigationDestination(for: MainlandLineTarget.self) { target in
                MainlandLineLoaderView(
                    lineId: target.lineId,
                    title: target.title,
                    seq: target.seq,
                    modeHint: target.modeHint,
                    origin: target.origin,
                    destination: target.destination,
                    firstDeparture: target.firstDeparture,
                    lastDeparture: target.lastDeparture,
                    fare: target.fare
                )
            }
            .navigationDestination(for: MainlandStopTarget.self) { target in
                MainlandStopBoardView(
                    stopID: target.stopID,
                    namesakeStopID: target.namesakeStopID,
                    title: target.title,
                    location: target.location
                )
            }
            .navigationDestination(for: SavedRouteTarget.self) { target in
                SavedRouteDestination(target: target)
            }
            .navigationDestination(for: SavedStopTarget.self) { target in
                SavedStopDestination(target: target)
            }
        }
        .searchable(text: $query, prompt: Text(L10n.t("search.placeholder")))
        .searchScopes($filter, activation: .onSearchPresentation) {
            ForEach(TransportFilter.allCases) { scope in
                Text(scope.title(language)).tag(scope)
            }
        }
        .task(id: request) { await performSearch(request) }
    }

    @ViewBuilder
    private var content: some View {
        if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            SearchLandingView()
        } else if app.mainlandProvider != nil {
            mainlandContent
        } else if isSearching && routes.isEmpty && stops.isEmpty {
            ProgressView(L10n.t("search.searching"))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityIdentifier("search.loading")
        } else if routes.isEmpty && stops.isEmpty {
            ContentUnavailableView {
                Label(L10n.t("search.noResults"), systemImage: "magnifyingglass")
            } description: {
                Text(L10n.t("search.noResults.hint"))
            }
            .accessibilityIdentifier("search.noResults")
        } else {
            List {
                if !routes.isEmpty {
                    Section(L10n.t("search.section.routes")) {
                        ForEach(routes) { result in
                            NavigationLink(value: RouteDetailTarget(routeKey: result.id)) {
                                RouteResultRow(entry: result.entry, language: language)
                                    .modifier(RouteZoomSource(id: result.id, namespace: routeTransition))
                            }
                            .accessibilityIdentifier("search.route.\(result.id)")
                        }
                    }
                }
                if !stops.isEmpty {
                    Section(L10n.t("search.section.stops")) {
                        ForEach(stops, id: \.id) { item in
                            NavigationLink(value: StopTarget(stopId: item.id)) {
                                StopRowView(item: item, distance: distanceText(item))
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped).listSectionSpacing(20)
            .transitListSurface().transitReadableWidth()
            .scrollDismissesKeyboard(.interactively)
            .accessibilityIdentifier("search.results")
        }
    }

    @ViewBuilder
    private var mainlandContent: some View {
        if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            ContentUnavailableView {
                Label(L10n.t("search.title"), systemImage: "bus")
            } description: {
                Text(L10n.t("search.empty.hint"))
            }
        } else if isSearching && mainlandLines.isEmpty && mainlandStops.isEmpty {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let mainlandError {
            ContentUnavailableView {
                Label(L10n.t("error.mainland.requestFailed"), systemImage: "wifi.exclamationmark")
            } description: {
                Text(mainlandError)
            } actions: {
                Button(L10n.t("common.retry")) { retryID += 1 }
            }
        } else if mainlandLines.isEmpty && mainlandStops.isEmpty {
            ContentUnavailableView {
                Label(L10n.t("search.noResults"), systemImage: "magnifyingglass")
            } description: {
                Text(L10n.t("search.noResults.hint"))
            }
        } else {
            List {
                if !mainlandLines.isEmpty {
                    Section(L10n.t("search.section.routes")) {
                        ForEach(mainlandLines) { hit in
                            NavigationLink(value: MainlandLineTarget(
                                lineId: hit.lineID,
                                title: hit.name,
                                seq: nil,
                                modeHint: hit.mode,
                                origin: hit.origin,
                                destination: hit.destination,
                                firstDeparture: hit.firstDeparture,
                                lastDeparture: hit.lastDeparture,
                                fare: hit.fare
                            )) {
                                MainlandLineRow(hit: hit)
                            }
                        }
                    }
                }
                if !mainlandStops.isEmpty {
                    Section(L10n.t("search.section.stops")) {
                        ForEach(mainlandStops) { hit in
                            NavigationLink(value: MainlandStopTarget(
                                stopID: hit.stopID,
                                namesakeStopID: hit.namesakeStopID,
                                title: hit.name,
                                location: hit.location.map { StopLocation($0) }
                            )) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(hit.name)
                                    if let subtitle = hit.subtitle {
                                        Text(subtitle)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped).listSectionSpacing(20)
            .transitListSurface().transitReadableWidth()
            .scrollDismissesKeyboard(.interactively)
            .accessibilityIdentifier("search.results")
        }
    }

    private func distanceText(_ item: StopSearchItem) -> String? {
        guard let location = app.location.location else { return nil }
        let distance = location.distance(from: CLLocation(latitude: item.location.lat, longitude: item.location.lng))
        return GeoUtils.distanceString(distance, language: language)
    }

    private func performSearch(_ request: TransitSearchRequest) async {
        guard !request.query.isEmpty else {
            routes = []; stops = []; mainlandLines = []; mainlandStops = []
            mainlandError = nil; isSearching = false
            return
        }
        let data = app.data
        let provider = app.mainlandProvider
        isSearching = true
        mainlandError = nil
        // A cancelled predecessor must not clear the replacement request's loading state.
        defer { if !Task.isCancelled { isSearching = false } }
        do {
            try await Task.sleep(for: .milliseconds(provider == nil ? 150 : 250))
            try Task.checkCancellation()
            if let provider {
                guard MainlandSearchFiltering.isSupported(request.filter) else {
                    mainlandLines = []; mainlandStops = []
                    return
                }
                let results = try await provider.search(keyword: request.query)
                let filtered = MainlandSearchFiltering.apply(request.filter, to: results)
                try Task.checkCancellation()
                mainlandLines = filtered.lines
                mainlandStops = filtered.stops
            } else {
                routes = data.searchRoutes(query: request.query, filter: request.filter).compactMap { hit in
                    guard let entry = data.entry(hit.key) else { return nil }
                    return TransitRouteSearchResult(id: hit.key, entry: entry)
                }
                stops = data.searchStops(query: request.query)
            }
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else { return }
            mainlandLines = []; mainlandStops = []
            mainlandError = MainlandErrorPresentation.message(for: error)
        }
    }
}

private struct TransitRouteSearchResult: Identifiable {
    let id: String
    let entry: RouteEntry
}

private struct TransitSearchRequest: Equatable {
    let query: String
    let filter: TransportFilter
    let language: AppLanguage
    let regionID: String
    let dataRevision: Date?
    let retryID: Int
}

struct MainlandLineRow: View {
    let hit: MainlandLineSummary

    var body: some View {
        HStack(spacing: 12) {
            RouteBadge(route: hit.name, entry: nil, colorHex: MainlandProviderPalette.color(for: hit.name))
            VStack(alignment: .leading, spacing: 2) {
                Text("\(L10n.t("route.to")) \(hit.destination)")
                    .font(.body)
                    .fontWeight(.medium)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 6) {
                    if let symbol = hit.mode.symbolName {
                        RouteModeIcon(
                            symbolName: symbol,
                            size: 11,
                            label: hit.mode == .metro ? L10n.t("mainland.metros") : nil
                        )
                    }
                    Text(hit.origin)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.vertical, 2)
    }
}

/// One row per direction of a route — the reverse direction is its own result.
struct RouteResultRow: View {
    let entry: RouteEntry
    let language: AppLanguage

    var body: some View {
        HStack(spacing: 12) {
            RouteBadge(route: entry.route, entry: entry)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text("\(L10n.t("route.to")) \(entry.dest.name(language))")
                        .font(.body)
                        .fontWeight(.medium)
                        .fixedSize(horizontal: false, vertical: true)
                    if entry.isSpecialTrip {
                        Text(L10n.t("route.special"))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                HStack(spacing: 6) {
                    Text(entry.orig.name(language))
                    Text("·")
                    CompanyLogos(co: entry.co, language: language, height: 14)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 2)
    }
}

struct StopRowView: View {
    let item: StopSearchItem
    var distance: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(L10n.language.isChinese ? L10n.display(item.nameZh) : item.nameEn)
            if let distance {
                Text(distance)
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
    }
}
