import CoreLocation
import MapKit
import SwiftUI

struct NearbyView: View {
    @Environment(AppState.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var stops: [NearbyDisplayStop] = []
    @State private var selection: String?
    @State private var camera: MapCameraPosition = .automatic
    @State private var isLoading = false
    @State private var error: String?

    /// Quantized location prevents tiny GPS movements from launching overlapping network calls.
    private var requestID: String {
        guard let location = app.location.location else { return app.region.id }
        return "\(app.region.id)|\(Int(location.coordinate.latitude * 1000))|\(Int(location.coordinate.longitude * 1000))"
    }

    var body: some View {
        NavigationStack {
            DataGate { content }
                .navigationTitle(L10n.t("nearby.title"))
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
        .onChange(of: app.data.lastLoaded) { Task { await load() } }
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
            VStack(spacing: 0) {
                if !typeSize.isAccessibilitySize, stops.contains(where: { $0.coordinate != nil }) {
                    Map(position: $camera, selection: $selection) {
                        UserAnnotation()
                        ForEach(stops) { stop in
                            if let coordinate = stop.coordinate {
                                Marker(stop.name, systemImage: "bus.fill", coordinate: coordinate).tag(stop.id)
                            }
                        }
                    }
                    .mapControls { MapUserLocationButton(); MapCompass() }
                    .frame(height: 230)
                    .accessibilityLabel(L10n.t("nearby.map"))
                }
                ScrollViewReader { proxy in
                    List {
                        if let error { Section { Label(error, systemImage: "wifi.exclamationmark").font(.caption) } }
                        Section(L10n.t("search.section.stops")) {
                            ForEach(stops) { stop in
                                HStack(spacing: 8) {
                                    Button { select(stop) } label: {
                                        HStack(alignment: .top, spacing: 12) {
                                            Image(systemName: stop.id == selection ? "mappin.circle.fill" : "mappin.circle")
                                                .foregroundStyle(DesignTokens.accent).font(.title3)
                                            VStack(alignment: .leading, spacing: 4) {
                                                Text(stop.name).font(.headline).foregroundStyle(.primary)
                                                    .fixedSize(horizontal: false, vertical: true)
                                                if let subtitle = stop.subtitle {
                                                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                                                }
                                            }
                                            Spacer(minLength: 0)
                                            if let distance = stop.distance {
                                                Text(GeoUtils.distanceString(distance, language: L10n.language))
                                                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                                            }
                                        }.frame(minHeight: 44).contentShape(Rectangle())
                                    }.buttonStyle(.plain)
                                    if app.mainlandProvider != nil {
                                        NavigationLink(value: MainlandStopTarget(stopID: stop.id, namesakeStopID: stop.namesakeID,
                                            title: stop.name, location: stop.location)) { Image(systemName: "arrow.up.right").frame(minWidth: 44, minHeight: 44) }
                                    } else {
                                        NavigationLink(value: StopTarget(stopId: stop.id)) { Image(systemName: "arrow.up.right").frame(minWidth: 44, minHeight: 44) }
                                    }
                                }
                                .accessibilityElement(children: .contain)
                                .accessibilityAddTraits(stop.id == selection ? [.isSelected] : [])
                                .listRowBackground(stop.id == selection ? DesignTokens.accentSoft : DesignTokens.surface)
                                .id(stop.id)
                            }
                        }
                    }
                    .listStyle(.plain)
                    .refreshable { await load() }
                    .onChange(of: selection) { _, id in
                        guard let id else { return }
                        withAnimation(TransitMotion.selection(reduced: reduceMotion)) { proxy.scrollTo(id, anchor: .center) }
                    }
                }
            }
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
        let data = app.data
        let provider = app.mainlandProvider
        let regionID = app.region.id
        isLoading = true
        defer { if regionID == app.region.id { isLoading = false } }
        await data.load()
        do {
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
            guard !Task.isCancelled, regionID == app.region.id else { return }
            stops = result; error = nil
        } catch {
            guard !Task.isCancelled, regionID == app.region.id else { return }
            self.error = MainlandErrorPresentation.message(for: error)
        }
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
