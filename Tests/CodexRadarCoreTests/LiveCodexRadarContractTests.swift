import Foundation
import XCTest
@testable import CodexRadarCore

final class LiveCodexRadarContractTests: XCTestCase {
    func testLiveCodexRadarPayloadsDecode() async throws {
        guard ProcessInfo.processInfo.environment["CODEX_RADAR_LIVE_CONTRACT_TESTS"] == "1" else {
            throw XCTSkip("Set CODEX_RADAR_LIVE_CONTRACT_TESTS=1 to check live CodexRadar payloads.")
        }

        let currentData = try await data(from: "https://codexradar.com/current.json")
        let predictionData = try await data(from: "https://codexradar.com/prediction.json")
        let modelIQData = try await data(from: "https://codexradar.com/model-iq.json")
        let decoder = JSONDecoder()

        let current = try decoder.decode(RadarCurrent.self, from: currentData)
        let prediction = try decoder.decode(RadarPrediction.self, from: predictionData)
        let modelIQ = try decoder.decode(ModelIQEnvelope.self, from: modelIQData)

        XCTAssertNotNil(current.checkedAt)
        XCTAssertNotNil(prediction.level)
        XCTAssertNotNil(modelIQ.latest?.iqScore)
        XCTAssertNotEqual(DisplayFormatters.iqScore(modelIQ.latest?.iqScore), DisplayFormatters.percentPlaceholder)
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
