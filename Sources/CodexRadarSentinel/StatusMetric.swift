import CodexRadarCore
import Foundation

enum StatusMetric: String, CaseIterable, Identifiable {
    case weeklyQuota
    case shortQuota
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
        case .codexIQ:
            return "IQ"
        case .signal:
            return language.text("信号", "Signal")
        }
    }

    func value(for state: DashboardState, language: AppLanguage) -> String {
        switch self {
        case .weeklyQuota:
            return DisplayFormatters.percent(state.rateLimits?.weeklyRemainingPercent)
        case .shortQuota:
            return DisplayFormatters.percent(state.rateLimits?.shortRemainingPercent)
        case .codexIQ:
            return DisplayFormatters.iqScore(state.modelIQ?.latest?.iqScore)
        case .signal:
            return Self.signalValue(for: state, language: language)
        }
    }

    func statusBarValue(
        for state: DashboardState,
        language: AppLanguage,
        preciseIQ: Bool
    ) -> String {
        switch self {
        case .codexIQ where !preciseIQ:
            return DisplayFormatters.compactIQScore(state.modelIQ?.latest?.iqScore)
        default:
            return value(for: state, language: language)
        }
    }

    static func signalValue(for state: DashboardState, language: AppLanguage) -> String {
        if state.current?.windowOpen == true {
            return language.text("速蹬", "speed")
        }
        if state.rateLimits?.isBlocked == true {
            return language.text("限额", "limit")
        }
        let level = state.prediction?.level ?? state.current?.prediction?.level
        switch level?.lowercased() {
        case "high":
            return language.text("高", "high")
        case "medium":
            return language.text("中", "med")
        case "low":
            return language.text("低", "low")
        default:
            return "-"
        }
    }
}
