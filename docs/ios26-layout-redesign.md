# iOS 26 layout revision

## Baseline and integration

Inspected on 2026-11-14 (Asia/Hong_Kong), after fetching all remotes:

| Ref | Commit | Integration status |
| --- | --- | --- |
| `main`, `origin/main` | `76b05be` | Starting point |
| `codex/route-aware-eta-redesign` (local and origin) | `6572173` | Already an ancestor of main |
| `feat/native-transit-live-activities` (local and origin) | `d180c55` | Already an ancestor of main |
| `master` | `410db07` | Already an ancestor of main |

All existing development work is already integrated. Re-merging or replaying those commits is unnecessary. This layout revision lives on `codex/ios26-native-layout`; the original branches are retained.

The app, extension and UI tests retain **iOS 17.0** and **Swift 5 language mode**. The project requires **Xcode 26 and the iOS 26 SDK**; it does not migrate to Swift 6 language mode. The existing SwiftUI/Observation services, provider boundaries, regional bookmarks, live activities and serialized identities are retained. No package dependencies were added.

## Design

Keep coral `#E85D3A` and operator-specific route identity, with system grouped backgrounds and semantic labels for app content. Native SF semantic text styles and rounded tabular departure numerals supply the type hierarchy. Global actions use `RouteTheme.global.accent` for the existing contrast adjustment of coral. A departure row puts its route sign, destination and boarding stop beside a compact next-arrival column. Native List owns grouped row shape, separators and section spacing.

| Screen | Result |
| --- | --- |
| Navigation | iOS 18+ uses one `.sidebarAdaptable` TabView through window changes, with Today, Nearby, Saved and a dedicated Search role. iOS 26 minimizes tabs on scroll except with Reduce Motion or accessibility text sizes. iOS 17 keeps classic navigation. |
| Today | Region-aware date, functional search/nearby shortcuts, active trips, boarding cards, saved routes and recent stops. Active trips are excluded from duplicate boarding rows. Cards disclose following departure/freshness and retain swipe removal. |
| Tracking | Shares the route sign and arrival value with boarding cards. The opaque surface improves reading under system bars; update capability, freshness, stale and terminal states remain explicit. Settings, display format and scheduled markers are respected. |
| Search | Native search field and scopes, simpler discovery intro, grouped results and a readable content width. No-result, loading and retry states remain distinct. |
| Nearby | Map above stops in narrow space and beside stops at 720pt of actual offered width. Row selection moves the camera; only a map-originated selection scrolls the list. Stops without MapKit-safe coordinates open their departure board directly. |
| Route | Reflows the same map and timeline with AnyLayout instead of rebuilding containers; map height follows available height. At accessibility text sizes the full stop timeline takes priority. |
| Saved / ETA | Readable-width grouped content, clearer city/count headings and a centered segmented picker for saved routes/stops (a native menu at accessibility text sizes). Empty saved collections can open Search. The existing compact ETA board and identity checks remain intact. |

Content width is capped at 960pt. Content surfaces have no custom outlines, shadows or glass; system colors, native bars, sheets and controls own contrast and Reduce Transparency behavior. Accessibility text sizes reflow trip identity, arrival and actions vertically. Primary controls retain 44pt targets, decorative symbols are hidden where appropriate, and existing VoiceOver labels/selected values remain available.

The native-control refinement removes padded/custom-width toolbar labels, makes region/settings actions symbol-only, and separates refresh/favorite, reverse/favorite and navigation/favorite with iOS 26 ToolbarSpacer. Navigation bars draw their own circular backgrounds; content-area icon actions use bordered circle buttons. City names move to native iOS 26 navigation subtitles. Text actions keep their native text/capsule styles. Pre-iOS-26 toolbar icons use native bordered circles.

## State and performance review

- Search uses a cancellable `.task(id:)` keyed by trimmed query, mode, language, region, data revision and explicit retry. Blank queries do not reach a provider. A cancelled predecessor cannot clear the current loading state. The data revision reruns a query after initial database loading.
- Route results resolve their entries once after searching, so List receives one concrete row per stable result ID instead of a conditional row and a database lookup during layout.
- Nearby reloads are keyed by quantized location, region, data revision and language. The existing generation guard still protects concurrent refreshes.
- Clock-dependent arrival text is isolated in `BoardingArrivalValue`; the page, route map and identity do not read its TimelineView clock. `Date.FormatStyle` replaces per-tick formatter construction in the new card renderer and uses the trip's time zone.
- AnyLayout changes geometry while retaining map/camera and disclosure ownership. List/ForEach continue to provide lazy, stable-identity rows.
- Foreground arrival refresh intervals, ActivityKit freshness rules and backend update contracts are unchanged. No frame-rate or CPU improvement is asserted without Instruments measurements.

## Reference and API checks

Read the current [SwiftUI Expert README](https://github.com/AvdLee/SwiftUI-Agent-Skill), [SKILL.md](https://github.com/AvdLee/SwiftUI-Agent-Skill/blob/main/skills/swiftui-expert-skill/SKILL.md), and references for Liquid Glass, layouts, accessibility, performance, navigation and relevant API migration. Newer SDK 27 examples in that repository are excluded from this Xcode 26 project.

Apple's documentation confirms [custom-label Tab with a role](https://developer.apple.com/documentation/swiftui/tab/init(value:role:content:label:)) and [SidebarAdaptableTabViewStyle](https://developer.apple.com/documentation/swiftui/sidebaradaptabletabviewstyle) require iOS 18; [tabBarMinimizeBehavior](https://developer.apple.com/documentation/swiftui/view/tabbarminimizebehavior(_:)) requires iOS 26. Those paths are availability-gated. [MapStyle.standard](https://developer.apple.com/documentation/mapkit/mapstyle/standard(elevation:emphasis:pointsofinterest:showstraffic:)) supports the iOS 17 baseline. Native chrome follows [Apple's new-design guidance](https://developer.apple.com/videos/play/wwdc2025/323/).

## Validation

The implementation environment is Windows, with Python 3.14 and Node 24.15. There is no Swift compiler, Xcode, Apple SDK, Instruments or iOS simulator in this environment.

Completed locally:

- `py -3 scripts/check_transit_resources.py`: literal UI keys have English, Traditional Chinese and Simplified Chinese; host/extension configuration and all six iOS 17 deployment settings pass.
- `npm test` in `server/live-activities`: **10/10 passed**, including provider identity, stale predictions, durable subscriptions and APNs request contracts.
- Swift syntax parsing with temporary `tree-sitter 0.26.1` / `tree-sitter-swift 0.7.4`: no grammar errors in the modified Swift files. This is not Swift type checking or an SDK build.
- Property lists, entitlements and shared Xcode schemes parse; the expanded screenshot script passes Bash syntax checking.
- `git diff --check`: passed.

Added UI regression scenarios for Home → Nearby → stop board, clearing/replacing search queries, and retaining an arrival destination through rotation. Existing boarding, tracking, stale-state and accessibility tests remain. The screenshot script now includes Home, Search, Nearby, Saved and Route in light/dark, accessibility text sizes and iPad, alongside existing ETA/activity scenarios.

The local checks do not establish simulator build, UI-test, screenshot, unsigned device archive, VoiceOver or Instruments results. Remote build evidence is recorded in the GitHub Actions run history. The manual Preview IPA path compiles and packages the app using Xcode 26.0.1 on the explicit `macos-15-intel` hosted image; the explicit toolchain keeps the iOS 26.0 SDK baseline and provides an alternative to the ARM runner queue. The full Build workflow separately owns simulator, UI-test and screenshot validation. Signed-device behavior and performance measurements require device testing.

An opt-in `native_ui_preview` workflow job uses Xcode 26.0.1 on `macos-26-intel`, with an iPhone 16 simulator, for focused iOS 26 geometry/action/accessibility tests and actual screenshots in light, dark and accessibility text sizes. It records button frames and verifies separate toolbar hit regions, including Settings beside the text Edit action; screenshots are reviewed separately to verify the visible circle backgrounds. The fixture database includes both route directions to exercise the reverse control. This preview job does not replace the full compatibility matrix or a signed-device test.
