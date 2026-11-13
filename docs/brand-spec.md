# Where My Bus Now — native transit

The app retains its coral brand accent and operator identity, with native semantic surfaces and grouped lists. The reading order is route → destination → boarding stop → next arrival. Native lists, maps, bars and sheets provide structure.

| App token | Native value | Purpose |
| --- | --- | --- |
| Background | `systemGroupedBackground` | Page canvas |
| Surface | `secondarySystemGroupedBackground` | Grouped rows |
| Muted surface | `tertiarySystemGroupedBackground` | Nested content |
| Primary / secondary text | SwiftUI `primary` / `secondary` | Content and metadata |
| Tertiary text | `tertiaryLabel` | Supporting information |
| Divider | `separator` | Quiet separation |
| Accent | Coral #E85D3A, contrast-adjusted for actions | Brand and selection |

`DesignTokens.swift` owns the app's system semantic colors. `Shared/TransitBrand.swift` retains the warm neutrals used on Live Activity surfaces. Operator logos, route badges and map lines retain their provider colors. Status never depends on coral alone.

SF Pro semantic typography, SF Rounded route/arrival numerals and monospaced digits scale with Dynamic Type. Content uses native section spacing. Toolbar icons use natural symbol-only sizing and circle border shapes; fixed toolbar spacers keep adjacent actions in separate system platters. The city is shown in an iOS 26 navigation subtitle and in the region button's accessible label. Settings uses a gear. Content-area icon buttons use native bordered circles with at least 44pt targets. Done, Edit and descriptive actions retain native text/capsule treatment.

No decorative gradients, custom fonts or third-party UI frameworks. iOS 26 supplies Liquid Glass on bars and sheets; toolbar items add no extra glass layer. The tracking action uses a native prominent button style. System controls handle Reduce Transparency and semantic colors handle contrast. Departure rows have no custom card outline or shadow. Glass does not cover the arrival board, Today rows or the Island.

See [the experience contract](native-transit-design.md) and [activity layouts and state behavior](activity-design.md).
