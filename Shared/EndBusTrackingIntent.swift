import ActivityKit
import AppIntents

/// Included in both targets: LiveActivityIntent executes in the host app process.
struct EndBusTrackingIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "End tracking"
    static var description = IntentDescription("End the selected bus arrival Live Activity.")
    @Parameter(title: "Activity") var activityID: String

    init() {}
    init(activityID: String) { self.activityID = activityID }

    func perform() async throws -> some IntentResult {
        for activity in Activity<BusActivityAttributes>.activities where activity.id == activityID {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
        return .result()
    }
}
