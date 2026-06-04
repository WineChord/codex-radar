import Foundation

public struct DashboardState: Equatable {
    public var rateLimits: RateLimitDashboard?
    public var current: RadarCurrent?
    public var prediction: RadarPrediction?
    public var modelIQ: ModelIQEnvelope?
    public var lastUpdatedAt: Date?
    public var lastError: String?

    public init(
        rateLimits: RateLimitDashboard? = nil,
        current: RadarCurrent? = nil,
        prediction: RadarPrediction? = nil,
        modelIQ: ModelIQEnvelope? = nil,
        lastUpdatedAt: Date? = nil,
        lastError: String? = nil
    ) {
        self.rateLimits = rateLimits
        self.current = current
        self.prediction = prediction
        self.modelIQ = modelIQ
        self.lastUpdatedAt = lastUpdatedAt
        self.lastError = lastError
    }

    public var statusTitle: String {
        if current?.windowOpen == true {
            return "速蹬 · WK \(DisplayFormatters.percent(rateLimits?.weeklyRemainingPercent))"
        }
        if rateLimits?.isBlocked == true {
            return "限额 · WK \(DisplayFormatters.percent(rateLimits?.weeklyRemainingPercent))"
        }
        var parts = ["WK \(DisplayFormatters.percent(rateLimits?.weeklyRemainingPercent))"]
        if let iqScore = modelIQ?.latest?.iqScore {
            parts.append("IQ\(iqScore)")
        }
        if let level = predictionLevelLabel {
            parts.append(level)
        }
        return parts.joined(separator: " · ")
    }

    public var actionLabel: String {
        if current?.windowOpen == true {
            return "速蹬窗口开启"
        }
        if rateLimits?.isBlocked == true {
            return "本机限额中"
        }
        if recentResetClosed {
            return "limit reset 已确认"
        }
        return "等待"
    }

    public var predictionLevelLabel: String? {
        let level = prediction?.level ?? current?.prediction?.level
        switch level?.lowercased() {
        case "high":
            return "高"
        case "medium":
            return "中"
        case "low":
            return "低"
        default:
            return nil
        }
    }

    public var recentResetClosed: Bool {
        current?.lastWindow?.status?.lowercased() == "closed"
            && current?.lastWindow?.closedAt != nil
    }
}
