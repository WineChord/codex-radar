import AppKit
import CodexRadarCore

enum StatusTitleFormatter {
    private static let separator = "/"
    private static let missingValue = DisplayFormatters.percentPlaceholder

    static func attributedTitle(for state: DashboardState) -> NSAttributedString {
        let font = NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .semibold)
        let title = NSMutableAttributedString()
        let quota = DisplayFormatters.percent(state.rateLimits?.weeklyRemainingPercent)
        let iq = state.modelIQ?.latest?.iqScore.map(String.init) ?? missingValue
        let signal = signalSegment(for: state)

        append(quota, color: quotaColor(for: state), font: font, to: title)
        appendSeparator(font: font, to: title)
        append(iq, color: iqColor(for: state), font: font, to: title)
        appendSeparator(font: font, to: title)
        append(signal, color: signalColor(for: state, signal: signal), font: font, to: title)

        return title
    }

    private static func append(
        _ value: String,
        color: NSColor,
        font: NSFont,
        to title: NSMutableAttributedString
    ) {
        title.append(
            NSAttributedString(
                string: value,
                attributes: [
                    .font: font,
                    .foregroundColor: color,
                ]
            )
        )
    }

    private static func appendSeparator(font: NSFont, to title: NSMutableAttributedString) {
        append(separator, color: .secondaryLabelColor, font: font, to: title)
    }

    private static func signalSegment(for state: DashboardState) -> String {
        if state.current?.windowOpen == true {
            return "速蹬"
        }
        if state.rateLimits?.isBlocked == true {
            return "限额"
        }
        return state.predictionLevelLabel ?? "-"
    }

    private static func quotaColor(for state: DashboardState) -> NSColor {
        if state.rateLimits?.isBlocked == true {
            return .systemRed
        }
        guard let remaining = state.rateLimits?.weeklyRemainingPercent else {
            return .secondaryLabelColor
        }
        if remaining <= AppConstants.criticalRemainingPercent {
            return .systemRed
        }
        if remaining <= AppConstants.warningRemainingPercent {
            return .systemOrange
        }
        return .systemGreen
    }

    private static func iqColor(for state: DashboardState) -> NSColor {
        guard let latest = state.modelIQ?.latest,
              let score = latest.iqScore
        else {
            return .secondaryLabelColor
        }
        if latest.status?.lowercased() == "red" || score < 80 {
            return .systemRed
        }
        if score < 90 {
            return .systemOrange
        }
        return .systemGreen
    }

    private static func signalColor(for state: DashboardState, signal: String) -> NSColor {
        if state.current?.windowOpen == true {
            return .systemRed
        }
        if state.rateLimits?.isBlocked == true {
            return .systemOrange
        }
        switch signal {
        case "高":
            return .systemRed
        case "中":
            return .systemOrange
        case "低":
            return .systemTeal
        default:
            return .secondaryLabelColor
        }
    }
}
