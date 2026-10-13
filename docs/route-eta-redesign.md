# Route-aware ETA departure board

## Screen structure

The previous ETA screen separated identity, an oversized numeral card, upcoming services, a full-width tracking button, pinning and freshness. The redesign makes one native departure board the primary reading group: route/operator and prediction type; destination/boarding point beside the next arrival; compact following departures; successful-update information; then a contextual tracking/pin row. Stops, fare and hours move into a secondary Journey details section. Refresh and favorite use ordinary native toolbar items, with the system owning their hit area and iOS 26 glass grouping.

Alternatives considered were retaining separate cards, a large collapsing route header, and one compact departure board. The departure board keeps the information a passenger compares in one place without extra header motion or nested surfaces. Semantic text, a restrained 46pt scaled primary numeral and native list insets establish hierarchy. Accessibility sizes stack identity, destination and arrival vertically; rows remain readable and scroll normally.

Tracking opens the native preview/authorization sheet. An active trip has an explicit tracking label. Pinning is a reversible action beside tracking, independent of favorite state. Favorites remain in the toolbar; tracking still preserves the existing favorite/boarding behavior. Controls retain accessible names and selected values. No new dependencies or pre-iOS-26 glass emulation are introduced.

## Theme ownership

Shared/RouteTheme.swift is the single serializable route color model. Provider metadata wins; Hong Kong railway line and operator mappings and the existing deterministic mainland palette are centralized there. EAL retains 0x5EB7E8. Route badges retain the exact identity color and choose black/white text by WCAG relative luminance. Text/icons/actions adjust toward white or black only enough to reach 4.5:1 against their intended surface. The Island uses black as its contrast reference. Global Warm Minimal remains the environment default.

The resolved theme is an optional Codable field on BusTrackingTarget, embedded in ActivityKit attributes. The extension renders it without networking or provider/database access. Existing bookmarks, deep links and activities decode without this field and resolve known line/operator/mainland colors. Theme and language do not change the boarding identity. Tracking a different route creates new immutable attributes. Deep links are validated against the real provider route before a new target/theme is created; a supplied presentation color does not determine a route's identity.

ETA, tracking sheets, route maps, selected timeline stops, toolbar controls and saved boarding summaries use scoped themes. The root app does not change color when navigating away from a route.

## Time rendering

The app computes ceil(max(0, arrival - currentTime) / 60) from absolute dates. Scheduled rows are labelled independently of live rows. Expired/terminal/error states remove the active countdown and preserve clock history only as labelled history. The second bus is promoted only by new provider data.

On iOS 18+, Text uses the built-in SystemFormatStyle.Timer through SystemMinuteCountdown. A native timer with minute precision truncates; its formatting endpoint is shifted to the representable instant before arrival + 60 seconds, giving ceil rounding. The actual prediction and ActivityKit stale date are unchanged. The bounded native style cannot become negative. Apple owns automatic time rendering; the extension has no Timer, task or background network fetch. Built-in style types avoid the remote decoding failure observed with an extension-defined DiscreteFormatStyle.

On iOS 17, minutes remain an explicitly marked snapshot at the last successful update, with an asterisk, update time and spoken explanation. ActivityKit staleness removes it after at most 90 seconds or at arrival if earlier. No ticking minute clock is claimed on that fallback. Foreground provider updates, system time presentation and newly received APNs predictions remain separate mechanisms. Remote predictions still require the documented backend deployment and signing.

## Digit stability and motion

The previous primary numeral used numericText plus an implicit smooth animation during timeline/provider updates. Rolling text intentionally composites old and new digit layers; it is a poor fit for this high-priority reading surface and can resemble ghosting while other layout changes occur. DepartureMinuteDigits keeps one stable Text, monospaced numerals, identity content transition and a transaction that disables inherited animation. It does not change view identity to restart a transition. Upcoming rows likewise update text without rolling layers. Other contextual navigation/map/selection animations remain native, scoped and Reduce Motion aware.

A debug-only revision fixture deliberately wraps an ETA update in a parent spring. UI tests check the new minute value and one stable identified numeral, alongside pin/favorite reversibility. This verifies state and hierarchy; screenshots do not establish frame-rate or hardware performance measurements.

## References and verification

The actual requested design/ActivityKit/WidgetKit/animation skills and library examples reviewed in reference-evaluation.md inform this revision: native hierarchy and controls, restrained motion, stable identity, version gates and honest widget update semantics. No library code was copied and no package was added. HIGDesign's iOS 18 minimum remains reference-only. The native timer is checked against Apple's current API documentation, not third-party timer examples.

The existing GitHub Actions workflow remains the build authority. It runs Foundation theme/contrast/serialization/ETA contracts, native formatter boundaries, existing offline providers/bookmarks/navigation, Xcode 26 simulator and device archive builds, IPA/extension verification, navigation/accessibility/revision and actual KMB/EAL Island UI tests. The same simulator binary is captured on iOS 17, 18 and 26, plus iPad. Previews cover EAL, TWL, KMB, Citybus, NLB, light/dark, large text and shared ActivityKit layouts. Before/after ETA captures use the previous d180c55 implementation. Final run/artifact evidence belongs in the PR after all required checks pass.

Primary API references: [SystemFormatStyle.Timer](https://developer.apple.com/documentation/swiftui/systemformatstyle/timer), [TimeDataSource](https://developer.apple.com/documentation/swiftui/timedatasource), [Live Activities HIG](https://developer.apple.com/design/human-interface-guidelines/live-activities).
