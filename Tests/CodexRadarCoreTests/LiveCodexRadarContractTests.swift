import Foundation
import XCTest
@testable import CodexRadarCore

final class LiveCodexRadarContractTests: XCTestCase {
    func testLiveCodexRadarPayloadsDecode() async throws {
        guard ProcessInfo.processInfo.environment["CODEX_RADAR_LIVE_CONTRACT_TESTS"] == "1" else {
            throw XCTSkip("Set CODEX_RADAR_LIVE_CONTRACT_TESTS=1 to check live CodexRadar payloads.")
        }

        let current = try await CodexRadarClient().fetchCurrent()

        XCTAssertNotNil(current.checkedAt)
        XCTAssertNotNil(current.predictionDetail?.level)
        XCTAssertNotNil(current.modelIQ?.latest?.iqScore)
        XCTAssertNotEqual(DisplayFormatters.iqScore(current.modelIQ?.latest?.iqScore), DisplayFormatters.percentPlaceholder)
    }
}
