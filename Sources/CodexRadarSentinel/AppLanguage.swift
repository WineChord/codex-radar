import Foundation

enum AppLanguage: String, CaseIterable, Identifiable {
    case zhHans
    case en

    var id: String {
        rawValue
    }

    var label: String {
        switch self {
        case .zhHans:
            return "中文"
        case .en:
            return "English"
        }
    }

    func text(_ zhHans: String, _ en: String) -> String {
        switch self {
        case .zhHans:
            return zhHans
        case .en:
            return en
        }
    }
}
