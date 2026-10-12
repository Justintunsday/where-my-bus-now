import Foundation
#if canImport(ActivityKit) && !BUS_CONTRACT_TESTS
import ActivityKit
#endif

/// Full provider identity, never just a route number or a station name.
struct BusTrackingTarget: Codable, Hashable, Identifiable, Sendable {
    let regionID: String
    let providerID: String
    let routeKey: String
    let route: String
    let destination: String
    let origin: String
    let serviceType: String
    let operators: [String]
    let directions: [String: String]
    let stopID: String
    let stopName: String
    let stopSequence: Int
    let lineID: String?
    let mode: String?
    let source: String?
    let language: String

    var id: String {
        // Length-prefixed components avoid collisions when provider IDs contain separators.
        [regionID, providerID, routeKey, serviceType,
         operators.sorted().map { "\($0.utf8.count):\($0)" }.joined(),
         directions.keys.sorted().map { key in
             let value = directions[key] ?? ""
             return "\(key.utf8.count):\(key)\(value.utf8.count):\(value)"
         }.joined(),
         stopID, String(stopSequence), lineID ?? "", mode ?? "", source ?? ""]
            .map { "\($0.utf8.count):\($0)" }.joined()
    }

    var deepLink: URL? {
        guard let data = try? JSONEncoder().encode(self) else { return nil }
        var components = URLComponents()
        components.scheme = "busnow"
        components.host = "eta"
        components.queryItems = [URLQueryItem(name: "target", value: data.base64EncodedString())]
        return components.url
    }

    static func decode(url: URL) -> Self? {
        guard url.scheme == "busnow", url.host == "eta", url.absoluteString.utf8.count < 12_000,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let encoded = components.queryItems?.first(where: { $0.name == "target" })?.value,
              let data = Data(base64Encoded: encoded),
              let target = try? JSONDecoder().decode(Self.self, from: data),
              !target.regionID.isEmpty, !target.providerID.isEmpty, !target.routeKey.isEmpty,
              !target.stopID.isEmpty, (0..<2000).contains(target.stopSequence)
        else { return nil }
        return target
    }
}

enum BusArrivalStatus: String, Codable, Hashable, Sendable {
    case live, scheduled, unavailable, cancelled, ended
}

/// Unix seconds are explicit in the APNs contract (no Foundation reference-date ambiguity).
struct BusArrivalState: Codable, Hashable, Sendable {
    var arrivalEpoch: Double?
    var updatedEpoch: Double
    var validUntilEpoch: Double
    var status: BusArrivalStatus
    var message: String

    var arrival: Date? { arrivalEpoch.map(Date.init(timeIntervalSince1970:)) }
    var updatedAt: Date { Date(timeIntervalSince1970: updatedEpoch) }
    var staleDate: Date { Date(timeIntervalSince1970: validUntilEpoch) }

    func isFresh(at date: Date) -> Bool {
        date.timeIntervalSince1970 < validUntilEpoch && (status == .live || status == .scheduled)
    }

    /// A prediction is no longer a live prediction after its arrival time.
    static func prediction(arrival: Date, updatedAt: Date, scheduled: Bool, message: String = "") -> Self {
        Self(arrivalEpoch: arrival.timeIntervalSince1970,
             updatedEpoch: updatedAt.timeIntervalSince1970,
             validUntilEpoch: min(updatedAt.addingTimeInterval(90), arrival).timeIntervalSince1970,
             status: scheduled ? .scheduled : .live, message: message)
    }

    static func unavailable(at date: Date, message: String = "", cancelled: Bool = false) -> Self {
        Self(arrivalEpoch: nil, updatedEpoch: date.timeIntervalSince1970,
             validUntilEpoch: date.timeIntervalSince1970,
             status: cancelled ? .cancelled : .unavailable, message: message)
    }
}

#if canImport(ActivityKit) && !BUS_CONTRACT_TESTS
struct BusActivityAttributes: ActivityAttributes {
    typealias ContentState = BusArrivalState
    let target: BusTrackingTarget
    let startedAt: Date
}
#endif

/// Shared by app previews and the extension; follows the language at activity creation.
enum BusActivityCopy {
    static func text(_ key: String, language: String) -> String {
        let values: [String: [String]] = [
            "updated": ["Updated", "更新於", "更新于"],
            "stale": ["Open app to refresh", "開啟 App 更新", "打开 App 更新"],
            "unavailable": ["No live prediction", "暫無實時預測", "暂无实时预测"],
            "cancelled": ["Service cancelled", "班次取消", "班次取消"],
            "ended": ["Tracking ended", "已停止追蹤", "已停止跟踪"],
            "scheduled": ["Scheduled", "預定班次", "计划班次"],
            "boarding": ["Board at", "上車站", "上车站"],
            "end": ["End tracking", "停止追蹤", "停止跟踪"],
            "foreground": ["Updates while app is open", "App 開啟時更新", "App 打开时更新"],
            "minutes": ["min", "分鐘", "分钟"]
        ]
        let index = language == "zhHans" ? 2 : (language == "zh" ? 1 : 0)
        return values[key]?[index] ?? key
    }
}
