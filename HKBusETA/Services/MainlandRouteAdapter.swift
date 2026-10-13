import Foundation

/// Explicit adapter from vendor-neutral mainland base data to the shared
/// route screens. Coordinate tags are preserved at this boundary; GCJ-02 is
/// never presented to MapKit as WGS-84.
enum MainlandRouteAdapter {
    static func makeSharedRoute(
        from payload: MainlandLinePayload
    ) -> (entry: RouteEntry, stops: [String: StopEntry], metadata: MainlandRouteMetadata)? {
        let stopIDs = payload.stops.map(\.stopID).filter { !$0.isEmpty }
        guard !stopIDs.isEmpty else { return nil }

        var stopEntries: [String: StopEntry] = [:]
        for stop in payload.stops where !stop.stopID.isEmpty {
            guard let coordinate = stop.location else { continue }
            let system: TransitCoordinateSystem = coordinate.system == .gcj02 ? .gcj02 : .wgs84
            stopEntries[stop.stopID] = StopEntry(
                location: StopLocation(
                    lat: coordinate.latitude,
                    lng: coordinate.longitude,
                    coordinateSystem: system
                ),
                name: Terminal(en: stop.name, zh: stop.name)
            )
        }

        let operatorName = payload.line.operatorName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let companies = operatorName.map { [$0] } ?? []
        let fares = payload.line.fare.map { [$0] }
        let entry = RouteEntry(
            route: payload.line.name,
            co: companies,
            orig: Terminal(en: payload.line.origin, zh: payload.line.origin),
            dest: Terminal(en: payload.line.destination, zh: payload.line.destination),
            fares: fares,
            faresHoliday: nil,
            freq: nil,
            jt: nil,
            seq: stopIDs.count,
            serviceType: FlexibleString("1"),
            stops: ["mainland": stopIDs],
            bound: [:],
            gtfsId: FlexibleString(payload.line.lineID),
            nlbId: nil
        )
        return (entry, stopEntries, payload.routeMetadata)
    }
}

enum MainlandProviderPalette {
    static func color(for line: String) -> UInt32 {
        RouteTheme.mainlandColor(for: line)
    }
}
