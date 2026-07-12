import Foundation
import XCTest
@testable import CodexRadarCore

final class LiveCodexRadarContractTests: XCTestCase {
    func testLiveCodexRadarPayloadsDecode() async throws {
        guard ProcessInfo.processInfo.environment["CODEX_RADAR_LIVE_CONTRACT_TESTS"] == "1" else {
            throw XCTSkip("Set CODEX_RADAR_LIVE_CONTRACT_TESTS=1 to check live CodexRadar payloads.")
        }

        let current = try await CodexRadarClient().fetchCurrent()
        let ratings = try await CodexRadarClient().fetchModelRatings()

        XCTAssertNotNil(current.checkedAt)
        XCTAssertNotNil(current.predictionDetail?.level)
        XCTAssertNotNil(current.modelIQ?.latest?.iqScore)
        XCTAssertNotEqual(DisplayFormatters.iqScore(current.modelIQ?.latest?.iqScore), DisplayFormatters.percentPlaceholder)
        XCTAssertGreaterThanOrEqual(current.modelIQ?.latestRows.count ?? 0, 1)
        XCTAssertGreaterThanOrEqual(current.modelIQ?.quotaRadar?.rows.count ?? 0, 1)
        XCTAssertGreaterThanOrEqual(current.resetJudgement?.cards.count ?? 0, 1)
        XCTAssertNotNil(current.communityKnowledge?.prompt)
        XCTAssertGreaterThanOrEqual(current.communityKnowledges.count, 1)
        XCTAssertNotNil(current.siteAnnouncement?.message)
        if current.modelIQ?.comparisons.isEmpty == false {
            XCTAssertGreaterThan(current.modelIQ?.latestRows.count ?? 0, 1)
        }
        XCTAssertFalse(ratings.models.isEmpty)
        XCTAssertNotNil(ratings.rating(for: current.modelIQ?.latest)?.average)
    }
}
