import SwiftUI

/// In-app navigation and tracking controls. System-managed Live Activities keep their own surfaces.
struct HomeTrackingCard: View {
    @Environment(AppState.self) private var app
    @Environment(\.transitReduceTransparency) private var reduceTransparency
    @Environment(\.dynamicTypeSize) private var typeSize
    let target: BusTrackingTarget

    var body: some View {
        surface
            .environment(\.routeTheme, target.resolvedTheme)
            .tint(target.resolvedTheme.accent)
    }

    @ViewBuilder private var surface: some View {
        if #available(iOS 26, *), !reduceTransparency {
            content.glassEffect(.regular, in: .rect(cornerRadius: 20))
        } else if reduceTransparency {
            content.background(DesignTokens.surface, in: RoundedRectangle(cornerRadius: 16))
        } else {
            content.background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 12) {
            NavigationLink(value: target) {
                let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12)) : AnyLayout(HStackLayout(alignment: .center, spacing: 16))
                layout {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            Text(target.route).font(.headline.monospacedDigit())
                                .padding(.horizontal, 9).padding(.vertical, 5)
                                .foregroundStyle(target.resolvedTheme.onIdentity)
                                .background(target.resolvedTheme.identity, in: RoundedRectangle(cornerRadius: 7))
                            Text(target.operators.map { app.provider.operators.op($0)?.name(L10n.language) ?? $0.uppercased() }.joined(separator: " · "))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Text(target.destination).font(.headline).foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                        HStack(spacing: 6) {
                            Image(systemName: "mappin.and.ellipse").accessibilityHidden(true)
                            Text(target.stopName).fixedSize(horizontal: false, vertical: true)
                        }
                        .font(.subheadline).foregroundStyle(.secondary)
                    }
                    if !typeSize.isAccessibilitySize { Spacer(minLength: 0) }
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        let state = app.activities.snapshots[target.id]
                        VStack(alignment: .trailing, spacing: 3) {
                            if let minutes = state?.remainingMinutes(at: context.date) {
                                Text("\(minutes)").font(.system(.largeTitle, design: .rounded, weight: .bold)).monospacedDigit()
                                    .foregroundStyle(target.resolvedTheme.accent)
                                    .contentTransition(.identity)
                                    .transaction { $0.animation = nil; $0.disablesAnimations = true }
                                Text(L10n.t("unit.minutes")).font(.caption).foregroundStyle(.secondary)
                            } else {
                                Image(systemName: "clock.badge.exclamationmark").font(.title2).foregroundStyle(.secondary)
                                Text(L10n.t("tracking.stale")).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("home.tracking.eta")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("home.tracking.open")
            Divider()
            HStack(alignment: .center, spacing: 8) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Image(systemName: "wave.3.right").accessibilityHidden(true)
                        Text(L10n.t(app.activities.remoteStatusKey(for: target))).fixedSize(horizontal: false, vertical: true)
                    }
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("home.tracking.status")
                    if let state = app.activities.snapshots[target.id] {
                        HStack(spacing: 4) {
                            Text(L10n.t("eta.updatedAt"))
                            Text(state.updatedAt, style: .time).monospacedDigit()
                        }
                    }
                }
                .font(.caption).foregroundStyle(.secondary)
                Spacer(minLength: 0)
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
        .padding(16)
    }
}
