import Foundation

struct EtaDB: Codable, Sendable {
    let holidays: [String]
    let routeList: [String: RouteEntry]
    let stopList: [String: StopEntry]
    let stopMap: [String: [[String]]]
    let serviceDayMap: [String: [String]]
}

extension EtaDB {
    static let empty = EtaDB(holidays: [], routeList: [:], stopList: [:], stopMap: [:], serviceDayMap: [:])
}

struct Terminal: Codable, Hashable, Sendable {
    private let values: [String: String]

    init(en: String, zh: String) {
        values = ["en": en, "zh": zh]
    }

    init(values: [String: String]) {
        self.values = values
    }

    var en: String { values["en"] ?? "" }
    var zh: String { values["zh"] ?? "" }

    /// Arbitrary locale lookup for future regions.
    func value(_ localeCode: String) -> String? { values[localeCode] }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        values = (try? container.decode([String: String].self)) ?? [:]
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(values)
    }

    func name(_ language: AppLanguage) -> String {
        switch language.resolved {
        case .zhHans:
            if let simplified = values["zh-Hans"] { return simplified }
            return ChineseConverter.simplified(zh)
        case .zh:
            if let traditional = values["zh-Hant"] { return traditional }
            return zh
        default:
            if let direct = values["en"] { return direct }
            return values.values.first ?? ""
        }
    }
}

/// Coordinate reference system for a stop position.
///
/// The bundled Hong Kong database and MapKit use WGS-84. AMap returns GCJ-02;
/// those coordinates are intentionally kept tagged instead of being passed
/// to MapKit as if they were WGS-84. Conversion is not performed without a
/// documented, approved transform.
enum TransitCoordinateSystem: String, Codable, Hashable, Sendable {
    case wgs84
    case gcj02
}

struct StopLocation: Codable, Hashable, Sendable {
    let lat: Double
    let lng: Double
    let coordinateSystem: TransitCoordinateSystem

    init(lat: Double, lng: Double, coordinateSystem: TransitCoordinateSystem = .wgs84) {
        self.lat = lat
        self.lng = lng
        self.coordinateSystem = coordinateSystem
    }

    var isValid: Bool {
        lat.isFinite && lng.isFinite && (-90...90).contains(lat) && (-180...180).contains(lng)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        lat = try container.decode(Double.self, forKey: .lat)
        lng = try container.decode(Double.self, forKey: .lng)
        coordinateSystem = try container.decodeIfPresent(TransitCoordinateSystem.self, forKey: .coordinateSystem) ?? .wgs84
    }

    private enum CodingKeys: String, CodingKey {
        case lat
        case lng
        case coordinateSystem
    }
}

struct StopEntry: Codable, Sendable {
    let location: StopLocation
    let name: Terminal
}

struct RouteEntry: Codable, Sendable {
    let route: String
    let co: [String]
    let orig: Terminal
    let dest: Terminal
    let fares: [String]?
    let faresHoliday: [String]?
    let freq: [String: [String: FreqSlot?]]?
    let jt: FlexibleString?
    let seq: Int
    let serviceType: FlexibleString
    let stops: [String: [String]]
    let bound: [String: String]
    let gtfsId: FlexibleString?
    let nlbId: FlexibleString?

    var serviceTypeValue: String { serviceType.value }

    var isSpecialTrip: Bool { (Int(serviceTypeValue) ?? 1) >= 2 }

    var journeyTimeMinutes: Int? {
        guard let jt, let value = Int(jt.value) else { return nil }
        return value
    }

    var companies: [String] {
        co
    }

    func stopIDs(_ operatorID: String) -> [String] {
        stops[operatorID] ?? []
    }

    /// The longest stop list among serving companies; used as canonical stop sequence.
    var canonicalStops: [String] {
        // Equal-length operator lists must not depend on Dictionary iteration order.
        let keys = co + stops.keys.filter { !co.contains($0) }.sorted()
        return keys.compactMap { stops[$0] }.reduce([]) { best, list in
            list.count > best.count ? list : best
        }
    }

    var boundValue: String { bound.values.first ?? "" }

    var routeKey: String {
        "\(route)+\(serviceTypeValue)+\(orig.en)+\(dest.en)"
    }
}

struct FreqSlot: Codable, Hashable, Sendable {
    /// End time in HHmm (may exceed 24 hours, e.g. "2620" = 02:20 next day).
    let end: String
    /// Headway in seconds.
    let headway: Int

    init(end: String, headway: Int) {
        self.end = end
        self.headway = headway
    }

    init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        end = (try? container.decode(String.self)) ?? ""
        let headwayValue = try? container.decode(FlexibleString.self)
        headway = Int(headwayValue?.value ?? "") ?? 0
    }
}

/// Decodes a value that may be encoded either as a JSON string or a JSON number.
struct FlexibleString: Codable, Hashable, Sendable {
    let value: String

    init(_ value: String) {
        self.value = value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let string = try? container.decode(String.self) {
            value = string
        } else if let int = try? container.decode(Int.self) {
            value = String(int)
        } else if let double = try? container.decode(Double.self) {
            value = String(double)
        } else {
            value = ""
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(value)
    }
}
