import SwiftUI

private struct PreviewReducedEffectsKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// Deterministic preview/test input; production always reads the system preferences.
    var previewReducedEffects: Bool {
        get { self[PreviewReducedEffectsKey.self] }
        set { self[PreviewReducedEffectsKey.self] = newValue }
    }
    var transitReduceMotion: Bool { accessibilityReduceMotion || previewReducedEffects }
    var transitReduceTransparency: Bool { accessibilityReduceTransparency || previewReducedEffects }
}
