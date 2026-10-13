# Native redesign reference evaluation

Reviewed 2026-10-13. These are engineering references, not runtime dependencies.
No third-party implementation source was copied into the app. The requested iOS 17
minimum and restrained native presentation take precedence over examples that target
newer operating systems or recommend decorative effects.

## Skills studied

Read the actual SKILL.md files and relevant design, stability, motion, Liquid Glass,
ActivityKit lifecycle/payload, WidgetKit and accessibility references:

- [SwiftUI Expert](https://github.com/AvdLee/SwiftUI-Agent-Skill/tree/main/skills/swiftui-expert-skill): ownership, stable identity, version gates and scoped numeric transitions.
- [SwiftUI Interface Design](https://github.com/ZHUOLIN0928/swiftui-interface-design-skill): standard profile, reversible state changes, native skeleton and evidence limits.
- [iOS Design Agent](https://github.com/vermont42/iOS-Design-Agent-Skill): semantic typography, scalable numbers, warm surfaces and feedback.
- [Apple Design](https://github.com/tzzs/apple-design-skill): platform conventions, system controls and content-first hierarchy.
- [ActivityKit](https://github.com/dpearson2699/swift-ios-skills/tree/main/skills/activitykit): ActivityContent, staleness, terminal paths, exact payloads and token rotation.
- [WidgetKit](https://github.com/dpearson2699/swift-ios-skills/tree/main/skills/widgetkit): extension registration, system rendering and deep links; no timeline widget is needed for a Live Activity.
- [SwiftUI Animation](https://github.com/dpearson2699/swift-ios-skills/tree/main/skills/swiftui-animation): retargetable springs, matched geometry, native navigation, numeric text, bounded phase/keyframe effects and Reduce Motion.
- [Liquid Glass](https://github.com/dpearson2699/swift-ios-skills/tree/main/skills/swiftui-liquid-glass): glass belongs to functional controls, with native pre-26 equivalents.
- [Push Notifications](https://github.com/dpearson2699/swift-ios-skills/tree/main/skills/push-notifications): APNs signing, delivery budgets and the distinction between alert permission and update tokens.
- [iOS Accessibility](https://github.com/dpearson2699/swift-ios-skills/tree/main/skills/ios-accessibility): semantic controls, Dynamic Type, spoken state and reduced effects.

## Libraries considered

Repository metadata, README examples and available Package.swift manifests were
inspected. Maintenance dates below are observations, not guarantees of future support.

| Reference | License / minimum observed | Maintenance observed | Decision |
| --- | --- | --- | --- |
| [SwiftUIX](https://github.com/SwiftUIX/SwiftUIX) | MIT; iOS 13, Swift 5.10 | Updated September 2026 | Broad compatibility toolkit; native controls already cover this app. |
| [ScalingHeaderScrollView](https://github.com/exyte/ScalingHeaderScrollView) | MIT; iOS 14 | Updated August 2026 | Sticky-header reference; fixed map plus independent timeline preserves interaction and reading space. |
| [PopupView](https://github.com/exyte/PopupView) | MIT; iOS 17, Swift 6 | Updated October 2026 | Native sheet, alert and ContentUnavailableView cover the states without overlay/window complexity. |
| [Awesome SwiftUI](https://github.com/onmyway133/awesome-swiftui) | MIT; reference collection | Updated October 2026 | Used to locate patterns; not a package to install. |
| [HIGDesign](https://github.com/promptdora/HIGDesign) | MIT; iOS 18 | Updated July 2026 | Reference only; adopting it would raise the required deployment target. |
| [Open SwiftUI Animations](https://github.com/amosgyamfi/open-swiftui-animations) | Unlicense; per-example availability | Updated August 2026 | Reviewed spring, phase, keyframe and symbol examples. No perpetual motion is appropriate for ETA reading. |
| [SwiftUI Navigation Transitions](https://github.com/davdroman/swiftui-navigation-transitions) | MIT; iOS 13, Swift 6.2 | Updated September 2026 | Native pushes on iOS 17 and native zoom on iOS 18+ retain interactive system navigation. |
| [AnimatedTabBar](https://github.com/exyte/AnimatedTabBar) | MIT; iOS 16 | Updated July 2026 | Custom tab geometry conflicts with the requested two generations of system TabView. |
| [LiveActivityDynamicIslandKit](https://github.com/mikonyaa/LiveActivityDynamicIslandKit) | MIT; iOS 17, Swift 6 | Updated July 2026 | Reviewed compact surfaces and lab approach; shared app/extension components avoid an extra rendering dependency. |
| [LiveTimerActivity](https://github.com/Navinneon/LiveTimerActivity) | No license identified in repository metadata | Updated April 2025 | Lifecycle and intent concept reference only; no copied code. A running timer demo is not evidence of background transit refresh. |

## Authoritative countdown APIs

The current Apple documentation identifies
[TimeDataSource](https://developer.apple.com/documentation/swiftui/timedatasource)
as system-updating input for Text in Live Activities and
[DiscreteFormatStyle](https://developer.apple.com/documentation/foundation/discreteformatstyle)
as a way to schedule output boundaries. Both start at iOS 18. A custom formatter passed compilation and JSON tests, but actual simulator logs showed that WidgetKit could not decode the extension-defined formatter in its remote process (`Errors.noType`). The experiment is removed. The route-aware revision uses the built-in SystemFormatStyle.Timer at minute precision on iOS 18+, with native formatter tests and actual remote-renderer UI checks. The default seconds precision is not used. iOS 17 retains the explicit timestamped fallback. The theme and digit-stability revision reuses the reviewed skills and references above without new dependencies.
See [activity design](activity-design.md) and [APNs deployment](live-activities-apns.md).
