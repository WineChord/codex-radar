import Foundation

public struct RateLimitResponse: Decodable, Equatable {
    public let rateLimits: RateLimitSnapshot
    public let rateLimitsByLimitId: [String: RateLimitSnapshot]?
}

public struct RateLimitSnapshot: Decodable, Equatable {
    public let limitId: String?
    public let limitName: String?
    public let primary: RateLimitWindow?
    public let secondary: RateLimitWindow?
    public let credits: CreditsSnapshot?
    public let planType: String?
    public let rateLimitReachedType: String?
}

public struct RateLimitWindow: Decodable, Equatable {
    public let usedPercent: Double
    public let windowDurationMins: Double?
    public let resetsAt: Int?

    public var remainingPercent: Int {
        let remaining = 100.0 - usedPercent
        return Int(round(min(max(remaining, 0.0), 100.0)))
    }
}

public struct CreditsSnapshot: Decodable, Equatable {
    public let hasCredits: Bool
    public let unlimited: Bool
    public let balance: String?
}

public struct RateLimitDashboard: Equatable {
    public let snapshot: RateLimitSnapshot
    public let allBuckets: [String: RateLimitSnapshot]

    public init(response: RateLimitResponse) {
        let buckets = response.rateLimitsByLimitId ?? [:]
        self.snapshot = buckets[AppConstants.codexLimitID] ?? response.rateLimits
        self.allBuckets = buckets
    }

    public var weeklyBucket: RateLimitWindow? {
        return bestWindow(near: AppConstants.weeklyWindowMinutes) ?? longestWindow
    }

    public var shortBucket: RateLimitWindow? {
        bestWindow(near: AppConstants.fiveHourWindowMinutes)
    }

    public var weeklyRemainingPercent: Int? {
        weeklyBucket?.remainingPercent
    }

    public var shortRemainingPercent: Int? {
        shortBucket?.remainingPercent
    }

    public var isBlocked: Bool {
        snapshot.rateLimitReachedType != nil
            || (snapshot.primary?.usedPercent ?? 0) >= 100
            || (snapshot.secondary?.usedPercent ?? 0) >= 100
    }

    private var windows: [RateLimitWindow] {
        [snapshot.primary, snapshot.secondary].compactMap { $0 }
    }

    private var longestWindow: RateLimitWindow? {
        windows.max {
            ($0.windowDurationMins ?? 0) < ($1.windowDurationMins ?? 0)
        }
    }

    private func bestWindow(near targetMinutes: Double) -> RateLimitWindow? {
        windows.first { window in
            guard let duration = window.windowDurationMins else {
                return false
            }
            let delta = abs(duration - targetMinutes)
            return delta <= targetMinutes * AppConstants.windowDurationTolerance
        }
    }
}
