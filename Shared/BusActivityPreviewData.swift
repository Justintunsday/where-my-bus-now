import Foundation
#if canImport(ActivityKit) && !BUS_CONTRACT_TESTS
import ActivityKit
#endif

extension BusTrackingTarget {
    static var preview: Self {
        Self(regionID: "hk", providerID: "hk", routeKey: "1A+1+STAR FERRY+SAU MAU PING (CENTRAL)",
             route: "1A", destination: "秀茂坪（中）", origin: "尖沙咀碼頭", serviceType: "1",
             operators: ["kmb"], directions: ["kmb": "O"], stopID: "preview-stop", stopName: "彌敦道",
             stopSequence: 2, lineID: nil, mode: nil, source: nil, language: "zh")
    }
}

extension BusArrivalState {
    static var preview: Self {
        BusArrivalPreview.state(.normal)
    }
}

enum BusArrivalPreview: String, CaseIterable, Identifiable {
    case normal, approaching, adjusted, nextBus, stale, networkError, unavailable, noService, arrived, departed, cancelled, ended
    var id: String { rawValue }

    static func state(_ scenario: Self, at now: Date = Date()) -> BusArrivalState {
        let live = BusArrivalState.snapshot(arrivals: [now.addingTimeInterval(180).timeIntervalSince1970,
                                                      now.addingTimeInterval(720).timeIntervalSince1970], updatedAt: now)
        var state = live
        switch scenario {
        case .normal: break
        case .approaching: state.arrivalEpoch = now.addingTimeInterval(35).timeIntervalSince1970; state.validUntilEpoch = state.arrivalEpoch!
        case .adjusted: state.arrivalEpoch = now.addingTimeInterval(300).timeIntervalSince1970; state.change = .adjusted
        case .nextBus: state.change = .nextBus
        case .stale: state.updatedEpoch -= 180; state.validUntilEpoch = now.addingTimeInterval(-90).timeIntervalSince1970
        case .networkError, .unavailable:
            state = .failed(previous: live, at: now, network: scenario == .networkError, message: "")
        case .noService: state = .snapshot(arrivals: [], updatedAt: now)
        case .arrived, .departed, .cancelled, .ended:
            state = .unavailable(at: now)
            state.status = BusArrivalStatus(rawValue: scenario.rawValue)!
        }
        return state
    }
}

#if canImport(ActivityKit) && !BUS_CONTRACT_TESTS
extension BusActivityAttributes {
    static var preview: Self { Self(target: .preview, startedAt: Date()) }
}
#endif
