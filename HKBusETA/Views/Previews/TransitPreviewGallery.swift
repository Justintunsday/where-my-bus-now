#if DEBUG
import SwiftUI

/// Isolated fixture storage and provider data: never touches production bookmarks or APIs.
@MainActor enum TransitPreviewData {
    static let entry = RouteEntry(route: "1A", co: ["kmb"],
        orig: Terminal(en: "Star Ferry", zh: "尖沙咀碼頭"), dest: Terminal(en: "Sau Mau Ping (Central)", zh: "秀茂坪（中）"),
        fares: ["7.2", "7.2", "7.2", "7.2"], faresHoliday: nil, freq: nil, jt: FlexibleString("65"),
        seq: 4, serviceType: FlexibleString("1"), stops: ["kmb": ["p1", "p2", "p3", "p4"]],
        bound: ["kmb": "O"], gtfsId: nil, nlbId: nil)

    static func entry(for sample: String?) -> RouteEntry {
        guard let sample else { return entry }
        let rail = sample == "eal" || sample == "twl"
        let route = sample == "eal" ? "EAL" : (sample == "twl" ? "TWL" : (sample == "ctb" ? "A21" : "3M"))
        let op = rail ? "mtr" : (sample == "ctb" ? "ctb" : "nlb")
        return RouteEntry(route: route, co: [op],
            orig: Terminal(en: sample == "eal" ? "Lo Wu" : (sample == "twl" ? "Tsuen Wan" : (sample == "nlb" ? "Tung Chung" : "Airport")), zh: sample == "eal" ? "羅湖" : (sample == "twl" ? "荃灣" : (sample == "nlb" ? "東涌" : "機場"))),
            dest: Terminal(en: sample == "eal" ? "Admiralty" : (sample == "twl" ? "Central" : (sample == "nlb" ? "Mui Wo" : "Hung Hom Station")), zh: sample == "eal" ? "金鐘" : (sample == "twl" ? "中環" : (sample == "nlb" ? "梅窩" : "紅磡站"))),
            fares: ["7.2", "7.2", "7.2", "7.2"], faresHoliday: nil, freq: nil, jt: FlexibleString("45"),
            seq: 4, serviceType: FlexibleString("1"), stops: [op: ["p1", "p2", "p3", "p4"]],
            bound: [op: rail ? "DT" : "O"], gtfsId: nil, nlbId: nil)
    }

    static func sample(in screen: String) -> String? {
        ["eal", "twl", "ctb", "nlb"].first { screen.hasSuffix("-" + $0) }
    }

    static func app(empty: Bool = false, failure: Bool = false, sample: String? = nil, loading: Bool = false) -> AppState {
        let entry = entry(for: sample)
        let suite = "busnow.preview.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.set("hk", forKey: "settings.regionID")
        let arguments = ProcessInfo.processInfo.arguments
        let languageIndex = arguments.firstIndex(of: "--snapshot-language")
        let language = languageIndex.flatMap { arguments.indices.contains($0 + 1) ? arguments[$0 + 1] : nil } ?? "zh"
        defaults.set(language, forKey: "settings.language")
        let app = AppState(defaults: defaults, bookmarkURL: FileManager.default.temporaryDirectory
            .appendingPathComponent("\(suite).json"))
        var names = [Terminal(en: "Star Ferry", zh: "尖沙咀碼頭"), Terminal(en: "Middle Road", zh: "中間道"),
                     Terminal(en: "Nathan Road", zh: "彌敦道"), Terminal(en: "Jordan Station", zh: "佐敦站")]
        if sample == "eal" {
            names = [Terminal(en: "Lo Wu", zh: "羅湖"), Terminal(en: "Mong Kok East", zh: "旺角東"),
                     Terminal(en: "Hung Hom", zh: "紅磡"), Terminal(en: "Admiralty", zh: "金鐘")]
        } else if sample == "twl" {
            names = [Terminal(en: "Tsuen Wan", zh: "荃灣"), Terminal(en: "Mong Kok", zh: "旺角"),
                     Terminal(en: "Tsim Sha Tsui", zh: "尖沙咀"), Terminal(en: "Central", zh: "中環")]
        }
        let stops = Dictionary(uniqueKeysWithValues: names.enumerated().map { index, name in
            ("p\(index + 1)", StopEntry(location: StopLocation(lat: 22.294 + Double(index) * 0.003, lng: 114.172), name: name))
        })
        app.data.installPreviewDatabase(EtaDB(holidays: [], routeList: [entry.routeKey: entry], stopList: stops,
                                             stopMap: [:], serviceDayMap: [:]))
        app.location.seedPreviewLocation()
        if !empty && !loading {
            app.bookmarks.toggleFavoriteRoute(entry: entry, routeKey: entry.routeKey)
            if let target = BusTrackingTarget(app: app, routeKey: entry.routeKey, seq: 2),
               let session = app.arrivals.session(for: target, app: app) {
                app.boarding.save(target)
                session.seed(etas: [420, 780, 1260].map { seconds in
                    Eta(eta: RegionClock.isoString(from: Date().addingTimeInterval(Double(seconds))),
                        remark: Terminal(en: seconds == 1260 ? "Scheduled" : "", zh: seconds == 1260 ? "預定班次" : ""), dest: entry.dest, co: entry.co.first ?? "kmb")
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
        _app = State(initialValue: TransitPreviewData.app(empty: screen == "empty", failure: screen == "error",
            sample: TransitPreviewData.sample(in: screen), loading: screen == "loading"))
    }

    var body: some View {
        Group {
            switch screen {
            case "route": NavigationStack { RouteDetailView(routeKey: TransitPreviewData.entry.routeKey).transitDestinations() }
            case "eta", "error", "loading", "eta-eal", "eta-twl", "eta-ctb", "eta-nlb":
                NavigationStack { RouteEtaView(routeKey: TransitPreviewData.entry(for: TransitPreviewData.sample(in: screen)).routeKey, seq: 2).transitDestinations() }
            case "search": SearchView()
            case "search-results": SearchView(initialQuery: "1A")
            case "nearby": NearbyView()
            case "stop": NavigationStack { StopEtaView(stopId: "p3").transitDestinations() }
            case "saved": FavoritesView()
            case "settings": SettingsView()
            case "region": RegionPickerView()
            case let value where value.hasPrefix("activity"):
                ActivityPreviewGallery(initialScenario: BusArrivalPreview(rawValue: String(value.dropFirst("activity-".count))) ?? .normal,
                                       initialLongRoute: value == "activity-long",
                    initialTarget: BusTrackingTarget(app: app, routeKey: TransitPreviewData.entry(for: TransitPreviewData.sample(in: screen)).routeKey, seq: 2) ?? .preview)
            default: RootView()
            }
        }
        .environment(app).environment(\.locale, app.settings.language.locale)
        .environment(\.timeZone, app.region.timeZone)
        .tint(DesignTokens.accent)
        .environment(\.previewReducedEffects, inheritedReducedEffects || ProcessInfo.processInfo.arguments.contains("--reduce-effects"))
        .environment(\.previewDimmed, ProcessInfo.processInfo.arguments.contains("--dimmed"))
        .task {
            // Debug-only render readiness for CI; screenshot capture waits instead of guessing startup time.
            await Task.yield()
            try? await Task.sleep(for: .seconds(1))
            try? Data(screen.utf8).write(to: FileManager.default.temporaryDirectory.appendingPathComponent("bus-snapshot-ready"))
        }
    }
}

#Preview("EAL • Light") { TransitPreviewGallery(screen: "eta-eal") }
#Preview("EAL • Dark") { TransitPreviewGallery(screen: "eta-eal").preferredColorScheme(.dark) }
#Preview("TWL • Red") { TransitPreviewGallery(screen: "eta-twl") }
#Preview("Citybus • Yellow") { TransitPreviewGallery(screen: "eta-ctb") }
#Preview("NLB • Teal") { TransitPreviewGallery(screen: "eta-nlb") }
#Preview("EAL • Activity") { TransitPreviewGallery(screen: "activity-eal") }
#Preview("Citybus • Activity dark") { TransitPreviewGallery(screen: "activity-ctb").preferredColorScheme(.dark) }
#Preview("Today") { TransitPreviewGallery(screen: "home") }
#Preview("Route • Dark") { TransitPreviewGallery(screen: "route").preferredColorScheme(.dark) }
#Preview("ETA • Accessibility") { TransitPreviewGallery(screen: "eta").environment(\.dynamicTypeSize, .accessibility3) }
#Preview("Empty") { TransitPreviewGallery(screen: "empty") }
#Preview("Network error") { TransitPreviewGallery(screen: "error") }
#Preview("ETA loading") { TransitPreviewGallery(screen: "loading") }
#Preview("Search results") { TransitPreviewGallery(screen: "search-results") }
#Preview("Reduced effects") {
    TransitPreviewGallery(screen: "home").environment(\.previewReducedEffects, true)
}
#Preview("Lock Screen • Stale") { TransitPreviewGallery(screen: "activity-stale") }
#endif
