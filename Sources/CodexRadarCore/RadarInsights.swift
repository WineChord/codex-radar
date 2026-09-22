import Foundation

public struct RadarInsightsEnvelope: Decodable, Equatable {
    public let generatedAt: String?
    public let sourceUpdatedAt: String?
    public let recommendations: [RadarRecommendationGroup]
    public let degradationAlerts: RadarDegradationCollection

    private enum WrapperKeys: String, CodingKey {
        case data
    }

    public init(from decoder: Decoder) throws {
        let outer = try RadarInsightsBody(from: decoder)
        let wrapper = try decoder.container(keyedBy: WrapperKeys.self)
        let wrapped = try wrapper.decodeIfPresent(
            RadarInsightsBody.self,
            forKey: .data
        )
        let body = wrapped ?? outer
        let declaredSchemas = [outer.schema, wrapped?.schema].compactMap { $0 }
        guard !declaredSchemas.isEmpty,
              declaredSchemas.allSatisfy({ $0 == 1 }) else {
            throw DecodingError.dataCorrupted(
                .init(
                    codingPath: decoder.codingPath,
                    debugDescription: "Unsupported radar insights schema"
                )
            )
        }
        generatedAt = body.generatedAt ?? outer.generatedAt
        sourceUpdatedAt = body.sourceUpdatedAt ?? outer.sourceUpdatedAt
        recommendations = body.recommendations
        degradationAlerts = body.degradationAlerts
    }
}

public struct RadarRecommendationGroup: Decodable, Equatable {
    public let key: String?
    public let title: String?
    public let rule: String?
    private let items: [RadarRecommendationItem]

    public var validItems: [RadarRecommendationItem] {
        items.filter(\.isValid)
    }

    private enum CodingKeys: String, CodingKey {
        case key
        case id
        case title
        case rule
        case description
        case items
        case models
        case recommendations
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        key = RadarInsightsDecoding.string(
            in: container,
            keys: [.key, .id]
        )
        title = RadarInsightsDecoding.string(
            in: container,
            keys: [.title]
        )
        rule = RadarInsightsDecoding.string(
            in: container,
            keys: [.rule, .description]
        )
        items = try RadarInsightsDecoding.array(
            in: container,
            keys: [.items, .models, .recommendations]
        )
    }
}

public struct RadarRecommendationItem: Decodable, Equatable {
    public let model: String?
    public let effort: String?
    public let iq: Double?
    public let averageCostUSD: Double?
    public let averageDurationMinutes: Double?

    fileprivate var isValid: Bool {
        guard RadarInsightsDecoding.hasText(model),
              RadarInsightsDecoding.hasText(effort),
              let iq,
              iq.isFinite,
              iq >= 0 else {
            return false
        }
        if let averageCostUSD,
           !averageCostUSD.isFinite || averageCostUSD < 0 {
            return false
        }
        if let averageDurationMinutes,
           !averageDurationMinutes.isFinite || averageDurationMinutes < 0 {
            return false
        }
        return true
    }

    private enum CodingKeys: String, CodingKey {
        case model
        case effort
        case iq
        case currentIQ = "current_iq"
        case averageCostUSD = "average_cost_usd"
        case averagePriceUSD = "average_price_usd"
        case priceUSD = "price_usd"
        case price
        case averageDurationMinutes = "average_duration_minutes"
        case averageMinutes = "average_minutes"
        case minutes
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        model = RadarInsightsDecoding.string(
            in: container,
            keys: [.model]
        )
        effort = RadarInsightsDecoding.string(
            in: container,
            keys: [.effort]
        )
        iq = RadarInsightsDecoding.double(
            in: container,
            keys: [.iq, .currentIQ]
        )
        averageCostUSD = RadarInsightsDecoding.double(
            in: container,
            keys: [
                .averageCostUSD,
                .averagePriceUSD,
                .priceUSD,
                .price,
            ]
        )
        averageDurationMinutes = RadarInsightsDecoding.double(
            in: container,
            keys: [
                .averageDurationMinutes,
                .averageMinutes,
                .minutes,
            ]
        )
    }
}

public struct RadarDegradationCollection: Decodable, Equatable {
    public let rule: String?
    private let items: [RadarDegradationAlert]

    public var validItems: [RadarDegradationAlert] {
        items.filter(\.isValid)
    }

    private enum CodingKeys: String, CodingKey {
        case rule
        case items
        case alerts
    }

    fileprivate init(
        rule: String? = nil,
        items: [RadarDegradationAlert] = []
    ) {
        self.rule = rule
        self.items = items
    }

    public init(from decoder: Decoder) throws {
        if let array = try? decoder.singleValueContainer().decode(
            [RadarDegradationAlert].self
        ) {
            self.init(items: array)
            return
        }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let rule = RadarInsightsDecoding.string(
            in: container,
            keys: [.rule]
        )
        let items: [RadarDegradationAlert] = try RadarInsightsDecoding.array(
            in: container,
            keys: [.items, .alerts]
        )
        self.init(rule: rule, items: items)
    }
}

public struct RadarDegradationAlert: Decodable, Equatable {
    public let model: String?
    public let effort: String?
    public let iq: Double?
    public let average24HourIQ: Double?
    public let average48HourIQ: Double?
    public let from24HourAverageIQ: Double?
    public let from48HourAverageIQ: Double?
    public let from24HourHighIQ: Double?
    public let from48HourHighIQ: Double?

    public var preferred24HourDropIQ: Double? {
        from24HourAverageIQ
            ?? averageDrop(from: average24HourIQ)
            ?? from24HourHighIQ
    }

    public var preferred48HourDropIQ: Double? {
        from48HourAverageIQ
            ?? averageDrop(from: average48HourIQ)
            ?? from48HourHighIQ
    }

    public var uses24HourAverageComparison: Bool {
        from24HourAverageIQ != nil || (average24HourIQ != nil && iq != nil)
    }

    public var uses48HourAverageComparison: Bool {
        from48HourAverageIQ != nil || (average48HourIQ != nil && iq != nil)
    }

    public var largestDrop: Double {
        [preferred24HourDropIQ, preferred48HourDropIQ]
            .compactMap { $0 }
            .filter(\.isFinite)
            .max() ?? 0
    }

    public var largestDropUsesAverageComparison: Bool {
        switch (preferred24HourDropIQ, preferred48HourDropIQ) {
        case let (drop24?, drop48?) where drop24 > drop48:
            return uses24HourAverageComparison
        case let (drop24?, drop48?) where drop48 > drop24:
            return uses48HourAverageComparison
        case (_?, _?):
            return uses24HourAverageComparison
                || uses48HourAverageComparison
        case (_?, nil):
            return uses24HourAverageComparison
        case (nil, _?):
            return uses48HourAverageComparison
        case (nil, nil):
            return false
        }
    }

    fileprivate var isValid: Bool {
        let averages = [average24HourIQ, average48HourIQ]
            .compactMap { $0 }
        let drops = [
            from24HourAverageIQ,
            from48HourAverageIQ,
            from24HourHighIQ,
            from48HourHighIQ,
        ].compactMap { $0 }
        return RadarInsightsDecoding.hasText(model)
            && RadarInsightsDecoding.hasText(effort)
            && iq?.isFinite == true
            && (iq ?? -1) >= 0
            && averages.allSatisfy { $0.isFinite && $0 >= 0 }
            && drops.allSatisfy { $0.isFinite && $0 >= 0 }
            && largestDrop > 0
    }

    private func averageDrop(from average: Double?) -> Double? {
        guard let iq, let average else {
            return nil
        }
        return average - iq
    }

    private enum CodingKeys: String, CodingKey {
        case model
        case effort
        case iq
        case currentIQ = "current_iq"
        case average24HourIQ = "average_iq_24h"
        case average48HourIQ = "average_iq_48h"
        case from24HourAverageIQ = "from_24h_average_iq"
        case from48HourAverageIQ = "from_48h_average_iq"
        case from24HourHighIQ = "from_24h_high_iq"
        case degradation24HourIQ = "degradation_24h_iq"
        case drop24Hour = "drop_24h"
        case drop24h
        case from48HourHighIQ = "from_48h_high_iq"
        case degradation48HourIQ = "degradation_48h_iq"
        case drop48Hour = "drop_48h"
        case drop48h
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        model = RadarInsightsDecoding.string(
            in: container,
            keys: [.model]
        )
        effort = RadarInsightsDecoding.string(
            in: container,
            keys: [.effort]
        )
        iq = RadarInsightsDecoding.double(
            in: container,
            keys: [.iq, .currentIQ]
        )
        average24HourIQ = RadarInsightsDecoding.double(
            in: container,
            keys: [.average24HourIQ]
        )
        average48HourIQ = RadarInsightsDecoding.double(
            in: container,
            keys: [.average48HourIQ]
        )
        from24HourAverageIQ = RadarInsightsDecoding.double(
            in: container,
            keys: [.from24HourAverageIQ]
        )
        from48HourAverageIQ = RadarInsightsDecoding.double(
            in: container,
            keys: [.from48HourAverageIQ]
        )
        from24HourHighIQ = RadarInsightsDecoding.double(
            in: container,
            keys: [
                .from24HourHighIQ,
                .degradation24HourIQ,
                .drop24Hour,
                .drop24h,
            ]
        )
        from48HourHighIQ = RadarInsightsDecoding.double(
            in: container,
            keys: [
                .from48HourHighIQ,
                .degradation48HourIQ,
                .drop48Hour,
                .drop48h,
            ]
        )
    }
}

private struct RadarInsightsBody: Decodable {
    let schema: Int?
    let generatedAt: String?
    let sourceUpdatedAt: String?
    let recommendations: [RadarRecommendationGroup]
    let degradationAlerts: RadarDegradationCollection

    private enum CodingKeys: String, CodingKey {
        case schema
        case generatedAt = "generated_at"
        case sourceUpdatedAt = "source_updated_at"
        case recommendations
        case stationRecommendations = "station_recommendations"
        case stationRecs = "station_recs"
        case degradationAlerts = "degradation_alerts"
        case alerts
        case degradation
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schema = try RadarInsightsDecoding.strictInt(
            in: container,
            key: .schema
        )
        generatedAt = RadarInsightsDecoding.string(
            in: container,
            keys: [.generatedAt]
        )
        sourceUpdatedAt = RadarInsightsDecoding.timestamp(
            in: container,
            keys: [.sourceUpdatedAt]
        )
        recommendations = try RadarInsightsDecoding.array(
            in: container,
            keys: [
                .recommendations,
                .stationRecommendations,
                .stationRecs,
            ]
        )
        degradationAlerts = try RadarInsightsDecoding.value(
            in: container,
            keys: [
                .degradationAlerts,
                .alerts,
                .degradation,
            ]
        ) ?? RadarDegradationCollection()
    }
}

private enum RadarInsightsDecoding {
    static func hasText(_ value: String?) -> Bool {
        value?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }

    static func string<Key: CodingKey>(
        in container: KeyedDecodingContainer<Key>,
        keys: [Key]
    ) -> String? {
        for key in keys where container.contains(key) {
            if let value = try? container.decode(String.self, forKey: key) {
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : trimmed
            }
        }
        return nil
    }

    static func double<Key: CodingKey>(
        in container: KeyedDecodingContainer<Key>,
        keys: [Key]
    ) -> Double? {
        for key in keys where container.contains(key) {
            if let value = try? container.decode(Double.self, forKey: key) {
                return value
            }
            if let value = try? container.decode(String.self, forKey: key),
               let number = Double(
                   value.trimmingCharacters(in: .whitespacesAndNewlines)
               ) {
                return number
            }
        }
        return nil
    }

    static func strictInt<Key: CodingKey>(
        in container: KeyedDecodingContainer<Key>,
        key: Key
    ) throws -> Int? {
        guard container.contains(key) else {
            return nil
        }
        if let value = try? container.decode(Int.self, forKey: key) {
            return value
        }
        if let value = try? container.decode(String.self, forKey: key),
           let number = Int(
               value.trimmingCharacters(in: .whitespacesAndNewlines)
           ) {
            return number
        }
        throw DecodingError.dataCorruptedError(
            forKey: key,
            in: container,
            debugDescription: "Radar insights schema must be an integer"
        )
    }

    static func array<Value: Decodable, Key: CodingKey>(
        in container: KeyedDecodingContainer<Key>,
        keys: [Key]
    ) throws -> [Value] {
        for key in keys where container.contains(key) {
            return try container.decodeIfPresent([Value].self, forKey: key) ?? []
        }
        return []
    }

    static func value<Value: Decodable, Key: CodingKey>(
        in container: KeyedDecodingContainer<Key>,
        keys: [Key]
    ) throws -> Value? {
        for key in keys where container.contains(key) {
            return try container.decodeIfPresent(Value.self, forKey: key)
        }
        return nil
    }

    static func timestamp<Key: CodingKey>(
        in container: KeyedDecodingContainer<Key>,
        keys: [Key]
    ) -> String? {
        for key in keys where container.contains(key) {
            if let value = try? container.decode(
                RadarInsightsTimestamp.self,
                forKey: key
            ) {
                return value.value
            }
        }
        return nil
    }
}

private struct RadarInsightsTimestamp: Decodable {
    let value: String?

    init(from decoder: Decoder) throws {
        if let string = try? decoder.singleValueContainer().decode(String.self) {
            value = Self.validTimestamp(string)
            return
        }
        guard let container = try? decoder.container(
            keyedBy: RadarInsightsDynamicKey.self
        ) else {
            value = nil
            return
        }
        let candidates = container.allKeys.compactMap { key in
            try? container.decode(String.self, forKey: key)
        }
        value = candidates
            .compactMap { candidate -> (Date, String)? in
                guard let timestamp = Self.validTimestamp(candidate),
                      let date = RadarDateParser.date(from: timestamp) else {
                    return nil
                }
                return (date, timestamp)
            }
            .max { $0.0 < $1.0 }?
            .1
    }

    private static func validTimestamp(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              RadarDateParser.date(from: trimmed) != nil else {
            return nil
        }
        return trimmed
    }
}

private struct RadarInsightsDynamicKey: CodingKey {
    let stringValue: String
    let intValue: Int?

    init?(stringValue: String) {
        self.stringValue = stringValue
        self.intValue = nil
    }

    init?(intValue: Int) {
        self.stringValue = String(intValue)
        self.intValue = intValue
    }
}
