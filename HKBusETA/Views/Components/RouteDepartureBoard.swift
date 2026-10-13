import SwiftUI

/// A single departure board: identity, boarding point and ETA share one reading group.
struct RouteDepartureBoard: View {
    @Environment(AppState.self) private var app
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.routeTheme) private var theme
    let entry: RouteEntry
    let target: BusTrackingTarget
    let session: ArrivalSession
    var realtimeAllowed = true

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let state = session.activityState
            let fresh = state.isFresh(at: context.date)
            VStack(alignment: .leading, spacing: 14) {
                let headerLayout = typeSize.isAccessibilitySize
                    ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6))
                    : AnyLayout(HStackLayout(spacing: 10))
                headerLayout {
                    RouteBadge(route: entry.route, entry: entry, fontSize: 21)
                    Text(operatorName).font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
                    if !typeSize.isAccessibilitySize { Spacer(minLength: 4) }
                    if fresh { predictionStatus(scheduled: state.status == .scheduled) }
                }
                let layout = typeSize.isAccessibilitySize
                    ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
                    : AnyLayout(HStackLayout(alignment: .center, spacing: 16))
                layout {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("\(L10n.t("route.to")) \(target.destination)")
                            .font(.title3.bold()).fixedSize(horizontal: false, vertical: true)
                        Label(target.stopName, systemImage: "mappin.and.ellipse")
                            .font(.subheadline.weight(.semibold)).foregroundStyle(theme.accent)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityLabel("\(L10n.t("eta.currentStop")) \(target.stopName)")
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    primary(state: state, at: context.date)
                }
                if !state.message.isEmpty, state.status != .scheduled {
                    Text(state.message).font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !following(at: context.date).isEmpty {
                    Divider()
                    VStack(spacing: 0) {
                        ForEach(ArrivalSlot.make(following(at: context.date))) { slot in
                            departure(slot.eta, at: context.date, fresh: fresh)
                        }
                    }
                }
                FreshnessLabel(updatedAt: session.updatedAt, error: session.error)
            }
            .padding(.vertical, 4)
        }
    }

    private var operatorName: String {
        let names = entry.co.compactMap { app.provider.operators.op($0)?.name(L10n.language) }
        return names.isEmpty ? app.region.localizedName : names.joined(separator: " · ")
    }

    @ViewBuilder private func primary(state: BusArrivalState, at date: Date) -> some View {
        if !realtimeAllowed {
            Label(L10n.t("mainland.metroNoRealtime"), systemImage: "tram.fill").font(.callout)
        } else if session.updatedAt == nil && session.error == nil {
            ArrivalLoadingState()
        } else if let minutes = state.remainingMinutes(at: date) {
            VStack(alignment: .trailing, spacing: 2) {
                Text(L10n.t("arrival.next")).font(.caption).foregroundStyle(.secondary)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    DepartureMinuteDigits(minutes: minutes)
                    Text(L10n.t("unit.minutes")).font(.subheadline.weight(.medium))
                        .accessibilityIdentifier("eta.primary-unit")
                }.foregroundStyle(theme.accent)
                if let arrival = state.arrival {
                    Text(arrival, style: .time).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
            }
            .fixedSize(horizontal: true, vertical: false)
        } else {
            VStack(alignment: .leading, spacing: 4) {
                Text(BusActivityCopy.text(statusKey(state), language: target.language))
                    .font(.callout.weight(.semibold))
                if let arrival = state.arrival {
                    HStack(spacing: 4) {
                        Text(L10n.t("arrival.lastKnown"))
                        Text(RegionClock.timeString(arrival))
                    }.font(.caption).foregroundStyle(.secondary)
                }
            }.fixedSize(horizontal: false, vertical: true)
        }
    }

    private func following(at date: Date) -> [Eta] {
        var upcoming = session.etas.filter { ($0.date ?? .distantFuture) > date }
            .sorted { ($0.date ?? .distantFuture) < ($1.date ?? .distantFuture) }
        if let first = upcoming.firstIndex(where: { $0.date == session.activityState.arrival && $0.date != nil }) {
            upcoming.remove(at: first) // Retain other services at the same timestamp.
        }
        return Array(upcoming.prefix(3))
    }

    private func departure(_ eta: Eta, at date: Date, fresh: Bool) -> some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 3))
            : AnyLayout(HStackLayout(spacing: 12))
        return layout {
            if app.settings.etaFormat != .diff || !fresh {
                Text(RegionClock.timeString(eta.eta)).font(.subheadline.monospacedDigit())
                    .frame(minWidth: 48, alignment: .leading)
            }
            VStack(alignment: .leading, spacing: 2) {
                if eta.co == "mtr", !eta.dest.name(L10n.language).isEmpty {
                    Text(eta.dest.name(L10n.language)).font(.subheadline)
                }
                Text(L10n.t(eta.date == nil ? "eta.noEta" : (eta.isScheduled ? "eta.scheduled" : (fresh ? "arrival.live" : "arrival.cached"))))
                    .font(.caption).foregroundStyle(.secondary)
                if !eta.remark.name(L10n.language).isEmpty, !eta.isScheduled {
                    Text(eta.remark.name(L10n.language)).font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if !typeSize.isAccessibilitySize { Spacer(minLength: 4) }
            if fresh, app.settings.etaFormat != .exact, let arrival = eta.date,
               let minutes = BusArrivalState.remainingMinutes(arrival: arrival, now: date) {
                Text("\(minutes) \(L10n.t("unit.minutes"))")
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .contentTransition(.identity)
                    .transaction { $0.animation = nil; $0.disablesAnimations = true }
            }
        }
        .padding(.vertical, 7)
        .accessibilityElement(children: .combine)
    }

    private func predictionStatus(scheduled: Bool) -> some View {
        HStack(spacing: 4) {
            Image(systemName: scheduled ? "calendar" : "dot.radiowaves.left.and.right")
                .accessibilityHidden(true)
            Text(L10n.t(scheduled ? "eta.scheduled" : "arrival.live")).fixedSize()
        }
        .font(.caption2.weight(.medium)).foregroundStyle(theme.accent)
        .accessibilityElement(children: .combine)
    }

    private func statusKey(_ state: BusArrivalState) -> String {
        switch state.status {
        case .live, .scheduled: "stale"
        default: state.status.rawValue
        }
    }
}

/// One stable Text layer. Refresh transactions cannot start rolling/fading digit layers.
struct DepartureMinuteDigits: View {
    let minutes: Int
    @ScaledMetric(relativeTo: .largeTitle) private var size: CGFloat = 46
    var body: some View {
        Text("\(minutes)").font(.system(size: size, weight: .bold, design: .rounded))
            .monospacedDigit().lineLimit(1).minimumScaleFactor(0.5)
            .frame(width: size * 1.35, alignment: .trailing)
            .contentTransition(.identity)
            .transaction { $0.animation = nil; $0.disablesAnimations = true }
            .accessibilityIdentifier("eta.primary-minutes")
    }
}
