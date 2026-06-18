import Foundation

public enum QuotaPacingStrategy: String, CaseIterable, Identifiable {
    case timeProportional
    case sevenDay
    case reserveTwenty
    case workdayWeighted
    case frontLoaded

    public var id: String {
        rawValue
    }
}

public enum QuotaPacingStatus: Equatable {
    case underTarget
    case onPace
    case overTarget
}

public struct QuotaPacingSnapshot: Equatable {
    public let strategy: QuotaPacingStrategy
    public let currentUsedPercent: Double
    public let targetUsedPercent: Double
    public let deltaToTargetPercent: Double
    public let elapsedWindowPercent: Double
    public let windowStartAt: Int
    public let resetAt: Int

    public var roundedCurrentUsedPercent: Int {
        roundedPercent(currentUsedPercent)
    }

    public var roundedTargetUsedPercent: Int {
        roundedPercent(targetUsedPercent)
    }

    public var roundedDeltaToTargetPercent: Int {
        Int(round(deltaToTargetPercent))
    }

    public var currentRemainingPercent: Double {
        100 - currentUsedPercent
    }

    public var targetRemainingPercent: Double {
        100 - targetUsedPercent
    }

    public var remainingDeltaPercent: Double {
        currentRemainingPercent - targetRemainingPercent
    }

    public var roundedCurrentRemainingPercent: Int {
        roundedPercent(currentRemainingPercent)
    }

    public var roundedTargetRemainingPercent: Int {
        roundedPercent(targetRemainingPercent)
    }

    public var roundedRemainingDeltaPercent: Int {
        Int(round(remainingDeltaPercent))
    }

    public var roundedElapsedWindowPercent: Int {
        roundedPercent(elapsedWindowPercent)
    }

    public var status: QuotaPacingStatus {
        if deltaToTargetPercent >= 8 {
            return .underTarget
        }
        if deltaToTargetPercent <= -8 {
            return .overTarget
        }
        return .onPace
    }

    private func roundedPercent(_ value: Double) -> Int {
        Int(round(min(max(value, 0), 100)))
    }
}

public extension RateLimitDashboard {
    func quotaPacing(
        strategy: QuotaPacingStrategy,
        now: Date = Date(),
        calendar: Calendar = .current,
        holidayCalendar: HolidayCalendar? = nil
    ) -> QuotaPacingSnapshot? {
        guard let bucket = weeklyBucket,
              let resetAt = bucket.resetsAt,
              let durationMinutes = bucket.windowDurationMins,
              durationMinutes > 0
        else {
            return nil
        }

        let durationSeconds = durationMinutes * 60
        let resetTime = Double(resetAt)
        let startTime = resetTime - durationSeconds
        let nowTime = min(max(now.timeIntervalSince1970, startTime), resetTime)
        let elapsedSeconds = nowTime - startTime
        let elapsedRatio = durationSeconds > 0 ? elapsedSeconds / durationSeconds : 0
        let targetUsedPercent: Double

        switch strategy {
        case .timeProportional:
            targetUsedPercent = elapsedRatio * 100
        case .sevenDay:
            targetUsedPercent = Self.dailyTargetUsedPercent(
                elapsedSeconds: elapsedSeconds,
                durationSeconds: durationSeconds
            )
        case .reserveTwenty:
            targetUsedPercent = Self.reserveTargetUsedPercent(
                elapsedSeconds: elapsedSeconds,
                durationSeconds: durationSeconds
            )
        case .workdayWeighted:
            targetUsedPercent = Self.weightedTargetUsedPercent(
                startTime: startTime,
                nowTime: nowTime,
                resetTime: resetTime,
                calendar: calendar,
                holidayCalendar: holidayCalendar
            )
        case .frontLoaded:
            targetUsedPercent = Self.frontLoadedTargetUsedPercent(elapsedRatio: elapsedRatio)
        }

        let currentUsedPercent = min(max(bucket.usedPercent, 0), 100)
        let target = min(max(targetUsedPercent, 0), 100)
        let elapsedWindow = min(max(elapsedRatio * 100, 0), 100)

        return QuotaPacingSnapshot(
            strategy: strategy,
            currentUsedPercent: currentUsedPercent,
            targetUsedPercent: target,
            deltaToTargetPercent: target - currentUsedPercent,
            elapsedWindowPercent: elapsedWindow,
            windowStartAt: Int(round(startTime)),
            resetAt: resetAt
        )
    }

    private static func dailyTargetUsedPercent(elapsedSeconds: Double, durationSeconds: Double) -> Double {
        guard elapsedSeconds > 0 else {
            return 0
        }
        let daySeconds = 86_400.0
        let totalDays = max(1, Int(ceil(durationSeconds / daySeconds)))
        let elapsedDays = min(totalDays, Int(ceil(elapsedSeconds / daySeconds)))
        return Double(elapsedDays) / Double(totalDays) * 100
    }

    private static func reserveTargetUsedPercent(elapsedSeconds: Double, durationSeconds: Double) -> Double {
        let reservePercent = 20.0
        let finalReleaseSeconds = min(86_400.0, durationSeconds * 0.2)
        let mainWindowSeconds = max(durationSeconds - finalReleaseSeconds, 1)
        if elapsedSeconds <= mainWindowSeconds {
            return elapsedSeconds / mainWindowSeconds * (100 - reservePercent)
        }
        let finalElapsed = min(max(elapsedSeconds - mainWindowSeconds, 0), finalReleaseSeconds)
        let finalRatio = finalReleaseSeconds > 0 ? finalElapsed / finalReleaseSeconds : 1
        return (100 - reservePercent) + finalRatio * reservePercent
    }

    private static func frontLoadedTargetUsedPercent(elapsedRatio: Double) -> Double {
        let firstHalfUsePercent = 70.0
        if elapsedRatio <= 0.5 {
            return elapsedRatio / 0.5 * firstHalfUsePercent
        }
        return firstHalfUsePercent + ((elapsedRatio - 0.5) / 0.5) * (100 - firstHalfUsePercent)
    }

    private static func weightedTargetUsedPercent(
        startTime: TimeInterval,
        nowTime: TimeInterval,
        resetTime: TimeInterval,
        calendar: Calendar,
        holidayCalendar: HolidayCalendar?
    ) -> Double {
        let total = weightedDayBudget(
            from: startTime,
            to: resetTime,
            calendar: calendar,
            holidayCalendar: holidayCalendar
        )
        guard total > 0 else {
            return 0
        }
        guard nowTime > startTime else {
            return 0
        }
        let elapsed = elapsedWeightedDayBudget(
            from: startTime,
            to: nowTime,
            resetTime: resetTime,
            calendar: calendar,
            holidayCalendar: holidayCalendar
        )
        return elapsed / total * 100
    }

    private static func elapsedWeightedDayBudget(
        from startTime: TimeInterval,
        to nowTime: TimeInterval,
        resetTime: TimeInterval,
        calendar: Calendar,
        holidayCalendar: HolidayCalendar?
    ) -> Double {
        guard nowTime > startTime,
              let currentDay = calendar.dateInterval(of: .day, for: Date(timeIntervalSince1970: nowTime)) else {
            return 0
        }
        let elapsedEnd = min(currentDay.end.timeIntervalSince1970, resetTime)
        return weightedDayBudget(
            from: startTime,
            to: elapsedEnd,
            calendar: calendar,
            holidayCalendar: holidayCalendar
        )
    }

    private static func weightedDayBudget(
        from startTime: TimeInterval,
        to endTime: TimeInterval,
        calendar: Calendar,
        holidayCalendar: HolidayCalendar?
    ) -> Double {
        guard endTime > startTime,
              let startDay = calendar.dateInterval(of: .day, for: Date(timeIntervalSince1970: startTime)) else {
            return 0
        }

        var total = 0.0
        var cursor = startDay.start
        let endDate = Date(timeIntervalSince1970: endTime)
        while cursor < endDate {
            guard let day = calendar.dateInterval(of: .day, for: cursor) else {
                break
            }
            let segmentEnd = min(day.end, endDate)
            guard segmentEnd > day.start else {
                break
            }
            let dayFraction = segmentEnd.timeIntervalSince(day.start) / day.duration
            total += dayFraction * dayWeight(
                for: cursor,
                calendar: calendar,
                holidayCalendar: holidayCalendar
            )
            cursor = segmentEnd
        }
        return total
    }

    private static func dayWeight(
        for date: Date,
        calendar: Calendar,
        holidayCalendar: HolidayCalendar?
    ) -> Double {
        switch holidayCalendar?.dayKind(for: date, calendar: calendar) {
        case .workday:
            return 1
        case .holiday:
            return 0.35
        case nil:
            break
        }
        let weekday = calendar.component(.weekday, from: date)
        if weekday == 1 || weekday == 7 {
            return 0.35
        }
        return 1
    }
}
