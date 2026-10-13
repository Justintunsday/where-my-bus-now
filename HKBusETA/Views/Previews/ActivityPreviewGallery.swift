#if DEBUG
import SwiftUI

/// Actual shared activity components. This is a layout inspection tool;
/// the WidgetKit previews render the system's Island and Lock Screen chrome.
struct ActivityPreviewGallery: View {
    var initialScenario: BusArrivalPreview = .normal
    var initialLongRoute = false
    var initialTarget: BusTrackingTarget = .preview
    @State private var scenario: BusArrivalPreview = .normal
    @State private var referenceDate = Date()
    @State private var longRoute = false
    @Environment(\.dynamicTypeSize) private var typeSize

    private var target: BusTrackingTarget {
        var fields = initialTarget
        if longRoute {
            fields = BusTrackingTarget(regionID: "cl-040", providerID: "chelaile", routeKey: "preview-long-route",
                route: "機場快線 A29P", destination: "Hong Kong–Zhuhai–Macao Bridge Port",
                origin: "Tseung Kwan O", serviceType: "1", operators: ["ctb"], directions: ["ctb": "O"],
                stopID: "preview", stopName: "Tseung Kwan O Station Public Transport Interchange",
                stopSequence: 0, lineID: nil, mode: nil, source: nil, language: "en")
        }
        return fields
    }
    private var state: BusArrivalState { BusArrivalPreview.state(scenario, at: referenceDate) }
    private var display: BusActivityDisplay { .init(target: target, state: state, isStale: scenario == .stale) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Picker(L10n.t("tracking.previewState"), selection: $scenario) {
                        ForEach(BusArrivalPreview.allCases) { item in
                            Text(BusActivityCopy.text(item == .normal ? "local" : item.rawValue, language: L10n.language.rawValue))
                                .tag(item)
                        }
                    }.pickerStyle(.menu)
                    Toggle(L10n.t("tracking.previewLongRoute"), isOn: $longRoute)
                    Text(L10n.t("tracking.previewLock")).font(.headline)
                    BusLockScreenView(target: target, state: state, isStale: scenario == .stale)
                        .background(TransitBrand.surface, in: RoundedRectangle(cornerRadius: 24))
                    Text(L10n.t("tracking.previewIsland")).font(.headline)
                    HStack {
                        HStack(spacing: 60) {
                            BusIslandRoute(target: target, compact: true).frame(maxWidth: 60)
                            BusActivityCountdown(target: target, state: state, isStale: scenario == .stale)
                                .font(.headline).frame(maxWidth: 60)
                        }.padding(.horizontal, 14).frame(height: 38)
                            .background(.black, in: Capsule())
                        Spacer(minLength: 8)
                        Image(systemName: display.symbol).foregroundStyle(target.resolvedTheme.islandAccent)
                            .frame(width: 38, height: 38).background(.black, in: Circle())
                    }.foregroundStyle(.white).environment(\.colorScheme, .dark)
                        // Match the finite system compact surface; expanded and
                        // Lock Screen layouts retain the user's full text size.
                        .dynamicTypeSize(...DynamicTypeSize.large)
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .top) {
                            BusIslandRoute(target: target)
                            Spacer(minLength: 12)
                            BusIslandExpandedArrival(display: display)
                        }
                        Text("\(display.copy("to")) \(target.destination)").font(.headline).lineLimit(1)
                        BusIslandExpandedDetails(display: display)
                    }.padding(14).foregroundStyle(.white)
                        .background(.black, in: RoundedRectangle(cornerRadius: 32))
                        .environment(\.colorScheme, .dark)
                    Text(L10n.t("tracking.previewDisclosure")).font(.caption).foregroundStyle(.secondary)
                }.padding(.horizontal, 16).padding(.vertical, 12)
            }
            .background(DesignTokens.background)
            .navigationTitle(L10n.t("tracking.preview")).navigationBarTitleDisplayMode(.inline)
        }
        .onAppear { scenario = initialScenario; longRoute = initialLongRoute }
        .onChange(of: scenario) { _, _ in referenceDate = Date() }
    }
}

#Preview("Activity • All layouts") { TransitPreviewGallery(screen: "activity") }
#Preview("Activity • Dark") { TransitPreviewGallery(screen: "activity").preferredColorScheme(.dark) }
#Preview("Activity • AOD") { TransitPreviewGallery(screen: "activity").preferredColorScheme(.dark).environment(\.previewDimmed, true) }
#Preview("Activity • Large text") { TransitPreviewGallery(screen: "activity").environment(\.dynamicTypeSize, .accessibility3) }
#endif
