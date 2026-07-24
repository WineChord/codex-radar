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
    public let resetJudgement: ResetJudgement?
    public let communityKnowledge: CommunityKnowledge?
    public let communityKnowledges: [CommunityKnowledge]
    public let siteAnnouncement: SiteAnnouncement?
    public let fastRadar: FastRadar?

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
        modelIQ: ModelIQEnvelope?,
        resetJudgement: ResetJudgement? = nil,
        communityKnowledge: CommunityKnowledge? = nil,
        communityKnowledges: [CommunityKnowledge] = [],
        siteAnnouncement: SiteAnnouncement? = nil,
        fastRadar: FastRadar? = nil
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
        self.resetJudgement = resetJudgement
        self.communityKnowledge = communityKnowledge
        self.communityKnowledges = communityKnowledges
        self.siteAnnouncement = siteAnnouncement
        self.fastRadar = fastRadar
    }

    public func withModelIQ(_ modelIQ: ModelIQEnvelope?) -> RadarCurrent {
        withSignals(modelIQ: modelIQ)
    }

    public func withSignals(
        modelIQ: ModelIQEnvelope? = nil,
        resetJudgement: ResetJudgement? = nil,
        communityKnowledge: CommunityKnowledge? = nil,
        communityKnowledges: [CommunityKnowledge]? = nil,
        siteAnnouncement: SiteAnnouncement? = nil,
        fastRadar: FastRadar? = nil
    ) -> RadarCurrent {
        RadarCurrent(
            schemaVersion: schemaVersion,
            checkedAt: checkedAt,
            status: status,
            windowOpen: windowOpen,
            recommendedAction: recommendedAction,
            lastWindow: lastWindow,
            prediction: prediction,
            predictionDetail: predictionDetail,
            modelIQ: modelIQ ?? self.modelIQ,
            resetJudgement: resetJudgement ?? self.resetJudgement,
            communityKnowledge: communityKnowledge ?? self.communityKnowledge,
            communityKnowledges: communityKnowledges ?? self.communityKnowledges,
            siteAnnouncement: siteAnnouncement ?? self.siteAnnouncement,
            fastRadar: fastRadar ?? self.fastRadar
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
        case resetJudgement = "reset_judgement"
        case communityKnowledge = "community_knowledge"
        case communityKnowledges = "community_knowledges"
        case siteAnnouncement = "site_announcement"
        case fastRadar = "fast_radar"
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
        resetJudgement = try container.decodeIfPresent(ResetJudgement.self, forKey: .resetJudgement)
        let decodedCommunityKnowledge = try container.decodeIfPresent(CommunityKnowledge.self, forKey: .communityKnowledge)
        communityKnowledge = decodedCommunityKnowledge
        communityKnowledges = try container.decodeIfPresent([CommunityKnowledge].self, forKey: .communityKnowledges)
            ?? decodedCommunityKnowledge.map { [$0] }
            ?? []
        siteAnnouncement = try container.decodeIfPresent(SiteAnnouncement.self, forKey: .siteAnnouncement)
        fastRadar = try container.decodeIfPresent(FastRadar.self, forKey: .fastRadar)
    }
}

public struct SiteAnnouncement: Decodable, Equatable {
    public let label: String?
    public let message: String?
    public let updatedLabel: String?
    public let sourceLabel: String?
    public let sourceURL: String?

    enum CodingKeys: String, CodingKey {
        case label
        case message
        case updatedLabel = "updated_label"
        case sourceLabel = "source_label"
        case sourceURL = "source_url"
    }
}

public struct ResetJudgement: Decodable, Equatable {
    public let updatedLabel: String?
    public let title: String?
    public let cards: [ResetJudgementCard]
    public let reasons: [String]

    enum CodingKeys: String, CodingKey {
        case updatedLabel = "updated_label"
        case title
        case cards
        case reasons
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        updatedLabel = try container.decodeIfPresent(String.self, forKey: .updatedLabel)
        title = try container.decodeIfPresent(String.self, forKey: .title)
        cards = try container.decodeIfPresent([ResetJudgementCard].self, forKey: .cards) ?? []
        reasons = try container.decodeIfPresent([String].self, forKey: .reasons) ?? []
    }
}

public struct ResetJudgementCard: Decodable, Equatable, Identifiable {
    public let label: String?
    public let level: String?
    public let summary: String?

    public var id: String {
        label ?? "\(level ?? "")-\(summary ?? "")"
    }
}

public struct CommunityKnowledge: Decodable, Equatable {
    public let title: String?
    public let prompt: String?

    enum CodingKeys: String, CodingKey {
        case title
        case prompt
    }
}

public struct FastRadar: Decodable, Equatable {
    public let title: String?
    public let updatedLabel: String?
    public let subtitle: String?
    public let summary: [FastRadarSummaryItem]
    public let rows: [FastRadarRow]
    public let method: String?

    enum CodingKeys: String, CodingKey {
        case title
        case updatedLabel = "updated_label"
        case subtitle
        case summary
        case rows
        case method
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        title = try container.decodeIfPresent(String.self, forKey: .title)
        updatedLabel = try container.decodeIfPresent(String.self, forKey: .updatedLabel)
        subtitle = try container.decodeIfPresent(String.self, forKey: .subtitle)
        summary = try container.decodeIfPresent([FastRadarSummaryItem].self, forKey: .summary) ?? []
        rows = try container.decodeIfPresent([FastRadarRow].self, forKey: .rows) ?? []
        method = try container.decodeIfPresent(String.self, forKey: .method)
    }
}

public struct FastRadarSummaryItem: Decodable, Equatable, Identifiable {
    public let label: String?
    public let value: String?

    public var id: String {
        "\(label ?? "")-\(value ?? "")"
    }
}

public struct FastRadarRow: Decodable, Equatable, Identifiable {
    public let model: String?
    public let e2e: FastRadarMetric?
    public let ttft: FastRadarMetric?
    public let tps: FastRadarMetric?

    public var id: String {
        model ?? "\(e2e?.value ?? "")-\(ttft?.value ?? "")-\(tps?.value ?? "")"
    }
}

public struct FastRadarMetric: Decodable, Equatable {
    public let label: String?
    public let range: String?
    public let value: String?
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

public struct IntelligenceEfficiencyEnvelope: Decodable, Equatable {
    public let schema: Int?
    public let type: String?
    public let sourceUpdatedAt: String?
    public let points: [IntelligenceEfficiencyPoint]

    enum CodingKeys: String, CodingKey {
        case schema
        case type
        case sourceUpdatedAt = "source_updated_at"
        case points
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schema = try container.decodeIfPresent(Int.self, forKey: .schema)
        type = try container.decodeIfPresent(String.self, forKey: .type)
        sourceUpdatedAt = try container.decodeIfPresent(String.self, forKey: .sourceUpdatedAt)
        points = try container.decodeIfPresent([IntelligenceEfficiencyPoint].self, forKey: .points) ?? []
    }

    fileprivate var usablePoints: [IntelligenceEfficiencyPoint] {
        points.filter(\.isUsable)
    }
}

public struct IntelligenceEfficiencyPoint: Decodable, Equatable {
    public let model: String?
    public let effort: String?
    public let iq: Double?
    public let passed: Int?
    public let validTasks: Int?
    public let averagePriceUSD: Double?
    public let averageMinutes: Double?
    public let latestGradedAt: String?
    public let cacheHitRate: Double?

    enum CodingKeys: String, CodingKey {
        case model
        case effort
        case iq
        case passed
        case validTasks = "valid_tasks"
        case averagePriceUSD = "average_price_usd"
        case averageMinutes = "average_minutes"
        case latestGradedAt = "latest_graded_at"
        case cacheHitRate = "cache_hit_rate"
    }

    fileprivate var pairKey: String? {
        guard let model = model?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              !model.isEmpty,
              let effort = effort?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              !effort.isEmpty else {
            return nil
        }
        return "\(model)/\(effort)"
    }

    fileprivate var isUsable: Bool {
        guard pairKey != nil,
              let iq,
              iq.isFinite,
              let validTasks,
              validTasks > 0,
              let passed,
              (0...validTasks).contains(passed) else {
            return false
        }
        if let averagePriceUSD, (!averagePriceUSD.isFinite || averagePriceUSD < 0) {
            return false
        }
        if let averageMinutes, (!averageMinutes.isFinite || averageMinutes < 0) {
            return false
        }
        return true
    }
}

public struct ModelIQEnvelope: Decodable, Equatable {
    public let updatedAt: String?
    public let latest: ModelIQSnapshot?
    public let comparisons: [String: ModelIQComparison]
    public let quotaRadar: QuotaRadar?
    public let dataSource: ModelIQDataSource?

    init(
        updatedAt: String?,
        latest: ModelIQSnapshot?,
        comparisons: [String: ModelIQComparison],
        quotaRadar: QuotaRadar?,
        dataSource: ModelIQDataSource?
    ) {
        self.updatedAt = updatedAt
        self.latest = latest
        self.comparisons = comparisons
        self.quotaRadar = quotaRadar
        self.dataSource = dataSource
    }

    init?(intelligenceEfficiency: IntelligenceEfficiencyEnvelope) {
        let points = intelligenceEfficiency.usablePoints
        guard let primary = Self.preferredPrimaryPoint(in: points) else {
            return nil
        }
        let latest = ModelIQSnapshot(
            intelligenceEfficiencyPoint: primary,
            sourceUpdatedAt: intelligenceEfficiency.sourceUpdatedAt
        )
        var comparisons = [String: ModelIQComparison]()
        for point in points where point.pairKey != primary.pairKey {
            let snapshot = ModelIQSnapshot(
                intelligenceEfficiencyPoint: point,
                sourceUpdatedAt: intelligenceEfficiency.sourceUpdatedAt
            )
            comparisons[Self.comparisonKey(for: point)] = ModelIQComparison(
                label: Self.modelLabel(snapshot),
                model: point.model,
                reasoningEffort: point.effort,
                latest: snapshot,
                recentDays: []
            )
        }
        let validCells = Self.validCellCount(
            latest: latest,
            comparisons: comparisons
        )
        self.init(
            updatedAt: intelligenceEfficiency.sourceUpdatedAt,
            latest: latest,
            comparisons: comparisons,
            quotaRadar: nil,
            dataSource: ModelIQDataSource(
                type: "distributed_community_runs",
                url: "https://deng.codexradar.com",
                checkedAt: intelligenceEfficiency.sourceUpdatedAt,
                validCells: validCells
            )
        )
    }

    func merging(intelligenceEfficiency: IntelligenceEfficiencyEnvelope) -> ModelIQEnvelope {
        let points = intelligenceEfficiency.usablePoints
        guard !points.isEmpty else {
            return self
        }

        var mergedComparisons = comparisons
        var existingComparisonKeys = [String: String]()
        for (key, comparison) in comparisons {
            if let pairKey = Self.pairKey(
                model: comparison.model ?? comparison.latest?.model,
                effort: comparison.reasoningEffort ?? comparison.latest?.reasoningEffort
            ) {
                existingComparisonKeys[pairKey] = key
            }
        }

        let existingPrimaryKey = Self.pairKey(model: latest?.model, effort: latest?.reasoningEffort)
        let primaryPoint = existingPrimaryKey.flatMap { key in
            points.first { $0.pairKey == key }
        }
        let mergedLatest: ModelIQSnapshot?
        let mergedPrimaryKey: String?
        if let primaryPoint {
            mergedLatest = ModelIQSnapshot(
                intelligenceEfficiencyPoint: primaryPoint,
                sourceUpdatedAt: intelligenceEfficiency.sourceUpdatedAt,
                preserving: latest
            )
            mergedPrimaryKey = primaryPoint.pairKey
        } else if let latest {
            mergedLatest = latest
            mergedPrimaryKey = existingPrimaryKey
        } else if let fallbackPrimary = Self.preferredPrimaryPoint(in: points) {
            mergedLatest = ModelIQSnapshot(
                intelligenceEfficiencyPoint: fallbackPrimary,
                sourceUpdatedAt: intelligenceEfficiency.sourceUpdatedAt
            )
            mergedPrimaryKey = fallbackPrimary.pairKey
        } else {
            mergedLatest = nil
            mergedPrimaryKey = nil
        }

        if let mergedPrimaryKey,
           let duplicateKey = existingComparisonKeys[mergedPrimaryKey] {
            mergedComparisons.removeValue(forKey: duplicateKey)
        }

        for point in points where point.pairKey != mergedPrimaryKey {
            guard let pairKey = point.pairKey else {
                continue
            }
            if let existingKey = existingComparisonKeys[pairKey],
               let existing = comparisons[existingKey] {
                mergedComparisons[existingKey] = existing.merging(
                    intelligenceEfficiencyPoint: point,
                    sourceUpdatedAt: intelligenceEfficiency.sourceUpdatedAt
                )
            } else {
                let snapshot = ModelIQSnapshot(
                    intelligenceEfficiencyPoint: point,
                    sourceUpdatedAt: intelligenceEfficiency.sourceUpdatedAt
                )
                mergedComparisons[Self.comparisonKey(for: point)] = ModelIQComparison(
                    label: Self.modelLabel(snapshot),
                    model: point.model,
                    reasoningEffort: point.effort,
                    latest: snapshot,
                    recentDays: []
                )
            }
        }

        let validCells = Self.validCellCount(
            latest: mergedLatest,
            comparisons: mergedComparisons
        )
        let mergedDataSource = ModelIQDataSource(
            type: dataSource?.type ?? "distributed_community_runs",
            url: dataSource?.url ?? "https://deng.codexradar.com",
            checkedAt: intelligenceEfficiency.sourceUpdatedAt
                ?? dataSource?.checkedAt,
            validCells: validCells ?? dataSource?.validCells
        )

        return ModelIQEnvelope(
            updatedAt: intelligenceEfficiency.sourceUpdatedAt ?? updatedAt,
            latest: mergedLatest,
            comparisons: mergedComparisons,
            quotaRadar: quotaRadar,
            dataSource: mergedDataSource
        )
    }

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
        case dataSource = "data_source"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        updatedAt = try container.decodeIfPresent(String.self, forKey: .updatedAt)
        latest = try container.decodeIfPresent(ModelIQSnapshot.self, forKey: .latest)
        comparisons = try container.decodeIfPresent([String: ModelIQComparison].self, forKey: .comparisons) ?? [:]
        quotaRadar = try container.decodeIfPresent(QuotaRadar.self, forKey: .quotaRadar)
        dataSource = try container.decodeIfPresent(ModelIQDataSource.self, forKey: .dataSource)
    }

    private static func sortComparisons(_ lhs: ModelIQComparison, _ rhs: ModelIQComparison) -> Bool {
        if lhs.modelVersionRank != rhs.modelVersionRank {
            return lhs.modelVersionRank > rhs.modelVersionRank
        }
        if lhs.modelFamilyRank != rhs.modelFamilyRank {
            return lhs.modelFamilyRank < rhs.modelFamilyRank
        }
        if lhs.effortRank != rhs.effortRank {
            return lhs.effortRank < rhs.effortRank
        }
        return (lhs.label ?? "") < (rhs.label ?? "")
    }

    private static func validCellCount(
        latest: ModelIQSnapshot?,
        comparisons: [String: ModelIQComparison]
    ) -> Int? {
        let snapshots = [latest].compactMap { $0 }
            + comparisons.values.compactMap(\.latest)
        guard !snapshots.isEmpty else {
            return nil
        }
        var total = 0
        for snapshot in snapshots {
            guard let count = snapshot.validTasks ?? snapshot.tasks,
                  count > 0 else {
                return nil
            }
            let result = total.addingReportingOverflow(count)
            guard !result.overflow else {
                return nil
            }
            total = result.partialValue
        }
        return total
    }

    private static func modelLabel(_ snapshot: ModelIQSnapshot) -> String? {
        guard let model = snapshot.model else {
            return snapshot.label ?? snapshot.reasoningEffort
        }
        let modelParts = model.split(separator: "-").map(String.init)
        let families = Set(["sol", "terra", "luna"])
        let prefix: String
        if modelParts.count >= 3,
           modelParts[0].lowercased() == "gpt",
           let family = modelParts.last?.lowercased(),
           families.contains(family) {
            let version = modelParts.dropLast().joined(separator: "-").uppercased()
            prefix = "\(version) \(family.prefix(1).uppercased())\(family.dropFirst())"
        } else {
            prefix = model.uppercased().hasPrefix("GPT-") ? model.uppercased() : model
        }
        guard let effort = snapshot.reasoningEffort else {
            return prefix
        }
        return "\(prefix) \(effort)"
    }

    private static func preferredPrimaryPoint(
        in points: [IntelligenceEfficiencyPoint]
    ) -> IntelligenceEfficiencyPoint? {
        points.first { $0.pairKey == "gpt-5.6-sol/max" }
            ?? points.max { ($0.iq ?? -.infinity) < ($1.iq ?? -.infinity) }
    }

    private static func pairKey(model: String?, effort: String?) -> String? {
        guard let model = model?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              !model.isEmpty,
              let effort = effort?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              !effort.isEmpty else {
            return nil
        }
        return "\(model)/\(effort)"
    }

    private static func comparisonKey(for point: IntelligenceEfficiencyPoint) -> String {
        (point.pairKey ?? "intelligence-efficiency")
            .replacingOccurrences(of: ".", with: "_")
            .replacingOccurrences(of: "-", with: "_")
            .replacingOccurrences(of: "/", with: "_")
    }
}

public struct ModelIQDataSource: Decodable, Equatable {
    public let type: String?
    public let url: String?
    public let checkedAt: String?
    public let validCells: Int?

    init(type: String?, url: String?, checkedAt: String?, validCells: Int?) {
        self.type = type
        self.url = url
        self.checkedAt = checkedAt
        self.validCells = validCells
    }

    public var isDistributedCommunityRuns: Bool {
        type == "distributed_community_runs"
    }

    public var linkURL: URL? {
        url.flatMap(URL.init(string:))
    }

    enum CodingKeys: String, CodingKey {
        case type
        case url
        case checkedAt = "checked_at"
        case validCells = "valid_cells"
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

    public var showsFiveHourValues: Bool {
        if let basisWindowLabel {
            return basisWindowLabel.lowercased().contains("5h")
        }
        return rows.contains { $0.fiveHourUSD != nil }
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

    init(
        label: String?,
        model: String?,
        reasoningEffort: String?,
        latest: ModelIQSnapshot?,
        recentDays: [ModelIQSnapshot]
    ) {
        self.label = label
        self.model = model
        self.reasoningEffort = reasoningEffort
        self.latest = latest
        self.recentDays = recentDays
    }

    fileprivate func merging(
        intelligenceEfficiencyPoint point: IntelligenceEfficiencyPoint,
        sourceUpdatedAt: String?
    ) -> ModelIQComparison {
        ModelIQComparison(
            label: label,
            model: point.model ?? model,
            reasoningEffort: point.effort ?? reasoningEffort,
            latest: ModelIQSnapshot(
                intelligenceEfficiencyPoint: point,
                sourceUpdatedAt: sourceUpdatedAt,
                preserving: latest
            ),
            recentDays: recentDays
        )
    }

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

    fileprivate var modelFamilyRank: Int {
        let source = (model ?? latest?.model ?? label ?? "").lowercased()
        if source.contains("sol") {
            return 0
        }
        if source.contains("terra") {
            return 1
        }
        if source.contains("luna") {
            return 2
        }
        return 9
    }

    fileprivate var effortRank: Int {
        let effort = (reasoningEffort ?? latest?.reasoningEffort ?? label ?? "").lowercased()
        if effort.contains("ultra") {
            return 0
        }
        if effort.contains("max") {
            return 1
        }
        if effort.contains("xhigh") {
            return 2
        }
        if effort.contains("high") {
            return 3
        }
        if effort.contains("medium") {
            return 4
        }
        if effort.contains("low") {
            return 5
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
    public let cacheHitRate: Double?
    public let outputTokens: Int?
    public let costUSD: Double?
    public let costUSDBasis: String?
    public let averageCostUSD: Double?
    public let averageTaskSeconds: Double?
    public let averageTaskTimeHuman: String?

    fileprivate init(
        intelligenceEfficiencyPoint point: IntelligenceEfficiencyPoint,
        sourceUpdatedAt: String?,
        preserving existing: ModelIQSnapshot? = nil
    ) {
        let validTasks = point.validTasks ?? existing?.validTasks ?? existing?.tasks
        let passed = point.passed ?? existing?.passed
        let score = point.iq ?? existing?.iqScore
        date = point.latestGradedAt ?? sourceUpdatedAt ?? existing?.date
        label = existing?.label
        model = point.model ?? existing?.model
        reasoningEffort = point.effort ?? existing?.reasoningEffort
        tasks = validTasks
        self.validTasks = validTasks
        self.passed = passed
        if let validTasks, let passed {
            failed = max(0, validTasks - passed)
            passRate = validTasks > 0 ? Double(passed) / Double(validTasks) : nil
        } else {
            failed = existing?.failed
            passRate = existing?.passRate
        }
        baselinePassRate = existing?.baselinePassRate
        iqScore = score
        if let score {
            if score < 80 {
                status = "red"
            } else if score < 95 {
                status = "yellow"
            } else {
                status = "green"
            }
        } else {
            status = existing?.status
        }
        wallSeconds = existing?.wallSeconds
        wallTimeHuman = existing?.wallTimeHuman
        totalTokens = existing?.totalTokens
        inputTokens = existing?.inputTokens
        cachedInputTokens = existing?.cachedInputTokens
        cacheHitRate = point.cacheHitRate ?? existing?.cacheHitRate
        outputTokens = existing?.outputTokens
        costUSD = existing?.costUSD
        costUSDBasis = existing?.costUSDBasis ?? "per_task_average"
        averageCostUSD = point.averagePriceUSD ?? existing?.averageCostUSD
        averageTaskSeconds = point.averageMinutes.map { $0 * 60 } ?? existing?.averageTaskSeconds
        if let averageMinutes = point.averageMinutes {
            averageTaskTimeHuman = "\(max(1, Int(round(averageMinutes))))分钟"
        } else {
            averageTaskTimeHuman = existing?.averageTaskTimeHuman
        }
    }

    public var displayedCostUSD: Double? {
        averageCostUSD ?? costUSD
    }

    public var usesPerTaskAverages: Bool {
        averageCostUSD != nil || averageTaskSeconds != nil || averageTaskTimeHuman != nil
    }

    public var cacheHitRateText: String {
        if let cacheHitRate {
            return String(format: "%.1f%%", cacheHitRate)
        }
        return DisplayFormatters.cacheHitRate(
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
        case cacheHitRate = "cache_hit_rate"
        case outputTokens = "output_tokens"
        case costUSD = "cost_usd"
        case costUSDBasis = "cost_usd_basis"
        case averageCostUSD = "average_cost_usd"
        case averageTaskSeconds = "average_task_seconds"
        case averageTaskTimeHuman = "average_task_time_human"
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
        cacheHitRate = try container.decodeIfPresent(Double.self, forKey: .cacheHitRate)
        outputTokens = try container.decodeIfPresent(Int.self, forKey: .outputTokens)
        costUSD = try container.decodeIfPresent(Double.self, forKey: .costUSD)
        costUSDBasis = try container.decodeIfPresent(String.self, forKey: .costUSDBasis)
        averageCostUSD = try container.decodeIfPresent(Double.self, forKey: .averageCostUSD)
        averageTaskSeconds = try container.decodeIfPresent(Double.self, forKey: .averageTaskSeconds)
        averageTaskTimeHuman = try container.decodeIfPresent(String.self, forKey: .averageTaskTimeHuman)
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
            return nil
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
            return nil
        }
        if let model,
           let grouped = models.first(where: { $0.group?.lowercased() == model || $0.label?.lowercased().hasPrefix(model) == true }) {
            return grouped
        }
        return nil
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
