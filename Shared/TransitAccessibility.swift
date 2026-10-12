import SwiftUI

private struct PreviewReducedEffectsKey: EnvironmentKey {
    static let defaultValue = false
}
private struct PreviewDimmedKey: EnvironmentKey { static let defaultValue = false }

extension EnvironmentValues {
    /// Deterministic preview/test input; production always reads the system preferences.
    var previewReducedEffects: Bool {
        get { self[PreviewReducedEffectsKey.self] }
        set { self[PreviewReducedEffectsKey.self] = newValue }
    }
    var transitReduceMotion: Bool { accessibilityReduceMotion || previewReducedEffects }
    var transitReduceTransparency: Bool { accessibilityReduceTransparency || previewReducedEffects }
    var previewDimmed: Bool {
        get { self[PreviewDimmedKey.self] }
        set { self[PreviewDimmedKey.self] = newValue }
    }
    var transitLuminanceReduced: Bool { isLuminanceReduced || previewDimmed }
}
