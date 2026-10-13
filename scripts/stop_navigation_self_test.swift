import Foundation

@main
struct StopNavigationSelfTest {
    static func main() {
        let wgs84 = StopLocation(lat: 22.3193, lng: 114.1694, coordinateSystem: .wgs84)
        let gcj02 = StopLocation(lat: 22.5431, lng: 114.0579, coordinateSystem: .gcj02)

        precondition(
            StopNavigationURLBuilder.strategy(for: wgs84) == .appleMapsWalking,
            "WGS-84 must use Apple Maps"
        )
        precondition(
            StopNavigationURLBuilder.strategy(for: gcj02) == .amapWalking,
            "GCJ-02 must use AMap"
        )
        precondition(
            StopNavigationURLBuilder.makeAMapURL(for: wgs84, localizedName: "WGS station") == nil,
            "WGS-84 must not produce an AMap URI"
        )

        guard let url = StopNavigationURLBuilder.makeAMapURL(
            for: gcj02,
            localizedName: "深圳車站 A/B"
        ) else {
            preconditionFailure("GCJ-02 AMap URI was not created")
        }
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            preconditionFailure("AMap URI could not be parsed")
        }
        let query = Dictionary(
            uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") }
        )
        precondition(url.scheme == "iosamap")
        precondition(url.host == "path")
        precondition(query["sourceApplication"] == "Where My Bus Now")
        precondition(query["dlat"] == "22.5431")
        precondition(query["dlon"] == "114.0579")
        precondition(query["dname"] == "深圳車站 A/B")
        precondition(query["dev"] == "0")
        precondition(query["t"] == "2")
        precondition(!query.keys.contains("slat"))
        precondition(!query.keys.contains("slon"))
        precondition(!query.keys.contains("sname"))
        precondition(url.absoluteString.contains("%E6%B7%B1%E5%9C%B3"))
        precondition(url.absoluteString.contains("sourceApplication=Where%20My%20Bus%20Now"))

        let invalid = StopLocation(lat: 91, lng: 114, coordinateSystem: .gcj02)
        precondition(StopNavigationURLBuilder.makeAMapURL(for: invalid, localizedName: "Invalid") == nil)

        let joint = RouteEntry(route: "1", co: ["kmb", "ctb"], orig: Terminal(en: "A", zh: "甲"),
            dest: Terminal(en: "A", zh: "甲"), fares: nil, faresHoliday: nil, freq: nil, jt: nil,
            seq: 0, serviceType: FlexibleString("1"), stops: ["ctb": ["x", "y", "x"], "kmb": ["a", "b", "a"]],
            bound: ["kmb": "O", "ctb": "O"], gtfsId: nil, nlbId: nil)
        precondition(joint.canonicalStops == ["a", "b", "a"])
        precondition(joint.canonicalSequence(for: "a", preferredSequence: 2) == 2, "Loop occurrence must survive")
        precondition(joint.canonicalSequence(for: "x", preferredSequence: 2) == 2, "Legacy operator identity must survive")
        precondition(joint.canonicalSequence(for: "b", preferredSequence: 0) == 1, "Moved stop must recover by ID")
        precondition(joint.canonicalSequence(for: "deleted", preferredSequence: 1) == nil, "Never silently open a different stop")

        print("STOP NAVIGATION SELF-TEST OK")
    }
}
