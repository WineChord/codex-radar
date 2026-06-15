import Foundation

public enum RadarDateParser {
    private static let fractionalFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let wholeSecondFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    public static func date(from value: String?) -> Date? {
        guard let value, !value.isEmpty else {
            return nil
        }
        return fractionalFormatter.date(from: value) ?? wholeSecondFormatter.date(from: value)
    }
}

public enum DisplayFormatters {
    public static let percentPlaceholder = "--"

    public static func percent(_ value: Int?, includesSymbol: Bool = true) -> String {
        guard let value else {
            return percentPlaceholder
        }
        return includesSymbol ? "\(value)%" : "\(value)"
    }

    public static func iqScore(_ value: Double?) -> String {
        guard let value, value.isFinite else {
            return percentPlaceholder
        }
        let rounded = (value * 10).rounded() / 10
        if rounded == rounded.rounded() {
            return "\(Int(rounded))"
        }
        return String(format: "%.1f", locale: Locale(identifier: "en_US_POSIX"), rounded)
    }

    public static func compactIQScore(_ value: Double?) -> String {
        guard let value, value.isFinite else {
            return percentPlaceholder
        }
        return "\(Int(value))"
    }

    public static func cacheHitRate(cachedInputTokens: Int?, inputTokens: Int?) -> String {
        guard let cachedInputTokens,
              let inputTokens,
              inputTokens > 0 else {
            return percentPlaceholder
        }
        let rate = Double(cachedInputTokens) / Double(inputTokens) * 100
        return String(format: "%.1f%%", locale: Locale(identifier: "en_US_POSIX"), rate)
    }

    public static func costUSD(_ value: Double?) -> String {
        guard let value, value.isFinite else {
            return percentPlaceholder
        }
        return String(format: "$%.2f", locale: Locale(identifier: "en_US_POSIX"), value)
    }

    public static func minutesFromSeconds(_ seconds: Int?) -> String {
        guard let seconds else {
            return percentPlaceholder
        }
        let minutes = max(1, Int(round(Double(seconds) / 60)))
        return "\(minutes)m"
    }

    public static func compactDateTime(_ date: Date?) -> String {
        guard let date else {
            return "unknown"
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "MM-dd HH:mm"
        return formatter.string(from: date)
    }

    public static func compactEpochDateTime(_ epochSeconds: Int?) -> String {
        guard let epochSeconds else {
            return "unknown"
        }
        return compactDateTime(Date(timeIntervalSince1970: TimeInterval(epochSeconds)))
    }

    public static func relativeReset(_ epochSeconds: Int?) -> String {
        guard let epochSeconds else {
            return "unknown"
        }
        let date = Date(timeIntervalSince1970: TimeInterval(epochSeconds))
        let seconds = Int(date.timeIntervalSinceNow)
        if seconds <= 0 {
            return "now"
        }
        let hours = seconds / 3_600
        let minutes = (seconds % 3_600) / 60
        if hours >= 24 {
            let days = hours / 24
            let remainingHours = hours % 24
            return "\(days)d \(remainingHours)h"
        }
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(max(minutes, 1))m"
    }
}
