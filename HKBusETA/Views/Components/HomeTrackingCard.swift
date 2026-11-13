import SwiftUI

/// Departure content stays opaque; navigation bars and sheets own the system material.
struct HomeTrackingCard: View {
    @Environment(AppState.self) private var app
    @Environment(\.dynamicTypeSize) private var typeSize
    let target: BusTrackingTarget

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            NavigationLink(value: target) {
                let layout = typeSize.isAccessibilitySize
                    ? AnyLayout(VStackLayout(alignment: .leading, spacing: 16))
                    : AnyLayout(HStackLayout(alignment: .top, spacing: 16))
                layout {
                    VStack(alignment: .leading, spacing: 12) {
                        BoardingRouteSign(target: target)
                        Text(target.destination).font(.headline).foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                        Label(target.stopName, systemImage: "mappin.and.ellipse")
                            .font(.subheadline).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    HomeTrackingArrival(target: target, alignment: typeSize.isAccessibilitySize ? .leading : .trailing)
                }
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("home.tracking.open")
            Divider()
            HStack(alignment: .center, spacing: 8) {
                HomeTrackingStatus(target: target)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Menu {
                    Button(role: .destructive) { Task { await app.activities.end(target) } } label: {
                        Label(L10n.t("tracking.end"), systemImage: "stop.circle")
                    }
                } label: {
                    Image(systemName: "ellipsis").font(.headline)
                        .frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
                }
                .accessibilityLabel(L10n.t("tracking.title"))
                .accessibilityIdentifier("home.tracking.menu")
            }
        }
        .transitCardSurface()
        .environment(\.routeTheme, target.resolvedTheme)
        .environment(\.timeZone, target.timeZone)
        .tint(target.resolvedTheme.accent)
    }
}

private struct HomeTrackingArrival: View {
    @Environment(AppState.self) private var app
    let target: BusTrackingTarget
    let alignment: HorizontalAlignment

    var body: some View {
        VStack(alignment: alignment, spacing: 8) {
            Text(L10n.t("arrival.next")).font(.caption).foregroundStyle(.secondary)
            BoardingArrivalValue(state: app.activities.snapshots[target.id] ?? .unavailable(at: .now),
                                 format: app.settings.etaFormat,
                                 annotateScheduled: app.settings.annotateScheduled, alignment: alignment)
                .accessibilityIdentifier("home.tracking.eta")
        }
    }
}

private struct HomeTrackingStatus: View {
    @Environment(AppState.self) private var app
    let target: BusTrackingTarget

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(L10n.t(app.activities.remoteStatusKey(for: target)), systemImage: "wave.3.right")
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("home.tracking.status")
            if let state = app.activities.snapshots[target.id] {
                HStack(spacing: 4) {
                    Text(L10n.t("eta.updatedAt"))
                    Text(state.updatedAt, style: .time).monospacedDigit()
                }
            }
        }
        .font(.caption).foregroundStyle(.secondary)
        .accessibilityElement(children: .combine)
    }
}
