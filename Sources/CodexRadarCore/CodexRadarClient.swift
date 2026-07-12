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
            let current = try decoder.decode(RadarCurrent.self, from: data)
            guard current.modelIQ?.latest?.iqScore == nil || current.resetJudgement == nil || current.communityKnowledge == nil || current.siteAnnouncement == nil,
                  let homepageHTML = try? await fetchHomepageHTML(),
                  let supplemented = try? Self.currentByMergingHomepageSignals(current, html: homepageHTML) else {
                return current
            }
            return supplemented
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
        let url = path.isEmpty ? baseURL : baseURL.appending(path: path)
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

    private func fetchHomepageHTML() async throws -> String {
        let data = try await fetchData("")
        guard let html = String(data: data, encoding: .utf8) else {
            throw ClientError.homepageFallbackUnavailable
        }
        return html
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
        guard let modelIQ = parseHomepageModelIQEnvelope(html: html, checkedAt: checkedAt) else {
            throw ClientError.homepageFallbackUnavailable
        }
        let resetJudgement = parseHomepageResetJudgement(html: html)
        let communityKnowledges = parseHomepageCommunityKnowledges(html: html)
        let communityKnowledge = communityKnowledges.first
        let siteAnnouncement = parseHomepageSiteAnnouncement(html: html)
        let checkedAtString = isoString(checkedAt)
        var payload: [String: Any] = [
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
                "latest": modelIQ["latest"] ?? [:],
                "comparisons": modelIQ["comparisons"] ?? [:]
            ]
        ]
        if let resetJudgement {
            payload["reset_judgement"] = resetJudgement
        }
        if let communityKnowledge {
            payload["community_knowledge"] = communityKnowledge
        }
        if !communityKnowledges.isEmpty {
            payload["community_knowledges"] = communityKnowledges
        }
        if let siteAnnouncement {
            payload["site_announcement"] = siteAnnouncement
        }
        let data = try JSONSerialization.data(withJSONObject: payload)
        return try JSONDecoder().decode(RadarCurrent.self, from: data)
    }

    static func currentByMergingHomepageModelIQ(
        _ current: RadarCurrent,
        html: String,
        checkedAt: Date = Date()
    ) throws -> RadarCurrent {
        guard let modelIQ = parseHomepageModelIQEnvelope(html: html, checkedAt: checkedAt) else {
            throw ClientError.homepageFallbackUnavailable
        }
        let data = try JSONSerialization.data(withJSONObject: modelIQ)
        let envelope = try JSONDecoder().decode(ModelIQEnvelope.self, from: data)
        return current.withModelIQ(envelope)
    }

    static func currentByMergingHomepageSignals(
        _ current: RadarCurrent,
        html: String,
        checkedAt: Date = Date()
    ) throws -> RadarCurrent {
        var modelIQEnvelope: ModelIQEnvelope?
        if current.modelIQ?.latest?.iqScore == nil,
           let modelIQ = parseHomepageModelIQEnvelope(html: html, checkedAt: checkedAt) {
            let data = try JSONSerialization.data(withJSONObject: modelIQ)
            modelIQEnvelope = try JSONDecoder().decode(ModelIQEnvelope.self, from: data)
        }
        let resetJudgementData = parseHomepageResetJudgement(html: html)
        let communityKnowledgesData = parseHomepageCommunityKnowledges(html: html)
        let communityKnowledgeData = communityKnowledgesData.first
        let siteAnnouncementData = parseHomepageSiteAnnouncement(html: html)
        let resetJudgement: ResetJudgement?
        if let resetJudgementData {
            let data = try JSONSerialization.data(withJSONObject: resetJudgementData)
            resetJudgement = try JSONDecoder().decode(ResetJudgement.self, from: data)
        } else {
            resetJudgement = nil
        }
        let communityKnowledge: CommunityKnowledge?
        if let communityKnowledgeData {
            let data = try JSONSerialization.data(withJSONObject: communityKnowledgeData)
            communityKnowledge = try JSONDecoder().decode(CommunityKnowledge.self, from: data)
        } else {
            communityKnowledge = nil
        }
        let communityKnowledges: [CommunityKnowledge]
        if !communityKnowledgesData.isEmpty {
            let data = try JSONSerialization.data(withJSONObject: communityKnowledgesData)
            communityKnowledges = try JSONDecoder().decode([CommunityKnowledge].self, from: data)
        } else {
            communityKnowledges = []
        }
        let siteAnnouncement: SiteAnnouncement?
        if let siteAnnouncementData {
            let data = try JSONSerialization.data(withJSONObject: siteAnnouncementData)
            siteAnnouncement = try JSONDecoder().decode(SiteAnnouncement.self, from: data)
        } else {
            siteAnnouncement = nil
        }
        return current.withSignals(
            modelIQ: modelIQEnvelope,
            resetJudgement: resetJudgement,
            communityKnowledge: communityKnowledge,
            communityKnowledges: communityKnowledges.isEmpty ? nil : communityKnowledges,
            siteAnnouncement: siteAnnouncement
        )
    }

    private static func parseHomepageModelIQEnvelope(html: String, checkedAt: Date) -> [String: Any]? {
        let pattern = #"<title>\s*(?:(\d{1,2})月(\d{1,2})日|(\d{1,2})\.(\d{1,2})(?:[_-]([A-Za-z]+))?)\s+([^:]+):\s*IQ指数\s*([0-9]+(?:\.[0-9]+)?),\s*(\d+)/(\d+)(?:,\s*费用\s*\$([0-9]+(?:\.[0-9]+)?),\s*耗时\s*([0-9]+)分钟,\s*cache命中率\s*([0-9]+(?:\.[0-9]+)?)%)?"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }
        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        let matches = regex.matches(in: html, range: range)
        let year = Calendar(identifier: .gregorian).component(.year, from: checkedAt)
        let snapshots: [HomepageIQSnapshot] = matches.compactMap { match in
            let monthText = capture(match, 1, in: html).isEmpty ? capture(match, 3, in: html) : capture(match, 1, in: html)
            let dayText = capture(match, 2, in: html).isEmpty ? capture(match, 4, in: html) : capture(match, 2, in: html)
            guard match.numberOfRanges >= 10,
                  let month = Int(monthText),
                  let day = Int(dayText),
                  let score = Double(capture(match, 7, in: html)),
                  let passed = Int(capture(match, 8, in: html)),
                  let tasks = Int(capture(match, 9, in: html)) else {
                return nil
            }
            let cost = Double(capture(match, 10, in: html))
            let minutes = Int(capture(match, 11, in: html))
            let cacheHitRate = Double(capture(match, 12, in: html))
            let modelParts = capture(match, 6, in: html).split(separator: " ", omittingEmptySubsequences: true)
            let model = modelParts.first.map(String.init)
            let effort = modelParts.dropFirst().isEmpty ? nil : modelParts.dropFirst().joined(separator: " ")
            return HomepageIQSnapshot(
                month: month,
                day: day,
                phase: capture(match, 5, in: html).lowercased(),
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
            lhs.sortKey < rhs.sortKey
        }) else {
            return nil
        }
        let latestByModel = Dictionary(grouping: snapshots, by: \.modelKey)
            .compactMapValues { snapshots in
                snapshots.max { $0.sortKey < $1.sortKey }
            }
        let comparisons = latestByModel
            .filter { $0.key != latest.modelKey }
            .reduce(into: [String: Any]()) { result, item in
                result[item.key] = item.value.comparisonPayload(year: year)
            }
        return [
            "updated_at": isoString(checkedAt),
            "latest": latest.snapshotPayload(year: year),
            "comparisons": comparisons
        ]
    }

    private static func parseHomepageResetJudgement(html: String) -> [String: Any]? {
        guard let section = firstCapture(
            #"<section\s+class="reset-judgement"[^>]*>(.*?)</section>"#,
            in: html
        ) else {
            return nil
        }
        let title = firstCapture(#"<div\s+class="reset-judgement-head">.*?<strong>(.*?)</strong>"#, in: section)
        let updatedLabel = firstCapture(#"<h2>.*?<em>(.*?)</em>.*?</h2>"#, in: section)
        let cards = allMatches(
            #"<article\s+class="reset-judgement-card[^"]*">\s*<span>(.*?)</span>\s*<strong>(.*?)</strong>\s*<p>(.*?)</p>"#,
            in: section
        ).map { groups in
            [
                "label": cleanHTMLText(groups[safe: 0]),
                "level": cleanHTMLText(groups[safe: 1]),
                "summary": cleanHTMLText(groups[safe: 2])
            ]
        }
        guard !cards.isEmpty else {
            return nil
        }
        let reasons = allMatches(#"<li>(.*?)</li>"#, in: section)
            .compactMap { groups in cleanHTMLText(groups.first) }
            .filter { !$0.isEmpty }
        return [
            "updated_label": cleanHTMLText(updatedLabel),
            "title": cleanHTMLText(title),
            "cards": cards,
            "reasons": reasons
        ]
    }

    private static func parseHomepageCommunityKnowledge(html: String) -> [String: Any]? {
        parseHomepageCommunityKnowledges(html: html).first
    }

    private static func parseHomepageCommunityKnowledges(html: String) -> [[String: Any]] {
        guard let section = firstCapture(
            #"<section\s+class="community-knowledge"[^>]*>(.*?)</section>"#,
            in: html
        ) else {
            return []
        }

        return allMatches(
            #"<article\s+class="[^"]*community-knowledge-card[^"]*"[^>]*>(.*?)</article>"#,
            in: section
        ).compactMap { groups in
            guard let card = groups.first else {
                return nil
            }
            let title = cleanHTMLText(firstCapture(#"<h2>(.*?)</h2>"#, in: card))
            let prompt = cleanHTMLMultilineText(firstCapture(
                #"<(?:code|div)[^>]*data-site-announcement-prompt[^>]*>(.*?)</(?:code|div)>"#,
                in: card
            ))
            guard !title.isEmpty, !prompt.isEmpty else {
                return nil
            }
            return [
                "title": title,
                "prompt": prompt
            ]
        }
    }

    private static func parseHomepageSiteAnnouncement(html: String) -> [String: Any]? {
        guard let section = firstCapture(
            #"<section\s+class="site-announcement"[^>]*>(.*?)</section>"#,
            in: html
        ),
        let paragraph = firstCapture(#"<p>(.*?)</p>"#, in: section) else {
            return nil
        }

        let label = cleanHTMLText(firstCapture(#"<span>(.*?)</span>"#, in: section))
        let updatedLabel = cleanHTMLText(firstCapture(#"<span\s+class="site-announcement-updated"[^>]*>(.*?)</span>"#, in: paragraph))
        let source = allMatches(
            #"<a\s+class="site-announcement-source"\s+href="([^"]+)"[^>]*>(.*?)</a>"#,
            in: paragraph
        ).first
        var messageHTML = paragraph
        messageHTML = messageHTML.replacingOccurrences(
            of: #"<a\s+class="site-announcement-source"[^>]*>.*?</a>"#,
            with: "",
            options: .regularExpression
        )
        messageHTML = messageHTML.replacingOccurrences(
            of: #"<br\s*/?>\s*<span\s+class="site-announcement-updated"[^>]*>.*?</span>"#,
            with: "",
            options: .regularExpression
        )
        let message = cleanHTMLText(messageHTML)
        guard !message.isEmpty else {
            return nil
        }

        var payload: [String: Any] = [
            "label": label.isEmpty ? "公告" : label,
            "message": message
        ]
        if !updatedLabel.isEmpty {
            payload["updated_label"] = updatedLabel
        }
        if let source, source.count >= 2 {
            let sourceURL = cleanHTMLText(source[0])
            let sourceLabel = cleanHTMLText(source[1])
            if !sourceURL.isEmpty {
                payload["source_url"] = sourceURL
            }
            if !sourceLabel.isEmpty {
                payload["source_label"] = sourceLabel
            }
        }
        return payload
    }

    fileprivate static func modelIQStatus(_ score: Double) -> String {
        if score < 80 {
            return "red"
        }
        if score < 95 {
            return "yellow"
        }
        return "green"
    }

    private static func capture(_ match: NSTextCheckingResult, _ index: Int, in text: String) -> String {
        guard let range = Range(match.range(at: index), in: text) else {
            return ""
        }
        return String(text[range])
    }

    private static func firstCapture(_ pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else {
            return nil
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              match.numberOfRanges > 1,
              let captureRange = Range(match.range(at: 1), in: text) else {
            return nil
        }
        return String(text[captureRange])
    }

    private static func allMatches(_ pattern: String, in text: String) -> [[String]] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else {
            return []
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, range: range).map { match in
            (1..<match.numberOfRanges).map { index in
                guard let captureRange = Range(match.range(at: index), in: text) else {
                    return ""
                }
                return String(text[captureRange])
            }
        }
    }

    private static func cleanHTMLText(_ value: String?) -> String {
        guard var value else {
            return ""
        }
        value = value.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        let entities = [
            "&amp;": "&",
            "&lt;": "<",
            "&gt;": ">",
            "&quot;": "\"",
            "&#39;": "'",
            "&nbsp;": " "
        ]
        for (entity, replacement) in entities {
            value = value.replacingOccurrences(of: entity, with: replacement)
        }
        return value
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func cleanHTMLMultilineText(_ value: String?) -> String {
        guard var value else {
            return ""
        }
        value = value.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        let entities = [
            "&amp;": "&",
            "&lt;": "<",
            "&gt;": ">",
            "&quot;": "\"",
            "&#39;": "'",
            "&nbsp;": " "
        ]
        for (entity, replacement) in entities {
            value = value.replacingOccurrences(of: entity, with: replacement)
        }
        return value
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
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
    let phase: String
    let model: String?
    let reasoningEffort: String?
    let score: Double
    let passed: Int
    let tasks: Int
    let costUSD: Double?
    let wallSeconds: Int?
    let cacheHitRate: Double?

    var sortKey: Int {
        month * 1_000_000 + day * 10_000 + phaseRank * 1_000 + modelPriority
    }

    var modelKey: String {
        let raw = [model, reasoningEffort]
            .compactMap { $0 }
            .joined(separator: "-")
            .lowercased()
        let slug = raw.replacingOccurrences(
            of: "[^a-z0-9]+",
            with: "_",
            options: .regularExpression
        )
        return slug.trimmingCharacters(in: CharacterSet(charactersIn: "_")).isEmpty ? "unknown" : slug
    }

    func snapshotPayload(year: Int) -> [String: Any] {
        let failed = max(0, tasks - passed)
        var payload: [String: Any] = [
            "date": dateText(year: year),
            "tasks": tasks,
            "valid_tasks": tasks,
            "passed": passed,
            "failed": failed,
            "pass_rate": tasks > 0 ? Double(passed) / Double(tasks) : 0,
            "iq_score": score,
            "score": score,
            "status": CodexRadarClient.modelIQStatus(score)
        ]
        if let wallSeconds {
            payload["wall_seconds"] = wallSeconds
            payload["wall_time_human"] = "\(wallSeconds / 60)分钟"
        }
        if let costUSD {
            payload["cost_usd"] = costUSD
        }
        if let cacheHitRate {
            let inputTokens = 1_000_000
            payload["input_tokens"] = inputTokens
            payload["cached_input_tokens"] = Int(round(Double(inputTokens) * cacheHitRate / 100))
        }
        if let model {
            payload["model"] = model
        }
        if let reasoningEffort {
            payload["reasoning_effort"] = reasoningEffort
        }
        return payload
    }

    func comparisonPayload(year: Int) -> [String: Any] {
        var payload: [String: Any] = [
            "label": modelLabel,
            "latest": snapshotPayload(year: year)
        ]
        if let model {
            payload["model"] = model
        }
        if let reasoningEffort {
            payload["reasoning_effort"] = reasoningEffort
        }
        return payload
    }

    private var phaseRank: Int {
        switch phase {
        case "pm":
            return 2
        case "am":
            return 1
        default:
            return 0
        }
    }

    private var modelPriority: Int {
        Int(modelVersion * 10) * 10 + effortPriority
    }

    private var modelVersion: Double {
        guard let model else {
            return 0
        }
        let pattern = #"(\d+(?:\.\d+)?)"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: model, range: NSRange(model.startIndex..<model.endIndex, in: model)),
              let range = Range(match.range(at: 1), in: model),
              let version = Double(model[range]) else {
            return 0
        }
        return version
    }

    private var effortPriority: Int {
        let effort = reasoningEffort?.lowercased() ?? ""
        if effort.contains("xhigh") {
            return 3
        }
        if effort.contains("high") {
            return 2
        }
        if effort.contains("medium") {
            return 1
        }
        return 0
    }

    private var modelLabel: String {
        let normalizedModel: String
        if let model {
            normalizedModel = model.lowercased().hasPrefix("gpt-") ? model.uppercased() : model
        } else {
            normalizedModel = "Unknown"
        }
        guard let reasoningEffort else {
            return normalizedModel
        }
        return "\(normalizedModel) \(reasoningEffort)"
    }

    private func dateText(year: Int) -> String {
        let base = String(format: "%04d-%02d-%02d", year, month, day)
        return phase.isEmpty ? base : "\(base)-\(phase)"
    }
}

private extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
