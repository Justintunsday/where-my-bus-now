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
- ETA: route/destination → boarding stop → next arrival → subsequent services → freshness/status. Tracking is a native sheet with a real WidgetKit layout preview and an explicit foreground-update disclosure.
- Settings: native Form, searchable region sheet, language and arrival display preferences, data source information.
- iPad: native NavigationSplitView sidebar; iPhone: native TabView and independent NavigationStacks. System sheets retain swipe dismissal and detents.

## Design system (standard profile)

System semantic backgrounds and label colors, one adaptive transit-blue action tint, operator colors limited to route identity. SF Pro for text; SF Rounded and tabular digits for route codes and arrivals. All readable typography scales with Dynamic Type. Spacing: 4/8/16/24/32. Primary controls have 44pt minimum targets. Content has no glass backgrounds; iOS 26 uses native bars plus one glass control style, with opaque Reduce Transparency and pre-26 fallbacks.

## Motion contract

| Interaction | Motion and state owner | Reduced effects |
| --- | --- | --- |
| Boarding selection | Retargetable 0.32s, low-bounce spring; route detail owns selected sequence; map camera follows and list scrolls to the same stable sequence | Immediate selection/camera and scroll |
| Saved trip expansion | matchedGeometryEffect within a single hierarchy; one source badge per trip; native navigation from the expanded preview to route detail/ETA | Immediate expansion |
| Route push on iOS 18+ | Native source-linked zoom, system interactive back | System push when Reduce Motion is enabled or iOS 17 |
| ETA changes | numericText + scoped smooth animation; arrival slots retain identity while timestamps change | Immediate text update |
| Favorite / tracking commit | Discrete symbol bounce and selection/success sensory feedback | Symbol effects removed; state and labels still update |
| Sheet | Native interactive detents, cancellation owned by sheet item | System accessibility behavior |

No perpetual symbol effects, phase loops, artificial animation delays or decorative gradients. Phase/keyframe animators are deliberately unnecessary for these finite interactions.

## Data and lifecycle

ETA sessions own loading, successful/empty/error snapshots and timestamps. Refreshes coalesce and preserve the previous snapshot on transport failure. Region/provider/operator-bound/service/stop-sequence identity is checked before requests and deep-link resolution. Refreshing never changes row identity or sorts the whole page. Timelines run only on visible/active surfaces. Live Activities use absolute arrival/freshness timestamps and ActivityContent, no extension networking; remote APNs deployment is a separate documented phase.

## Skill provenance

Applied: [SwiftUI Expert](https://github.com/AvdLee/SwiftUI-Agent-Skill/tree/main/skills/swiftui-expert-skill), [Interface Design](https://github.com/ZHUOLIN0928/swiftui-interface-design-skill), [iOS Design Agent](https://github.com/vermont42/iOS-Design-Agent-Skill/tree/main/ios-design-agent-skill), [Animation](https://github.com/dpearson2699/swift-ios-skills/tree/main/skills/swiftui-animation), [Liquid Glass](https://github.com/dpearson2699/swift-ios-skills/tree/main/skills/swiftui-liquid-glass), [ActivityKit](https://github.com/dpearson2699/swift-ios-skills/tree/main/skills/activitykit). Availability and SDK compilation take precedence over examples targeting later Swift versions. User-requested native restraint takes precedence over decorative suggestions. Validation evidence and remaining hard gates are recorded separately; no Apple-quality or frame-rate score is inferred from code alone.
