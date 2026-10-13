import SwiftUI

struct RouteDetailTarget: Hashable {
    let routeKey: String
}

struct RouteEtaTarget: Hashable {
    let routeKey: String
    let seq: Int
}

struct StopTarget: Hashable {
    let stopId: String
}

struct MainlandLineTarget: Hashable {
    let lineId: String
    let title: String
    /// When non-nil the loader pushes the ETA screen at this stop sequence.
    let seq: Int?
    let modeHint: MainlandTransitMode
    let origin: String?
    let destination: String?
    let firstDeparture: String?
    let lastDeparture: String?
    let fare: String?

    init(
        lineId: String,
        title: String,
        seq: Int? = nil,
        modeHint: MainlandTransitMode = .bus,
        origin: String? = nil,
        destination: String? = nil,
        firstDeparture: String? = nil,
        lastDeparture: String? = nil,
        fare: String? = nil
    ) {
        self.lineId = lineId
        self.title = title
        self.seq = seq
        self.modeHint = modeHint
        self.origin = origin
        self.destination = destination
        self.firstDeparture = firstDeparture
        self.lastDeparture = lastDeparture
        self.fare = fare
    }
}

struct MainlandStopTarget: Hashable {
    let stopID: String
    let namesakeStopID: String?
    let title: String
    let location: StopLocation?

    init(
        stopID: String,
        namesakeStopID: String? = nil,
        title: String,
        location: StopLocation? = nil
    ) {
        self.stopID = stopID
        self.namesakeStopID = namesakeStopID
        self.title = title
        self.location = location
    }
}

/// A persisted navigation target that keeps the owning transit region. This
/// prevents identical route/stop IDs in different cities from being resolved
/// against whichever region happens to be active.
struct SavedRouteTarget: Hashable {
    let regionID: String
    let routeKey: String
    let lineID: String?
    let route: String
    let origin: String
    let destination: String
    let seq: Int?
    let modeRawValue: String?
    let stopID: String?

    init(_ item: RegionalFavoriteRoute) {
        let value = item.favorite
        regionID = item.regionID
        routeKey = value.routeKey
        lineID = value.lineID
        route = value.route
        origin = value.origZh.isEmpty ? value.origEn : value.origZh
        destination = value.destZh.isEmpty ? value.destEn : value.destZh
        seq = nil
        modeRawValue = value.modeRawValue
        stopID = nil
    }

    init(regionID: String, recent: RecentRoute) {
        self.regionID = regionID
        routeKey = recent.routeKey
        lineID = recent.lineID
        route = recent.route
        origin = recent.origZh.isEmpty ? recent.origEn : recent.origZh
        destination = recent.destZh.isEmpty ? recent.destEn : recent.destZh
        seq = recent.seq
        modeRawValue = recent.modeRawValue
        stopID = recent.stopId
    }

    var modeHint: MainlandTransitMode {
        modeRawValue.flatMap { MainlandTransitMode(rawValue: $0) } ?? .bus
    }
}

struct SavedStopTarget: Hashable {
    let regionID: String
    let stopID: String
    let title: String
    let latitude: Double
    let longitude: Double

    init(_ item: RegionalFavoriteStop) {
        regionID = item.regionID
        stopID = item.favorite.id
        title = item.favorite.nameZh.isEmpty ? item.favorite.nameEn : item.favorite.nameZh
        latitude = item.favorite.lat
        longitude = item.favorite.lng
    }

    init(regionID: String, recent: RecentStop) {
        self.regionID = regionID
        stopID = recent.id
        title = recent.nameZh.isEmpty ? recent.nameEn : recent.nameZh
        latitude = recent.lat
        longitude = recent.lng
    }

    var location: StopLocation {
        StopLocation(lat: latitude, lng: longitude)
    }
}
