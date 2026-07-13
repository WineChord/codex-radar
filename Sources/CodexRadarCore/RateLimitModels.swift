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
        if let weekly = bestWindow(near: AppConstants.weeklyWindowMinutes) {
            return weekly
        }
        guard windows.count == 1, windows[0].windowDurationMins == nil else {
            return nil
        }
        return windows[0]
    }

    public var weeklyRemainingPercent: Int? {
        weeklyBucket?.remainingPercent
    }

    public var isBlocked: Bool {
        snapshot.rateLimitReachedType != nil
            || (weeklyBucket?.usedPercent ?? 0) >= 100
    }

    private var windows: [RateLimitWindow] {
        [snapshot.primary, snapshot.secondary].compactMap { $0 }
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
