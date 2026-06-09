import Foundation

public enum StatusBarIQDisplayMode: String, CaseIterable, Identifiable {
    case raw
    case dividedBy10Integer
    case dividedBy10Decimal

    public var id: String {
        rawValue
    }

    public func format(_ value: Double?, preciseRaw: Bool) -> String {
        switch self {
        case .raw:
            return preciseRaw ? DisplayFormatters.iqScore(value) : DisplayFormatters.compactIQScore(value)
        case .dividedBy10Integer:
            guard let value, value.isFinite else {
                return DisplayFormatters.percentPlaceholder
            }
            return "\(Int(value / 10))"
        case .dividedBy10Decimal:
            guard let value, value.isFinite else {
                return DisplayFormatters.percentPlaceholder
            }
            return DisplayFormatters.iqScore(value / 10)
        }
    }
}

public enum StatusBarPercentDisplayMode: String, CaseIterable, Identifiable {
    case symbol
    case numberOnly

    public var id: String {
        rawValue
    }

    public var includesSymbol: Bool {
        self == .symbol
    }
}
