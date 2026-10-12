import SwiftUI

struct SavedRouteDestination: View {
    @Environment(AppState.self) private var app
    let target: SavedRouteTarget

    var body: some View {
        Group {
            if app.region.id != target.regionID {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .task { app.openSavedRegion(target.regionID) }
            } else if app.mainlandProvider != nil {
                SavedMainlandRouteResolver(target: target)
            } else {
                DataGate {
                    if let entry = app.data.entry(target.routeKey), let previous = target.seq,
                       let stopID = target.stopID, let seq = entry.canonicalSequence(for: stopID, preferredSequence: previous) {
                        RouteEtaView(routeKey: target.routeKey, seq: seq)
                    } else {
                        RouteDetailView(routeKey: target.routeKey)
                    }
                }
            }
        }
    }
}

private struct SavedMainlandRouteResolver: View {
    @Environment(AppState.self) private var app
    let target: SavedRouteTarget

    @State private var resolvedLineID: String?
    @State private var resolvedMode: MainlandTransitMode?
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if let lineID = target.lineID ?? resolvedLineID {
                MainlandLineLoaderView(
                    lineId: lineID,
                    title: target.route,
                    seq: target.seq,
                    stopID: target.stopID,
                    modeHint: resolvedMode ?? target.modeHint,
                    origin: target.origin,
                    destination: target.destination
                )
            } else if let errorMessage {
                ContentUnavailableView {
                    Label(L10n.t("route.notFound"), systemImage: "questionmark.circle")
                } description: {
                    Text(errorMessage)
                }
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .task(id: target) { await resolveLegacyRecord() }
            }
        }
    }

    /// v1.4.0 and earlier did not persist the mainland line ID. Recover it
    /// once from search metadata so existing favorites/history keep working.
    private func resolveLegacyRecord() async {
        guard let provider = app.mainlandProvider else { return }
        do {
            let results = try await provider.search(keyword: target.route)
            let exactName = results.lines.filter { $0.name == target.route }
            let match = exactName.first {
                ($0.origin == target.origin || target.origin.isEmpty)
                    && ($0.destination == target.destination || target.destination.isEmpty)
            } ?? exactName.first
            guard let match else {
                errorMessage = L10n.t("route.notFound")
                return
            }
            resolvedLineID = match.lineID
            resolvedMode = match.mode
        } catch {
            errorMessage = MainlandErrorPresentation.message(for: error)
        }
    }
}

struct SavedStopDestination: View {
    @Environment(AppState.self) private var app
    let target: SavedStopTarget

    var body: some View {
        Group {
            if app.region.id != target.regionID {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .task { app.openSavedRegion(target.regionID) }
            } else if app.mainlandProvider != nil {
                MainlandStopBoardView(
                    stopID: target.stopID,
                    title: target.title,
                    location: target.location
                )
            } else {
                StopEtaView(stopId: target.stopID)
            }
        }
    }
}
