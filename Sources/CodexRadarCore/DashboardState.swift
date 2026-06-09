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
        let quota = DisplayFormatters.percent(rateLimits?.weeklyRemainingPercent)
        let iq = DisplayFormatters.compactIQScore(modelIQ?.latest?.iqScore)
        let signal: String
        if current?.windowOpen == true {
            signal = "速蹬"
        } else if rateLimits?.isBlocked == true {
            signal = "限额"
        } else {
            signal = predictionLevelLabel ?? "-"
        }
        return "\(quota)/\(iq)/\(signal)"
    }

    public var actionLabel: String {
        if current?.windowOpen == true {
            return "速蹬窗口开启"
        }
        if rateLimits?.isBlocked == true {
            return "本机限额中"
        }
        if recentResetClosed {
            return "CodexRadar 已记录 reset"
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

    public var speedAlertKey: String? {
        guard current?.windowOpen == true else {
            return nil
        }
        guard let window = current?.lastWindow else {
            return "unknown-open"
        }
        return "\(window.id ?? "unknown"):\(window.openedAt ?? "unknown")"
    }
}
