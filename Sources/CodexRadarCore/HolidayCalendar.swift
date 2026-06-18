import Foundation

public struct HolidayCalendar: Equatable {
    public let id: String
    public let sourceName: String
    public let sourceURL: URL?
    private let holidays: Set<String>
    private let makeupWorkdays: Set<String>

    public init(
        id: String,
        sourceName: String,
        sourceURL: URL?,
        holidays: Set<String>,
        makeupWorkdays: Set<String>
    ) {
        self.id = id
        self.sourceName = sourceName
        self.sourceURL = sourceURL
        self.holidays = holidays
        self.makeupWorkdays = makeupWorkdays
    }

    public func dayKind(for date: Date, calendar: Calendar) -> HolidayCalendarDayKind? {
        let key = Self.dayKey(for: date, calendar: calendar)
        if makeupWorkdays.contains(key) {
            return .workday
        }
        if holidays.contains(key) {
            return .holiday
        }
        return nil
    }

    private static func dayKey(for date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        let year = components.year ?? 0
        let month = components.month ?? 0
        let day = components.day ?? 0
        return String(format: "%04d-%02d-%02d", year, month, day)
    }
}

public enum HolidayCalendarDayKind: Equatable {
    case holiday
    case workday
}

public extension HolidayCalendar {
    static let chinaMainland2026 = HolidayCalendar(
        id: "cn-2026",
        sourceName: "国务院办公厅 2026 年部分节假日安排",
        sourceURL: URL(string: "https://www.scio.gov.cn/zdgz/jj/202511/t20251110_938367.html"),
        holidays: [
            "2026-01-01", "2026-01-02", "2026-01-03",
            "2026-02-15", "2026-02-16", "2026-02-17", "2026-02-18", "2026-02-19", "2026-02-20", "2026-02-21", "2026-02-22", "2026-02-23",
            "2026-04-04", "2026-04-05", "2026-04-06",
            "2026-05-01", "2026-05-02", "2026-05-03", "2026-05-04", "2026-05-05",
            "2026-06-19", "2026-06-20", "2026-06-21",
            "2026-09-25", "2026-09-26", "2026-09-27",
            "2026-10-01", "2026-10-02", "2026-10-03", "2026-10-04", "2026-10-05", "2026-10-06", "2026-10-07",
        ],
        makeupWorkdays: [
            "2026-01-04",
            "2026-02-14", "2026-02-28",
            "2026-05-09",
            "2026-09-20",
            "2026-10-10",
        ]
    )
}
