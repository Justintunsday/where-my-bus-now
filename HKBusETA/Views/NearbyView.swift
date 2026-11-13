import CoreLocation
import MapKit
import SwiftUI

struct NearbyView: View {
    @Environment(AppState.self) private var app
    @Environment(\.transitReduceMotion) private var reduceMotion
    @State private var stops: [NearbyDisplayStop] = []
    @State private var selection: String?
    @State private var camera: MapCameraPosition = .automatic
    @State private var isLoading = false
    @State private var error: String?
    @State private var loadGeneration = 0
    @State private var path = NavigationPath()

    /// Quantized location prevents tiny GPS movements from launching overlapping network calls.
    private var requestID: String {
        let locationID = app.location.location.map {
            "\(Int($0.coordinate.latitude * 1000))|\(Int($0.coordinate.longitude * 1000))"
        } ?? "locating"
        return "\(app.region.id)|\(locationID)|\(app.data.lastLoaded?.timeIntervalSince1970 ?? 0)|\(app.settings.language.rawValue)"
    }

    var body: some View {
        NavigationStack(path: $path) {
            DataGate { content }
                .background(DesignTokens.background)
                .navigationTitle(L10n.t("nearby.title"))
                .navigationBarTitleDisplayMode(.inline)
                .transitRegionSubtitle()
                .toolbar { TransitAppToolbar() }
                .transitDestinations()
                .navigationDestination(for: MainlandStopTarget.self) { target in
                    MainlandStopBoardView(stopID: target.stopID, namesakeStopID: target.namesakeStopID,
                                          title: target.title, location: target.location)
                }
                .navigationDestination(for: MainlandLineTarget.self) { target in
                    MainlandLineLoaderView(lineId: target.lineId, title: target.title, seq: target.seq,
                        modeHint: target.modeHint, origin: target.origin, destination: target.destination,
                        firstDeparture: target.firstDeparture, lastDeparture: target.lastDeparture, fare: target.fare)
                }
        }
        .task(id: requestID) { await load() }
        .task { app.location.startUpdating() }
        .sensoryFeedback(.selection, trigger: selection)
    }

    @ViewBuilder private var content: some View {
        if app.location.isDenied {
            ContentUnavailableView {
                Label(L10n.t("nearby.denied.title"), systemImage: "location.slash")
            } description: { Text(L10n.t("nearby.denied.message")) } actions: {
                Link(L10n.t("nearby.openSettings"), destination: URL(string: UIApplication.openSettingsURLString)!)
            }
        } else if !app.location.isAuthorized {
            ContentUnavailableView {
                Label(L10n.t("nearby.permission.title"), systemImage: "location")
            } description: { Text(L10n.t("nearby.permission.message")) } actions: {
                Button(L10n.t("nearby.permission.button")) { app.location.requestAuthorization() }.buttonStyle(.borderedProminent)
            }
        } else if app.location.location == nil || (isLoading && stops.isEmpty) {
            ProgressView(L10n.t("nearby.locating")).frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if stops.isEmpty {
            ContentUnavailableView {
                Label(L10n.t("nearby.empty"), systemImage: "mappin.slash")
            } description: { Text(error ?? L10n.t("nearby.emptyHint")) } actions: {
                Button(L10n.t("common.retry")) { Task { await load() } }
            }
        } else {
            NearbyStopsContent(stops: stops, error: error, camera: $camera, selection: $selection,
                               select: select, open: open, refresh: load)
        }
    }

    private func open(_ stop: NearbyDisplayStop) {
        if app.mainlandProvider != nil {
            path.append(MainlandStopTarget(stopID: stop.id, namesakeStopID: stop.namesakeID,
                title: stop.name, location: stop.location))
        } else {
            path.append(StopTarget(stopId: stop.id))
        }
    }

    private func select(_ stop: NearbyDisplayStop) {
        withAnimation(TransitMotion.selection(reduced: reduceMotion)) {
            selection = stop.id
            if let coordinate = stop.coordinate {
                camera = .region(MKCoordinateRegion(center: coordinate, span: MKCoordinateSpan(latitudeDelta: 0.006, longitudeDelta: 0.006)))
            }
        }
    }

    private func load() async {
        guard let location = app.location.location else { return }
        loadGeneration += 1
        let generation = loadGeneration
        let data = app.data
        let provider = app.mainlandProvider
        let regionID = app.region.id
        isLoading = true
        defer { if generation == loadGeneration { isLoading = false } }
        do {
            try await data.ensureLoaded()
            let result: [NearbyDisplayStop]
            if let provider {
                result = try await provider.nearby(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude, limit: 20).map {
                    NearbyDisplayStop(id: $0.stopID, namesakeID: $0.namesakeStopID, name: $0.name,
                        subtitle: $0.arrivals.map(\.lineName).joined(separator: " · "),
                        distance: $0.distanceMeters, location: $0.location.map { StopLocation($0) })
                }
            } else {
                result = data.nearestStops(to: location, limit: 30).map {
                    NearbyDisplayStop(id: $0.item.id, namesakeID: nil,
                        name: L10n.language.isChinese ? L10n.display($0.item.nameZh) : $0.item.nameEn,
                        subtitle: "\(data.routeCount(at: $0.item.id)) \(L10n.t("unit.routes"))",
                        distance: $0.distance, location: $0.item.location)
                }
            }
            guard !Task.isCancelled, regionID == app.region.id, generation == loadGeneration else { return }
            stops = result; error = nil
            if let selection, !result.contains(where: { $0.id == selection }) { self.selection = nil }
        } catch {
            guard !Task.isCancelled, regionID == app.region.id, generation == loadGeneration else { return }
            self.error = MainlandErrorPresentation.message(for: error)
        }
    }
}

/// Reflow keeps the map camera, selection and list alive while the window resizes.
private struct NearbyStopsContent: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.transitReduceMotion) private var reduceMotion
    let stops: [NearbyDisplayStop]
    let error: String?
    @Binding var camera: MapCameraPosition
    @Binding var selection: String?
    let select: (NearbyDisplayStop) -> Void
    let open: (NearbyDisplayStop) -> Void
    let refresh: () async -> Void
    @State private var mapSelection: String?

    var body: some View {
        GeometryReader { geometry in
            let hasMap = !typeSize.isAccessibilitySize && stops.contains { $0.coordinate != nil }
            let sideBySide = hasMap && geometry.size.width >= DesignTokens.Layout.mapColumnBreakpoint
            let layout = sideBySide ? AnyLayout(HStackLayout(spacing: 0)) : AnyLayout(VStackLayout(spacing: 0))
            layout {
                if hasMap {
                    map
                        .frame(height: sideBySide ? nil : min(max(geometry.size.height * 0.36, 140), 300))
                        .frame(maxWidth: .infinity, maxHeight: sideBySide ? .infinity : nil)
                }
                stopList
                    .frame(minWidth: sideBySide ? 300 : nil,
                           maxWidth: sideBySide ? DesignTokens.Layout.detailColumnWidth : .infinity)
            }
        }
    }

    private var map: some View {
        Map(position: $camera, selection: Binding(get: { selection }, set: {
            selection = $0
            mapSelection = $0
        })) {
            UserAnnotation()
            ForEach(stops) { stop in
                if let coordinate = stop.coordinate {
                    Marker(stop.name, systemImage: "bus.fill", coordinate: coordinate).tag(stop.id)
                }
            }
        }
        .mapStyle(.standard(pointsOfInterest: .excludingAll))
        .mapControls { MapUserLocationButton(); MapCompass() }
        .tint(DesignTokens.accent)
        .accessibilityLabel(L10n.t("nearby.map"))
    }

    private var stopList: some View {
        ScrollViewReader { proxy in
            List {
                if let error {
                    Section {
                        Label(error, systemImage: "wifi.exclamationmark")
                            .font(.subheadline).foregroundStyle(DesignTokens.warning)
                    }
                }
                Section {
                    ForEach(stops) { stop in
                        NearbyStopRow(stop: stop, isSelected: selection == stop.id, select: {
                            mapSelection = nil
                            if stop.coordinate == nil || typeSize.isAccessibilitySize { open(stop) }
                            else { select(stop) }
                        }, open: { open(stop) })
                        .listRowBackground(selection == stop.id ? DesignTokens.accentSoft : DesignTokens.surface)
                        .id(stop.id)
                    }
                } header: {
                    TransitSectionHeading(title: L10n.t("search.section.stops"), count: stops.count)
                }
            }
            .listStyle(.insetGrouped).transitListSurface()
            .refreshable { await refresh() }
            .onChange(of: mapSelection) { _, id in
                guard let id else { return }
                withAnimation(TransitMotion.selection(reduced: reduceMotion)) { proxy.scrollTo(id, anchor: .center) }
            }
        }
    }
}

private struct NearbyStopRow: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    let stop: NearbyDisplayStop
    let isSelected: Bool
    let select: () -> Void
    let open: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Button(action: select) {
                let layout = typeSize.isAccessibilitySize
                    ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
                    : AnyLayout(HStackLayout(alignment: .top, spacing: 12))
                layout {
                    Image(systemName: isSelected ? "mappin.circle.fill" : "mappin.circle")
                        .font(.title2).foregroundStyle(DesignTokens.accent).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(stop.name).font(.headline).foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                        if let subtitle = stop.subtitle, !subtitle.isEmpty {
                            Text(subtitle).font(.caption).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        if let distance = stop.distance {
                            Text(GeoUtils.distanceString(distance, language: L10n.language))
                                .font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("nearby.stop.\(stop.id)")
            .accessibilityAddTraits(isSelected ? [.isSelected] : [])
            Button(action: open) {
                Label(L10n.t("route.fullEta"), systemImage: "arrow.up.right")
            }
            .transitInlineIconControl().tint(DesignTokens.action)
            .accessibilityLabel("\(L10n.t("route.fullEta")) · \(stop.name)")
            .accessibilityIdentifier("nearby.open.\(stop.id)")
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .contain)
    }
}

private struct NearbyDisplayStop: Identifiable {
    let id: String
    let namesakeID: String?
    let name: String
    let subtitle: String?
    let distance: Double?
    let location: StopLocation?
    var coordinate: CLLocationCoordinate2D? {
        guard let location, location.isValid, location.coordinateSystem == .wgs84 else { return nil }
        return CLLocationCoordinate2D(latitude: location.lat, longitude: location.lng)
    }
}
