import CoreLocation
import Foundation
import Observation

@MainActor
@Observable
final class AppState {
    let settings: AppSettings
    /// Active region. Everything region-specific goes through this provider.
    private(set) var region: TransitRegion
    private(set) var provider: any TransitProvider
    private(set) var data: DataStore
    let bookmarks: BookmarkStore
    let location: LocationService
    let arrivals = ArrivalStore()
    let boarding: BoardingStore
    let activities: BusActivityManager
    var presentation: TransitSheet?

    /// Optional mainland query capability exposed to views without coupling
    /// them to a concrete vendor implementation.
    var mainlandProvider: (any MainlandTransitProvider)? {
        provider as? any MainlandTransitProvider
    }

    init(defaults: UserDefaults = .standard, bookmarkURL: URL? = nil,
         activityRegistrar: (any BusActivityPushRegistering)? = nil) {
        let settings = AppSettings(defaults: defaults)
        let region = RegionCatalog.region(for: settings.selectedRegionID) ?? RegionCatalog.hongKong
        let provider = RegionCatalog.provider(for: region)
        self.settings = settings
        self.region = region
        self.provider = provider
        data = DataStore(provider: provider)
        bookmarks = BookmarkStore(regionID: region.id, storageURL: bookmarkURL)
        boarding = BoardingStore(defaults: defaults)
        location = LocationService()
        activities = BusActivityManager(registrar: activityRegistrar ?? BusActivityRemoteConfiguration.registrar())
        RegionClock.timeZone = provider.timeZone
    }

    /// Applies a region selection from Settings or auto-detection.
    func selectRegion(_ regionID: String) {
        if regionID == RegionCatalog.autoID {
            if let current = location.location {
                let nearest = RegionCatalog.nearest(to: current)
                if nearest.id != region.id {
                    apply(nearest)
                }
            }
            return
        }
        guard let region = RegionCatalog.region(for: regionID), region.id != self.region.id else { return }
        apply(region)
    }

    /// Opens a nationwide favorite in its owning transit system and keeps the
    /// explicit selection stable instead of allowing auto-location to switch
    /// regions while the destination is loading.
    func openSavedRegion(_ regionID: String) {
        guard RegionCatalog.region(for: regionID) != nil else { return }
        settings.selectedRegionID = regionID
        settings.persist()
        selectRegion(regionID)
    }

    /// In auto mode, resolves the region from the device location once known.
    func resolveAutoRegion(location: CLLocation?) {
        guard settings.selectedRegionID == RegionCatalog.autoID, let location else { return }
        let nearest = RegionCatalog.nearest(to: location)
        guard nearest.id != region.id else { return }
        apply(nearest)
    }

    private func apply(_ region: TransitRegion) {
        let provider = RegionCatalog.provider(for: region)
        self.region = region
        self.provider = provider
        RegionClock.timeZone = provider.timeZone
        bookmarks.selectRegion(region.id)
        data = DataStore(provider: provider)
        Task { await data.load() }
    }
}
