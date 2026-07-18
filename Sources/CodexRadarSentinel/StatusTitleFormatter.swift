import AppKit
import CodexRadarCore

enum StatusTitleFormatter {
    static func plainTitle(
        for state: DashboardState,
        metrics: [StatusMetric],
        language: AppLanguage,
        options: StatusBarDisplayOptions
    ) -> String {
        let activeMetrics = normalizedMetrics(metrics, state: state)
        return activeMetrics.map {
            $0.statusBarValue(for: state, language: language, options: options)
        }.joined(separator: options.separator.text)
    }

    static func attributedTitle(
        for state: DashboardState,
        emphasized: Bool,
        metrics: [StatusMetric],
        language: AppLanguage,
        options: StatusBarDisplayOptions
    ) -> NSAttributedString {
        let fontSize = NSFont.systemFontSize * options.fontScale.multiplier
        let font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .semibold)
        let title = NSMutableAttributedString()
        let activeMetrics = normalizedMetrics(metrics, state: state)

        for (index, metric) in activeMetrics.enumerated() {
            if index > 0 {
                let color = emphasized ? NSColor.white.withAlphaComponent(0.75) : .secondaryLabelColor
                append(options.separator.text, color: color, font: font, to: title)
            }
            let color = emphasized ? .white : metricColor(
                for: metric,
                state: state,
                language: language,
                options: options
            )
            append(
                metric.statusBarValue(for: state, language: language, options: options),
                color: color,
                font: font,
                to: title
            )
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

    private static func normalizedMetrics(_ metrics: [StatusMetric], state: DashboardState) -> [StatusMetric] {
        let configured = metrics.isEmpty
            ? [.weeklyQuota]
            : StatusMetric.allCases.filter { metrics.contains($0) }
        let available = configured.filter { metric in
            metric != .shortQuota || state.rateLimits?.shortBucket != nil
        }
        return available.isEmpty ? [.weeklyQuota] : available
    }

    private static func metricColor(
        for metric: StatusMetric,
        state: DashboardState,
        language: AppLanguage,
        options: StatusBarDisplayOptions
    ) -> NSColor {
        switch metric {
        case .weeklyQuota:
            return quotaColor(for: state, remaining: state.rateLimits?.weeklyRemainingPercent)
        case .shortQuota:
            return quotaColor(for: state, remaining: state.rateLimits?.shortRemainingPercent)
        case .quotaPace:
            return quotaPaceColor(
                for: state,
                strategy: options.quotaPacingStrategy,
                holidayCalendar: options.holidayCalendar
            )
        case .codexIQ:
            return iqColor(for: state)
        case .signal:
            return signalColor(
                for: state,
                signal: metric.value(
                    for: state,
                    language: language,
                    pacingStrategy: options.quotaPacingStrategy,
                    holidayCalendar: options.holidayCalendar
                )
            )
        }
    }

    private static func quotaColor(for state: DashboardState, remaining: Int?) -> NSColor {
        if state.rateLimits?.isBlocked == true {
            return .systemRed
        }
        guard let remaining else {
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

    private static func quotaPaceColor(
        for state: DashboardState,
        strategy: QuotaPacingStrategy,
        holidayCalendar: HolidayCalendar?
    ) -> NSColor {
        guard let pacing = state.rateLimits?.quotaPacing(
            strategy: strategy,
            holidayCalendar: holidayCalendar
        ) else {
            return .secondaryLabelColor
        }
        switch pacing.status {
        case .underTarget:
            return .systemGreen
        case .onPace:
            return .systemTeal
        case .overTarget:
            return .systemOrange
        }
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
        if state.activeSpeedWindow {
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
        case "正常", "ok":
            return .systemGreen
        case "权益", "event":
            return .systemTeal
        case "低", "low":
            return iqColor(for: state)
        default:
            return .secondaryLabelColor
        }
    }
}
