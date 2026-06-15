import Foundation

public struct DashboardState: Equatable {
    public var rateLimits: RateLimitDashboard?
    public var current: RadarCurrent?
    public var prediction: RadarPrediction?
    public var modelIQ: ModelIQEnvelope?
    public var modelRatings: ModelRatingsEnvelope?
    public var lastUpdatedAt: Date?
    public var lastError: String?

    public init(
        rateLimits: RateLimitDashboard? = nil,
        current: RadarCurrent? = nil,
        prediction: RadarPrediction? = nil,
        modelIQ: ModelIQEnvelope? = nil,
        modelRatings: ModelRatingsEnvelope? = nil,
        lastUpdatedAt: Date? = nil,
        lastError: String? = nil
    ) {
        self.rateLimits = rateLimits
        self.current = current
        self.prediction = prediction
        self.modelIQ = modelIQ
        self.modelRatings = modelRatings
        self.lastUpdatedAt = lastUpdatedAt
        self.lastError = lastError
    }

    public var statusTitle: String {
        let quota = DisplayFormatters.percent(rateLimits?.weeklyRemainingPercent)
        let iq = DisplayFormatters.compactIQScore(modelIQ?.latest?.iqScore)
        let signal: String
        if activeSpeedWindow {
            signal = "速蹬"
        } else if rateLimits?.isBlocked == true {
            signal = "限额"
        } else {
            signal = qualityLabel ?? entitlementEventLabel ?? predictionLevelLabel ?? "-"
        }
        return "\(quota)/\(iq)/\(signal)"
    }

    public var actionLabel: String {
        if activeSpeedWindow {
            return "速蹬窗口开启"
        }
        if rateLimits?.isBlocked == true {
            return "本机限额中"
        }
        if recentResetClosed {
            return "上次 reset 时间"
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

    public var qualityLabel: String? {
        guard let score = modelIQ?.latest?.iqScore else {
            return nil
        }
        let status = modelIQ?.latest?.status?.lowercased()
        if status == "red" || score < 80 {
            return "低"
        }
        if status == "yellow" || score < 95 {
            return "中"
        }
        return "正常"
    }

    public var recentResetClosed: Bool {
        current?.lastWindow?.status?.lowercased() == "closed"
            && current?.lastWindow?.closedAt != nil
    }

    public var activeSpeedWindow: Bool {
        guard current?.windowOpen == true else {
            return false
        }
        let fields = [
            current?.lastWindow?.id,
            current?.lastWindow?.title,
            current?.lastWindow?.summary,
            current?.lastWindow?.windowHuman,
            current?.recommendedAction,
        ]
        let joined = fields.compactMap { $0?.lowercased() }.joined(separator: " ")
        return joined.contains("速蹬")
            || joined.contains("speed-window")
            || joined.contains("speed window")
    }

    public var activeEntitlementEvent: Bool {
        current?.windowOpen == true && !activeSpeedWindow
    }

    public var entitlementEventLabel: String? {
        activeEntitlementEvent ? "权益" : nil
    }

    public var speedAlertKey: String? {
        guard activeSpeedWindow else {
            return nil
        }
        guard let window = current?.lastWindow else {
            return "unknown-open"
        }
        return "\(window.id ?? "unknown"):\(window.openedAt ?? "unknown")"
    }
}
