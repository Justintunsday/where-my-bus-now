# Where My Bus Now (WMBN) · 1.9.0

![Build](https://github.com/Justintunsday/where-my-bus-now/actions/workflows/build.yml/badge.svg)

An unofficial, ad-free multi-region realtime bus ETA app built with SwiftUI.

Where My Bus Now started as a SwiftUI rewrite of [hkbus/hk-independent-bus-eta](https://github.com/hkbus/hk-independent-bus-eta).
Since 1.1 it supports mainland Chinese cities. Mainland data is served by the
hosted [chelaile-api-server](https://github.com/Justintunsday/chelaile-api-server)
with automatic failover between its public instances; AMap remains optional
official base data when configured. This is not an official app.

## Features

- **Region switching, auto-detected from your location**: Hong Kong, plus
  Shenzhen, Guangzhou, Shanghai, Beijing, Tianjin, Chongqing, Chengdu,
  Foshan, Qingdao, Shenyang, Nanjing and Xi'an
- Every region has its own independent data; search, nearby, favorites and
  history are stored in separate region namespaces and follow the selected city
- **Hong Kong**: realtime arrivals for KMB, Citybus, NLB, green minibus,
  MTR Bus, Light Rail, MTR and ferries; route details with fares, service
  hours and headways
- **Mainland cities**: hosted CheLaile API search, nearby, stop boards, line
  details and realtime ETAs, with automatic failover between the two public
  API instances; configured AMap data is kept as an official base-data layer
- Route detail: MapKit map (polyline, numbered stop pins, tap to sync),
  timeline of stops, tap a stop to expand inline arrivals, and navigate to
  any stop with a valid coordinate
- Stop departure boards with aligned tabular ETA columns
- Nearby stops with distance, favorites for whole routes and stops, recents
- ETA display modes (clock time / minutes / both), scheduled-trip markers
- Traditional Chinese, Simplified Chinese and English
- iPhone and iPad, dark mode, iOS 26 Liquid Glass

## Architecture

- SwiftUI + `@Observable` (iOS 17+), no third-party dependencies
- **`TransitProvider` protocol**: everything region-specific (data source,
  time zone, operators, calendars, fares, colors, ETA fetching) lives behind
  one interface
  - `HongKongProvider`: static database (updated daily) + data.gov.hk
    operator ETA APIs
- `MainlandTransitProvider`: vendor-neutral search, nearby, stop-board,
  line-payload and ETA capabilities with `MainlandProviderRouter` fallback
  composition
  - `CheLaileAPIClient`/`CheLaileAPIProvider`: hosted `/v1` API primary,
    including source-safe `physicalStId` → `sId` realtime translation. The
    client fails over between the documented public instances
    (`ts-api.tundrey.com`, then the Vercel deployment) on transport and 5xx
    failures
  - `AMapTransitProvider`: optional official AMap Web Service base-data layer;
    its IDs are never sent to the hosted realtime endpoint
- `RegionCatalog`: bundled city list and "nearest city" auto-selection;
  `RegionClock` carries the active time zone
- Query-mode lines are synthesized into standard `RouteEntry` values and
  registered in `DataStore`, so the map / timeline / ETA screens are fully
  reused across regions
- **Liquid Glass**: built with the Xcode 26 / iOS 26 SDK, standard controls
  adopt Liquid Glass automatically on iOS 26+; custom controls use the
  `glassEffect` API (compiler-gated so Xcode 16 still builds)
- Xcode 16 synchronized folders (`PBXFileSystemSynchronizedRootGroup`) — new
  files need no `project.pbxproj` changes
- `HKBusETA/Models` — EtaDB, TransitOperator, TransitRegion
- `HKBusETA/Services` — TransitProvider, HongKongProvider, mainland provider
  protocols/routers, AMapClient/AMapTransitProvider, hosted CheLaile client,
  DataStore, ETA services, bookmarks, location
- `HKBusETA/Views` — search, route, ETA, nearby, favorites, settings
- `docs/brand-spec.md` — Warm Minimal design system

## Build

Requirements: macOS + Xcode 26 (iOS 26 SDK for Liquid Glass; Xcode 16 also
builds, without the glass material).

```bash
git clone https://github.com/Justintunsday/where-my-bus-now.git
cd where-my-bus-now
open HKBusETA.xcodeproj
```

GitHub Actions (`macos-26` / Xcode 26.6) runs the offline fixture self-tests
and a non-blocking hosted API reachability probe, then builds the simulator
app, an unsigned device archive and an IPA on every push.

## Data Sources

- Hong Kong ETA data: DATA.GOV.HK and operator APIs; routes, stops, fares
  and headways come from [HK Bus Crawling@2021](https://github.com/hkbus/hk-bus-crawling)
  (`https://data.hkbus.app/routeFareList.min.json`, ~8 MB, downloaded once on
  first launch, cached locally and checked for updates daily)
- Mainland data: [chelaile-api-server](https://github.com/Justintunsday/chelaile-api-server)
  (see its [API documentation](https://github.com/Justintunsday/chelaile-api-server/blob/main/docs/API.md)).
  The app uses `https://ts-api.tundrey.com/v1` as the primary instance and
  `https://chelaile-api-server.vercel.app/v1` as the automatic fallback. It
  supplies search, nearby stops, stop boards, line stations and realtime ETA.
  The default deployment needs no key. Optional `CHELAILE_API_BASE_URL` and
  `CHELAILE_API_KEY` are read from generated `Info.plist` or the process
  environment; no key is stored in source code. An explicit base URL override
  disables the fallback chain.
- Mainland optional base data: [AMap Bus Web Service](https://lbs.amap.com/api/webservice/guide/api-advanced/bus-inquiry)
  endpoints `v3/bus/linename`, `v3/bus/lineid`, `v3/bus/stopname` and
  `v3/bus/stopid` when `AMAP_WEB_SERVICE_KEY` is configured. AMap data is
  GCJ-02 and its line/stop IDs are not mixed with hosted API realtime IDs.
- Station navigation: WGS-84 coordinates open Apple Maps walking directions
  from the current location. GCJ-02 coordinates open the official AMap iOS
  URI with the localized station name; they are never sent to MapKit.
- Mainland realtime ETA: supplied by the hosted CheLaile API, which adapts the
  unofficial CheLaile upstream and may break at any time. AMap is never
  described or used as realtime.
- Operator glyphs: from [hk-independent-bus-eta](https://github.com/hkbus/hk-independent-bus-eta)
  `public/img` (GPL-3.0)

## Disclaimer

This is an unofficial project. Hong Kong data comes from public open data;
mainland data comes from the hosted CheLaile API (which adapts an unofficial
upstream) plus optional official AMap base data — it can stop working at any
time. All arrival data is for reference only — always check with the operator.

## License

[GPL-3.0](LICENSE), matching the upstream
[hk-independent-bus-eta](https://github.com/hkbus/hk-independent-bus-eta) project.
