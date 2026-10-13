import SwiftUI

/// Simple transit-mode glyph used for regions that have no operator logos
/// (mainland 车来了 lines) and as a quiet fallback for ferry operators.
struct RouteModeIcon: View {
    let symbolName: String
    var size: CGFloat = 12
    var label: String?
    @ScaledMetric(relativeTo: .caption) private var typeScale: CGFloat = 1

    var body: some View {
        if let label {
            chip.accessibilityLabel(Text(label))
        } else {
            chip.accessibilityHidden(true)
        }
    }

    private var chip: some View {
        Image(systemName: symbolName)
            .font(.system(size: size * typeScale, weight: .semibold))
            .foregroundStyle(DesignTokens.textSecondary)
            .frame(width: (size + 9) * typeScale, height: (size + 9) * typeScale)
            .background(
                DesignTokens.surfaceMuted,
                in: RoundedRectangle(cornerRadius: 5, style: .continuous)
            )
    }
}

extension MainlandTransitMode {
    var symbolName: String? {
        switch self {
        case .bus: return "bus.fill"
        case .metro: return "tram.fill"
        case .unknown: return nil
        }
    }
}
