import Foundation

public struct CodexRadarClient {
    public enum ClientError: LocalizedError {
        case invalidStatus(Int)
        case homepageFallbackUnavailable

        public var errorDescription: String? {
            switch self {
            case .invalidStatus(let statusCode):
                return "CodexRadar returned HTTP \(statusCode)"
            case .homepageFallbackUnavailable:
                return "CodexRadar homepage did not include a readable Model IQ signal"
            }
        }
    }

    private let baseURL: URL
    private let session: URLSession
    private let decoder: JSONDecoder

    public init(
        baseURL: URL = AppConstants.codexRadarBaseURL,
        session: URLSession = .shared
    ) {
        self.baseURL = baseURL
        self.session = session
        self.decoder = JSONDecoder()
    }

    public func fetchCurrent() async throws -> RadarCurrent {
        let data = try await fetchData(AppConstants.currentPath)
        do {
            return try decoder.decode(RadarCurrent.self, from: data)
        } catch {
            guard let html = String(data: data, encoding: .utf8),
                  html.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("<") else {
                throw error
            }
            return try Self.currentFromHomepageHTML(html)
        }
    }

    public func fetchModelRatings() async throws -> ModelRatingsEnvelope {
        try await fetchJSON(AppConstants.modelRatingsPath, as: ModelRatingsEnvelope.self)
    }

    private func fetchJSON<T: Decodable>(_ path: String, as type: T.Type) async throws -> T {
        let data = try await fetchData(path)
        return try decoder.decode(T.self, from: data)
    }

    private func fetchData(_ path: String) async throws -> Data {
        let url = baseURL.appending(path: path)
        let (data, response) = try await withTimeout(seconds: AppConstants.requestTimeoutSeconds) {
            try await session.data(from: url)
        }
        guard let httpResponse = response as? HTTPURLResponse else {
            return data
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw ClientError.invalidStatus(httpResponse.statusCode)
        }
        return data
    }

    private func withTimeout<T>(
        seconds: UInt64,
        operation: @escaping () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }
            group.addTask {
                try await Task.sleep(nanoseconds: seconds * 1_000_000_000)
                throw URLError(.timedOut)
            }
            guard let value = try await group.next() else {
                throw URLError(.timedOut)
            }
            group.cancelAll()
            return value
        }
    }

    static func currentFromHomepageHTML(_ html: String, checkedAt: Date = Date()) throws -> RadarCurrent {
        guard let modelIQ = parseHomepageModelIQ(html: html, checkedAt: checkedAt) else {
            throw ClientError.homepageFallbackUnavailable
        }
        let checkedAtString = isoString(checkedAt)
        let payload: [String: Any] = [
            "schema_version": "homepage-fallback-v1",
            "checked_at": checkedAtString,
            "status": "retired",
            "window_open": false,
            "recommended_action": "wait",
            "last_window": [
                "id": "codexradar-reset-radar-retired",
                "title": "CodexRadar 已转向模型质量雷达",
                "status": "retired",
                "window_human": "无窗",
                "scope": "CodexRadar 模型质量雷达",
                "summary": "CodexRadar 已下架 reset 预测、速蹬窗口提醒和历史窗口；当前聚焦 Model IQ 与社区体感分。"
            ],
            "prediction": [
                "level": "low",
                "probability_24h": 0,
                "probability_48h": 0,
                "should_notify": false,
                "summary": "CodexRadar 已下架 reset 预测和速蹬窗口提醒；当前只保留 Model IQ 相关信号。",
                "updated_at": checkedAtString
            ],
            "model_iq": [
                "updated_at": checkedAtString,
                "latest": modelIQ
            ]
        ]
        let data = try JSONSerialization.data(withJSONObject: payload)
        return try JSONDecoder().decode(RadarCurrent.self, from: data)
    }

    private static func parseHomepageModelIQ(html: String, checkedAt: Date) -> [String: Any]? {
        let pattern = #"<title>\s*(\d{1,2})月(\d{1,2})日\s+([^:]+):\s*IQ指数\s*([0-9]+(?:\.[0-9]+)?),\s*(\d+)/(\d+)(?:,\s*费用\s*\$([0-9]+(?:\.[0-9]+)?),\s*耗时\s*([0-9]+)分钟,\s*cache命中率\s*([0-9]+(?:\.[0-9]+)?)%)?"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }
        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        let matches = regex.matches(in: html, range: range)
        let year = Calendar(identifier: .gregorian).component(.year, from: checkedAt)
        let snapshots: [HomepageIQSnapshot] = matches.compactMap { match in
            guard match.numberOfRanges >= 7,
                  let month = Int(capture(match, 1, in: html)),
                  let day = Int(capture(match, 2, in: html)),
                  let score = Double(capture(match, 4, in: html)),
                  let passed = Int(capture(match, 5, in: html)),
                  let tasks = Int(capture(match, 6, in: html)) else {
                return nil
            }
            let cost = Double(capture(match, 7, in: html))
            let minutes = Int(capture(match, 8, in: html))
            let cacheHitRate = Double(capture(match, 9, in: html))
            let modelParts = capture(match, 3, in: html).split(separator: " ", omittingEmptySubsequences: true)
            let model = modelParts.first.map(String.init)
            let effort = modelParts.dropFirst().isEmpty ? nil : modelParts.dropFirst().joined(separator: " ")
            return HomepageIQSnapshot(
                month: month,
                day: day,
                model: model,
                reasoningEffort: effort,
                score: score,
                passed: passed,
                tasks: tasks,
                costUSD: cost,
                wallSeconds: minutes.map { $0 * 60 },
                cacheHitRate: cacheHitRate
            )
        }
        guard let latest = snapshots.max(by: { lhs, rhs in
            if lhs.month != rhs.month {
                return lhs.month < rhs.month
            }
            if lhs.day != rhs.day {
                return lhs.day < rhs.day
            }
            return lhs.modelPriority < rhs.modelPriority
        }) else {
            return nil
        }
        let failed = max(0, latest.tasks - latest.passed)
        var payload: [String: Any] = [
            "date": String(format: "%04d-%02d-%02d", year, latest.month, latest.day),
            "tasks": latest.tasks,
            "valid_tasks": latest.tasks,
            "passed": latest.passed,
            "failed": failed,
            "pass_rate": latest.tasks > 0 ? Double(latest.passed) / Double(latest.tasks) : 0,
            "iq_score": latest.score,
            "score": latest.score,
            "status": modelIQStatus(latest.score)
        ]
        if let wallSeconds = latest.wallSeconds {
            payload["wall_seconds"] = wallSeconds
            payload["wall_time_human"] = "\(wallSeconds / 60)分钟"
        }
        if let costUSD = latest.costUSD {
            payload["cost_usd"] = costUSD
        }
        if let cacheHitRate = latest.cacheHitRate {
            let inputTokens = 1_000_000
            payload["input_tokens"] = inputTokens
            payload["cached_input_tokens"] = Int(round(Double(inputTokens) * cacheHitRate / 100))
        }
        if let model = latest.model {
            payload["model"] = model
        }
        if let effort = latest.reasoningEffort {
            payload["reasoning_effort"] = effort
        }
        return payload
    }

    private static func capture(_ match: NSTextCheckingResult, _ index: Int, in text: String) -> String {
        guard let range = Range(match.range(at: index), in: text) else {
            return ""
        }
        return String(text[range])
    }

    private static func modelIQStatus(_ score: Double) -> String {
        if score < 80 {
            return "red"
        }
        if score < 95 {
            return "yellow"
        }
        return "green"
    }

    private static func isoString(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }
}

private struct HomepageIQSnapshot {
    let month: Int
    let day: Int
    let model: String?
    let reasoningEffort: String?
    let score: Double
    let passed: Int
    let tasks: Int
    let costUSD: Double?
    let wallSeconds: Int?
    let cacheHitRate: Double?

    var modelPriority: Int {
        if model?.contains("5.5") == true {
            return 2
        }
        if model?.contains("5") == true {
            return 1
        }
        return 0
    }
}
