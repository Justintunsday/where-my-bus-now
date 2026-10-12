import ActivityKit
import AppIntents

/// Included in both targets: LiveActivityIntent executes in the host app process.
struct EndBusTrackingIntent: LiveActivityIntent {
    static var title = LocalizedStringResource("End tracking", table: "BusIntents")
    static var description = IntentDescription(LocalizedStringResource("End the selected bus arrival Live Activity.", table: "BusIntents"))
    @Parameter(title: LocalizedStringResource("Activity", table: "BusIntents")) var activityID: String

    init() {}
    init(activityID: String) { self.activityID = activityID }

    func perform() async throws -> some IntentResult {
        for activity in Activity<BusActivityAttributes>.activities where activity.id == activityID {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
        return .result()
    }
}
