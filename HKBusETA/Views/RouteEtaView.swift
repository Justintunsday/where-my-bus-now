import SwiftUI

struct RouteEtaView: View {
    @Environment(AppState.self) private var app
    let routeKey: String
    let seq: Int

    var body: some View {
        DataGate {
            if let target = BusTrackingTarget(app: app, routeKey: routeKey, seq: seq),
               let session = app.arrivals.session(for: target, app: app), let entry = app.data.entry(routeKey) {
                ArrivalScreen(entry: entry, target: target, session: session)
            } else { ContentUnavailableView(L10n.t("route.notFound"), systemImage: "questionmark.circle") }
        }
    }
}

struct ArrivalScreen: View {
    @Environment(AppState.self) private var app
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.transitReduceMotion) private var reduceMotion
    let entry: RouteEntry
    let target: BusTrackingTarget
    let session: ArrivalSession
    @State private var showsTracking = false
    @AccessibilityFocusState private var trackingFocused: Bool

    private var realtimeAllowed: Bool {
        MainlandRealtimePolicy.allowsRequest(modeHint: target.mode.flatMap(MainlandTransitMode.init(rawValue:)))
    }

    private var theme: RouteTheme { target.resolvedTheme }
    private var isPinned: Bool { app.boarding.targets.contains { $0.id == target.id } }
    private var isFavorite: Bool { app.bookmarks.isFavoriteRoute(target.routeKey) }

    var body: some View {
        List {
            Section {
                RouteDepartureBoard(entry: entry, target: target, session: session, realtimeAllowed: realtimeAllowed)
                    .listRowInsets(EdgeInsets(top: 14, leading: 16, bottom: 10, trailing: 16))
                if realtimeAllowed {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 12) { trackingAction; pinAction }
                        VStack(alignment: .leading, spacing: 8) { trackingAction; pinAction }
                    }
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 12, trailing: 16))
                    .listRowSeparator(.hidden)
                }
            }
            Section(L10n.t("arrival.journey")) {
                NavigationLink(value: RouteDetailTarget(routeKey: target.routeKey)) {
                    Label(L10n.t("route.section.stops"), systemImage: "point.topleft.down.curvedto.point.bottomright.up")
                }
                if let metadata = app.data.mainlandMetadata(for: target.routeKey) {
                    MainlandRouteOverview(metadata: metadata)
                } else {
                    if let hours = app.provider.serviceHoursToday(entry: entry, db: app.data.db ?? .empty, at: Date()) {
                        Label(hours, systemImage: "clock")
                    }
                    if let fare = app.provider.fare(entry: entry, at: target.stopSequence, db: app.data.db ?? .empty, at: Date()) {
                        LabeledContent(L10n.t("route.fare"), value: "$\(fare)")
                    }
                }
            }
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--eta-motion-test") {
                Button("Revise fixture ETA") {
                    withAnimation(.spring()) {
                        session.seed(etas: [180, 540].map { seconds in
                            Eta(eta: RegionClock.isoString(from: Date().addingTimeInterval(Double(seconds))),
                                remark: Terminal(en: "", zh: ""), dest: entry.dest, co: entry.co.first ?? "kmb")
                        }, updatedAt: Date())
                    }
                }.accessibilityIdentifier("eta.test.revise")
            }
            #endif
        }
        .listStyle(.insetGrouped).transitListSurface()
        .environment(\.routeTheme, theme).tint(theme.accent)
        .navigationTitle(target.route).navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button { Task { await refresh() } } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(session.isRefreshing).accessibilityLabel(L10n.t("common.retry"))
                .accessibilityIdentifier("eta.refresh")
                Button {
                    app.bookmarks.toggleFavoriteRoute(entry: entry, routeKey: target.routeKey, modeRawValue: target.mode)
                } label: {
                    Image(systemName: isFavorite ? "star.fill" : "star")
                }
                .accessibilityLabel(L10n.t(isFavorite ? "common.unfavorite" : "common.favorite"))
                .accessibilityIdentifier("eta.favorite")
            }
        }
        .refreshable { await refresh() }
        .sheet(isPresented: $showsTracking, onDismiss: { trackingFocused = true }) {
            TrackingSheet(target: target, session: session)
                .environment(\.routeTheme, theme).tint(theme.accent)
                .presentationDetents([.medium, .large]).presentationDragIndicator(.visible)
        }
        .task(id: "\(target.id)|\(target.language)|\(scenePhase)") {
            guard scenePhase == .active else { return }
            if let stop = app.data.stop(target.stopID) {
                app.bookmarks.recordRecentRoute(entry: entry, routeKey: target.routeKey, stopId: target.stopID,
                    seq: target.stopSequence, stopName: stop.name, modeRawValue: target.mode)
            }
            guard realtimeAllowed else { return }
            while !Task.isCancelled {
                await session.refresh()
                do { try await Task.sleep(for: .seconds(30)) } catch { break }
            }
        }
    }

    private var trackingAction: some View {
        Button { showsTracking = true } label: {
            Label(L10n.t(app.activities.isTracking(target) ? "arrival.trackingActive" : "tracking.start"),
                  systemImage: app.activities.isTracking(target) ? "checkmark.circle.fill" : "wave.3.right.circle")
                .font(.subheadline.weight(.semibold))
                .padding(.vertical, 4)
        }
        .transitPrimaryAction().controlSize(.regular)
        .foregroundStyle(theme.onAccent)
        .accessibilityIdentifier("tracking.open").accessibilityFocused($trackingFocused)
    }

    private var pinAction: some View {
        Button {
            if isPinned { app.boarding.remove(target) }
            else { app.boarding.save(target) }
        } label: {
            Label(L10n.t(isPinned ? "boarding.saved" : "boarding.save"), systemImage: isPinned ? "pin.fill" : "pin")
                .font(.subheadline).padding(.vertical, 4)
        }
        .buttonStyle(.borderless).frame(minHeight: 44)
        .accessibilityIdentifier("eta.pin")
        .accessibilityValue(L10n.t(isPinned ? "common.selected" : "common.notSelected"))
        .sensoryFeedback(.selection, trigger: isPinned)
    }

    private func refresh() async {
        await session.refresh(force: true)
        await app.activities.refreshActive(app: app)
    }
}

struct ArrivalSlot: Identifiable {
    let id: String
    let eta: Eta
    static func make(_ etas: [Eta]) -> [Self] {
        var counts: [String: Int] = [:]
        return etas.map { eta in
            let key = "\(eta.co)|\(eta.dest.en)"
            let slot = counts[key, default: 0]
            counts[key] = slot + 1
            return Self(id: "\(key)|\(slot)", eta: eta)
        }
    }
}
