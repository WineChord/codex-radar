import Foundation

public struct RadarCurrent: Decodable, Equatable {
    public let schemaVersion: String?
    public let checkedAt: String?
    public let status: String?
    public let windowOpen: Bool
    public let recommendedAction: String?
    public let lastWindow: RadarWindow?
    public let prediction: RadarPredictionSummary?
    public let predictionDetail: RadarPrediction?
    public let modelIQ: ModelIQEnvelope?

    public var checkedDate: Date? {
        RadarDateParser.date(from: checkedAt)
    }

    public init(
        schemaVersion: String?,
        checkedAt: String?,
        status: String?,
        windowOpen: Bool,
        recommendedAction: String?,
        lastWindow: RadarWindow?,
        prediction: RadarPredictionSummary?,
        predictionDetail: RadarPrediction?,
        modelIQ: ModelIQEnvelope?
    ) {
        self.schemaVersion = schemaVersion
        self.checkedAt = checkedAt
        self.status = status
        self.windowOpen = windowOpen
        self.recommendedAction = recommendedAction
        self.lastWindow = lastWindow
        self.prediction = prediction
        self.predictionDetail = predictionDetail
        self.modelIQ = modelIQ
    }

    public func withModelIQ(_ modelIQ: ModelIQEnvelope?) -> RadarCurrent {
        RadarCurrent(
            schemaVersion: schemaVersion,
            checkedAt: checkedAt,
            status: status,
            windowOpen: windowOpen,
            recommendedAction: recommendedAction,
            lastWindow: lastWindow,
            prediction: prediction,
            predictionDetail: predictionDetail,
            modelIQ: modelIQ ?? self.modelIQ
        )
    }

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case checkedAt = "checked_at"
        case monitoredAt = "monitored_at"
        case status
        case windowOpen = "window_open"
        case recommendedAction = "recommended_action"
        case lastWindow = "last_window"
        case window
        case recentWindows = "recent_windows"
        case prediction
        case modelIQ = "model_iq"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(String.self, forKey: .schemaVersion)
        checkedAt = try container.decodeIfPresent(String.self, forKey: .checkedAt)
            ?? container.decodeIfPresent(String.self, forKey: .monitoredAt)
        status = try container.decodeIfPresent(String.self, forKey: .status)
        let windowPayload = try container.decodeIfPresent(RadarWindowPayload.self, forKey: .window)
        windowOpen = try container.decodeIfPresent(Bool.self, forKey: .windowOpen)
            ?? windowPayload?.open
            ?? false
        recommendedAction = try container.decodeIfPresent(String.self, forKey: .recommendedAction)
            ?? windowPayload?.action

        let recentWindows = try container.decodeIfPresent([RadarWindow].self, forKey: .recentWindows) ?? []
        if let decodedLastWindow = try container.decodeIfPresent(RadarWindow.self, forKey: .lastWindow) {
            lastWindow = decodedLastWindow
        } else if windowPayload?.open == true {
            lastWindow = windowPayload?.radarWindow ?? recentWindows.first
        } else {
            lastWindow = recentWindows.first ?? windowPayload?.radarWindow
        }

        predictionDetail = try container.decodeIfPresent(RadarPrediction.self, forKey: .prediction)
        prediction = predictionDetail.map(RadarPredictionSummary.init)
        modelIQ = try container.decodeIfPresent(ModelIQEnvelope.self, forKey: .modelIQ)
    }
}

public struct RadarWindow: Decodable, Equatable {
    public let id: String?
    public let title: String?
    public let status: String?
    public let openedAt: String?
    public let closedAt: String?
    public let windowMinutes: Int?
    public let windowHuman: String?
    public let scope: String?
    public let summary: String?
    public let sources: [RadarSource]?
    public let sourceURL: String?

    public var openedDate: Date? {
        RadarDateParser.date(from: openedAt)
    }

    public var closedDate: Date? {
        RadarDateParser.date(from: closedAt)
    }

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case status
        case openedAt = "opened_at"
        case closedAt = "closed_at"
        case windowMinutes = "window_minutes"
        case windowHuman = "window_human"
        case scope
        case summary
        case sources
        case sourceURL = "source_url"
    }
}

private struct RadarWindowPayload: Decodable, Equatable {
    let open: Bool?
    let status: String?
    let action: String?
    let message: String?
    let title: String?
    let scope: String?
    let openedAt: String?
    let closedAt: String?
    let sourceURL: String?

    var radarWindow: RadarWindow {
        let url = sourceURL.map { RadarSource(type: "source", url: $0) }
        return RadarWindow(
            id: nil,
            title: title,
            status: normalizedStatus,
            openedAt: openedAt,
            closedAt: closedAt,
            windowMinutes: nil,
            windowHuman: open == true ? message : "无窗",
            scope: scope,
            summary: message,
            sources: url.map { [$0] },
            sourceURL: sourceURL
        )
    }

    private var normalizedStatus: String? {
        if open == true {
            return status == "none" ? "open" : status
        }
        if closedAt != nil {
            return "closed"
        }
        return status
    }

    enum CodingKeys: String, CodingKey {
        case open
        case status
        case action
        case message
        case title
        case scope
        case openedAt = "opened_at"
        case closedAt = "closed_at"
        case sourceURL = "source_url"
    }
}

public struct RadarSource: Decodable, Equatable {
    public let type: String?
    public let url: String?
}

public struct RadarPredictionSummary: Decodable, Equatable {
    public let level: String?
    public let probability24h: Double?
    public let probability48h: Double?
    public let shouldNotify: Bool?

    enum CodingKeys: String, CodingKey {
        case level
        case probability24h = "probability_24h"
        case probability48h = "probability_48h"
        case shouldNotify = "should_notify"
    }

    init(_ detail: RadarPrediction) {
        level = detail.level
        probability24h = detail.probability24h
        probability48h = detail.probability48h
        shouldNotify = detail.shouldNotify
    }
}

public struct RadarPrediction: Decodable, Equatable {
    public let level: String?
    public let probability24h: Double?
    public let probability48h: Double?
    public let shouldNotify: Bool?
    public let expectedWindow: String?
    public let reasoningSummary: String?
    public let updatedAt: String?

    public var updatedDate: Date? {
        RadarDateParser.date(from: updatedAt)
    }

    enum CodingKeys: String, CodingKey {
        case level
        case probability24h = "probability_24h"
        case probability48h = "probability_48h"
        case shouldNotify = "should_notify"
        case expectedWindow = "expected_window"
        case reasoningSummary = "reasoning_summary"
        case summary
        case updatedAt = "updated_at"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        level = try container.decodeIfPresent(String.self, forKey: .level)
        probability24h = try container.decodeIfPresent(Double.self, forKey: .probability24h)
        probability48h = try container.decodeIfPresent(Double.self, forKey: .probability48h)
        shouldNotify = try container.decodeIfPresent(Bool.self, forKey: .shouldNotify)
        expectedWindow = try container.decodeIfPresent(String.self, forKey: .expectedWindow)
        reasoningSummary = try container.decodeIfPresent(String.self, forKey: .reasoningSummary)
            ?? container.decodeIfPresent(String.self, forKey: .summary)
        updatedAt = try container.decodeIfPresent(String.self, forKey: .updatedAt)
    }
}

public struct ModelIQEnvelope: Decodable, Equatable {
    public let updatedAt: String?
    public let latest: ModelIQSnapshot?
    public let comparisons: [String: ModelIQComparison]
    public let quotaRadar: QuotaRadar?

    public var latestRows: [ModelIQLatestRow] {
        var rows = [ModelIQLatestRow]()
        if let latest {
            rows.append(ModelIQLatestRow(label: Self.modelLabel(latest), snapshot: latest))
        }
        rows.append(contentsOf: comparisons.values
            .sorted(by: Self.sortComparisons)
            .compactMap { comparison in
                guard let latest = comparison.latest else {
                    return nil
                }
                return ModelIQLatestRow(
                    label: comparison.label ?? Self.modelLabel(latest),
                    snapshot: latest
                )
            })
        return rows
    }

    enum CodingKeys: String, CodingKey {
        case updatedAt = "updated_at"
        case latest
        case comparisons
        case quotaRadar = "quota_radar"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        updatedAt = try container.decodeIfPresent(String.self, forKey: .updatedAt)
        latest = try container.decodeIfPresent(ModelIQSnapshot.self, forKey: .latest)
        comparisons = try container.decodeIfPresent([String: ModelIQComparison].self, forKey: .comparisons) ?? [:]
        quotaRadar = try container.decodeIfPresent(QuotaRadar.self, forKey: .quotaRadar)
    }

    private static func sortComparisons(_ lhs: ModelIQComparison, _ rhs: ModelIQComparison) -> Bool {
        if lhs.modelVersionRank != rhs.modelVersionRank {
            return lhs.modelVersionRank > rhs.modelVersionRank
        }
        if lhs.effortRank != rhs.effortRank {
            return lhs.effortRank < rhs.effortRank
        }
        return (lhs.label ?? "") < (rhs.label ?? "")
    }

    private static func modelLabel(_ snapshot: ModelIQSnapshot) -> String? {
        guard let model = snapshot.model else {
            return snapshot.reasoningEffort
        }
        let prefix = model.uppercased().hasPrefix("GPT-") ? model.uppercased() : model
        guard let effort = snapshot.reasoningEffort else {
            return prefix
        }
        return "\(prefix) \(effort)"
    }
}

public struct QuotaRadar: Decodable, Equatable {
    public let date: String?
    public let updatedAt: String?
    public let basisDate: String?
    public let basisWindowLabel: String?
    public let costUSD: Double?
    public let totalTokens: Int?
    public let rows: [QuotaRadarRow]
    public let trend: [QuotaRadarTrendPoint]

    public var sevenDayTrendDelta20x: Double? {
        guard trend.count >= 2,
              let previous = trend.dropLast().last?.sevenDay20x,
              let latest = trend.last?.sevenDay20x else {
            return nil
        }
        return latest - previous
    }

    enum CodingKeys: String, CodingKey {
        case date
        case updatedAt = "updated_at"
        case basisDate = "basis_date"
        case basisWindowLabel = "basis_window_label"
        case costUSD = "cost_usd"
        case totalTokens = "total_tokens"
        case rows
        case trend
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        date = try container.decodeIfPresent(String.self, forKey: .date)
        updatedAt = try container.decodeIfPresent(String.self, forKey: .updatedAt)
        basisDate = try container.decodeIfPresent(String.self, forKey: .basisDate)
        basisWindowLabel = try container.decodeIfPresent(String.self, forKey: .basisWindowLabel)
        costUSD = try container.decodeIfPresent(Double.self, forKey: .costUSD)
        totalTokens = try container.decodeIfPresent(Int.self, forKey: .totalTokens)
        rows = try container.decodeIfPresent([QuotaRadarRow].self, forKey: .rows) ?? []
        trend = try container.decodeIfPresent([QuotaRadarTrendPoint].self, forKey: .trend) ?? []
    }
}

public struct QuotaRadarRow: Decodable, Equatable, Identifiable {
    public let tier: String?
    public let basis: String?
    public let fiveHourUSD: Double?
    public let sevenDayUSD: Double?

    public var id: String {
        tier ?? "\(fiveHourUSD ?? -1)-\(sevenDayUSD ?? -1)"
    }

    enum CodingKeys: String, CodingKey {
        case tier
        case basis
        case fiveHourUSD = "five_h"
        case sevenDayUSD = "seven_d"
    }
}

public struct QuotaRadarTrendPoint: Decodable, Equatable {
    public let date: String?
    public let updatedAt: String?
    public let basisWindowLabel: String?
    public let fiveHour20x: Double?
    public let sevenDay20x: Double?

    enum CodingKeys: String, CodingKey {
        case date
        case updatedAt = "updated_at"
        case basisWindowLabel = "basis_window_label"
        case fiveHour20x = "five_h_20x"
        case sevenDay20x = "seven_d_20x"
    }
}

public struct ModelIQComparison: Decodable, Equatable {
    public let label: String?
    public let model: String?
    public let reasoningEffort: String?
    public let latest: ModelIQSnapshot?
    public let recentDays: [ModelIQSnapshot]

    enum CodingKeys: String, CodingKey {
        case label
        case model
        case reasoningEffort = "reasoning_effort"
        case latest
        case recentDays = "recent_days"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        label = try container.decodeIfPresent(String.self, forKey: .label)
        model = try container.decodeIfPresent(String.self, forKey: .model)
        reasoningEffort = try container.decodeIfPresent(String.self, forKey: .reasoningEffort)
        latest = try container.decodeIfPresent(ModelIQSnapshot.self, forKey: .latest)
        recentDays = try container.decodeIfPresent([ModelIQSnapshot].self, forKey: .recentDays) ?? []
    }

    fileprivate var modelVersionRank: Double {
        let source = model ?? latest?.model ?? label ?? ""
        let pattern = #"(\d+(?:\.\d+)?)"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: source, range: NSRange(source.startIndex..<source.endIndex, in: source)),
              let range = Range(match.range(at: 1), in: source),
              let version = Double(source[range]) else {
            return 0
        }
        return version
    }

    fileprivate var effortRank: Int {
        let effort = (reasoningEffort ?? latest?.reasoningEffort ?? label ?? "").lowercased()
        if effort.contains("xhigh") {
            return 0
        }
        if effort.contains("high") {
            return 1
        }
        if effort.contains("medium") {
            return 2
        }
        if effort.contains("low") {
            return 3
        }
        return 9
    }
}

public struct ModelIQLatestRow: Equatable, Identifiable {
    public let label: String?
    public let snapshot: ModelIQSnapshot

    public var id: String {
        [
            label,
            snapshot.model,
            snapshot.reasoningEffort,
            snapshot.date
        ]
        .compactMap { $0 }
        .joined(separator: "-")
    }
}

public struct ModelIQSnapshot: Decodable, Equatable {
    public let date: String?
    public let label: String?
    public let model: String?
    public let reasoningEffort: String?
    public let tasks: Int?
    public let validTasks: Int?
    public let passed: Int?
    public let failed: Int?
    public let passRate: Double?
    public let baselinePassRate: Double?
    public let iqScore: Double?
    public let status: String?
    public let wallSeconds: Int?
    public let wallTimeHuman: String?
    public let totalTokens: Int?
    public let inputTokens: Int?
    public let cachedInputTokens: Int?
    public let outputTokens: Int?
    public let costUSD: Double?

    public var cacheHitRateText: String {
        DisplayFormatters.cacheHitRate(
            cachedInputTokens: cachedInputTokens,
            inputTokens: inputTokens
        )
    }

    public var wallTimeText: String {
        wallTimeHuman ?? DisplayFormatters.minutesFromSeconds(wallSeconds)
    }

    enum CodingKeys: String, CodingKey {
        case date
        case label
        case model
        case reasoningEffort = "reasoning_effort"
        case tasks
        case validTasks = "valid_tasks"
        case passed
        case failed
        case passRate = "pass_rate"
        case baselinePassRate = "baseline_pass_rate"
        case iqScore = "iq_score"
        case score
        case status
        case wallSeconds = "wall_seconds"
        case wallTimeHuman = "wall_time_human"
        case totalTokens = "total_tokens"
        case inputTokens = "input_tokens"
        case cachedInputTokens = "cached_input_tokens"
        case outputTokens = "output_tokens"
        case costUSD = "cost_usd"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        date = try container.decodeIfPresent(String.self, forKey: .date)
        label = try container.decodeIfPresent(String.self, forKey: .label)
        model = try container.decodeIfPresent(String.self, forKey: .model)
        reasoningEffort = try container.decodeIfPresent(String.self, forKey: .reasoningEffort)
        tasks = try container.decodeIfPresent(Int.self, forKey: .tasks)
        validTasks = try container.decodeIfPresent(Int.self, forKey: .validTasks)
        passed = try container.decodeIfPresent(Int.self, forKey: .passed)
        failed = try container.decodeIfPresent(Int.self, forKey: .failed)
        passRate = try container.decodeIfPresent(Double.self, forKey: .passRate)
        baselinePassRate = try container.decodeIfPresent(Double.self, forKey: .baselinePassRate)
        iqScore = try container.decodeIfPresent(Double.self, forKey: .iqScore)
            ?? container.decodeIfPresent(Double.self, forKey: .score)
        status = try container.decodeIfPresent(String.self, forKey: .status)
        wallSeconds = try container.decodeIfPresent(Int.self, forKey: .wallSeconds)
        wallTimeHuman = try container.decodeIfPresent(String.self, forKey: .wallTimeHuman)
        totalTokens = try container.decodeIfPresent(Int.self, forKey: .totalTokens)
        inputTokens = try container.decodeIfPresent(Int.self, forKey: .inputTokens)
        cachedInputTokens = try container.decodeIfPresent(Int.self, forKey: .cachedInputTokens)
        outputTokens = try container.decodeIfPresent(Int.self, forKey: .outputTokens)
        costUSD = try container.decodeIfPresent(Double.self, forKey: .costUSD)
    }
}

public struct ModelRatingsEnvelope: Decodable, Equatable {
    public let ok: Bool?
    public let day: String?
    public let timezone: String?
    public let refreshSeconds: Int?
    public let updatedAt: String?
    public let models: [ModelRating]
    public let source: String?

    enum CodingKeys: String, CodingKey {
        case ok
        case day
        case timezone
        case refreshSeconds = "refresh_seconds"
        case updatedAt = "updated_at"
        case models
        case source
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        ok = try container.decodeIfPresent(Bool.self, forKey: .ok)
        day = try container.decodeIfPresent(String.self, forKey: .day)
        timezone = try container.decodeIfPresent(String.self, forKey: .timezone)
        refreshSeconds = try container.decodeIfPresent(Int.self, forKey: .refreshSeconds)
        updatedAt = try container.decodeIfPresent(String.self, forKey: .updatedAt)
        models = try container.decodeIfPresent([ModelRating].self, forKey: .models) ?? []
        source = try container.decodeIfPresent(String.self, forKey: .source)
    }

    public func rating(for snapshot: ModelIQSnapshot?) -> ModelRating? {
        guard let snapshot else {
            return models.first
        }
        let model = snapshot.model?.lowercased()
        let effort = snapshot.reasoningEffort?.lowercased()
        if let model, let effort {
            let expectedID = "\(model)-\(effort)"
            if let exact = models.first(where: { $0.id?.lowercased() == expectedID }) {
                return exact
            }
            if let exactLabel = models.first(where: { $0.label?.lowercased() == "\(model) \(effort)" }) {
                return exactLabel
            }
        }
        if let model,
           let grouped = models.first(where: { $0.group?.lowercased() == model || $0.label?.lowercased().hasPrefix(model) == true }) {
            return grouped
        }
        return models.first
    }
}

public struct ModelRating: Decodable, Equatable {
    public let id: String?
    public let label: String?
    public let group: String?
    public let average: Double?
    public let count: Int?

    enum CodingKeys: String, CodingKey {
        case id
        case label
        case group
        case average
        case count
    }
}
