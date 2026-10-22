import Foundation

/// Linear projections use complete, continuous windows within the current quota cycle.
public struct QuotaDepletionForecast: Equatable {
    public enum Window: Int, CaseIterable, Identifiable {
        case minutes30 = 30
        case hour1 = 60
        case hours2 = 120
        case hours5 = 300

        public var id: Int { rawValue }
        public var duration: TimeInterval { Double(rawValue) * 60 }
    }

    public enum Outcome: Equatable {
        case insufficientData
        case noConsumption
        case alreadyDepleted
        case depletes(at: Date)
        case resetsFirst
        case slowConsumption
    }

    public let window: Window
    /// Percentage points of the total quota consumed per hour.
    public let hourlyConsumption: Double?
    public let outcome: Outcome

    public static func estimates(
        timeline: QuotaHistoryTimeline,
        current: QuotaHistorySample
    ) -> [Self] {
        let cutoff = current.timestamp.addingTimeInterval(-Window.hours5.duration - maximumGap)
        var recent = timeline.samples.filter {
            $0.timestamp >= cutoff && $0.timestamp < current.timestamp
        }
        recent.append(current)
        return Window.allCases.map { window in
            estimate(window: window, samples: recent, current: current)
        }
    }

    private static let maximumGap = QuotaHistoryRange.hours24.continuityGap

    private static func estimate(
        window: Window,
        samples: [QuotaHistorySample],
        current: QuotaHistorySample
    ) -> Self {
        func result(_ outcome: Outcome, rate: Double? = nil) -> Self {
            Self(window: window, hourlyConsumption: rate, outcome: outcome)
        }
        guard QuotaHistoryTimeline.isValid(current) else { return result(.insufficientData) }
        if current.remainingPercent == 0 { return result(.alreadyDepleted) }
        if let reset = current.resetsAt, reset <= current.timestamp {
            return result(.insufficientData)
        }
        let start = current.timestamp.addingTimeInterval(-window.duration)
        guard let index = samples.lastIndex(where: { $0.timestamp <= start }),
              index + 1 < samples.count else { return result(.insufficientData) }
        let segment = samples[index...]
        for (previous, next) in zip(segment, segment.dropFirst()) {
            let resetMoved = previous.resetsAt.flatMap { old in
                next.resetsAt.map { abs($0.timeIntervalSince(old)) >= 30 * 60 }
            } ?? false
            guard next.timestamp.timeIntervalSince(previous.timestamp) <= maximumGap,
                  next.remainingPercent <= previous.remainingPercent,
                  !resetMoved else { return result(.insufficientData) }
        }
        let before = samples[index]
        let after = samples[index + 1]
        let fraction = start.timeIntervalSince(before.timestamp)
            / after.timestamp.timeIntervalSince(before.timestamp)
        let remainingAtStart = before.remainingPercent
            + fraction * (after.remainingPercent - before.remainingPercent)
        let consumed = max(0, remainingAtStart - current.remainingPercent)
        let rate = consumed * 3600 / window.duration
        guard rate > 0 else { return result(.noConsumption, rate: 0) }
        let duration = current.remainingPercent / rate * 3600
        if let reset = current.resetsAt,
           duration >= reset.timeIntervalSince(current.timestamp) {
            return result(.resetsFirst, rate: rate)
        }
        // Avoid displaying precise calendar dates for negligible consumption far in the future.
        guard duration.isFinite, duration <= 365 * 86_400 else {
            return result(.slowConsumption, rate: rate)
        }
        return result(.depletes(at: current.timestamp.addingTimeInterval(duration)), rate: rate)
    }
}
