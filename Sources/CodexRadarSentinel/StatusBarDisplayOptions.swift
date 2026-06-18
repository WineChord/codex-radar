import CodexRadarCore
import CoreGraphics
import Foundation

struct StatusBarDisplayOptions: Equatable {
    var preciseIQ: Bool
    var iqDisplayMode: StatusBarIQDisplayMode
    var percentDisplayMode: StatusBarPercentDisplayMode
    var separator: StatusBarSeparator
    var horizontalPadding: StatusBarHorizontalPadding
    var fontScale: StatusBarFontScale
    var quotaPacingStrategy: QuotaPacingStrategy
    var usesChinaHolidayCalendar: Bool

    static let defaultOptions = StatusBarDisplayOptions(
        preciseIQ: false,
        iqDisplayMode: .raw,
        percentDisplayMode: .symbol,
        separator: .slash,
        horizontalPadding: .system,
        fontScale: .normal,
        quotaPacingStrategy: .timeProportional,
        usesChinaHolidayCalendar: true
    )

    var holidayCalendar: HolidayCalendar? {
        usesChinaHolidayCalendar ? .chinaMainland2026 : nil
    }
}

enum StatusBarSeparator: String, CaseIterable, Identifiable {
    case slash
    case narrowSlash
    case thinSpace
    case dot
    case none

    var id: String {
        rawValue
    }

    var text: String {
        switch self {
        case .slash:
            return "/"
        case .narrowSlash:
            return "⁄"
        case .thinSpace:
            return " "
        case .dot:
            return "·"
        case .none:
            return ""
        }
    }

    func label(language: AppLanguage) -> String {
        switch self {
        case .slash:
            return "/"
        case .narrowSlash:
            return language.text("窄斜杠", "Narrow /")
        case .thinSpace:
            return language.text("细空格", "Thin space")
        case .dot:
            return "·"
        case .none:
            return language.text("无", "None")
        }
    }
}

enum StatusBarHorizontalPadding: String, CaseIterable, Identifiable {
    case system
    case compact
    case tight

    var id: String {
        rawValue
    }

    var fixedExtraWidth: CGFloat? {
        switch self {
        case .system:
            return nil
        case .compact:
            return 12
        case .tight:
            return 6
        }
    }

    func label(language: AppLanguage) -> String {
        switch self {
        case .system:
            return language.text("系统", "System")
        case .compact:
            return language.text("紧凑", "Compact")
        case .tight:
            return language.text("极窄", "Tight")
        }
    }
}

enum StatusBarFontScale: String, CaseIterable, Identifiable {
    case normal
    case compact
    case tiny

    var id: String {
        rawValue
    }

    var multiplier: CGFloat {
        switch self {
        case .normal:
            return 1
        case .compact:
            return 0.92
        case .tiny:
            return 0.86
        }
    }

    func label(language: AppLanguage) -> String {
        switch self {
        case .normal:
            return language.text("正常", "Normal")
        case .compact:
            return language.text("紧凑", "Compact")
        case .tiny:
            return language.text("更小", "Tiny")
        }
    }
}
