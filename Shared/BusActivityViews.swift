import AppIntents
import SwiftUI

/// A small value adapter; there are no timers, tasks or provider calls in these views.
struct BusActivityDisplay {
    let target: BusTrackingTarget
    let state: BusArrivalState
    let isStale: Bool
    var now = Date()

    var fresh: Bool { !isStale && state.isFresh(at: now) }
    var statusKey: String {
        switch state.status {
        case .cancelled: return "cancelled"
        case .ended: return "ended"
        case .arrived: return "arrived"
        case .departed: return "departed"
        case .noService: return "noService"
        case .networkError: return "networkError"
        case .unavailable: return "unavailable"
        case .live, .scheduled:
            guard fresh else { return "stale" }
            if state.change == .nextBus { return "nextBus" }
            if state.change == .adjusted { return "adjusted" }
            if let arrival = state.arrival, arrival.timeIntervalSince(now) <= 60 { return "approaching" }
            return state.status == .scheduled ? "scheduled" : (state.updateSource == .push ? "remote" : "local")
        }
    }
    var symbol: String {
        switch statusKey {
        case "cancelled": return "xmark.circle.fill"
        case "ended", "arrived": return "checkmark.circle.fill"
        case "departed": return "arrow.right.circle.fill"
        case "noService": return "moon.zzz.fill"
        case "networkError": return "wifi.slash"
        case "stale", "unavailable": return "clock.badge.exclamationmark"
        case "adjusted": return "clock.arrow.2.circlepath"
        default: return "bus.fill"
        }
    }
    func copy(_ key: String) -> String { BusActivityCopy.text(key, language: target.language) }
}

/// Dedicated horizontal departure board for the Lock Screen, rather than an enlarged Island.
struct BusLockScreenView: View {
    let target: BusTrackingTarget
    let state: BusArrivalState
    var isStale = false
    var activityID: String? = nil
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.transitLuminanceReduced) private var dimmed
    @Environment(\.colorSchemeContrast) private var contrast
    private var display: BusActivityDisplay { .init(target: target, state: state, isStale: isStale) }
    private var accent: Color { dimmed || contrast == .increased ? .primary : TransitBrand.coral }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(target.route).font(.title3.bold()).fontDesign(.rounded)
                            .foregroundStyle(accent).lineLimit(1).minimumScaleFactor(0.7)
                        Text("\(display.copy("to")) \(target.destination)")
                            .font(.headline).lineLimit(1)
                            .accessibilityLabel("\(display.copy("to")) \(target.destination)")
                    }
                    Label(target.stopName, systemImage: "mappin.circle.fill")
                        .font(.subheadline).lineLimit(1)
                        .accessibilityLabel("\(display.copy("boarding")) \(target.stopName)")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .trailing, spacing: 2) {
                    BusActivityCountdown(target: target, state: state, isStale: isStale)
                        .font(typeSize.isAccessibilitySize ? .title2.bold() : .largeTitle.bold())
                        .fontDesign(.rounded).foregroundStyle(accent)
                    if display.fresh { Text(display.copy("timer")).font(.caption2.weight(.medium)).foregroundStyle(.secondary) }
                }
                .frame(maxWidth: typeSize.isAccessibilitySize ? 130 : 110, alignment: .trailing)
            }
            .accessibilityElement(children: .combine)
            if !typeSize.isAccessibilitySize {
                BusDepartureClocks(display: display)
            }
            BusActivityFooter(display: display, activityID: activityID)
        }
        .padding(14)
        .environment(\.timeZone, target.timeZone).environment(\.locale, target.locale)
        .foregroundStyle(.primary)
    }
}

struct BusDepartureClocks: View {
    let display: BusActivityDisplay
    var body: some View {
        HStack(spacing: 5) {
            if let arrival = display.state.arrival {
                Text(display.copy(display.fresh ? "arrival" : "lastKnown"))
                Text(arrival, style: .time).monospacedDigit()
                Spacer(minLength: 8)
                if let second = display.state.secondArrival {
                    Text(display.copy("following"))
                    Text(second, style: .time).monospacedDigit()
                }
            }
        }
        .font(.caption.weight(.medium)).foregroundStyle(.secondary)
        .lineLimit(1).accessibilityElement(children: .combine)
    }
}

struct BusActivityFooter: View {
    let display: BusActivityDisplay
    var activityID: String? = nil
    @Environment(\.transitReduceMotion) private var reduceMotion
    @Environment(\.transitLuminanceReduced) private var dimmed
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: display.symbol)
                .contentTransition(reduceMotion || dimmed ? .identity : .symbolEffect(.replace))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(display.copy(display.statusKey)).fontWeight(.medium)
                    .contentTransition(reduceMotion || dimmed ? .identity : .opacity)
                HStack(spacing: 4) {
                    Text(display.copy("updated"))
                    Text(display.state.updatedAt, style: .time).monospacedDigit()
                }.foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: 0)
            if let activityID {
                Button(intent: EndBusTrackingIntent(activityID: activityID)) {
                    Image(systemName: "stop.circle").font(.title3).frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(display.copy("end"))
            }
        }
        .font(.caption2)
    }
}

struct BusActivityCountdown: View {
    let target: BusTrackingTarget
    let state: BusArrivalState
    let isStale: Bool
    @Environment(\.transitReduceMotion) private var reduceMotion
    @Environment(\.transitLuminanceReduced) private var dimmed
    private var display: BusActivityDisplay { .init(target: target, state: state, isStale: isStale) }

    var body: some View {
        if display.fresh, let arrival = state.arrival, arrival > state.updatedAt {
            // Only the system advances this text; a countdown is not a fresh provider response.
            Text(timerInterval: state.updatedAt...arrival, countsDown: true, showsHours: false)
                .monospacedDigit().lineLimit(1).minimumScaleFactor(0.75)
                .contentTransition(reduceMotion || dimmed ? .identity : .numericText(countsDown: true))
                .accessibilityLabel(display.copy("remaining"))
                .accessibilityValue(Text(timerInterval: state.updatedAt...arrival, countsDown: true, showsHours: false))
        } else {
            Image(systemName: display.symbol).accessibilityLabel(display.copy(display.statusKey))
        }
    }
}

/// Full route codes are never ellipsized. Very long names yield an identifiable bus symbol.
struct BusIslandRoute: View {
    let target: BusTrackingTarget
    var compact = false
    var body: some View {
        ViewThatFits(in: .horizontal) {
            Text(target.route).font(compact ? .headline : .title2.bold())
                .fontDesign(.rounded).fixedSize()
            Text(target.route).font(.caption2.bold()).fontDesign(.rounded).fixedSize()
            Image(systemName: "bus.fill").font(.headline)
        }
        .foregroundStyle(TransitBrand.coral)
        .accessibilityLabel(target.route)
    }
}

struct BusIslandExpandedArrival: View {
    let display: BusActivityDisplay
    var body: some View {
        VStack(alignment: .trailing, spacing: 2) {
            BusActivityCountdown(target: display.target, state: display.state, isStale: display.isStale)
                .font(.title.bold()).fontDesign(.rounded)
            if let arrival = display.state.arrival {
                HStack(spacing: 4) {
                    Text(display.copy(display.fresh ? "arrival" : "lastKnown"))
                    Text(arrival, style: .time).monospacedDigit()
                }.font(.caption2.weight(.medium)).foregroundStyle(.secondary)
            }
        }
        .environment(\.timeZone, display.target.timeZone).environment(\.locale, display.target.locale)
    }
}

struct BusIslandExpandedDetails: View {
    let display: BusActivityDisplay
    var activityID: String? = nil
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("\(display.copy("to")) \(display.target.destination)").font(.headline).lineLimit(1)
                .minimumScaleFactor(0.8)
            Label(display.target.stopName, systemImage: "mappin.circle.fill")
                .font(.caption.weight(.medium)).lineLimit(1)
            if !typeSize.isAccessibilitySize, let second = display.state.secondArrival {
                HStack(spacing: 5) {
                    Text(display.copy(display.fresh ? "following" : "lastKnown"))
                    Text(second, style: .time).monospacedDigit()
                }.font(.caption.weight(.medium)).foregroundStyle(.secondary)
            }
            BusActivityFooter(display: display, activityID: activityID)
        }
        .environment(\.timeZone, display.target.timeZone).environment(\.locale, display.target.locale)
    }
}

struct BusSmallActivityView: View {
    let display: BusActivityDisplay
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                BusIslandRoute(target: display.target, compact: true)
                Spacer(minLength: 6)
                BusActivityCountdown(target: display.target, state: display.state, isStale: display.isStale)
                    .font(.headline)
            }
            Text(display.target.destination).font(.caption.weight(.medium)).lineLimit(1)
            Text(display.fresh ? display.target.stopName : display.copy(display.statusKey))
                .font(.caption2).lineLimit(1).foregroundStyle(.secondary)
        }.padding(8).accessibilityElement(children: .combine)
    }
}
