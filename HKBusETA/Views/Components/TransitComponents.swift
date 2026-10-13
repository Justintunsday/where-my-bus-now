import SwiftUI

enum TransitMotion {
    static func selection(reduced: Bool) -> Animation? {
        reduced ? nil : .spring(duration: 0.32, bounce: 0.12)
    }
}

struct ArrivalLoadingState: View {
    var body: some View {
        HStack(spacing: 12) {
            ProgressView()
            Text(L10n.t("status.loading")).foregroundStyle(.secondary)
        }
        .padding(.vertical, 24)
        .accessibilityElement(children: .combine)
    }
}

struct FavoriteRouteButton: View {
    @Environment(AppState.self) private var app
    @Environment(\.transitReduceMotion) private var reduceMotion
    let routeKey: String
    let entry: RouteEntry
    private var isFavorite: Bool { app.bookmarks.isFavoriteRoute(routeKey) }

    var body: some View {
        Button {
            app.bookmarks.toggleFavoriteRoute(entry: entry, routeKey: routeKey,
                modeRawValue: app.data.mainlandMetadata(for: routeKey)?.mode.rawValue)
        } label: {
            Image(systemName: isFavorite ? "star.fill" : "star")
                .symbolEffect(.bounce, value: isFavorite)
                .symbolEffectsRemoved(reduceMotion)
                .frame(minWidth: 44, minHeight: 44)
        }
        .accessibilityLabel(L10n.t(isFavorite ? "common.unfavorite" : "common.favorite"))
        .sensoryFeedback(.selection, trigger: isFavorite)
        .transitCircularToolbarControl()
    }
}

struct RouteIdentityHeader: View {
    @Environment(AppState.self) private var app
    let entry: RouteEntry
    var stopName: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 12) {
                RouteBadge(route: entry.route, entry: entry, fontSize: 24)
                CompanyLogos(co: entry.co, language: L10n.language, height: 18,
                             mode: app.data.mainlandMetadata(for: entry.routeKey)?.mode)
                Spacer(minLength: 0)
                if entry.isSpecialTrip { Text(L10n.t("route.special")).font(.caption) }
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.t("route.to")).font(.caption).foregroundStyle(.secondary)
                Text(entry.dest.name(L10n.language)).font(.title2.bold())
                    .fixedSize(horizontal: false, vertical: true)
                Text(entry.orig.name(L10n.language)).font(.subheadline).foregroundStyle(.secondary)
            }
            if let stopName {
                Label(stopName, systemImage: "mappin.circle.fill")
                    .font(.headline).foregroundStyle(DesignTokens.accent)
                    .accessibilityLabel("\(L10n.t("eta.currentStop")) \(stopName)")
            }
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
    }
}

/// Value-only view: timeline ticks invalidate this small subtree, not the route or map.
struct ArrivalHero: View {
    let state: BusArrivalState
    @Environment(\.transitReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .largeTitle) private var numeralSize: CGFloat = 64

    var body: some View {
        TimelineView(.periodic(from: .now, by: 15)) { context in
            VStack(alignment: .leading, spacing: 12) {
                Text(L10n.t("arrival.next")).font(.subheadline).foregroundStyle(.secondary)
                if let minutes = state.remainingMinutes(at: context.date), let arrival = state.arrival {
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            number(minutes)
                            Text(L10n.t("unit.minutes")).font(.title3).foregroundStyle(.secondary)
                            Spacer()
                            Text(arrival, style: .time).font(.title3.monospacedDigit()).foregroundStyle(.secondary)
                        }
                        VStack(alignment: .leading, spacing: 8) {
                            number(minutes)
                            Text("\(L10n.t("unit.minutes")) · \(RegionClock.timeString(arrival))").font(.headline)
                        }
                    }
                    if state.status == .scheduled {
                        Label(L10n.t("eta.scheduled"), systemImage: "calendar.badge.clock")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                } else {
                    Label(BusActivityCopy.text(statusKey, language: L10n.language.rawValue),
                          systemImage: "clock.badge.exclamationmark")
                        .font(.title3.weight(.semibold))
                    if let arrival = state.arrival {
                        HStack {
                            Text(BusActivityCopy.text("lastKnown", language: L10n.language.rawValue))
                            Text(arrival, style: .time).monospacedDigit()
                        }.font(.subheadline).foregroundStyle(.secondary)
                    }
                    if !state.message.isEmpty { Text(state.message).font(.subheadline).foregroundStyle(.secondary) }
                }
            }
            .padding(.vertical, 16)
            .accessibilityElement(children: .combine)
        }
    }

    private var statusKey: String {
        switch state.status {
        case .live, .scheduled: "stale"
        case .networkError: "networkError"
        case .noService: "noService"
        case .arrived: "arrived"
        case .departed: "departed"
        case .cancelled: "cancelled"
        case .ended: "ended"
        case .unavailable: "unavailable"
        }
    }

    private func number(_ minutes: Int) -> some View {
        Text("\(minutes)")
            .font(.system(size: numeralSize, weight: .bold, design: .rounded)).monospacedDigit()
            .foregroundStyle(DesignTokens.accent)
            .contentTransition(.identity)
            .transaction { $0.animation = nil; $0.disablesAnimations = true }
    }
}

struct FreshnessLabel: View {
    let updatedAt: Date?
    let error: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let error { Label(error, systemImage: "wifi.exclamationmark").foregroundStyle(DesignTokens.warning) }
            if let updatedAt {
                HStack(spacing: 4) {
                    Text(L10n.t("eta.updatedAt"))
                    Text(updatedAt, style: .time).monospacedDigit()
                }
            }
        }
        .font(.caption).foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }
}

struct TransitPrimaryStyle: ViewModifier {
    @Environment(\.transitReduceTransparency) private var reduceTransparency
    @ViewBuilder func body(content: Content) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *), !reduceTransparency {
            content.buttonStyle(.glassProminent)
        } else { content.buttonStyle(.borderedProminent) }
        #else
        content.buttonStyle(.borderedProminent)
        #endif
    }
}

extension View {
    func transitPrimaryAction() -> some View { modifier(TransitPrimaryStyle()) }
    func transitListSurface() -> some View {
        scrollContentBackground(.hidden).background(DesignTokens.background)
    }
}
