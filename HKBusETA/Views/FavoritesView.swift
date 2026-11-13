import SwiftUI

/// Nationwide saved routes and stops, grouped by their owning transit region.
struct FavoritesView: View {
    @Environment(AppState.self) private var app
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var navigationPath = NavigationPath()
    @State private var showsStops = false
    var openSearch: (() -> Void)? = nil

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
                if showsStops ? stopSections.isEmpty : routeSections.isEmpty {
                    emptyState
                } else {
                    List {
                        if showsStops { stopList } else { routeList }
                    }.listStyle(.insetGrouped).transitListSurface()
                }
            }
            .background(DesignTokens.background)
            .transitReadableWidth()
            .navigationTitle(L10n.t("favorites.title"))
            .transitRegionSubtitle()
            .toolbar { TransitAppToolbar() }
            .toolbar {
                if #available(iOS 26.0, *) {
                    ToolbarSpacer(.fixed, placement: .primaryAction)
                }
                ToolbarItem(placement: .primaryAction) {
                    EditButton().disabled(showsStops ? stopSections.isEmpty : routeSections.isEmpty)
                        .accessibilityIdentifier("saved.edit")
                }
            }
            .safeAreaInset(edge: .top) {
                kindPicker.frame(maxWidth: 480)
                    .padding(.horizontal, 16).padding(.vertical, 12)
                    .frame(maxWidth: .infinity)
                    .background(DesignTokens.background)
                    .accessibilityIdentifier("saved.kind")
            }
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

    @ViewBuilder private var kindPicker: some View {
        if typeSize.isAccessibilitySize {
            picker.pickerStyle(.menu).controlSize(.large).frame(minHeight: 44)
        } else {
            picker.pickerStyle(.segmented)
        }
    }

    private var picker: some View {
        Picker(L10n.t("favorites.title"), selection: $showsStops) {
            Text(L10n.t("favorites.routes")).tag(false)
            Text(L10n.t("favorites.stops")).tag(true)
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
                                .accessibilityHidden(true)
                        }
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .onDelete { offsets in
                    app.bookmarks.removeFavoriteRoutes(offsets.map { section.items[$0] })
                }
            } header: {
                FavoriteSectionHeader(
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
                                .accessibilityHidden(true)
                        }
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .onDelete { offsets in
                    app.bookmarks.removeFavoriteStops(offsets.map { section.items[$0] })
                }
            } header: {
                FavoriteSectionHeader(
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
        } actions: {
            if let openSearch {
                Button(L10n.t("tab.search"), action: openSearch).buttonStyle(.borderedProminent)
            }
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

/// The segmented control supplies the kind; section headings identify the owning city.
private struct FavoriteSectionHeader: View {
    let regionID: String
    let count: Int

    var body: some View {
        TransitSectionHeading(title: regionName, count: count)
    }

    private var regionName: String {
        RegionCatalog.region(for: regionID)?.localizedName ?? regionID
    }
}

private struct RouteFavoriteRow: View {
    @Environment(AppState.self) private var app
    @Environment(\.dynamicTypeSize) private var typeSize
    let item: RegionalFavoriteRoute

    private var language: AppLanguage { L10n.language }

    var body: some View {
        let favorite = item.favorite
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
            : AnyLayout(HStackLayout(spacing: 12))
        return layout {
            RouteBadge(
                route: favorite.route,
                entry: item.regionID == app.region.id ? app.data.entry(favorite.routeKey) : nil
            )
            VStack(alignment: .leading, spacing: 2) {
                Text("\(L10n.t("route.to")) \(language.isChinese ? L10n.display(favorite.destZh) : favorite.destEn)")
                    .font(DesignTokens.body)
                    .fontWeight(.medium)
                    .fixedSize(horizontal: false, vertical: true)
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
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, DesignTokens.Spacing.s)
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
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }
}
