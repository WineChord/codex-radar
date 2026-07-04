import Foundation

public struct ResetCreditSnapshot: Codable, Equatable {
    public let checkedAt: Date
    public let credits: [ResetCredit]
    public let availableCount: Int?
    public let totalEarnedCount: Int?

    public init(
        checkedAt: Date,
        credits: [ResetCredit],
        availableCount: Int? = nil,
        totalEarnedCount: Int? = nil
    ) {
        self.checkedAt = checkedAt
        self.credits = credits
        self.availableCount = availableCount
        self.totalEarnedCount = totalEarnedCount
    }

    public init(responseData: Data, checkedAt: Date = Date()) throws {
        let response = try JSONDecoder().decode(ResetCreditAPIResponse.self, from: responseData)
        let credits = response.credits.map(\.resetCredit).sorted { lhs, rhs in
            if lhs.isAvailable != rhs.isAvailable {
                return lhs.isAvailable
            }
            return (lhs.expiresAt ?? .distantFuture) < (rhs.expiresAt ?? .distantFuture)
        }
        self.init(
            checkedAt: checkedAt,
            credits: credits,
            availableCount: response.availableCount,
            totalEarnedCount: response.totalEarnedCount
        )
    }

    public var effectiveAvailableCount: Int {
        availableCount ?? credits.filter(\.isAvailable).count
    }
}

public struct ResetCredit: Codable, Equatable, Identifiable {
    public let idSuffix: String?
    public let title: String?
    public let status: String?
    public let resetType: String?
    public let grantedAt: Date?
    public let expiresAt: Date?
    public let redeemStartedAt: Date?
    public let redeemedAt: Date?

    public init(
        idSuffix: String?,
        title: String?,
        status: String?,
        resetType: String?,
        grantedAt: Date?,
        expiresAt: Date?,
        redeemStartedAt: Date? = nil,
        redeemedAt: Date? = nil
    ) {
        self.idSuffix = idSuffix
        self.title = title
        self.status = status
        self.resetType = resetType
        self.grantedAt = grantedAt
        self.expiresAt = expiresAt
        self.redeemStartedAt = redeemStartedAt
        self.redeemedAt = redeemedAt
    }

    public var id: String {
        if let idSuffix {
            return idSuffix
        }
        return [
            title,
            status,
            expiresAt.map { String(Int($0.timeIntervalSince1970)) },
            grantedAt.map { String(Int($0.timeIntervalSince1970)) },
        ]
        .compactMap { $0 }
        .joined(separator: "-")
    }

    public var isAvailable: Bool {
        let normalized = status?.lowercased() ?? ""
        return normalized == "available"
    }

    public func isExpired(now: Date = Date()) -> Bool {
        guard let expiresAt else {
            return false
        }
        return expiresAt <= now
    }
}

private struct ResetCreditAPIResponse: Decodable {
    let credits: [ResetCreditPayload]
    let availableCount: Int?
    let totalEarnedCount: Int?

    enum CodingKeys: String, CodingKey {
        case credits
        case availableCount = "available_count"
        case totalEarnedCount = "total_earned_count"
    }
}

private struct ResetCreditPayload: Decodable {
    let id: String?
    let resetType: String?
    let status: String?
    let grantedAt: String?
    let expiresAt: String?
    let redeemStartedAt: String?
    let redeemedAt: String?
    let title: String?

    enum CodingKeys: String, CodingKey {
        case id
        case resetType = "reset_type"
        case status
        case grantedAt = "granted_at"
        case expiresAt = "expires_at"
        case redeemStartedAt = "redeem_started_at"
        case redeemedAt = "redeemed_at"
        case title
    }

    var resetCredit: ResetCredit {
        ResetCredit(
            idSuffix: id.map(Self.safeIDSuffix),
            title: title,
            status: status,
            resetType: resetType,
            grantedAt: RadarDateParser.date(from: grantedAt),
            expiresAt: RadarDateParser.date(from: expiresAt),
            redeemStartedAt: RadarDateParser.date(from: redeemStartedAt),
            redeemedAt: RadarDateParser.date(from: redeemedAt)
        )
    }

    private static func safeIDSuffix(_ id: String) -> String {
        String(id.suffix(6))
    }
}
