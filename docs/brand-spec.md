# Where My Bus Now — native transit

The 2.0 interface replaces Warm Minimal with a standard, commute-first native iOS design. The primary reading order is route → destination → boarding stop → next arrival. Maps and departure data are content; native bars, menus and sheets provide navigation and depth.

| Token | Value / purpose |
| --- | --- |
| Action accent | #005FCC light / #64A9FF dark; controls and selection |
| Accent surface | #EAF2FF light / #172B47 dark |
| Background | systemGroupedBackground |
| Surface | secondarySystemGroupedBackground |
| Nested surface | tertiarySystemGroupedBackground |
| Primary text | primary semantic label |
| Secondary text | secondary semantic label |
| Dividers | separator semantic color |
| Success | #2E8B57 light / #4CD07D dark |
| Warning | #B26A00 light / #FFB340 dark, always paired with a symbol/text |
| Text | SF Pro semantic text styles |
| Route / arrival numerals | SF Rounded, tabular digits, scaled metrics for display sizes |
| Spacing | 4 / 8 / 16 / 24 / 32 pt |
| Minimum primary tap target | 44 × 44 pt |

Operator colors belong to route identity and maps; they do not color whole pages. Existing operator logos are retained. No decorative gradients, custom fonts, third-party UI frameworks or perpetual animation. The system supplies iOS 26 Liquid Glass on bars and sheets; the prominent tracking control opts into `.glassProminent`. Reduce Transparency and older systems use opaque/bordered equivalents.

Dynamic Type reflows arrival boards and route metadata, accessibility sizes prioritize the stop timeline over the fixed map, and native navigation supplies keyboard and assistive control semantics. Motion uses one retargetable spring vocabulary, scoped numeric transitions and discrete symbol feedback. See [the experience contract](native-transit-design.md) and [Live Activity behavior/deployment](live-activities-apns.md).
