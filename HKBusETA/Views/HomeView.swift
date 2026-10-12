import SwiftUI

struct HomeView: View {
    @Environment(AppState.self) private var app
    let openSearch: () -> Void

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button(action: openSearch) {
                        Label(L10n.t("search.placeholder"), systemImage: "magnifyingglass")
                            .foregroundStyle(.secondary).frame(minHeight: 44)
                    }
                }
                if !app.activities.activeTargets.isEmpty {
                    Section(L10n.t("home.tracking")) {
                        ForEach(app.activities.activeTargets) { target in
                            NavigationLink(value: target) {
                                Label("\(target.route) · \(target.stopName)", systemImage: "wave.3.right.circle.fill")
                                    .font(.headline)
                            }
                        }
                    }
                }
                Section {
                    if app.boarding.targets.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Image(systemName: "bus.fill").font(.largeTitle).foregroundStyle(DesignTokens.accent)
                            Text(L10n.t("home.empty.title")).font(.title2.bold())
                            Text(L10n.t("home.empty.message")).font(.subheadline).foregroundStyle(.secondary)
                            Button(L10n.t("tab.search"), action: openSearch).buttonStyle(.bordered)
                        }
                        .padding(.vertical, 16)
                    } else {
                        ForEach(app.boarding.targets) { target in
                            BoardingTripRow(target: target)
                                .swipeActions {
                                    Button(role: .destructive) { app.boarding.remove(target) } label: {
                                        Label(L10n.t("common.remove"), systemImage: "pin.slash")
                                    }
                                }
                        }
                    }
                } header: {
                    HStack { Text(L10n.t("home.boarding")); Spacer(); Image(systemName: "pin.fill") }
                }
                if !app.bookmarks.favoriteRoutes.isEmpty {
                    Section(L10n.t("favorites.routes")) {
                        ForEach(app.bookmarks.favoriteRoutes.prefix(6)) { favorite in
                            NavigationLink(value: SavedRouteTarget(RegionalFavoriteRoute(regionID: app.region.id, favorite: favorite))) {
                                HStack(spacing: 16) {
                                    RouteBadge(route: favorite.route, entry: app.data.entry(favorite.routeKey))
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(L10n.language.isChinese ? L10n.display(favorite.destZh) : favorite.destEn)
                                            .font(.headline)
                                        Text(L10n.t("boarding.choose")).font(.caption).foregroundStyle(.secondary)
                                    }
                                }.padding(.vertical, 8)
                            }
                        }
                    }
                }
                if !app.bookmarks.recentStops.isEmpty {
                    Section(L10n.t("home.frequentStops")) {
                        ForEach(app.bookmarks.recentStops.prefix(4)) { stop in
                            NavigationLink(value: SavedStopTarget(regionID: app.region.id, recent: stop)) {
                                Label(L10n.language.isChinese ? L10n.display(stop.nameZh) : stop.nameEn, systemImage: "mappin.circle")
                                    .padding(.vertical, 8)
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle(L10n.t("home.title"))
            .toolbar { TransitAppToolbar() }
            .transitDestinations()
        }
    }
}

/// The badge moves between compact and expanded boarding detail in the same hierarchy.
/// The full ETA push remains system-interactive; iOS 18+ adds native zoom continuity.
private struct BoardingTripRow: View {
    @Environment(AppState.self) private var app
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let target: BusTrackingTarget
    @State private var expanded = false
    @Namespace private var identity

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Button {
                withAnimation(TransitMotion.selection(reduced: reduceMotion)) { expanded.toggle() }
            } label: {
                HStack(alignment: .center, spacing: 16) {
                    if !expanded { badge.matchedGeometryEffect(id: "route", in: identity) }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(target.destination).font(.headline).foregroundStyle(.primary)
                        Text(target.stopName).font(.subheadline).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.down").font(.caption.bold())
                        .rotationEffect(.degrees(expanded ? 180 : 0)).foregroundStyle(.secondary)
                }
                .frame(minHeight: 44).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityValue(L10n.t(expanded ? "common.expanded" : "common.collapsed"))
            if expanded {
                HStack {
                    badge.matchedGeometryEffect(id: "route", in: identity)
                    Text(RegionCatalog.region(for: target.regionID)?.name ?? target.regionID).font(.caption).foregroundStyle(.secondary)
                    Spacer()
                }
                .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
            }
            if let session = app.arrivals.session(for: target, app: app) {
                BoardingArrivalSummary(session: session, expanded: expanded)
                    .task(id: scenePhase) {
                        guard scenePhase == .active else { return }
                        while !Task.isCancelled {
                            await session.refresh()
                            do { try await Task.sleep(for: .seconds(30)) } catch { break }
                        }
                    }
            }
            NavigationLink(value: target) {
                Label(L10n.t("route.fullEta"), systemImage: "arrow.up.right")
                    .font(.subheadline.weight(.semibold)).frame(minHeight: 44)
            }
        }
        .padding(.vertical, 8)
        .sensoryFeedback(.selection, trigger: expanded)
    }

    private var badge: some View {
        Text(target.route).font(.title3.bold()).fontDesign(.rounded).monospacedDigit()
            .foregroundStyle(DesignTokens.accent).padding(10)
            .background(DesignTokens.accentSoft, in: RoundedRectangle(cornerRadius: 10))
    }
}

private struct BoardingArrivalSummary: View {
    let session: ArrivalSession
    let expanded: Bool
    var body: some View {
        if expanded { ArrivalHero(state: session.activityState) }
        else {
            TimelineView(.periodic(from: .now, by: 30)) { context in
                let state = session.activityState
                HStack(spacing: 8) {
                    Image(systemName: state.isFresh(at: context.date) ? "clock.fill" : "clock.badge.exclamationmark")
                    if state.isFresh(at: context.date), let arrival = state.arrival {
                        Text(arrival, style: .relative).monospacedDigit()
                        Text("·")
                        Text(arrival, style: .time).monospacedDigit()
                    } else { Text(L10n.t(session.isRefreshing ? "status.loading" : "arrival.stale")) }
                }
                .font(.subheadline.weight(.medium)).foregroundStyle(DesignTokens.accent)
            }
        }
        if expanded { FreshnessLabel(updatedAt: session.updatedAt, error: session.error) }
    }
}
