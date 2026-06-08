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

    enum CodingKeys: String, CodingKey {
        case updatedAt = "updated_at"
        case latest
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
    }
}
