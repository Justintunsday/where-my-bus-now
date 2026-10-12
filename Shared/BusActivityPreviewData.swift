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
        .prediction(arrival: Date().addingTimeInterval(420), updatedAt: Date(), scheduled: false)
    }
}

#if canImport(ActivityKit) && !BUS_CONTRACT_TESTS
extension BusActivityAttributes {
    static var preview: Self { Self(target: .preview, startedAt: Date()) }
}
#endif
