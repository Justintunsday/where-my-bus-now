# Independent bus activity design

## Four surfaces, four jobs

| Surface | Hierarchy and behavior |
| --- | --- |
| Compact leading | Full rounded route code, then a smaller full code if needed; an identifiable bus symbol for unusually long route names. No ellipsis through a route identifier. The tracked route theme is an accent on the system's black background. |
| Compact trailing | System-rendered whole minutes on iOS 18+; explicitly timestamped minute snapshots on iOS 17. A status symbol replaces an invalid countdown. Monospaced digits and no unnecessary surrounding label preserve width. |
| Minimal | One recognizable bus/status symbol. The full route and status remain in its accessibility label. No destination or competing tiny numbers. |
| Expanded | Route and dominant countdown form the top row. Actual ETA clock sits beneath the countdown. Destination occupies the expanded center region; boarding stop and optional second departure and status/update timestamp form the lower region. Long top content may move below the sensor region using the system placement API. |
| Lock Screen | A horizontal departure board: route/destination/stop on the left, countdown on the right. Clock times form a separate line; status/update timestamp and the native end intent form the footer. This is structurally different from the expanded Island. |
| Additional system surfaces | The system adapts the registered core layouts for other supported surfaces. No custom supplemental family is registered, keeping a single native Widget entry point across iOS 17 and later. |

The Lock Screen adapts warm white/charcoal surfaces to appearance. The Island's black background belongs to the system. Always-On reduces emphasis and removes content transitions; the real environment is `isLuminanceReduced`. A debug-only override supports layout inspection and does not pretend to be a hardware AOD capture. Accessibility sizes switch to a single-column board with a full-width boarding stop, route/countdown header and short 24-hour arrival clock. Smaller semantic caption styles still scale with Dynamic Type; destination and last-update metadata remain in VoiceOver descriptions rather than competing for finite Lock Screen height. The primary arrival and stop take priority over the optional second departure. Full stop/destination descriptions are available to VoiceOver and the ETA deep link; finite system surfaces necessarily limit visible lines.

## Prediction states

| Incoming evidence | State / visible response | Lifecycle |
| --- | --- | --- |
| Valid future predictions | Next and optional second arrival; actual clock and timestamped whole minutes | Update the existing activity |
| Next arrival within a minute | “Arriving soon”, same restrained hierarchy | No alert or loop |
| New prediction differs by at least 15 seconds | “ETA revised”, replace the absolute clock and countdown | Native content update |
| A new snapshot replaces a past prediction | “Next departure selected” | Keep the same route/stop identity |
| Operator explicitly reports arrived/departed | Distinct check/arrow status; no live countdown | End with a short dismissal interval unless a new future service is already available |
| Explicit cancellation | Cancellation symbol/text; remove arrival | End with a short dismissal interval |
| Successful response has no future departures | “No further departures” | End with a short dismissal interval |
| Transport failure | Offline status; retain last clock times and the last successful timestamp | Mark stale; configured server retries independently of the app |
| API/data failure | Prediction unavailable; preserve last clock history when available | Mark stale, no fabricated ETA |
| No new snapshot before stale date / predicted arrival | “Open app to refresh”; countdown becomes invalid | No local inference that the bus physically arrived |
| User ends | End immediately | App, Settings or Lock Screen intent |

The second bus never silently becomes the first merely because a timer elapsed. Only a fresh provider snapshot or APNs content update can make that decision. `change` is metadata for a single update, not a perpetual animation. Unix timestamp fields and optional additions preserve decoding of existing activities and saved boarding identities.

## System-supported motion

Countdown digits use identity content transitions to avoid overlapping rolling layers; status changes retain scoped replacement/opacity transitions. ActivityKit owns update animation, scheduling and duration. There is no extension timer, TimelineView, task, network request, spring, matched geometry or repeated symbol effect. Reduce Motion and dimmed presentation remove transitions. The main app continues to use springs, source-linked navigation, matched geometry and sensory feedback where supported; these are separate from widget animation.

## Inspection and validation

`BusArrivalWidget.swift` supplies actual WidgetKit previews for Lock Screen, compact, expanded and minimal presentations. The Lock Screen preview cycles all twelve scenarios; expanded previews include normal, revised, next bus, offline, no service and cancellation. `ActivityPreviewGallery` displays the actual shared components, with an interactive status picker and long-name toggle; SwiftUI previews include light, dark, accessibility text and dimmed variants. CI screenshots of this gallery are layout evidence, not photos of a signed device's Island.

The eight design checks are: appropriate system structure, useful hierarchy, restrained material, consistent brand, explicit interaction feedback, readable compact content, truthful freshness, and accessibility alternatives. They are implemented in code and checked through previews/tests; hardware presentation, VoiceOver exploration, interruption performance and real APNs delivery remain explicit device/deployment gates. No visual quality score or frame-rate claim is inferred from source code.

Primary specifications: [Apple Live Activities HIG](https://developer.apple.com/design/human-interface-guidelines/live-activities), [custom ActivityKit views](https://developer.apple.com/documentation/activitykit/creating-custom-views-for-live-activities), [ActivityKit push updates](https://developer.apple.com/documentation/activitykit/starting-and-updating-live-activities-with-activitykit-push-notifications).

## Exact minute rendering

The app and native system path share ceil rounding. iOS 18+ uses the built-in SystemFormatStyle.Timer at minute precision; its truncation is compensated only in the formatting endpoint, leaving the actual arrival and stale dates unchanged. Native formatter tests cover fractional minutes, minute/hour/day boundaries and bounded zero output. WidgetKit uses the system-owned time source and serializable built-in style, avoiding custom formatter decoding. iOS 17 retains the explicit `*` snapshot at updatedAt with a timestamp and VoiceOver disclosure. Stale/cancelled/unavailable states never continue a live prediction. See [the complete route-aware design](route-eta-redesign.md).

Primary API references: [SystemFormatStyle.Timer](https://developer.apple.com/documentation/swiftui/systemformatstyle/timer) and [TimeDataSource](https://developer.apple.com/documentation/swiftui/timedatasource).
