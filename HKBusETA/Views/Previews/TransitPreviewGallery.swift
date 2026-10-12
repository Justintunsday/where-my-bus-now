#if DEBUG
import SwiftUI

/// Isolated fixture storage and provider data: never touches production bookmarks or APIs.
@MainActor enum TransitPreviewData {
    static let entry = RouteEntry(route: "1A", co: ["kmb"],
        orig: Terminal(en: "Star Ferry", zh: "尖沙咀碼頭"), dest: Terminal(en: "Sau Mau Ping (Central)", zh: "秀茂坪（中）"),
        fares: ["7.2", "7.2", "7.2", "7.2"], faresHoliday: nil, freq: nil, jt: FlexibleString("65"),
        seq: 4, serviceType: FlexibleString("1"), stops: ["kmb": ["p1", "p2", "p3", "p4"]],
        bound: ["kmb": "O"], gtfsId: nil, nlbId: nil)

    static func app(empty: Bool = false, failure: Bool = false) -> AppState {
        let suite = "busnow.preview.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.set("hk", forKey: "settings.regionID")
        let arguments = ProcessInfo.processInfo.arguments
        let languageIndex = arguments.firstIndex(of: "--snapshot-language")
        let language = languageIndex.flatMap { arguments.indices.contains($0 + 1) ? arguments[$0 + 1] : nil } ?? "zh"
        defaults.set(language, forKey: "settings.language")
        let app = AppState(defaults: defaults, bookmarkURL: FileManager.default.temporaryDirectory
            .appendingPathComponent("\(suite).json"))
        let names = [Terminal(en: "Star Ferry", zh: "尖沙咀碼頭"), Terminal(en: "Middle Road", zh: "中間道"),
                     Terminal(en: "Nathan Road", zh: "彌敦道"), Terminal(en: "Jordan Station", zh: "佐敦站")]
        let stops = Dictionary(uniqueKeysWithValues: names.enumerated().map { index, name in
            ("p\(index + 1)", StopEntry(location: StopLocation(lat: 22.294 + Double(index) * 0.003, lng: 114.172), name: name))
        })
        app.data.installPreviewDatabase(EtaDB(holidays: [], routeList: [entry.routeKey: entry], stopList: stops,
                                             stopMap: [:], serviceDayMap: [:]))
        app.location.seedPreviewLocation()
        if !empty {
            app.bookmarks.toggleFavoriteRoute(entry: entry, routeKey: entry.routeKey)
            if let target = BusTrackingTarget(app: app, routeKey: entry.routeKey, seq: 2),
               let session = app.arrivals.session(for: target, app: app) {
                app.boarding.save(target)
                session.seed(etas: [420, 780, 1260].map { seconds in
                    Eta(eta: RegionClock.isoString(from: Date().addingTimeInterval(Double(seconds))),
                        remark: Terminal(en: "", zh: ""), dest: entry.dest, co: "kmb")
                }, updatedAt: Date(), error: failure ? L10n.t("arrival.networkError") : nil)
                if let stop = stops["p3"] {
                    app.bookmarks.recordRecentRoute(entry: entry, routeKey: entry.routeKey, stopId: "p3", seq: 2, stopName: stop.name)
                    app.bookmarks.recordRecentStop(id: "p3", name: stop.name, location: stop.location)
                }
            }
        }
        // Export only isolated fixtures for the CI before/after comparison.
        if let db = app.data.db, let encoded = try? JSONEncoder().encode(db) {
            try? encoded.write(to: FileManager.default.temporaryDirectory.appendingPathComponent("bus-snapshot-db.json"))
        }
        if let bookmarks = try? Data(contentsOf: FileManager.default.temporaryDirectory.appendingPathComponent("\(suite).json")) {
            try? bookmarks.write(to: FileManager.default.temporaryDirectory.appendingPathComponent("bus-snapshot-bookmarks.json"))
        }
        return app
    }
}

struct TransitPreviewGallery: View {
    @Environment(\.previewReducedEffects) private var inheritedReducedEffects
    let screen: String
    @State private var app: AppState
    init(screen: String) {
        self.screen = screen
        _app = State(initialValue: TransitPreviewData.app(empty: screen == "empty", failure: screen == "error"))
    }

    var body: some View {
        Group {
            switch screen {
            case "route": NavigationStack { RouteDetailView(routeKey: TransitPreviewData.entry.routeKey).transitDestinations() }
            case "eta", "error": NavigationStack { RouteEtaView(routeKey: TransitPreviewData.entry.routeKey, seq: 2).transitDestinations() }
            case "search": SearchView()
            case "nearby": NearbyView()
            case "stop": NavigationStack { StopEtaView(stopId: "p3").transitDestinations() }
            case "saved": FavoritesView()
            case "settings": SettingsView()
            case "region": RegionPickerView()
            case "activity", "activity-stale":
                VStack(spacing: 24) {
                    Text(L10n.t("tracking.preview")).font(.title2.bold())
                    BusLockScreenView(target: .preview, state: .preview, isStale: screen == "activity-stale")
                        .background(DesignTokens.surface, in: RoundedRectangle(cornerRadius: 24))
                    Text(L10n.t("tracking.foregroundNotice")).font(.caption).foregroundStyle(.secondary)
                }.padding(24).frame(maxHeight: .infinity).background(DesignTokens.background)
            default: RootView()
            }
        }
        .environment(app).environment(\.locale, app.settings.language.locale)
        .tint(DesignTokens.accent)
        .environment(\.previewReducedEffects, inheritedReducedEffects || ProcessInfo.processInfo.arguments.contains("--reduce-effects"))

    }
}

#Preview("Today") { TransitPreviewGallery(screen: "home") }
#Preview("Route • Dark") { TransitPreviewGallery(screen: "route").preferredColorScheme(.dark) }
#Preview("ETA • Accessibility") { TransitPreviewGallery(screen: "eta").environment(\.dynamicTypeSize, .accessibility3) }
#Preview("Empty") { TransitPreviewGallery(screen: "empty") }
#Preview("Network error") { TransitPreviewGallery(screen: "error") }
#Preview("Reduced effects") {
    TransitPreviewGallery(screen: "home").environment(\.previewReducedEffects, true)
}
#Preview("Lock Screen • Stale") { TransitPreviewGallery(screen: "activity-stale") }
#endif
