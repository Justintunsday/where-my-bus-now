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
    var timeZoneIdentifier: String? = nil

    var timeZone: TimeZone {
        TimeZone(identifier: timeZoneIdentifier ?? "Asia/Hong_Kong") ?? TimeZone(secondsFromGMT: 28_800)!
    }
    var locale: Locale { Locale(identifier: language == "zh" ? "zh_Hant_HK" : (language == "zhHans" ? "zh_Hans_CN" : "en_GB")) }

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
    case live, scheduled, unavailable, networkError, noService, arrived, departed, cancelled, ended
}

enum BusArrivalChange: String, Codable, Hashable, Sendable { case adjusted, nextBus }
enum BusArrivalSource: String, Codable, Hashable, Sendable { case foreground, push }

/// Unix seconds are explicit in the APNs contract (no Foundation reference-date ambiguity).
struct BusArrivalState: Codable, Hashable, Sendable {
    var arrivalEpoch: Double?
    var updatedEpoch: Double
    var validUntilEpoch: Double
    var status: BusArrivalStatus
    var message: String
    // Optional additions decode activities created by earlier versions unchanged.
    var secondArrivalEpoch: Double? = nil
    var change: BusArrivalChange? = nil
    var updateSource: BusArrivalSource? = nil

    var arrival: Date? { arrivalEpoch.map(Date.init(timeIntervalSince1970:)) }
    var updatedAt: Date { Date(timeIntervalSince1970: updatedEpoch) }
    var staleDate: Date { Date(timeIntervalSince1970: validUntilEpoch) }
    var secondArrival: Date? { secondArrivalEpoch.map(Date.init(timeIntervalSince1970:)) }
    var isTerminal: Bool { [.cancelled, .noService, .arrived, .departed, .ended].contains(status) }

    /// Only unambiguous stop/service statements. “Departed from terminal” and
    /// “已開出” can mean an NLB bus is on its way; they must not end this trip.
    static func reportedStatus(_ message: String) -> BusArrivalStatus? {
        switch message.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "cancelled", "canceled", "service cancelled", "service canceled", "班次取消", "已取消", "取消": .cancelled
        case "arrived at stop", "bus arrived", "已到站", "班次已到站": .arrived
        case "departed from this stop", "bus departed", "班次已離站", "班次已离站": .departed
        case "eta unavailable", "temporarily unavailable", "暫無實時預測", "暂无实时预测", "服務暫停", "服务暂停", "暫停服務", "暂停服务": .unavailable
        default: nil
        }
    }

    func isFresh(at date: Date) -> Bool {
        guard let arrivalEpoch, arrivalEpoch.isFinite, updatedEpoch.isFinite,
              validUntilEpoch.isFinite, date.timeIntervalSince1970.isFinite else { return false }
        return date.timeIntervalSince1970 >= updatedEpoch
            && date.timeIntervalSince1970 < min(validUntilEpoch, arrivalEpoch)
            && (status == .live || status == .scheduled)
    }

    /// Round positive fractions up: 60 seconds = 1 min, 61 seconds = 2 min.
    /// Absolute timestamps make hour/day/time-zone boundaries irrelevant.
    static func remainingMinutes(arrival: Date, now: Date) -> Int? {
        let seconds = arrival.timeIntervalSince(now)
        guard seconds.isFinite else { return nil }
        return Int(exactly: ceil(max(0, seconds) / 60))
    }

    func remainingMinutes(at date: Date) -> Int? {
        guard isFresh(at: date), let arrival else { return nil }
        return Self.remainingMinutes(arrival: arrival, now: date)
    }

    /// A prediction is no longer a live prediction after its arrival time.
    static func prediction(arrival: Date, updatedAt: Date, scheduled: Bool, message: String = "") -> Self {
        Self(arrivalEpoch: arrival.timeIntervalSince1970,
             updatedEpoch: updatedAt.timeIntervalSince1970,
             validUntilEpoch: min(updatedAt.addingTimeInterval(90), arrival).timeIntervalSince1970,
             status: scheduled ? .scheduled : .live, message: String(message.prefix(160)))
    }

    static func unavailable(at date: Date, message: String = "", cancelled: Bool = false) -> Self {
        Self(arrivalEpoch: nil, updatedEpoch: date.timeIntervalSince1970,
             validUntilEpoch: date.timeIntervalSince1970,
             status: cancelled ? .cancelled : .unavailable, message: String(message.prefix(160)))
    }

    /// Time passing alone never proves that a bus physically arrived or departed.
    /// Only a new provider snapshot can advance the tracked service.
    static func snapshot(arrivals: [Double], updatedAt: Date, scheduled: Bool = false,
                         message: String = "", explicitStatus: BusArrivalStatus? = nil,
                         previous: Self? = nil) -> Self {
        let upcoming = Array(Set(arrivals.filter { $0.isFinite && $0 > updatedAt.timeIntervalSince1970 })).sorted()
        guard let first = upcoming.first else {
            var result = unavailable(at: updatedAt, message: message)
            result.status = explicitStatus ?? .noService
            return result
        }
        var result = prediction(arrival: Date(timeIntervalSince1970: first), updatedAt: updatedAt,
                                scheduled: scheduled, message: message)
        result.updateSource = .foreground
        result.secondArrivalEpoch = upcoming.dropFirst().first
        if let old = previous?.arrivalEpoch {
            if old <= updatedAt.timeIntervalSince1970 { result.change = .nextBus }
            else if abs(old - first) >= 15 { result.change = .adjusted }
        }
        return result
    }

    /// Retain the last clock times as history, never continue a live countdown after a failure.
    static func failed(previous: Self?, at date: Date, network: Bool, message: String) -> Self {
        var result = previous ?? unavailable(at: date)
        result.status = network ? .networkError : .unavailable
        result.validUntilEpoch = min(result.validUntilEpoch, date.timeIntervalSince1970)
        result.message = String(message.prefix(160))
        result.change = nil
        return result
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
            "arrival": ["Arrival", "預計到站", "预计到站"],
            "stale": ["Open app to refresh", "開啟 App 更新", "打开 App 更新"],
            "unavailable": ["No live prediction", "暫無實時預測", "暂无实时预测"],
            "cancelled": ["Service cancelled", "班次取消", "班次取消"],
            "ended": ["Tracking ended", "已停止追蹤", "已停止跟踪"],
            "scheduled": ["Scheduled", "預定班次", "计划班次"],
            "boarding": ["Board at", "上車站", "上车站"],
            "remaining": ["Time until arrival", "距離到站", "距离到站"],
            "end": ["End tracking", "停止追蹤", "停止跟踪"],
            "foreground": ["Updates while app is open", "App 開啟時更新", "App 打开时更新"],
            "minutes": ["min", "分鐘", "分钟"],
            "asOf": ["At last update", "上次更新時", "上次更新时"],
            "to": ["To", "往", "往"],
            "next": ["Next", "下一班", "下一班"],
            "following": ["Following", "後續班次", "后续班次"],
            "lastKnown": ["Last ETA", "上次預測", "上次预测"],
            "networkError": ["Offline · last received data", "網絡中斷 · 上次資料", "网络中断 · 上次资料"],
            "noService": ["No further departures", "暫無後續班次", "暂无后续班次"],
            "arrived": ["Bus arrived", "班次已到站", "班次已到站"],
            "departed": ["Bus departed", "班次已離站", "班次已离站"],
            "approaching": ["Arriving soon", "即將到站", "即将到站"],
            "adjusted": ["ETA revised", "到站預測已調整", "到站预测已调整"],
            "nextBus": ["Next departure selected", "已切換下一班", "已切换下一班"],
            "timer": ["min:sec", "分：秒", "分：秒"],
            "local": ["Foreground data", "前台資料", "前台资料"],
            "remote": ["Operator prediction", "營運商預測", "运营商预测"]
        ]
        let index = language == "zhHans" ? 2 : (language == "zh" ? 1 : 0)
        return values[key]?[index] ?? key
    }
}
