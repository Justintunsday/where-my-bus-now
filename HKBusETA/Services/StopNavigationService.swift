import MapKit
import SwiftUI
import UIKit

enum StopNavigationFailure: Hashable, Sendable {
    case invalidLocation
    case appleMapsUnavailable
    case amapUnavailable

    var localizationKey: String {
        switch self {
        case .invalidLocation:
            return "navigation.invalidLocation"
        case .appleMapsUnavailable:
            return "navigation.openMapFailed"
        case .amapUnavailable:
            return "navigation.amapUnavailable"
        }
    }
}

/// Performs the platform-specific handoff after the pure URL/strategy layer
/// has selected the correct map app for the coordinate reference system.
@MainActor
enum StopNavigationService {
    static func open(
        stopName: String,
        location: StopLocation,
        onFailure: @escaping @MainActor (StopNavigationFailure) -> Void
    ) {
        guard location.isValid else {
            onFailure(.invalidLocation)
            return
        }

        switch StopNavigationURLBuilder.strategy(for: location) {
        case .appleMapsWalking:
            let coordinate = CLLocationCoordinate2D(latitude: location.lat, longitude: location.lng)
            let destination = MKMapItem(placemark: MKPlacemark(coordinate: coordinate))
            destination.name = stopName
            let options: [String: Any] = [
                MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeWalking
            ]
            guard destination.openInMaps(launchOptions: options) else {
                onFailure(.appleMapsUnavailable)
                return
            }

        case .amapWalking:
            guard let url = StopNavigationURLBuilder.makeAMapURL(
                for: location,
                localizedName: stopName
            ) else {
                onFailure(.invalidLocation)
                return
            }
            guard UIApplication.shared.canOpenURL(url) else {
                onFailure(.amapUnavailable)
                return
            }
            UIApplication.shared.open(url, options: [:]) { success in
                guard !success else { return }
                Task { @MainActor in
                    onFailure(.amapUnavailable)
                }
            }
        }
    }
}

/// Shared navigation control used by stop boards and inline route stops.
/// Toolbar symbols keep the system's natural sizing. Inline actions retain an
/// independent 44pt target so a List never hands the entire row to Maps.
struct StopNavigationButton<Label: View>: View {
    let stopName: String
    let location: StopLocation
    let inToolbar: Bool
    let label: () -> Label

    @State private var failure: StopNavigationFailure?

    init(
        stopName: String,
        location: StopLocation,
        inToolbar: Bool = false,
        @ViewBuilder label: @escaping () -> Label
    ) {
        self.stopName = stopName
        self.location = location
        self.inToolbar = inToolbar
        self.label = label
    }

    var body: some View {
        styledButton
            .accessibilityLabel(L10n.t("navigation.navigate"))
            .alert(
                L10n.t("navigation.error.title"),
                isPresented: Binding(
                    get: { failure != nil },
                    set: { if !$0 { failure = nil } }
                ),
                presenting: failure
            ) { _ in
                Button(L10n.t("common.ok"), role: .cancel) { failure = nil }
            } message: { failure in
                Text(L10n.t(failure.localizationKey))
            }
    }

    @ViewBuilder private var styledButton: some View {
        if inToolbar {
            button.transitToolbarControl()
        } else {
            // Explicit style keeps sibling disclosures and arrival links independent.
            button.buttonStyle(.borderless).frame(minWidth: 44, minHeight: 44)
        }
    }

    private var button: some View {
        Button {
            StopNavigationService.open(stopName: stopName, location: location) { failure in
                self.failure = failure
            }
        } label: {
            label()
        }
    }
}
