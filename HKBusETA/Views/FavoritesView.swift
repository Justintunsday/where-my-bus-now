import SwiftUI

/// Favorites, grouped by transit region.
///
/// Warm Minimal pass (swiftui-design-skill): the region used to be a
/// third-line caption inside every row, which buried the one piece of
/// context that matters when favorites span several cities. The region is now
/// the section header itself — the page's organising element — and rows only
/// carry destination, origin and operators.
struct FavoritesView: View {
    @Environment(AppState.self) private var app
    @State private var navigationPath = NavigationPath()

    private var language: AppLanguage { L10n.language }

    private var routeSections: [FavoriteSection<RegionalFavoriteRoute>] {
        makeSections(app.bookmarks.allFavoriteRoutes) { $0.regionID }
    }

    private var stopSections: [FavoriteSection<RegionalFavoriteStop>] {
        makeSections(app.bookmarks.allFavoriteStops) { $0.regionID }
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            Group {
                if routeSections.isEmpty && stopSections.isEmpty {
                    emptyState
                } else {
                    List {
                        routeList
                        stopList
                    }
                }
            }
            .navigationTitle(L10n.t("favorites.title"))
            .navigationDestination(for: RouteDetailTarget.self) { target in
                RouteDetailView(routeKey: target.routeKey)
            }
            .navigationDestination(for: RouteEtaTarget.self) { target in
                RouteEtaView(routeKey: target.routeKey, seq: target.seq)
            }
            .navigationDestination(for: StopTarget.self) { target in
                StopEtaView(stopId: target.stopId)
            }
            .navigationDestination(for: SavedRouteTarget.self) { target in
                SavedRouteDestination(target: target)
            }
            .navigationDestination(for: SavedStopTarget.self) { target in
                SavedStopDestination(target: target)
            }
        }
    }

    @ViewBuilder
    private var routeList: some View {
        ForEach(routeSections) { section in
            Section {
                ForEach(section.items) { item in
                    Button {
                        navigationPath.append(SavedRouteTarget(item))
                    } label: {
                        HStack(spacing: DesignTokens.Spacing.s) {
                            RouteFavoriteRow(item: item)
                            Image(systemName: "chevron.forward")
                                .font(DesignTokens.captionMedium)
                                .foregroundStyle(DesignTokens.textTertiary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .onDelete { offsets in
                    app.bookmarks.removeFavoriteRoutes(offsets.map { section.items[$0] })
                }
            } header: {
                FavoriteSectionHeader(
                    kind: L10n.t("favorites.routes"),
                    regionID: section.regionID,
                    count: section.items.count
                )
            }
        }
    }

    @ViewBuilder
    private var stopList: some View {
        ForEach(stopSections) { section in
            Section {
                ForEach(section.items) { item in
                    Button {
                        navigationPath.append(SavedStopTarget(item))
                    } label: {
                        HStack(spacing: DesignTokens.Spacing.s) {
                            StopFavoriteRow(item: item)
                            Image(systemName: "chevron.forward")
                                .font(DesignTokens.captionMedium)
                                .foregroundStyle(DesignTokens.textTertiary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .onDelete { offsets in
                    app.bookmarks.removeFavoriteStops(offsets.map { section.items[$0] })
                }
            } header: {
                FavoriteSectionHeader(
                    kind: L10n.t("favorites.stops"),
                    regionID: section.regionID,
                    count: section.items.count
                )
            }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label(L10n.t("favorites.empty.title"), systemImage: "star")
        } description: {
            Text(L10n.t("favorites.empty.message"))
        }
    }

    /// Groups favorites by region, keeping the newest-first order inside each
    /// group and the catalog order (Hong Kong first) for the sections.
    private func makeSections<Item: Identifiable>(
        _ items: [Item],
        regionID: (Item) -> String
    ) -> [FavoriteSection<Item>] {
        var order: [String] = []
        var buckets: [String: [Item]] = [:]
        for item in items {
            let id = regionID(item)
            if buckets[id] == nil { order.append(id) }
            buckets[id, default: []].append(item)
        }
        order.sort { regionSortIndex($0) < regionSortIndex($1) }
        return order.map { FavoriteSection(regionID: $0, items: buckets[$0] ?? []) }
    }

    private func regionSortIndex(_ regionID: String) -> Int {
        RegionCatalog.all.firstIndex { $0.id == regionID } ?? Int.max
    }
}

struct FavoriteSection<Item: Identifiable>: Identifiable {
    let regionID: String
    let items: [Item]

    var id: String { regionID }
}

/// Section header: kind · region on the left, count on the right.
private struct FavoriteSectionHeader: View {
    let kind: String
    let regionID: String
    let count: Int

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.xs) {
            Image(systemName: "mappin.and.ellipse")
                .font(DesignTokens.footnote)
            Text("\(kind) · \(regionName)")
                .font(DesignTokens.caption)
            Spacer()
            Text("\(count)")
                .font(DesignTokens.caption)
                .monospacedDigit()
        }
        .foregroundStyle(DesignTokens.textTertiary)
        .textCase(nil)
    }

    private var regionName: String {
        RegionCatalog.region(for: regionID)?.name ?? regionID
    }
}

private struct RouteFavoriteRow: View {
    @Environment(AppState.self) private var app
    let item: RegionalFavoriteRoute

    private var language: AppLanguage { L10n.language }

    var body: some View {
        let favorite = item.favorite
        return HStack(spacing: DesignTokens.Spacing.s + DesignTokens.Spacing.xs) {
            RouteBadge(
                route: favorite.route,
                entry: item.regionID == app.region.id ? app.data.entry(favorite.routeKey) : nil
            )
            VStack(alignment: .leading, spacing: 2) {
                Text("\(L10n.t("route.to")) \(language.isChinese ? L10n.display(favorite.destZh) : favorite.destEn)")
                    .font(DesignTokens.body)
                    .fontWeight(.medium)
                    .lineLimit(1)
                HStack(spacing: DesignTokens.Spacing.xs + 2) {
                    Text(language.isChinese ? L10n.display(favorite.origZh) : favorite.origEn)
                    Text("·")
                    CompanyLogos(
                        co: favorite.co,
                        language: language,
                        height: 13,
                        mode: item.regionID == app.region.id
                            ? app.data.mainlandMetadata(for: favorite.routeKey)?.mode
                            : nil
                    )
                }
                .font(DesignTokens.caption)
                .foregroundStyle(DesignTokens.textSecondary)
                .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, DesignTokens.Spacing.xxs)
    }
}

private struct StopFavoriteRow: View {
    let item: RegionalFavoriteStop

    private var language: AppLanguage { L10n.language }

    var body: some View {
        let favorite = item.favorite
        return HStack(spacing: DesignTokens.Spacing.s) {
            Text(language.isChinese ? L10n.display(favorite.nameZh) : favorite.nameEn)
                .font(DesignTokens.body)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
    }
}
