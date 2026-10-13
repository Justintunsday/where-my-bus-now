import SwiftUI

struct ETALineView: View {
    @Environment(\.routeTheme) private var theme
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.transitReduceMotion) private var reduceMotion
    @Environment(AppState.self) private var app
    let eta: Eta
    let language: AppLanguage
    let format: EtaFormat
    let annotateScheduled: Bool
    var highlight: Bool = false
    var showCompany: Bool = false
    var showDestination: Bool = true

    var body: some View {
        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8)) : AnyLayout(HStackLayout(spacing: 8))
        return layout {
            if showCompany, let op = app.provider.operators.op(eta.co) {
                Text(op.name(language))
                    .font(DesignTokens.footnote)
                    .foregroundStyle(.tertiary)
            }
            if annotateScheduled && eta.isScheduled {
                Image(systemName: "calendar.badge.clock")
                    .font(DesignTokens.footnote)
                    .foregroundStyle(.tertiary)
            }
            if showDestination, eta.co == "mtr", !eta.dest.name(language).isEmpty {
                Text(eta.dest.name(language))
                    .font(DesignTokens.caption)
                    .foregroundStyle(.secondary)
            }
            remarkText
            if hasMetadata && !typeSize.isAccessibilitySize { Spacer(minLength: DesignTokens.Spacing.xs) }
            timeContent
        }
    }

    private var hasMetadata: Bool {
        showCompany || (annotateScheduled && eta.isScheduled)
            || (showDestination && eta.co == "mtr" && !eta.dest.name(language).isEmpty)
            || (!eta.remark.name(language).isEmpty && !eta.isScheduled)
    }

    @ViewBuilder
    private var remarkText: some View {
        let remark = eta.remark.name(language)
        if !remark.isEmpty, !eta.isScheduled {
            Text(remark)
                .font(DesignTokens.footnote)
                .foregroundStyle(.tertiary)
                .lineLimit(typeSize.isAccessibilitySize ? nil : 2)
        }
    }

    @ViewBuilder
    private var timeContent: some View {
        if eta.date != nil, let minutes = eta.minutesUntil {
            switch format {
            case .exact:
                Text(RegionClock.timeString(eta.eta))
                    .font(DesignTokens.tabular(17, weight: highlight ? .bold : .medium))
                    .foregroundStyle(highlight ? theme.accent : Color.primary)
            case .diff:
                if isArriving(minutes) {
                    arrivingText
                } else {
                    minutesWithUnit(minutes)
                }
            case .mixed:
                let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8)) : AnyLayout(HStackLayout(spacing: 8))
                layout {
                    Text(RegionClock.timeString(eta.eta))
                        .font(DesignTokens.tabular(14, weight: .regular))
                        .foregroundStyle(.secondary)
                    if !typeSize.isAccessibilitySize { Spacer(minLength: 8) }
                    if isArriving(minutes) {
                        arrivingText
                    } else {
                        minutesWithUnit(minutes)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            Text(eta.remark.name(language))
                .font(DesignTokens.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var arrivingText: some View {
        Text(L10n.t("eta.arriving"))
            .font(DesignTokens.subheading)
            .fontWeight(.semibold)
            .foregroundStyle(highlight ? theme.accent : Color.primary)
    }

    private func minutesWithUnit(_ minutes: Int) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: DesignTokens.Spacing.xxs) {
            Text("\(minutes)")
                .font(DesignTokens.tabular(20, weight: .bold))
                .contentTransition(reduceMotion ? .identity : .numericText(countsDown: true))
                .animation(reduceMotion ? nil : .smooth(duration: 0.3), value: minutes)
            Text(L10n.t("unit.minutes"))
                .font(DesignTokens.footnote)
                .foregroundStyle(.tertiary)
        }
        .foregroundStyle(highlight ? theme.accent : Color.primary)
    }

    private func isArriving(_ minutes: Int) -> Bool {
        minutes < threshold
    }

    private var threshold: Int {
        app.provider.arrivingThreshold(operatorID: eta.co)
    }
}

/// Single-line compact ETA used by the stop departure board.
struct ETACompactLineView: View {
    @Environment(\.routeTheme) private var theme
    @Environment(\.transitReduceMotion) private var reduceMotion
    @Environment(AppState.self) private var app
    let eta: Eta
    let format: EtaFormat
    let annotateScheduled: Bool
    var highlight: Bool = false

    private var language: AppLanguage { L10n.language }
    private var threshold: Int { app.provider.arrivingThreshold(operatorID: eta.co) }

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.xs) {
            if annotateScheduled && eta.isScheduled {
                Image(systemName: "calendar.badge.clock")
                    .font(DesignTokens.footnote)
                    .foregroundStyle(.tertiary)
            }
            if eta.date != nil, let minutes = eta.minutesUntil {
                if format != .diff {
                    Text(RegionClock.timeString(eta.eta))
                        .font(DesignTokens.tabular(13, weight: .regular))
                        .foregroundStyle(.tertiary)
                }
                if minutes < threshold {
                    Text(L10n.t("eta.arriving"))
                        .font(DesignTokens.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(highlight ? theme.accent : Color.primary)
                } else {
                    Text("\(minutes)")
                        .font(DesignTokens.tabular(18, weight: .bold))
                        .contentTransition(reduceMotion ? .identity : .numericText(countsDown: true))
                        .animation(reduceMotion ? nil : .smooth(duration: 0.3), value: minutes)
                        .foregroundStyle(highlight ? theme.accent : Color.primary)
                    Text(L10n.t("unit.minutes"))
                        .font(DesignTokens.footnote)
                        .foregroundStyle(.tertiary)
                }
            } else {
                Text(eta.remark.name(language).isEmpty ? L10n.t("eta.noEta") : eta.remark.name(language))
                    .font(DesignTokens.footnote)
                    .foregroundStyle(.tertiary)
            }
        }
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: false)
    }
}
