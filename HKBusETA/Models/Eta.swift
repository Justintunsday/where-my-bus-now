import Foundation

struct Eta: Identifiable, Equatable, Sendable {
    let eta: String
    let remark: Terminal
    let dest: Terminal
    let co: String

    var id: String { "\(co)|\(eta)|\(dest.en)|\(remark.en)" }

    var date: Date? { RegionClock.date(fromISO: eta) }

    var isScheduled: Bool {
        remark.zh.hasSuffix("班次") || remark.en.hasSuffix("Scheduled Bus") || remark.en == "Scheduled"
    }

    var minutesUntil: Int? {
        guard let date else { return nil }
        return Int(round(date.timeIntervalSinceNow / 60))
    }
}

/// Raw ETA payloads from data.gov.hk
struct KMBEtaResponse: Decodable {
    let data: [Item]

    struct Item: Decodable {
        let dir: String
        let seq: Int
        let eta: String?
        let rmk_tc: String?
        let rmk_en: String?
        let dest_tc: String?
        let dest_en: String?
        let service_type: Int?
    }
}

struct CTBEtaResponse: Decodable {
    let data: [Item]

    struct Item: Decodable {
        let dir: String?
        let seq: Int?
        let eta: String?
        let rmk_tc: String?
        let rmk_en: String?
        let dest_tc: String?
        let dest_en: String?
    }
}

struct NLBEtaResponse: Decodable {
    let estimatedArrivals: [Item]?
    let message: String?

    struct Item: Decodable {
        let estimatedArrivalTime: String?
        let departed: String?
        let noGPS: String?
        let routeVariantName: String?
    }
}

struct GMBEtaResponse: Decodable {
    let data: [Item]?

    struct Item: Decodable {
        let route_seq: Int
        let stop_seq: Int
        let enabled: Bool
        let eta: [EtaItem]?
        let description_tc: String?
        let description_en: String?
    }

    struct EtaItem: Decodable {
        let timestamp: String?
        let remarks_tc: String?
        let remarks_en: String?
    }
}

struct MTRBusScheduleResponse: Decodable {
    let busStop: [StopItem]?
    let routeStatusRemarkTitle: String?

    struct StopItem: Decodable {
        let busStopId: String
        let busStopRemark: String?
        let bus: [BusItem]
    }

    struct BusItem: Decodable {
        let arrivalTimeInSecond: String?
        let departureTimeInSecond: String?
        let busRemark: String?
        let isScheduled: String?
    }
}

struct MTRScheduleResponse: Decodable {
    let data: [String: LineData]?
    let status: Int?
    let message: String?

    struct LineData: Decodable {
        let UP: [TrainItem]?
        let DOWN: [TrainItem]?
    }

    struct TrainItem: Decodable {
        let time: String?
        let plat: String?
        let dest: String?
    }
}

struct LRTScheduleResponse: Decodable {
    let platform_list: [Platform]?

    struct Platform: Decodable {
        let platform_id: Int
        let route_list: [RouteItem]?
        let end_service_status: Int?
    }

    struct RouteItem: Decodable {
        let route_no: String
        let dest_ch: String?
        let dest_en: String?
        let time_en: String?
        let train_length: Int?
        let routeRemarkEng2: String?
        let routeRemarkChi2: String?
        let additionalInfo1: String?
        let stop: Int?
    }
}
