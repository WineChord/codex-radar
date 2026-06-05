import XCTest
@testable import CodexRadarCore

final class RateLimitDashboardTests: XCTestCase {
    func testSelectsCodexWeeklyAndShortBuckets() throws {
        let response = try JSONDecoder().decode(RateLimitResponse.self, from: sampleRateLimitData)
        let dashboard = RateLimitDashboard(response: response)

        XCTAssertEqual(dashboard.snapshot.limitId, AppConstants.codexLimitID)
        XCTAssertEqual(dashboard.shortRemainingPercent, 90)
        XCTAssertEqual(dashboard.weeklyRemainingPercent, 98)
        XCTAssertFalse(dashboard.isBlocked)
    }

    func testFallsBackToLongestWindowForWeeklyBucket() throws {
        let json = """
        {
          "rateLimits": {
            "limitId": "codex",
            "limitName": null,
            "primary": { "usedPercent": 20, "windowDurationMins": 60, "resetsAt": 100 },
            "secondary": { "usedPercent": 40, "windowDurationMins": 120, "resetsAt": 200 },
            "credits": null,
            "planType": "pro",
            "rateLimitReachedType": null
          },
          "rateLimitsByLimitId": null
        }
        """
        let response = try JSONDecoder().decode(RateLimitResponse.self, from: Data(json.utf8))
        let dashboard = RateLimitDashboard(response: response)

        XCTAssertEqual(dashboard.weeklyRemainingPercent, 60)
        XCTAssertEqual(dashboard.shortRemainingPercent, 80)
    }

    func testDashboardStatusTitleUsesCompactSegments() throws {
        let response = try JSONDecoder().decode(RateLimitResponse.self, from: sampleRateLimitData)
        let dashboard = RateLimitDashboard(response: response)
        let prediction = try JSONDecoder().decode(RadarPrediction.self, from: Data(#"{ "level": "low" }"#.utf8))
        let iq = try JSONDecoder().decode(ModelIQEnvelope.self, from: Data(#"{ "latest": { "iq_score": 62.5, "status": "red" } }"#.utf8))
        let state = DashboardState(
            rateLimits: dashboard,
            current: nil,
            prediction: prediction,
            modelIQ: iq
        )

        XCTAssertEqual(state.statusTitle, "98%/62/低")

        let current = try JSONDecoder().decode(RadarCurrent.self, from: Data(#"{ "window_open": true }"#.utf8))
        let speedState = DashboardState(
            rateLimits: dashboard,
            current: current,
            prediction: prediction,
            modelIQ: iq
        )

        XCTAssertEqual(speedState.statusTitle, "98%/62/速蹬")
    }

    func testIQDisplayFormattersSupportCompactAndPreciseOutput() {
        XCTAssertEqual(DisplayFormatters.compactIQScore(62.5), "62")
        XCTAssertEqual(DisplayFormatters.iqScore(62.5), "62.5")
        XCTAssertEqual(DisplayFormatters.compactIQScore(75), "75")
        XCTAssertEqual(DisplayFormatters.iqScore(75), "75")
    }
}

private let sampleRateLimitData = Data("""
{
  "rateLimits": {
    "limitId": "codex",
    "limitName": null,
    "primary": { "usedPercent": 10, "windowDurationMins": 300, "resetsAt": 1780571944 },
    "secondary": { "usedPercent": 2, "windowDurationMins": 10080, "resetsAt": 1781140743 },
    "credits": { "hasCredits": false, "unlimited": false, "balance": "0" },
    "planType": "pro",
    "rateLimitReachedType": null
  },
  "rateLimitsByLimitId": {
    "codex": {
      "limitId": "codex",
      "limitName": null,
      "primary": { "usedPercent": 10, "windowDurationMins": 300, "resetsAt": 1780571944 },
      "secondary": { "usedPercent": 2, "windowDurationMins": 10080, "resetsAt": 1781140743 },
      "credits": { "hasCredits": false, "unlimited": false, "balance": "0" },
      "planType": "pro",
      "rateLimitReachedType": null
    },
    "codex_bengalfox": {
      "limitId": "codex_bengalfox",
      "limitName": "GPT-5.3-Codex-Spark",
      "primary": { "usedPercent": 0, "windowDurationMins": 300, "resetsAt": 1780583310 },
      "secondary": { "usedPercent": 0, "windowDurationMins": 10080, "resetsAt": 1781170110 },
      "credits": null,
      "planType": "pro",
      "rateLimitReachedType": null
    }
  }
}
""".utf8)
