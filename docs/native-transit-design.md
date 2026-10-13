# Native transit redesign

## Audit and experience contract

The source audit found search as the launch destination, equal visual weight for route and metadata, a map embedded in a scrolling list, repeated ETA polling implementations, fixed-size text, and tap gestures on timeline/map controls. There is no ActivityKit target. Existing regional providers, bookmarks (including migrations), coordinate tags and language resources remain the business foundation. No screenshots were available at audit time; this is a source audit, not a claim of simulator inspection.

Three structural alternatives were considered: search-first (fast for unfamiliar routes), map-first (good for exploration, expensive for repeat trips), and commute-first (best for checking a known departure). The implementation chooses commute-first, with map exploration one tab away.

## Information architecture

- Today: active Lock Screen tracking, saved boarding points with next arrivals, favorite routes, frequently visited stops, quick search. No account, onboarding carousel or decorative hero.
- Search: native searchable and mode scopes, recent destinations, exact route/direction results, separate stop results.
- Nearby: map and list synchronized by selection, walking/navigation action, explicit permission and empty/error states. Coordinates retain their declared reference system.
- Saved: nationwide region sections, route and stop favorites, editing and a direct path to choosing a boarding stop.
- Route: fixed map above an independently scrolling timeline on iPhone; map/timeline side by side in regular width. Direction and service variant remain explicit. Selected stop expands inline; full ETA is a native push.
- ETA: route/destination → boarding stop → next arrival → subsequent services → freshness/status. Tracking is a native sheet with a real WidgetKit layout preview and a disclosure matching the configured update capability.
- Settings: native Form, searchable region sheet, language and arrival display preferences, data source information.
- iPad: native NavigationSplitView sidebar; iPhone: native TabView and independent NavigationStacks. System sheets retain swipe dismissal and detents.

## Design system (Warm Minimal brand)

Original adaptive warm backgrounds and semantic text tokens, Warm Coral #E85D3A for actions, and operator colors limited to route identity. SF Pro for text; SF Rounded and tabular digits for route codes and arrivals. All readable typography scales with Dynamic Type. Spacing: 4/8/16/24/32. Primary controls have 44pt minimum targets. Content has no glass backgrounds; iOS 26 uses native bars plus one glass control style, with opaque Reduce Transparency and pre-26 fallbacks.

## Motion contract

| Interaction | Motion and state owner | Reduced effects |
| --- | --- | --- |
| Boarding selection | Retargetable 0.32s, low-bounce spring; route detail owns selected sequence; map camera follows a list selection; only map-originated selections scroll the timeline, so tapping an expanded stop never moves its own disclosure button | Immediate selection/camera and scroll |
| Saved trip expansion | matchedGeometryEffect within a single hierarchy; one source badge per trip; native navigation from the expanded preview to route detail/ETA | Immediate expansion |
| Route push on iOS 26+ | Native source-linked zoom, system interactive back | System push when Reduce Motion is enabled |
| ETA changes | numericText + scoped smooth animation; arrival slots retain identity while timestamps change | Immediate text update |
| Favorite / tracking commit | Discrete symbol bounce and selection/success sensory feedback | Symbol effects removed; state and labels still update |
| Sheet | Native interactive detents, cancellation owned by sheet item | System accessibility behavior |

No perpetual symbol effects, phase loops, artificial animation delays or decorative gradients. Phase/keyframe animators are deliberately unnecessary for these finite interactions.

Toolbar refinement: account, region, favorite, refresh and direction controls have 44 × 44pt targets. iOS 17–18 retain traditional native toolbar buttons. iOS 26 hides the bar's shared capsule before applying interactive glass in `Circle()`; Reduce Transparency on iOS 26 uses an opaque circular surface; older systems use native buttons without custom glass or circle backgrounds. Textual Done/Edit controls retain native text button treatment.

## Data and lifecycle

ETA sessions own loading, successful/empty/error snapshots and timestamps. Refreshes coalesce and preserve the previous snapshot on transport failure. Region/provider/operator-bound/service/stop-sequence identity is checked before requests and deep-link resolution. Refreshing never changes row identity or sorts the whole page. Timelines run only on visible/active surfaces. Live Activities use absolute arrival/freshness timestamps and ActivityContent, no extension networking; remote APNs deployment is a separate documented phase.

## Skill provenance

Applied: [SwiftUI Expert](https://github.com/AvdLee/SwiftUI-Agent-Skill/tree/main/skills/swiftui-expert-skill), [Interface Design](https://github.com/ZHUOLIN0928/swiftui-interface-design-skill), [iOS Design Agent](https://github.com/vermont42/iOS-Design-Agent-Skill/tree/main/ios-design-agent-skill), [Animation](https://github.com/dpearson2699/swift-ios-skills/tree/main/skills/swiftui-animation), [Liquid Glass](https://github.com/dpearson2699/swift-ios-skills/tree/main/skills/swiftui-liquid-glass), [ActivityKit](https://github.com/dpearson2699/swift-ios-skills/tree/main/skills/activitykit). Availability and SDK compilation take precedence over examples targeting later Swift versions. User-requested native restraint takes precedence over decorative suggestions. Validation evidence and remaining hard gates are recorded separately; no Apple-quality or frame-rate score is inferred from code alone.


The activity-focused revision additionally applies [Apple Design](https://github.com/tzzs/apple-design-skill), [WidgetKit](https://github.com/dpearson2699/swift-ios-skills/tree/main/skills/widgetkit), [Push Notifications](https://github.com/dpearson2699/swift-ios-skills/tree/main/skills/push-notifications) and [iOS Accessibility](https://github.com/dpearson2699/swift-ios-skills/tree/main/skills/ios-accessibility), including their relevant references for compact layouts, lifecycle, token rotation, animation and accessibility. Pasted list numbers in the requested URLs were resolved to the actual skill directories. Apple HIG and ActivityKit documentation take precedence; Xcode 26 builds verify availability; the deployment target is iOS 17. See [the independent activity design](activity-design.md).

## Supported generations and countdown verification

The app, extension and UI test targets all deploy to iOS 17. Native TabView/NavigationStack, List/Form, menus, searchable and interactive sheets retain the installed system appearance. iOS 26 alone opts into native glass effects and prominent glass actions; iOS 18 adds source-linked native navigation. iOS 17 retains native push transitions. iOS 18+ activity minutes use the built-in system minute timer; iOS 17 uses explicitly timestamped snapshots. Route themes and the compact ETA board are detailed in route-eta-redesign.md. No pre-26 glass emulation is used. Shared providers, boarding identity and Codable state are unchanged.

The countdown contract uses ceil(max(0, arrival - currentTime) / 60), with finite-value checks. Contract tests cover 07:54/07:57/07:59 to 08:00, fractional minutes, cross-midnight, equivalent time zones, DST, expiry, cancellation, revised predictions, timestamped minute snapshots and state serialization. CI verifies the packaged deployment versions and captures the same simulator binary on each supported OS generation.
