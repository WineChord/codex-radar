import AppKit
import CodexRadarCore

enum StatusTitleFormatter {
    private static let separator = "/"

    static func plainTitle(
        for state: DashboardState,
        metrics: [StatusMetric],
        language: AppLanguage
    ) -> String {
        let activeMetrics = normalizedMetrics(metrics)
        return activeMetrics.map { $0.value(for: state, language: language) }.joined(separator: separator)
    }

    static func attributedTitle(
        for state: DashboardState,
        emphasized: Bool,
        metrics: [StatusMetric],
        language: AppLanguage
    ) -> NSAttributedString {
        let font = NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .semibold)
        let title = NSMutableAttributedString()
        let activeMetrics = normalizedMetrics(metrics)

        for (index, metric) in activeMetrics.enumerated() {
            if index > 0 {
                let color = emphasized ? NSColor.white.withAlphaComponent(0.75) : .secondaryLabelColor
                appendSeparator(color: color, font: font, to: title)
            }
            let color = emphasized ? .white : metricColor(for: metric, state: state, language: language)
            append(metric.value(for: state, language: language), color: color, font: font, to: title)
        }

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

    private static func appendSeparator(color: NSColor, font: NSFont, to title: NSMutableAttributedString) {
        append(separator, color: color, font: font, to: title)
    }

    private static func normalizedMetrics(_ metrics: [StatusMetric]) -> [StatusMetric] {
        if metrics.isEmpty {
            return [.weeklyQuota]
        }
        return StatusMetric.allCases.filter { metrics.contains($0) }
    }

    private static func metricColor(
        for metric: StatusMetric,
        state: DashboardState,
        language: AppLanguage
    ) -> NSColor {
        switch metric {
        case .weeklyQuota:
            return quotaColor(for: state)
        case .codexIQ:
            return iqColor(for: state)
        case .signal:
            return signalColor(for: state, signal: metric.value(for: state, language: language))
        }
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
        if score < 60 {
            return .systemRed
        }
        if latest.status?.lowercased() == "red" || score < 90 {
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
        case "高", "high":
            return .systemRed
        case "中", "med":
            return .systemOrange
        case "低", "low":
            return .systemTeal
        default:
            return .secondaryLabelColor
        }
    }
}
