import SwiftUI

struct RouteDetailView: View {
    @Environment(AppState.self) private var app
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.transitReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    let routeKey: String
    @State private var selectedSeq: Int?
    @State private var mapSelection: Int?

    var body: some View {
        DataGate {
            if let entry = app.data.entry(routeKey) {
                let points = makePoints(entry)
                Group {
                    if sizeClass == .regular, !typeSize.isAccessibilitySize {
                        HStack(spacing: 0) {
                            map(entry, points: points).frame(maxWidth: .infinity, maxHeight: .infinity)
                            timeline(entry, points: points).frame(minWidth: 340, idealWidth: 420, maxWidth: 480)
                        }
                    } else {
                        VStack(spacing: 0) {
                            if !typeSize.isAccessibilitySize {
                                map(entry, points: points).frame(height: 240)
                            }
                            timeline(entry, points: points)
                        }
                    }
                }
                .background(DesignTokens.background)
                .navigationTitle(entry.route).navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    if let opposite = app.data.oppositeEntry(for: entry) {
                        ToolbarItem(placement: .topBarTrailing) {
                            NavigationLink(value: RouteDetailTarget(routeKey: opposite.key)) {
                                Image(systemName: "arrow.left.arrow.right").frame(minWidth: 44, minHeight: 44)
                            }.accessibilityLabel(L10n.t("route.reverse"))
                                .transitCircularToolbarControl()
                        }
                        .transitIndependentToolbarItem()
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        FavoriteRouteButton(routeKey: routeKey, entry: entry)
                    }
                    .transitIndependentToolbarItem()
                }
                .sensoryFeedback(.selection, trigger: selectedSeq)
                .environment(\.routeTheme, RouteTheme.resolve(route: entry.route, operators: entry.co, providerHex: app.provider.routeColorHex(entry: entry)))
                .tint(RouteTheme.resolve(route: entry.route, operators: entry.co, providerHex: app.provider.routeColorHex(entry: entry)).accent)
            } else { ContentUnavailableView(L10n.t("route.notFound"), systemImage: "questionmark.circle") }
        }
    }

    @ViewBuilder private func map(_ entry: RouteEntry, points: [RouteStopPoint]) -> some View {
        if points.contains(where: { $0.coordinate != nil }) {
            RouteMapSection(entry: entry, points: points, selectedSeq: Binding(
                get: { selectedSeq }, set: { selectedSeq = $0; mapSelection = $0 }))
                .accessibilityLabel(L10n.t("route.map"))
        } else {
            ContentUnavailableView(L10n.t("route.mapUnavailable"), systemImage: "map")
        }
    }

    private func timeline(_ entry: RouteEntry, points: [RouteStopPoint]) -> some View {
        ScrollViewReader { proxy in
            List {
                Section {
                    RouteIdentityHeader(entry: entry)
                    if let metadata = app.data.mainlandMetadata(for: routeKey) { MainlandRouteOverview(metadata: metadata) }
                    else { serviceSummary(entry) }
                }
                Section {
                    ForEach(points) { point in
                        StopTimelineRow(point: point, isLast: point.seq == points.last?.seq,
                            isSelected: selectedSeq == point.seq, isExpanded: selectedSeq == point.seq) {
                                mapSelection = nil
                                withAnimation(TransitMotion.selection(reduced: reduceMotion)) {
                                    selectedSeq = selectedSeq == point.seq ? nil : point.seq
                                }
                            }
                            .id(point.seq)
                            .listRowSeparator(.hidden)
                        if selectedSeq == point.seq {
                            // Keep navigation in a separate List row: iOS 17 otherwise
                            // promotes an inline link into the station header's tap area.
                            HStack(alignment: .top, spacing: 16) {
                                Rectangle().fill(point.seq == points.last?.seq ? Color.clear : DesignTokens.divider)
                                    .frame(width: 2).frame(width: 24)
                                StopEtaInlineView(entry: entry, seq: point.seq)
                            }
                            .listRowSeparator(.hidden)
                            .buttonStyle(.borderless)
                        }
                    }
                } header: {
                    Text("\(L10n.t("route.section.stops")) · \(points.count)")
                } footer: { Text(L10n.t("boarding.timelineHint")) }
            }
            .listStyle(.insetGrouped)
            .transitListSurface()
            .onChange(of: mapSelection) { _, seq in
                guard let seq else { return }
                withAnimation(TransitMotion.selection(reduced: reduceMotion)) { proxy.scrollTo(seq, anchor: .center) }
            }
        }
    }

    private func serviceSummary(_ entry: RouteEntry) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let hours = app.provider.serviceHoursToday(entry: entry, db: app.data.db ?? .empty, at: Date()) {
                Label(hours, systemImage: "clock")
            }
            if let headway = app.provider.currentHeadway(entry: entry, db: app.data.db ?? .empty, at: Date()) {
                Label("\(L10n.t("route.every")) \(max(headway / 60, 1)) \(L10n.t("unit.minutes"))", systemImage: "timer")
            }
            if let journey = entry.journeyTimeMinutes {
                Label("\(journey) \(L10n.t("unit.minutes"))", systemImage: "hourglass")
            }
        }.font(.subheadline).foregroundStyle(.secondary)
    }

    private func makePoints(_ entry: RouteEntry) -> [RouteStopPoint] {
        entry.canonicalStops.enumerated().map { seq, id in
            let stop = app.data.stop(id)
            return RouteStopPoint(seq: seq, stopId: id, nameZh: stop?.name.zh ?? id, nameEn: stop?.name.en ?? id,
                lat: stop?.location.coordinateSystem == .wgs84 ? stop?.location.lat : nil,
                lng: stop?.location.coordinateSystem == .wgs84 ? stop?.location.lng : nil)
        }
    }
}
