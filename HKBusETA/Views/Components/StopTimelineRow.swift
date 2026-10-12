import SwiftUI

struct StopTimelineRow: View {
    @Environment(AppState.self) private var app
    @Environment(\.transitReduceMotion) private var reduceMotion
    let entry: RouteEntry
    let point: RouteStopPoint
    let isLast: Bool
    let isSelected: Bool
    let isExpanded: Bool
    let onTap: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(spacing: 0) {
                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .font(.body.weight(.bold)).foregroundStyle(DesignTokens.accent)
                    .frame(width: 24, height: 44)
                if !isLast { Rectangle().fill(DesignTokens.divider).frame(width: 2).frame(maxHeight: .infinity) }
            }.accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 8) {
                Button(action: onTap) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("\(point.seq + 1)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        Text(point.name(L10n.language)).font(isSelected ? .headline : .body).foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.down").font(.caption.bold()).foregroundStyle(.secondary)
                            .rotationEffect(.degrees(isExpanded ? 180 : 0))
                    }.frame(minHeight: 44).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("route.stop.\(point.seq)")
                .accessibilityValue(L10n.t(isExpanded ? "common.expanded" : "common.collapsed"))
                .accessibilityAddTraits(isSelected ? [.isSelected] : [])
                if isExpanded {
                    StopEtaInlineView(entry: entry, seq: point.seq)
                        .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
                }
            }
        }
        .padding(.vertical, 4)
    }
}

struct StopEtaInlineView: View {
    @Environment(AppState.self) private var app
    @Environment(\.scenePhase) private var scenePhase
    let entry: RouteEntry
    let seq: Int
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let target = BusTrackingTarget(app: app, routeKey: entry.routeKey, seq: seq),
               let session = app.arrivals.session(for: target, app: app) {
                InlineArrivals(session: session)
                    .task(id: scenePhase) {
                        guard scenePhase == .active else { return }
                        while !Task.isCancelled {
                            await session.refresh()
                            do { try await Task.sleep(for: .seconds(30)) } catch { break }
                        }
                    }
                NavigationLink(value: RouteEtaTarget(routeKey: entry.routeKey, seq: seq)) {
                    Label(L10n.t("route.fullEta"), systemImage: "clock.arrow.circlepath")
                        .frame(minHeight: 44)
                }.buttonStyle(.bordered)
                if let stop = app.data.stop(target.stopID), stop.location.isValid {
                    StopNavigationButton(stopName: stop.name.name(L10n.language), location: stop.location) {
                        Label(L10n.t("navigation.navigate"), systemImage: "figure.walk").frame(minHeight: 44)
                    }
                    Button {
                        app.bookmarks.toggleFavoriteStop(id: target.stopID, name: stop.name, location: stop.location)
                    } label: {
                        Label(L10n.t(app.bookmarks.isFavoriteStop(target.stopID) ? "common.unfavorite" : "common.favorite"), systemImage: "star")
                            .frame(minHeight: 44)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .font(.subheadline)
    }
}

private struct InlineArrivals: View {
    @Environment(AppState.self) private var app
    let session: ArrivalSession
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if session.etas.isEmpty {
                Text(L10n.t(session.isRefreshing ? "status.loading" : "eta.noEta")).foregroundStyle(.secondary)
            }
            ForEach(ArrivalSlot.make(Array(session.etas.prefix(2)))) { slot in
                ETALineView(eta: slot.eta, language: L10n.language, format: app.settings.etaFormat,
                            annotateScheduled: app.settings.annotateScheduled, highlight: true)
            }
            FreshnessLabel(updatedAt: session.updatedAt, error: session.error)
        }
    }
}
