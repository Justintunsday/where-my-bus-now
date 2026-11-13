import SwiftUI

struct HomeView: View {
    @Environment(AppState.self) private var app
    @Environment(\.transitReduceMotion) private var reduceMotion
    let openSearch: () -> Void
    var openNearby: (() -> Void)? = nil
    var openSaved: (() -> Void)? = nil

    private var boardingTargets: [BusTrackingTarget] {
        let activeIDs = Set(app.activities.activeTargets.map(\.id))
        return app.boarding.targets.filter { !activeIDs.contains($0.id) }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HomeOverviewHeader(region: app.region, openSearch: openSearch, openNearby: openNearby)
                        .transitCardRow()
                }
                if !app.activities.activeTargets.isEmpty {
                    Section {
                        ForEach(app.activities.activeTargets) { target in
                            HomeTrackingCard(target: target).transitCardRow()
                        }
                    } header: {
                        TransitSectionHeading(title: L10n.t("home.tracking"), count: app.activities.activeTargets.count)
                    }
                }
                if !boardingTargets.isEmpty {
                    Section {
                        ForEach(boardingTargets) { target in
                            BoardingTripCard(target: target)
                                .environment(\.routeTheme, target.resolvedTheme)
                                .tint(target.resolvedTheme.accent)
                                .transitCardRow()
                                .swipeActions {
                                    Button(role: .destructive) { app.boarding.remove(target) } label: {
                                        Label(L10n.t("common.remove"), systemImage: "pin.slash")
                                    }
                                }
                        }
                    } header: {
                        TransitSectionHeading(title: L10n.t("home.boarding"), count: boardingTargets.count)
                    }
                } else if app.activities.activeTargets.isEmpty {
                    Section {
                        HomeEmptyBoarding(openSearch: openSearch).transitCardRow()
                    }
                }
                if !app.bookmarks.favoriteRoutes.isEmpty {
                    Section {
                        ForEach(app.bookmarks.favoriteRoutes.prefix(6)) { favorite in
                            NavigationLink(value: SavedRouteTarget(RegionalFavoriteRoute(regionID: app.region.id, favorite: favorite))) {
                                HStack(spacing: 16) {
                                    RouteBadge(route: favorite.route, entry: app.data.entry(favorite.routeKey))
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(L10n.language.isChinese ? L10n.display(favorite.destZh) : favorite.destEn)
                                            .font(.headline).fixedSize(horizontal: false, vertical: true)
                                        Text(L10n.t("boarding.choose")).font(.subheadline).foregroundStyle(.secondary)
                                    }
                                }.padding(.vertical, 8)
                            }
                        }
                        if let openSaved {
                            Button(action: openSaved) {
                                Label(L10n.t("home.allSaved"), systemImage: "star").frame(minHeight: 44)
                            }
                            .accessibilityIdentifier("home.saved")
                        }
                    } header: {
                        TransitSectionHeading(title: L10n.t("favorites.routes"))
                    }
                }
                if !app.bookmarks.recentStops.isEmpty {
                    Section {
                        ForEach(app.bookmarks.recentStops.prefix(4)) { stop in
                            NavigationLink(value: SavedStopTarget(regionID: app.region.id, recent: stop)) {
                                Label(L10n.language.isChinese ? L10n.display(stop.nameZh) : stop.nameEn, systemImage: "mappin.circle")
                                    .padding(.vertical, 8)
                            }
                        }
                    } header: {
                        TransitSectionHeading(title: L10n.t("home.frequentStops"))
                    }
                }
            }
            .listStyle(.insetGrouped).listSectionSpacing(20)
            .transitListSurface().transitReadableWidth()
            .navigationTitle(L10n.t("home.title"))
            .toolbar { TransitAppToolbar() }
            .transitDestinations()
            .animation(reduceMotion ? nil : .smooth(duration: 0.3), value: app.activities.activeTargets.map(\.id))
        }
    }
}

private struct HomeOverviewHeader: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    let region: TransitRegion
    let openSearch: () -> Void
    let openNearby: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            TimelineView(.periodic(from: .now, by: 60)) { context in
                Text(context.date, format: Date.FormatStyle(date: .complete, time: .omitted,
                    locale: L10n.language.locale, timeZone: region.timeZone))
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            Text(L10n.t("home.overview.message"))
                .font(.title2.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
            let layout = typeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
                : AnyLayout(HStackLayout(spacing: 12))
            layout {
                Button(action: openSearch) {
                    Label(L10n.t("tab.search"), systemImage: "magnifyingglass")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .accessibilityIdentifier("home.search")
                if let openNearby {
                    Button(action: openNearby) {
                        Label(L10n.t("nearby.title"), systemImage: "location")
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .accessibilityIdentifier("home.nearby")
                }
            }
            .buttonStyle(.bordered).buttonBorderShape(.capsule)
        }
        .padding(.vertical, 4)
    }
}

private struct HomeEmptyBoarding: View {
    let openSearch: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: "pin.circle").font(.largeTitle).foregroundStyle(DesignTokens.accent)
                .accessibilityHidden(true)
            Text(L10n.t("home.empty.title")).font(.title2.bold())
            Text(L10n.t("home.empty.message")).font(.body).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button(L10n.t("tab.search"), action: openSearch)
                .buttonStyle(.borderedProminent).controlSize(.large).frame(minHeight: 44)
                .tint(DesignTokens.action)
                .foregroundStyle(RouteTheme.global.onAccent)
        }
        .padding(.vertical, 8)
        .transitCardSurface()
    }
}
