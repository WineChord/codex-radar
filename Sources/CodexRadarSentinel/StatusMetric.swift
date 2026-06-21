import CodexRadarCore
import Foundation

enum StatusMetric: String, CaseIterable, Identifiable {
    case weeklyQuota
    case shortQuota
    case quotaPace
    case codexIQ
    case signal

    var id: String {
        rawValue
    }

    func label(language: AppLanguage) -> String {
        switch self {
        case .weeklyQuota:
            return language.text("周额度", "Weekly")
        case .shortQuota:
            return "5h"
        case .quotaPace:
            return language.text("应剩", "Pace")
        case .codexIQ:
            return "IQ"
        case .signal:
            return language.text("质量", "Quality")
        }
    }

    func value(
        for state: DashboardState,
        language: AppLanguage,
        pacingStrategy: QuotaPacingStrategy = .timeProportional,
        holidayCalendar: HolidayCalendar? = nil
    ) -> String {
        switch self {
        case .weeklyQuota:
            return DisplayFormatters.percent(state.rateLimits?.weeklyRemainingPercent)
        case .shortQuota:
            return DisplayFormatters.percent(state.rateLimits?.shortRemainingPercent)
        case .quotaPace:
            guard let pacing = state.rateLimits?.quotaPacing(
                strategy: pacingStrategy,
                holidayCalendar: holidayCalendar
            ) else {
                return "-"
            }
            return DisplayFormatters.percent(pacing.roundedTargetRemainingPercent)
        case .codexIQ:
            return DisplayFormatters.iqScore(state.modelIQ?.latest?.iqScore)
        case .signal:
            return Self.signalValue(for: state, language: language)
        }
    }

    func statusBarValue(
        for state: DashboardState,
        language: AppLanguage,
        options: StatusBarDisplayOptions
    ) -> String {
        switch self {
        case .weeklyQuota:
            return DisplayFormatters.percent(
                state.rateLimits?.weeklyRemainingPercent,
                includesSymbol: options.percentDisplayMode.includesSymbol
            )
        case .shortQuota:
            return DisplayFormatters.percent(
                state.rateLimits?.shortRemainingPercent,
                includesSymbol: options.percentDisplayMode.includesSymbol
            )
        case .quotaPace:
            guard let pacing = state.rateLimits?.quotaPacing(
                strategy: options.quotaPacingStrategy,
                holidayCalendar: options.holidayCalendar
            ) else {
                return "-"
            }
            let target = DisplayFormatters.percent(
                pacing.roundedTargetRemainingPercent,
                includesSymbol: options.percentDisplayMode.includesSymbol
            )
            return language.text("应\(target)", "R\(target)")
        case .codexIQ:
            return options.iqDisplayMode.format(
                state.modelIQ?.latest?.iqScore,
                preciseRaw: options.preciseIQ
            )
        default:
            return value(
                for: state,
                language: language,
                pacingStrategy: options.quotaPacingStrategy,
                holidayCalendar: options.holidayCalendar
            )
        }
    }

    static func signalValue(for state: DashboardState, language: AppLanguage) -> String {
        if state.activeSpeedWindow {
            return language.text("速蹬", "speed")
        }
        if state.rateLimits?.isBlocked == true {
            return language.text("限额", "limit")
        }
        if let score = state.modelIQ?.latest?.iqScore {
            let status = state.modelIQ?.latest?.status?.lowercased()
            if status == "red" || score < 80 {
                return language.text("低", "low")
            }
            if status == "yellow" || score < 95 {
                return language.text("中", "med")
            }
            return language.text("正常", "ok")
        }
        if state.activeEntitlementEvent {
            return language.text("权益", "event")
        }
        let level = state.prediction?.level ?? state.current?.prediction?.level
        switch level?.lowercased() {
        case "high":
            return language.text("高", "high")
        case "medium_high", "medium-high":
            return language.text("中高", "med-high")
        case "medium":
            return language.text("中", "med")
        case "medium_low", "medium-low":
            return language.text("中低", "med-low")
        case "low":
            return language.text("低", "low")
        default:
            return "-"
        }
    }
}
