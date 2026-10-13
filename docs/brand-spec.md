# Where My Bus Now — Warm Minimal, native transit

The redesign retains the original Warm Minimal brand palette. It replaces the old layouts and navigation, not the brand. The reading order is route → destination → boarding stop → next arrival. Native lists, maps, bars and sheets provide structure.

| Token | Light | Dark | Purpose |
| --- | --- | --- | --- |
| Warm Coral | #E85D3A | #E85D3A | Primary action, selection, arrival emphasis |
| Soft accent | #FBE9E2 | #3B241C | Selected boarding point and map row |
| Background | #FAF9F7 | #1C1C1E | Page canvas |
| Surface | #FFFFFF | #2C2C2E | Native list rows and Lock Screen content |
| Muted surface | #F2EFEB | #242426 | Nested content |
| Primary text | #1A1A1A | #F2F2F7 | App text |
| Secondary text | #6B6862 | #9A9A9E | Metadata |
| Tertiary text | #9A968F | #6E6E73 | Supporting information |
| Divider | #E9E5E0 | #38383A | Quiet separation |
| Success | #2E8B57 | #4CD07D | Always accompanied by meaning in text/symbols |
| Warning | #B26A00 | #FFB340 | Always accompanied by meaning in text/symbols |

`Shared/TransitBrand.swift` owns the adaptive brand colors; `DesignTokens.swift` retains their semantic app names. The asset accent uses the original coral. Operator logos, route badges and map lines retain their existing provider colors. System semantic labels are used where system-owned chrome requires them, especially the black Dynamic Island. Status never depends on coral alone; increased contrast and dimmed Lock Screen presentation prioritize readable primary text.

SF Pro semantic typography, SF Rounded route/arrival numerals and monospaced digits scale with Dynamic Type. Spacing follows 4/8/16/24/32 pt; Live Activity content follows the system’s compact margins. Primary controls have 44 × 44 pt tap targets. Account/settings, region, favorite, refresh and direction toolbar controls are completely circular.

No decorative gradients, custom fonts or third-party UI frameworks. iOS 26 supplies Liquid Glass on bars and sheets; circular toolbar controls and the tracking action opt into native glass. Reduce Transparency and older systems use opaque/bordered equivalents. Glass does not cover the arrival board or the Island.

See [the experience contract](native-transit-design.md) and [activity layouts and state behavior](activity-design.md).
