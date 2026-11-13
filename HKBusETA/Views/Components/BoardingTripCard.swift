import SwiftUI

/// Disclosure state stays with the trip while AnyLayout reflows for Dynamic Type.
struct BoardingTripCard: View {
    @Environment(AppState.self) private var app
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.transitReduceMotion) private var reduceMotion
    let target: BusTrackingTarget
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            let layout = typeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
                : AnyLayout(HStackLayout(alignment: .top, spacing: 16))
            layout {
                Button {
                    withAnimation(TransitMotion.selection(reduced: reduceMotion)) { expanded.toggle() }
                } label: {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 8) {
                            BoardingRouteSign(target: target)
                            Image(systemName: "chevron.down").font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary).rotationEffect(.degrees(expanded ? 180 : 0))
                                .accessibilityHidden(true)
                        }
                        Text(target.destination).font(.headline).foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                        Label(target.stopName, systemImage: "mappin.and.ellipse")
                            .font(.subheadline).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("boarding.toggle")
                .accessibilityValue(L10n.t(expanded ? "common.expanded" : "common.collapsed"))
                if let session = app.arrivals.session(for: target, app: app) {
                    BoardingArrivalSummary(session: session,
                                           alignment: typeSize.isAccessibilitySize ? .leading : .trailing)
                        .task(id: scenePhase) {
                            guard scenePhase == .active else { return }
                            while !Task.isCancelled {
                                await session.refresh()
                                do { try await Task.sleep(for: .seconds(30)) } catch { break }
                            }
                        }
                }
            }
            if expanded, let session = app.arrivals.session(for: target, app: app) {
                BoardingTripDetails(session: session)
            }
            Divider()
            let footer = typeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
                : AnyLayout(HStackLayout(spacing: 12))
            footer {
                Text(RegionCatalog.region(for: target.regionID)?.localizedName ?? target.regionID)
                    .font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                NavigationLink(value: target) {
                    Label(L10n.t("route.fullEta"), systemImage: "arrow.up.right")
                        .font(.subheadline.weight(.semibold)).frame(minHeight: 44)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .buttonStyle(.borderless)
                .accessibilityIdentifier("boarding.open")
            }
        }
        .transitCardSurface()
        .environment(\.timeZone, target.timeZone)
        .sensoryFeedback(.selection, trigger: expanded)
    }
}

/// Only this subtree observes ETA changes and the clock; the page does not tick.
private struct BoardingArrivalSummary: View {
    @Environment(AppState.self) private var app
    let session: ArrivalSession
    let alignment: HorizontalAlignment

    var body: some View {
        VStack(alignment: alignment, spacing: 8) {
            Text(L10n.t("arrival.next")).font(.caption).foregroundStyle(.secondary)
            BoardingArrivalValue(state: session.activityState, format: app.settings.etaFormat,
                                 annotateScheduled: app.settings.annotateScheduled,
                                 isLoading: session.isRefreshing, alignment: alignment)
        }
    }
}

private struct BoardingTripDetails: View {
    let session: ArrivalSession

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let arrival = session.activityState.secondArrival {
                BoardingFollowingArrival(state: session.activityState, arrival: arrival)
            }
            FreshnessLabel(updatedAt: session.updatedAt, error: session.error)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct BoardingFollowingArrival: View {
    let state: BusArrivalState
    let arrival: Date

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            if state.isFresh(at: context.date), arrival > context.date {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.t("home.following")).font(.caption).foregroundStyle(.secondary)
                    Text(arrival, style: .time).font(.subheadline.monospacedDigit())
                }
                .accessibilityElement(children: .combine)
            }
        }
    }
}

struct BoardingArrivalValue: View {
    @Environment(\.routeTheme) private var theme
    @Environment(\.timeZone) private var timeZone
    let state: BusArrivalState
    var format: EtaFormat = .mixed
    var annotateScheduled = true
    var isLoading = false
    var alignment: HorizontalAlignment = .trailing

    private var clockStyle: Date.FormatStyle {
        Date.FormatStyle(date: .omitted, time: .shortened,
                         locale: Locale(identifier: "en_GB"), timeZone: timeZone)
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            VStack(alignment: alignment, spacing: 4) {
                if let minutes = state.remainingMinutes(at: context.date), let arrival = state.arrival {
                    if format == .exact {
                        Text(arrival, format: clockStyle)
                            .font(.system(.title2, design: .rounded, weight: .bold)).monospacedDigit()
                            .foregroundStyle(theme.accent)
                    } else {
                        ViewThatFits(in: .horizontal) {
                            HStack(alignment: .firstTextBaseline, spacing: 4) {
                                minuteText(minutes)
                                Text(L10n.t("unit.minutes")).font(.caption).foregroundStyle(.secondary)
                            }
                            VStack(alignment: alignment, spacing: 2) {
                                minuteText(minutes)
                                Text(L10n.t("unit.minutes")).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        if format == .mixed {
                            Text(arrival, format: clockStyle)
                                .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        }
                    }
                    if annotateScheduled && state.status == .scheduled {
                        Label(L10n.t("eta.scheduled"), systemImage: "calendar")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                } else {
                    Label(statusText, systemImage: "clock.badge.exclamationmark")
                        .font(.subheadline).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .accessibilityElement(children: .combine)
        }
    }

    private var statusText: String {
        if isLoading { return L10n.t("status.loading") }
        if state.status == .live || state.status == .scheduled { return L10n.t("tracking.stale") }
        return BusActivityCopy.text(state.status.rawValue, language: L10n.language.rawValue)
    }

    private func minuteText(_ minutes: Int) -> some View {
        Text(minutes, format: .number)
            .font(.system(.largeTitle, design: .rounded, weight: .bold)).monospacedDigit()
            .foregroundStyle(theme.accent)
            .contentTransition(.identity)
            .transaction { $0.animation = nil; $0.disablesAnimations = true }
    }
}
