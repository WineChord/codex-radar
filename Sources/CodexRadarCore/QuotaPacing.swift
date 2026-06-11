import Foundation

public enum QuotaPacingStrategy: String, CaseIterable, Identifiable {
    case timeProportional
    case sevenDay

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
    func quotaPacing(strategy: QuotaPacingStrategy, now: Date = Date()) -> QuotaPacingSnapshot? {
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
}
