import Foundation
import XCTest
@testable import CodexRadarCore

final class LiveCodexRadarContractTests: XCTestCase {
    func testLiveCodexRadarPayloadsDecode() async throws {
        guard ProcessInfo.processInfo.environment["CODEX_RADAR_LIVE_CONTRACT_TESTS"] == "1" else {
            throw XCTSkip("Set CODEX_RADAR_LIVE_CONTRACT_TESTS=1 to check live CodexRadar payloads.")
        }

        let currentData = try await data(from: "https://codexradar.com/current.json")
        let feedData = try await data(from: "https://codexradar.com/feed.xml")
        let decoder = JSONDecoder()

        let current = try decoder.decode(RadarCurrent.self, from: currentData)

        XCTAssertNotNil(current.checkedAt)
        XCTAssertNotNil(current.predictionDetail?.level)
        XCTAssertNotNil(current.modelIQ?.latest?.iqScore)
        XCTAssertNotEqual(DisplayFormatters.iqScore(current.modelIQ?.latest?.iqScore), DisplayFormatters.percentPlaceholder)
        XCTAssertFalse(feedData.isEmpty)
    }

    private func data(from urlString: String) async throws -> Data {
        guard let url = URL(string: urlString) else {
            throw URLError(.badURL)
        }
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse,
              200..<300 ~= httpResponse.statusCode else {
            throw URLError(.badServerResponse)
        }
        return data
    }
}
