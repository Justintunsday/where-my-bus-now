import AppIntents
import SwiftUI

/// A small value adapter; there are no timers, tasks or provider calls in these views.
struct BusActivityDisplay {
    let target: BusTrackingTarget
    let state: BusArrivalState
    let isStale: Bool
    var now = Date()
    var theme: RouteTheme { target.resolvedTheme }

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
            if state.status == .scheduled { return "scheduled" }
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
        default: return target.operators.contains("mtr") || target.operators.contains("lightRail") ? "tram.fill" : "bus.fill"
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
    private var accent: Color { dimmed ? .primary : target.resolvedTheme.accent }

    var body: some View {
        if typeSize.isAccessibilitySize {
            BusActivityAccessibleBoard(display: display, activityID: activityID)
        } else { standardBoard }
    }

    private var standardBoard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(target.route).font(.headline).fontDesign(.rounded)
                    .foregroundStyle(accent).lineLimit(1).minimumScaleFactor(0.7)
                Text("\(display.copy("to")) \(target.destination)")
                    .font(.subheadline.weight(.medium)).lineLimit(1)
                    .accessibilityLabel("\(display.copy("to")) \(target.destination)")
            }
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Label(target.stopName, systemImage: "mappin.circle.fill")
                        .font(.headline).lineLimit(1)
                        .accessibilityLabel("\(display.copy("boarding")) \(target.stopName)")
                    if let second = state.secondArrival {
                        HStack(spacing: 4) {
                            Text(display.copy(display.fresh ? "following" : "lastKnown"))
                            Text(second, style: .time).monospacedDigit()
                        }.font(.caption).foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .trailing, spacing: 2) {
                    BusActivityCountdown(target: target, state: state, isStale: isStale)
                        .font(typeSize.isAccessibilitySize ? .title2.bold() : .largeTitle.bold())
                        .fontDesign(.rounded).foregroundStyle(accent)
                    if display.fresh {
                        if #available(iOS 18.0, *) { Text(display.copy("remaining")).font(.caption2).foregroundStyle(.secondary) }
                        else { Text(display.copy("asOf")).font(.caption2).foregroundStyle(.secondary) }
                    }
                }
                .frame(maxWidth: 132, alignment: .trailing)
            }
            .accessibilityElement(children: .combine)
            BusActivityFooter(display: display, activityID: activityID)
        }
        .padding(14)
        .environment(\.timeZone, target.timeZone).environment(\.locale, target.locale)
        .foregroundStyle(.primary)
    }
}

/// Large-text composition gives the boarding stop a full line. Metadata moves
/// into the status symbol's spoken description rather than squeezing two columns.
struct BusActivityAccessibleBoard: View {
    let display: BusActivityDisplay
    var activityID: String? = nil
    var showHeader = true
    @Environment(\.transitLuminanceReduced) private var dimmed
    private var clock: Date.FormatStyle {
        Date.FormatStyle(locale: display.target.locale, timeZone: display.target.timeZone)
            .hour(.twoDigits(amPM: .omitted)).minute(.twoDigits)
    }
    private var spokenStatus: String {
        let stamp = display.state.updatedAt.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened,
            locale: display.target.locale, timeZone: display.target.timeZone))
        return "\(display.copy(display.statusKey)) · \(display.copy("updated")) \(stamp)"
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if showHeader {
                HStack(spacing: 8) {
                    Text(display.target.route).font(.caption2.bold()).fontDesign(.rounded)
                        .accessibilityLabel("\(display.target.route) · \(display.copy("to")) \(display.target.destination)")
                    Spacer(minLength: 4)
                    BusActivityCountdown(target: display.target, state: display.state, isStale: display.isStale)
                        .font(.caption.bold()).fontDesign(.rounded)
                }.foregroundStyle(dimmed ? Color.primary : display.theme.accent)
            }
            Text(display.target.stopName).font(.caption2.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.8)
                .accessibilityLabel("\(display.copy("boarding")) \(display.target.stopName)")
            HStack(spacing: 4) {
                Image(systemName: display.symbol).accessibilityLabel(spokenStatus)
                if let arrival = display.state.arrival {
                    Text(display.copy(display.fresh ? "arrival" : "lastKnown")).lineLimit(1).minimumScaleFactor(0.7)
                    Text(arrival, format: clock).monospacedDigit().fixedSize()
                } else {
                    Text(display.copy(display.statusKey)).lineLimit(1).minimumScaleFactor(0.7)
                }
                Spacer(minLength: 0)
                if let activityID {
                    Button(intent: EndBusTrackingIntent(activityID: activityID)) {
                        Image(systemName: "stop.circle").frame(width: 44, height: 44)
                    }.buttonStyle(.plain).accessibilityLabel(display.copy("end"))
                }
            }.font(.caption2)
        }.padding(showHeader ? 8 : 0)
            .environment(\.locale, display.target.locale).environment(\.timeZone, display.target.timeZone)
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
                    if #available(iOS 18.0, *) { Text(display.copy("updated")) }
                    else { Text("* \(display.copy("asOf"))") }
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
        if display.fresh {
            countdown
                .monospacedDigit().lineLimit(1).minimumScaleFactor(0.75)
                .multilineTextAlignment(.trailing)
                .contentTransition(.identity)
                .accessibilityLabel(display.copy("remaining"))
        } else {
            Image(systemName: display.symbol).accessibilityLabel(display.copy(display.statusKey))
        }
    }

    @ViewBuilder private var countdown: some View {
        if #available(iOS 18.0, *), let arrival = state.arrival {
            // Built-in style types can be decoded in WidgetKit's remote renderer.
            // The bounded system timer owns ticking; there is no extension Timer.
            Text(.currentDate, format: SystemMinuteCountdown.style(updatedAt: state.updatedAt, arrival: arrival))
                .environment(\.locale, target.locale)
                .accessibilityValue(Text(.currentDate, format: SystemMinuteCountdown.style(
                    updatedAt: state.updatedAt, arrival: arrival)))
        } else if let minutes = state.remainingMinutes(at: state.updatedAt) {
            // Custom DiscreteFormatStyle types cannot be decoded by the remote
            // WidgetKit renderer (verified in CI). Use a timestamped snapshot on
            // every OS; context.isStale replaces it when the prediction expires.
            Text("\(minutes) \(display.copy("minutes"))*")
                .accessibilityValue("\(minutes) \(display.copy("minutes")) · \(display.copy("asOf")) \(state.updatedAt.formatted(Date.FormatStyle(date: .omitted, time: .shortened, locale: target.locale, timeZone: target.timeZone)))")
        }
    }
}

/// Full route codes are never ellipsized. Very long names yield an identifiable bus symbol.
struct BusIslandRoute: View {
    let target: BusTrackingTarget
    var compact = false
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        ViewThatFits(in: .horizontal) {
            Text(target.route).font(typeSize.isAccessibilitySize ? .caption2.bold() : (compact ? .headline : .title2.bold()))
                .fontDesign(.rounded).fixedSize()
            Text(target.route).font(.caption2.bold()).fontDesign(.rounded).fixedSize()
            Image(systemName: "bus.fill").font(.headline)
        }
        .foregroundStyle(target.resolvedTheme.islandAccent)
        .accessibilityLabel("\(target.route) · \(BusActivityCopy.text("to", language: target.language)) \(target.destination)")
    }
}

struct BusIslandExpandedArrival: View {
    let display: BusActivityDisplay
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        VStack(alignment: .trailing, spacing: 2) {
            BusActivityCountdown(target: display.target, state: display.state, isStale: display.isStale)
                .font(typeSize.isAccessibilitySize ? .caption.bold() : .title.bold()).fontDesign(.rounded)
                .foregroundStyle(display.theme.islandAccent)
            if !typeSize.isAccessibilitySize, let arrival = display.state.arrival {
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
        if typeSize.isAccessibilitySize {
            BusActivityAccessibleBoard(display: display, activityID: activityID, showHeader: false)
        } else { standardDetails }
    }
    private var standardDetails: some View {
        VStack(alignment: .leading, spacing: 5) {
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
