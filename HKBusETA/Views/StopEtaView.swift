import SwiftUI

struct StopEtaView: View {
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
            .task(id: stopId) {
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
        }
    }

    private func recordRecent() {
        guard let stop = app.data.stop(stopId) else { return }
        app.bookmarks.recordRecentStop(id: stopId, name: stop.name, location: stop.location)
    }

    private func refresh() async {
        guard let db = app.data.db else { return }
        if items.isEmpty { isLoading = true }
        let refs = app.data.routesAtStop(stopId)
        let result = await StopBoardService.fetchStopBoard(refs: refs, db: db, provider: app.provider, language: language)
        items = result
        lastUpdated = Date()
        isLoading = false
    }
}

struct StopBoardRowView: View {
    let item: StopBoardItem
    let language: AppLanguage
    let settings: AppSettings

    var body: some View {
        HStack(alignment: .center, spacing: DesignTokens.Spacing.s) {
            RouteBadge(route: item.entry.route, entry: item.entry)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(L10n.t("route.to")) \(item.entry.dest.name(language))")
                    .font(.body)
                    .lineLimit(1)
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
                    ForEach(Array(upcoming.prefix(3).enumerated()), id: \.offset) { index, eta in
                        ETACompactLineView(
                            eta: eta,
                            format: settings.etaFormat,
                            annotateScheduled: settings.annotateScheduled,
                            highlight: index == 0
                        )
                    }
                }
            }
            .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.vertical, DesignTokens.Spacing.xs)
    }
}
