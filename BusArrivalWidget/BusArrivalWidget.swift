import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

@main
struct BusArrivalWidgetBundle: WidgetBundle {
    var body: some Widget { BusArrivalWidget() }
}

struct BusArrivalWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: BusActivityAttributes.self) { context in
            VStack(spacing: 0) {
                BusLockScreenView(target: context.attributes.target, state: context.state, isStale: context.isStale)
                Button(intent: EndBusTrackingIntent(activityID: context.activityID)) {
                    Label(BusActivityCopy.text("end", language: context.attributes.target.language), systemImage: "stop.circle")
                        .font(.caption).frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.plain)
            }
            .activityBackgroundTint(Color(uiColor: .secondarySystemBackground))
            .activitySystemActionForegroundColor(.primary)
            .widgetURL(context.attributes.target.deepLink)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Text(context.attributes.target.route)
                        .font(.title2.bold().monospacedDigit()).fontDesign(.rounded)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    BusActivityCountdown(target: context.attributes.target, state: context.state, isStale: context.isStale)
                        .font(.title2.bold().monospacedDigit()).frame(maxWidth: 90)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(context.attributes.target.destination).font(.headline).lineLimit(1)
                        HStack(alignment: .firstTextBaseline) {
                            Label(context.attributes.target.stopName, systemImage: "mappin.circle.fill")
                            Spacer(minLength: 8)
                            if !context.isStale, context.state.isFresh(at: Date()), let arrival = context.state.arrival {
                                Text(BusActivityCopy.text("arrival", language: context.attributes.target.language))
                                Text(arrival, style: .time).monospacedDigit()
                            }
                        }
                        .font(.caption)
                        .environment(\.timeZone, context.attributes.target.timeZone)
                        HStack {
                            Text(BusActivityCopy.text(context.isStale ? "stale" : "updated", language: context.attributes.target.language))
                            Text(context.state.updatedAt, style: .time).environment(\.timeZone, context.attributes.target.timeZone)
                            Spacer()
                            Button(intent: EndBusTrackingIntent(activityID: context.activityID)) {
                                Label(BusActivityCopy.text("end", language: context.attributes.target.language), systemImage: "stop.circle")
                            }
                            .buttonStyle(.plain)
                        }
                        .font(.caption2).foregroundStyle(.secondary)
                    }
                }
            } compactLeading: {
                Text(context.attributes.target.route).font(.caption.bold()).lineLimit(1)
            } compactTrailing: {
                BusActivityCountdown(target: context.attributes.target, state: context.state, isStale: context.isStale)
                    .font(.caption.monospacedDigit()).frame(maxWidth: 52)
            } minimal: {
                Image(systemName: context.isStale ? "clock.badge.exclamationmark" : "bus.fill")
            }
            .widgetURL(context.attributes.target.deepLink)
            .keylineTint(.blue)
        }
    }
}

#Preview("Lock Screen", as: .content, using: BusActivityAttributes.preview) {
    BusArrivalWidget()
} contentStates: {
    BusArrivalState.preview
    BusArrivalState.unavailable(at: Date(), message: "Service cancelled", cancelled: true)
}

#Preview("Compact", as: .dynamicIsland(.compact), using: BusActivityAttributes.preview) {
    BusArrivalWidget()
} contentStates: { BusArrivalState.preview }

#Preview("Expanded", as: .dynamicIsland(.expanded), using: BusActivityAttributes.preview) {
    BusArrivalWidget()
} contentStates: { BusArrivalState.preview }

#Preview("Minimal", as: .dynamicIsland(.minimal), using: BusActivityAttributes.preview) {
    BusArrivalWidget()
} contentStates: { BusArrivalState.preview }
