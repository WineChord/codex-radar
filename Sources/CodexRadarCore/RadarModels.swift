import Foundation

public struct RadarCurrent: Decodable, Equatable {
    public let schemaVersion: String?
    public let checkedAt: String?
    public let status: String?
    public let windowOpen: Bool
    public let recommendedAction: String?
    public let lastWindow: RadarWindow?
    public let prediction: RadarPredictionSummary?

    public var checkedDate: Date? {
        RadarDateParser.date(from: checkedAt)
    }

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case checkedAt = "checked_at"
        case status
        case windowOpen = "window_open"
        case recommendedAction = "recommended_action"
        case lastWindow = "last_window"
        case prediction
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
        case updatedAt = "updated_at"
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
    public let iqScore: Int?
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
        case status
        case wallSeconds = "wall_seconds"
    }
}
