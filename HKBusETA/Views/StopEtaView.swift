import SwiftUI

struct StopEtaView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(AppState.self) private var app
    let stopId: String

    @State private var items: [StopBoardItem] = []
    @State private var isLoading = false
    @State private var lastUpdated: Date?

    private var language: AppLanguage { L10n.language }

    var body: some View {
        DataGate {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Label(L10n.t("eta.currentStop"), systemImage: "mappin.circle.fill")
                            .font(.caption).foregroundStyle(DesignTokens.accent)
                        Text(app.data.stopName(stopId, language)).font(.title2.bold())
                            .fixedSize(horizontal: false, vertical: true)
                    }.padding(.vertical, 8)
                }
                Section {
                    if isLoading && items.isEmpty {
                        HStack(spacing: DesignTokens.Spacing.s) {
                            ProgressView()
                            Text(L10n.t("status.loading"))
                                .foregroundStyle(.secondary)
                        }
                    } else if items.isEmpty {
                        Text(L10n.t("stop.noRoutes"))
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(items) { item in
                            NavigationLink(value: RouteEtaTarget(routeKey: item.routeKey, seq: item.seq)) {
                                StopBoardRowView(item: item, language: language, settings: app.settings)
                            }
                        }
                    }
                } header: {
                    Text(sectionTitle)
                }
                if let lastUpdated {
                    Section {
                        HStack {
                            Text(L10n.t("eta.updatedAt"))
                            Spacer()
                            Text(RegionClock.timeString(lastUpdated))
                                .monospacedDigit()
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle(app.data.stopName(stopId, language))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    if let stop = app.data.stop(stopId), stop.location.isValid {
                        StopNavigationButton(
                            stopName: stop.name.name(language),
                            location: stop.location
                        ) {
                            Image(systemName: "map")
                        }
                    }
                    favoriteButton
                }
            }
            .refreshable { await refresh() }
            .task(id: "\(stopId)|\(scenePhase)") {
                guard scenePhase == .active else { return }
                recordRecent()
                while !Task.isCancelled {
                    await refresh()
                    do {
                        try await Task.sleep(nanoseconds: 30_000_000_000)
                    } catch {
                        break
                    }
                }
            }
        }
    }

    private var sectionTitle: String {
        let count = app.data.routesAtStop(stopId).count
        guard count > 0 else { return L10n.t("stop.section.routes") }
        return "\(L10n.t("stop.section.routes")) · \(count) \(L10n.t("unit.routes"))"
    }

    @ViewBuilder
    private var favoriteButton: some View {
        if let stop = app.data.stop(stopId) {
            let isFavorite = app.bookmarks.isFavoriteStop(stopId)
            Button {
                app.bookmarks.toggleFavoriteStop(id: stopId, name: stop.name, location: stop.location)
            } label: {
                Image(systemName: isFavorite ? "star.fill" : "star")
            }
            .tint(DesignTokens.accent)
            .accessibilityLabel(L10n.t(isFavorite ? "common.unfavorite" : "common.favorite"))
            .sensoryFeedback(.selection, trigger: isFavorite)
        }
    }

    private func recordRecent() {
        guard let stop = app.data.stop(stopId) else { return }
        app.bookmarks.recordRecentStop(id: stopId, name: stop.name, location: stop.location)
    }

    private func refresh() async {
        guard !isLoading else { return }
        guard let db = app.data.db else { return }
        #if DEBUG
        if app.data.isPreview {
            items = app.data.routesAtStop(stopId).compactMap { ref in
                guard let entry = app.data.entry(ref.routeKey),
                      let target = BusTrackingTarget(app: app, routeKey: ref.routeKey, seq: ref.seq),
                      let session = app.arrivals.session(for: target, app: app) else { return nil }
                return StopBoardItem(routeKey: ref.routeKey, entry: entry, etas: session.etas, seq: ref.seq)
            }
            lastUpdated = Date()
            return
        }
        #endif
        isLoading = true
        defer { isLoading = false }
        let refs = app.data.routesAtStop(stopId)
        let result = await StopBoardService.fetchStopBoard(refs: refs, db: db, provider: app.provider, language: language)
        guard !Task.isCancelled else { return }
        // Keep visible row positions while predictions change. New services append naturally.
        let order = Dictionary(uniqueKeysWithValues: items.enumerated().map { ($0.element.id, $0.offset) })
        items = result.sorted { (order[$0.id] ?? Int.max) < (order[$1.id] ?? Int.max) }
        lastUpdated = Date()
    }
}

struct StopBoardRowView: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    let item: StopBoardItem
    let language: AppLanguage
    let settings: AppSettings

    var body: some View {
        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12)) : AnyLayout(HStackLayout(alignment: .center, spacing: 12))
        return layout {
            RouteBadge(route: item.entry.route, entry: item.entry)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(L10n.t("route.to")) \(item.entry.dest.name(language))")
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)
                CompanyLogos(co: item.entry.co, language: language, height: 13)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .trailing, spacing: 3) {
                let upcoming = item.upcoming
                if upcoming.isEmpty {
                    let remark = item.etas.first?.remark.name(language) ?? ""
                    Text(remark.isEmpty ? L10n.t("eta.noEta") : remark)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing)
                        .lineLimit(2)
                } else {
                    ForEach(ArrivalSlot.make(Array(upcoming.prefix(3)))) { slot in
                        ETACompactLineView(
                            eta: slot.eta,
                            format: settings.etaFormat,
                            annotateScheduled: settings.annotateScheduled,
                            highlight: slot.id == ArrivalSlot.make(Array(upcoming.prefix(3))).first?.id
                        )
                    }
                }
            }
            .fixedSize(horizontal: !typeSize.isAccessibilitySize, vertical: false)
        }
        .padding(.vertical, DesignTokens.Spacing.xs)
    }
}
