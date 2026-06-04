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

    public static func percent(_ value: Int?) -> String {
        guard let value else {
            return percentPlaceholder
        }
        return "\(value)%"
    }

    public static func compactDateTime(_ date: Date?) -> String {
        guard let date else {
            return "unknown"
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "MM-dd HH:mm"
        return formatter.string(from: date)
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
