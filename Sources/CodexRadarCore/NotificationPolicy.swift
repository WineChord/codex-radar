import Foundation

public struct NotificationEvent: Equatable {
    public enum Severity: String, Equatable {
        case passive
        case active
        case urgent
    }

    public let identifier: String
    public let title: String
    public let body: String
    public let severity: Severity

    public init(
        identifier: String,
        title: String,
        body: String,
        severity: Severity
    ) {
        self.identifier = identifier
        self.title = title
        self.body = body
        self.severity = severity
    }
}

public struct NotificationMemory: Equatable {
    public var initialized: Bool
    public var lastSpeedOpenKey: String?
    public var lastResetCloseKey: String?
    public var lastPredictionKey: String?
    public var lastIQKey: String?
    public var lastWeeklyWarningKey: String?
    public var lastWeeklyCriticalKey: String?
    public var lastWeeklyRestoreKey: String?
    public var lastWeeklyWarningAt: Date?
    public var lastWeeklyCriticalAt: Date?

    public init(
        initialized: Bool = false,
        lastSpeedOpenKey: String? = nil,
        lastResetCloseKey: String? = nil,
        lastPredictionKey: String? = nil,
        lastIQKey: String? = nil,
        lastWeeklyWarningKey: String? = nil,
        lastWeeklyCriticalKey: String? = nil,
        lastWeeklyRestoreKey: String? = nil,
        lastWeeklyWarningAt: Date? = nil,
        lastWeeklyCriticalAt: Date? = nil
    ) {
        self.initialized = initialized
        self.lastSpeedOpenKey = lastSpeedOpenKey
        self.lastResetCloseKey = lastResetCloseKey
        self.lastPredictionKey = lastPredictionKey
        self.lastIQKey = lastIQKey
        self.lastWeeklyWarningKey = lastWeeklyWarningKey
        self.lastWeeklyCriticalKey = lastWeeklyCriticalKey
        self.lastWeeklyRestoreKey = lastWeeklyRestoreKey
        self.lastWeeklyWarningAt = lastWeeklyWarningAt
        self.lastWeeklyCriticalAt = lastWeeklyCriticalAt
    }
}

public struct NotificationPolicy {
    public init() {}

    public func evaluate(
        previous: DashboardState?,
        current: DashboardState,
        memory: inout NotificationMemory,
        now: Date = Date()
    ) -> [NotificationEvent] {
        let wasInitialized = memory.initialized
        if !memory.initialized {
            seedInitialMemory(current: current, memory: &memory)
        }

        var events: [NotificationEvent] = []
        appendSpeedWindowEvents(
            current: current,
            wasInitialized: wasInitialized,
            memory: &memory,
            events: &events
        )
        guard wasInitialized else {
            return events
        }
        appendResetEvents(current: current, memory: &memory, events: &events)
        appendWeeklyLimitEvents(
            previous: previous,
            current: current,
            memory: &memory,
            events: &events,
            now: now
        )
        appendPredictionEvents(
            previous: previous,
            current: current,
            memory: &memory,
            events: &events
        )
        appendIQEvents(current: current, memory: &memory, events: &events)
        return events
    }

    private func seedInitialMemory(current: DashboardState, memory: inout NotificationMemory) {
        memory.initialized = true
        if let key = speedOpenKey(current: current), current.current?.windowOpen != true {
            memory.lastSpeedOpenKey = key
        }
        if let key = resetCloseKey(current: current) {
            memory.lastResetCloseKey = key
        }
        if let key = iqKey(current: current) {
            memory.lastIQKey = key
        }
        if let key = predictionKey(current: current) {
            memory.lastPredictionKey = key
        }
    }

    private func appendSpeedWindowEvents(
        current: DashboardState,
        wasInitialized: Bool,
        memory: inout NotificationMemory,
        events: inout [NotificationEvent]
    ) {
        guard current.activeSpeedWindow, let key = speedOpenKey(current: current) else {
            return
        }
        guard memory.lastSpeedOpenKey != key else {
            return
        }
        memory.lastSpeedOpenKey = key
        let weekly = DisplayFormatters.percent(current.rateLimits?.weeklyRemainingPercent)
        events.append(NotificationEvent(
            identifier: "speed-window-open-\(key)",
            title: "速蹬窗口开启",
            body: wasInitialized ? "当前周额度剩余 \(weekly)，建议尽快使用。" : "App 启动时检测到窗口已开启，当前周额度剩余 \(weekly)。",
            severity: .urgent
        ))
    }

    private func appendResetEvents(
        current: DashboardState,
        memory: inout NotificationMemory,
        events: inout [NotificationEvent]
    ) {
        guard let key = resetCloseKey(current: current) else {
            return
        }
        guard memory.lastResetCloseKey != key else {
            return
        }
        memory.lastResetCloseKey = key
        let title = current.current?.lastWindow?.title ?? "Codex limit reset"
        events.append(NotificationEvent(
            identifier: "reset-close-\(key)",
            title: "CodexRadar 记录到 reset",
            body: title,
            severity: .urgent
        ))
    }

    private func appendWeeklyLimitEvents(
        previous: DashboardState?,
        current: DashboardState,
        memory: inout NotificationMemory,
        events: inout [NotificationEvent],
        now: Date
    ) {
        guard let remaining = current.rateLimits?.weeklyRemainingPercent else {
            return
        }
        let resetKey = current.rateLimits?.weeklyBucket?.resetsAt.map(String.init) ?? "unknown"

        if remaining <= AppConstants.criticalRemainingPercent {
            let key = "\(resetKey):critical"
            if shouldSendQuotaNotification(
                key: key,
                lastKey: memory.lastWeeklyCriticalKey,
                lastSentAt: memory.lastWeeklyCriticalAt,
                cooldown: AppConstants.weeklyCriticalNotificationCooldownSeconds,
                now: now
            ) {
                memory.lastWeeklyCriticalKey = key
                memory.lastWeeklyCriticalAt = now
                events.append(NotificationEvent(
                    identifier: "weekly-critical-\(key)",
                    title: "Codex 周额度很低",
                    body: "当前周额度剩余 \(remaining)%。",
                    severity: .urgent
                ))
            }
        } else if remaining <= AppConstants.warningRemainingPercent {
            let key = "\(resetKey):warning"
            if shouldSendQuotaNotification(
                key: key,
                lastKey: memory.lastWeeklyWarningKey,
                lastSentAt: memory.lastWeeklyWarningAt,
                cooldown: AppConstants.weeklyWarningNotificationCooldownSeconds,
                now: now
            ) {
                memory.lastWeeklyWarningKey = key
                memory.lastWeeklyWarningAt = now
                events.append(NotificationEvent(
                    identifier: "weekly-warning-\(key)",
                    title: "Codex 周额度偏低",
                    body: "当前周额度剩余 \(remaining)%。",
                    severity: .active
                ))
            }
        }

        guard let previousRemaining = previous?.rateLimits?.weeklyRemainingPercent else {
            return
        }
        let previousReset = previous?.rateLimits?.weeklyBucket?.resetsAt
        let currentReset = current.rateLimits?.weeklyBucket?.resetsAt
        guard previousRemaining <= AppConstants.warningRemainingPercent,
              remaining >= AppConstants.restoredRemainingPercent,
              previousReset != currentReset else {
            return
        }
        let key = "\(resetKey):restored"
        guard memory.lastWeeklyRestoreKey != key else {
            return
        }
        memory.lastWeeklyRestoreKey = key
        events.append(NotificationEvent(
            identifier: "weekly-restored-\(key)",
            title: "Codex 周额度已恢复",
            body: "当前周额度剩余 \(remaining)%。",
            severity: .active
        ))
    }

    private func shouldSendQuotaNotification(
        key: String,
        lastKey: String?,
        lastSentAt: Date?,
        cooldown: TimeInterval,
        now: Date
    ) -> Bool {
        guard lastKey != key else {
            return false
        }
        guard let lastSentAt else {
            return true
        }
        return now.timeIntervalSince(lastSentAt) >= cooldown
    }

    private func appendPredictionEvents(
        previous: DashboardState?,
        current: DashboardState,
        memory: inout NotificationMemory,
        events: inout [NotificationEvent]
    ) {
        guard current.current?.status?.lowercased() != "retired" else {
            return
        }
        guard let prediction = current.prediction else {
            return
        }
        let level = prediction.level?.lowercased()
        let previousLevel = previous?.prediction?.level?.lowercased()
        let shouldNotify = prediction.shouldNotify == true || (level == "high" && previousLevel != "high")
        guard shouldNotify, let key = predictionKey(current: current) else {
            return
        }
        guard memory.lastPredictionKey != key else {
            return
        }
        memory.lastPredictionKey = key
        let probability = prediction.probability24h.map { "\(Int(round($0 * 100)))%" } ?? "unknown"
        events.append(NotificationEvent(
            identifier: "prediction-\(key)",
            title: "Codex reset 预测升高",
            body: "未来 24h 概率 \(probability)，等级 \(prediction.level ?? "unknown")。",
            severity: .active
        ))
    }

    private func appendIQEvents(
        current: DashboardState,
        memory: inout NotificationMemory,
        events: inout [NotificationEvent]
    ) {
        guard let latest = current.modelIQ?.latest,
              let score = latest.iqScore,
              score < 80 || latest.status?.lowercased() == "red",
              let key = iqKey(current: current),
              memory.lastIQKey != key else {
            return
        }
        memory.lastIQKey = key
        let passed = latest.passed.map(String.init) ?? "?"
        let tasks = latest.tasks.map(String.init) ?? "?"
        let scoreText = DisplayFormatters.iqScore(score)
        events.append(NotificationEvent(
            identifier: "model-iq-\(key)",
            title: "Codex IQ 偏低",
            body: "IQ \(scoreText)，\(passed)/\(tasks) tasks 通过。",
            severity: .passive
        ))
    }

    private func speedOpenKey(current: DashboardState) -> String? {
        guard let window = current.current?.lastWindow else {
            return current.activeSpeedWindow ? "unknown-open" : nil
        }
        return "\(window.id ?? "unknown"):\(window.openedAt ?? "unknown")"
    }

    private func resetCloseKey(current: DashboardState) -> String? {
        guard let window = current.current?.lastWindow,
              window.status?.lowercased() == "closed",
              let closedAt = window.closedAt else {
            return nil
        }
        return "\(window.id ?? "unknown"):\(closedAt)"
    }

    private func predictionKey(current: DashboardState) -> String? {
        guard let prediction = current.prediction else {
            return nil
        }
        return "\(prediction.updatedAt ?? "unknown"):\(prediction.level ?? "unknown"):\(prediction.probability24h ?? -1)"
    }

    private func iqKey(current: DashboardState) -> String? {
        guard let latest = current.modelIQ?.latest else {
            return nil
        }
        return "\(latest.date ?? "unknown"):\(DisplayFormatters.iqScore(latest.iqScore)):\(latest.status ?? "unknown")"
    }
}
