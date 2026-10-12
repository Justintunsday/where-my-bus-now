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
/// The minimum frame keeps the tappable target at least 44 points in both
/// toolbar and inline action layouts.
struct StopNavigationButton<Label: View>: View {
    let stopName: String
    let location: StopLocation
    let label: () -> Label

    @State private var failure: StopNavigationFailure?

    init(
        stopName: String,
        location: StopLocation,
        @ViewBuilder label: @escaping () -> Label
    ) {
        self.stopName = stopName
        self.location = location
        self.label = label
    }

    var body: some View {
        Button {
            StopNavigationService.open(stopName: stopName, location: location) { failure in
                self.failure = failure
            }
        } label: {
            label()
        }
        // List's automatic button style otherwise hands the entire row to Maps,
        // including sibling controls such as the station disclosure button.
        .buttonStyle(.plain)
        .frame(minWidth: 44, minHeight: 44)
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
}
