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

    private var realtimeAllowed: Bool {
        MainlandRealtimePolicy.allowsRequest(modeHint: target.mode.flatMap(MainlandTransitMode.init(rawValue:)))
    }

    var body: some View {
        List {
            Section { RouteIdentityHeader(entry: entry, stopName: target.stopName) }
            Section {
                if !realtimeAllowed { Label(L10n.t("mainland.metroNoRealtime"), systemImage: "tram.fill") }
                else if session.updatedAt == nil && session.error == nil {
                    HStack { ProgressView(); Text(L10n.t("status.loading")).foregroundStyle(.secondary) }.padding(.vertical, 24)
                } else { ArrivalHero(state: session.activityState) }
            }
            if !session.etas.isEmpty {
                Section(L10n.t("arrival.upcoming")) {
                    ForEach(ArrivalSlot.make(session.etas)) { slot in
                        ETALineView(eta: slot.eta, language: L10n.language,
                            format: app.settings.etaFormat, annotateScheduled: app.settings.annotateScheduled,
                            highlight: false, showCompany: entry.co.count > 1).padding(.vertical, 8)
                    }
                }
            }
            if realtimeAllowed {
                Section {
                    Button { showsTracking = true } label: {
                        Label(L10n.t(app.activities.isTracking(target) ? "tracking.manage" : "tracking.start"),
                              systemImage: "wave.3.right.circle.fill").frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .transitPrimaryAction().listRowBackground(Color.clear).listRowInsets(EdgeInsets())
                    .accessibilityIdentifier("tracking.open")
                    Button {
                        if !app.bookmarks.isFavoriteRoute(target.routeKey) {
                            app.bookmarks.toggleFavoriteRoute(entry: entry, routeKey: target.routeKey, modeRawValue: target.mode)
                        }
                        app.boarding.save(target)
                    } label: {
                        Label(L10n.t(app.boarding.targets.contains { $0.id == target.id } ? "boarding.saved" : "boarding.save"),
                              systemImage: "pin.fill").frame(minHeight: 44)
                    }
                    .sensoryFeedback(.success, trigger: app.boarding.targets.contains { $0.id == target.id })
                }
            }
            if let metadata = app.data.mainlandMetadata(for: target.routeKey) {
                Section { MainlandRouteOverview(metadata: metadata) }
            } else {
                Section {
                    if let hours = app.provider.serviceHoursToday(entry: entry, db: app.data.db ?? .empty, at: Date()) {
                        Label(hours, systemImage: "clock")
                    }
                    if let fare = app.provider.fare(entry: entry, at: target.stopSequence, db: app.data.db ?? .empty, at: Date()) {
                        LabeledContent(L10n.t("route.fare"), value: "$\(fare)")
                    }
                    NavigationLink(value: RouteDetailTarget(routeKey: target.routeKey)) {
                        Label(L10n.t("route.section.stops"), systemImage: "point.topleft.down.curvedto.point.bottomright.up")
                    }
                }
            }
            Section { FreshnessLabel(updatedAt: session.updatedAt, error: session.error) }.listRowBackground(Color.clear)
        }
        .listStyle(.insetGrouped)
        .navigationTitle(target.route).navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button { Task { await refresh() } } label: {
                    Image(systemName: "arrow.clockwise").symbolEffect(.bounce, value: session.updatedAt)
                        .symbolEffectsRemoved(reduceMotion).frame(minWidth: 44, minHeight: 44)
                }
                .disabled(session.isRefreshing).accessibilityLabel(L10n.t("common.retry"))
                FavoriteRouteButton(routeKey: target.routeKey, entry: entry)
            }
        }
        .refreshable { await refresh() }
        .sheet(isPresented: $showsTracking) {
            TrackingSheet(target: target, session: session)
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
