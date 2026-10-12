import SwiftUI

struct SearchLandingView: View {
    @Environment(AppState.self) private var app
    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Label(app.region.localizedName, systemImage: "location.circle.fill").foregroundStyle(DesignTokens.accent)
                    Text(L10n.t("search.discoveryTitle")).font(.title2.bold())
                    Text(L10n.t("search.empty.hint")).font(.subheadline).foregroundStyle(.secondary)
                }.padding(.vertical, 12)
            }
            if !app.bookmarks.recentRoutes.isEmpty {
                Section(L10n.t("search.recent.routes")) {
                    ForEach(app.bookmarks.recentRoutes.prefix(12)) { recent in
                        NavigationLink(value: SavedRouteTarget(regionID: app.region.id, recent: recent)) {
                            HStack(spacing: 16) {
                                RouteBadge(route: recent.route, entry: app.data.entry(recent.routeKey))
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(L10n.language.isChinese ? L10n.display(recent.destZh) : recent.destEn).font(.headline)
                                    Text(L10n.language.isChinese ? L10n.display(recent.stopNameZh) : recent.stopNameEn)
                                        .font(.subheadline).foregroundStyle(.secondary)
                                }
                            }.padding(.vertical, 8)
                        }
                    }
                }
            }
            if !app.bookmarks.favoriteRoutes.isEmpty {
                Section(L10n.t("favorites.routes")) {
                    ForEach(app.bookmarks.favoriteRoutes.prefix(8)) { favorite in
                        NavigationLink(value: SavedRouteTarget(RegionalFavoriteRoute(regionID: app.region.id, favorite: favorite))) {
                            HStack(spacing: 16) {
                                RouteBadge(route: favorite.route, entry: app.data.entry(favorite.routeKey))
                                Text(L10n.language.isChinese ? L10n.display(favorite.destZh) : favorite.destEn).font(.headline)
                            }.padding(.vertical, 8)
                        }
                    }
                }
            }
            if !app.bookmarks.recentStops.isEmpty {
                Section(L10n.t("search.recent.stops")) {
                    ForEach(app.bookmarks.recentStops.prefix(8)) { recent in
                        NavigationLink(value: SavedStopTarget(regionID: app.region.id, recent: recent)) {
                            Label(L10n.language.isChinese ? L10n.display(recent.nameZh) : recent.nameEn, systemImage: "mappin.circle")
                                .padding(.vertical, 8)
                        }
                    }
                }
            }
        }.listStyle(.insetGrouped)
    }
}
