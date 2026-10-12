import SwiftUI

enum TransitSheet: String, Identifiable {
    case settings, region
    var id: String { rawValue }
}

struct TransitAppToolbar: ToolbarContent {
    @Environment(AppState.self) private var app
    var body: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button { app.presentation = .region } label: {
                Label(app.region.name, systemImage: "location.circle")
                    .font(.subheadline.weight(.medium))
            }
            .accessibilityLabel("\(L10n.t("settings.region")) \(app.region.name)")
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button { app.presentation = .settings } label: { Image(systemName: "person.crop.circle").frame(minWidth: 44, minHeight: 44) }
                .accessibilityLabel(L10n.t("settings.title"))
        }
    }
}

struct TransitDestinations: ViewModifier {
    func body(content: Content) -> some View {
        content
            .navigationDestination(for: RouteDetailTarget.self) { RouteDetailView(routeKey: $0.routeKey) }
            .navigationDestination(for: RouteEtaTarget.self) { RouteEtaView(routeKey: $0.routeKey, seq: $0.seq) }
            .navigationDestination(for: StopTarget.self) { StopEtaView(stopId: $0.stopId) }
            .navigationDestination(for: SavedRouteTarget.self) { SavedRouteDestination(target: $0) }
            .navigationDestination(for: SavedStopTarget.self) { SavedStopDestination(target: $0) }
            .navigationDestination(for: BusTrackingTarget.self) { TrackingDestination(target: $0) }
    }
}

extension View {
    func transitDestinations() -> some View { modifier(TransitDestinations()) }
}

struct TrackingDestination: View {
    @Environment(AppState.self) private var app
    let target: BusTrackingTarget
    @State private var ready = false
    @State private var error: String?

    var body: some View {
        Group {
            if let error { ContentUnavailableView(error, systemImage: "exclamationmark.triangle") }
            else if ready { RouteEtaView(routeKey: target.routeKey, seq: target.stopSequence) }
            else { ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity) }
        }
        .task(id: target.id) {
            guard RegionCatalog.region(for: target.regionID) != nil else { error = L10n.t("tracking.identityChanged"); return }
            app.openSavedRegion(target.regionID)
            await app.data.load()
            do {
                if app.data.entry(target.routeKey) == nil, let provider = app.mainlandProvider, let lineID = target.lineID,
                   let payload = try await provider.linePayload(lineID: lineID, modeHint: target.mode.flatMap(MainlandTransitMode.init(rawValue:)) ?? .bus),
                   let shared = MainlandRouteAdapter.makeSharedRoute(from: payload) {
                    guard !Task.isCancelled else { return }
                    app.data.registerSynthetic(entry: shared.entry, stops: shared.stops, mainlandMetadata: shared.metadata)
                }
                guard !Task.isCancelled else { return }
                guard let entry = app.data.entry(target.routeKey),
                      target.matches(entry: entry, providerID: app.provider.id,
                                     source: app.data.mainlandMetadata(for: target.routeKey)?.source.rawValue)
                else { error = L10n.t("tracking.identityChanged"); return }
                ready = true
            } catch { self.error = MainlandErrorPresentation.message(for: error) }
        }
    }
}
