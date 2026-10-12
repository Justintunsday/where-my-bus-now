import SwiftUI

/// Real Lock Screen content, also used in the app's reviewable tracking sheet.
struct BusLockScreenView: View {
    let target: BusTrackingTarget
    let state: BusArrivalState
    var isStale: Bool = false
    var showsEndButton: Bool = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private func copy(_ key: String) -> String {
        BusActivityCopy.text(key, language: target.language)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                Text(target.route)
                    .font(.title2.bold().monospacedDigit())
                    .fontDesign(.rounded)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 4) {
                    Text(target.destination).font(.headline).lineLimit(2)
                    Label(target.stopName, systemImage: "mappin.circle.fill")
                        .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
                Spacer(minLength: 0)
                BusActivityCountdown(target: target, state: state, isStale: isStale)
                    .font(.title2.bold().monospacedDigit())
                    .frame(maxWidth: 100, alignment: .trailing)
            }
            HStack(alignment: .firstTextBaseline) {
                Label(copy("updated"), systemImage: "clock")
                Text(state.updatedAt, style: .time).monospacedDigit()
                Spacer(minLength: 0)
                if let arrival = state.arrival, !isStale, state.isFresh(at: Date()) {
                    Text(arrival, style: .time).monospacedDigit()
                }
            }
            .font(.caption2).foregroundStyle(.secondary)
            Text(statusText).font(.caption2).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .accessibilityElement(children: .combine)
    }

    private var statusText: String {
        if state.status == .ended { return copy("ended") }
        if state.status == .cancelled { return copy("cancelled") }
        if isStale || !state.isFresh(at: Date()) {
            return state.message.isEmpty ? copy("stale") : "\(state.message) · \(copy("stale"))"
        }
        return state.status == .scheduled ? copy("scheduled") : copy("foreground")
    }
}

struct BusActivityCountdown: View {
    let target: BusTrackingTarget
    let state: BusArrivalState
    let isStale: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if !isStale, state.isFresh(at: Date()), let arrival = state.arrival, arrival > state.updatedAt {
            // Native timer rendering continues without running extension code or networking.
            Text(timerInterval: state.updatedAt...arrival, countsDown: true, showsHours: false)
                .monospacedDigit()
                .contentTransition(reduceMotion ? .identity : .numericText(countsDown: true))
                .accessibilityLabel(BusActivityCopy.text("boarding", language: target.language))
        } else {
            Image(systemName: state.status == .cancelled ? "xmark.circle" : "clock.badge.exclamationmark")
                .accessibilityLabel(BusActivityCopy.text("stale", language: target.language))
        }
    }
}
