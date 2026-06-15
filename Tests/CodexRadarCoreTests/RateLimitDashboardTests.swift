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

        let normalIQ = try JSONDecoder().decode(ModelIQEnvelope.self, from: Data(#"{ "latest": { "iq_score": 112.5, "status": "green" } }"#.utf8))
        let normalState = DashboardState(
            rateLimits: dashboard,
            current: nil,
            prediction: prediction,
            modelIQ: normalIQ
        )

        XCTAssertEqual(normalState.statusTitle, "98%/112/正常")

        let current = try JSONDecoder().decode(RadarCurrent.self, from: Data("""
        {
          "window_open": true,
          "last_window": {
            "id": "debug-speed-window",
            "title": "Codex 速蹬窗口开启",
            "status": "open"
          }
        }
        """.utf8))
        let speedState = DashboardState(
            rateLimits: dashboard,
            current: current,
            prediction: prediction,
            modelIQ: iq
        )

        XCTAssertEqual(speedState.statusTitle, "98%/62/速蹬")

        let entitlement = try JSONDecoder().decode(RadarCurrent.self, from: Data("""
        {
          "window_open": true,
          "status": "open",
          "window": {
            "open": true,
            "status": "open",
            "title": "Codex 用量限制重置",
            "message": "当前有已确认官方权益事件"
          }
        }
        """.utf8))
        let entitlementState = DashboardState(
            rateLimits: dashboard,
            current: entitlement,
            prediction: prediction,
            modelIQ: normalIQ
        )

        XCTAssertEqual(entitlementState.statusTitle, "98%/112/正常")
        XCTAssertFalse(entitlementState.activeSpeedWindow)
        XCTAssertTrue(entitlementState.activeEntitlementEvent)
    }

    func testIQDisplayFormattersSupportCompactAndPreciseOutput() {
        XCTAssertEqual(DisplayFormatters.compactIQScore(62.5), "62")
        XCTAssertEqual(DisplayFormatters.iqScore(62.5), "62.5")
        XCTAssertEqual(DisplayFormatters.compactIQScore(75), "75")
        XCTAssertEqual(DisplayFormatters.iqScore(75), "75")
    }

    func testStatusBarAdvancedFormattersSupportCompactOutput() {
        XCTAssertEqual(DisplayFormatters.percent(69), "69%")
        XCTAssertEqual(DisplayFormatters.percent(69, includesSymbol: false), "69")
        XCTAssertEqual(StatusBarIQDisplayMode.raw.format(100, preciseRaw: false), "100")
        XCTAssertEqual(StatusBarIQDisplayMode.dividedBy10Integer.format(100, preciseRaw: false), "10")
        XCTAssertEqual(StatusBarIQDisplayMode.dividedBy10Integer.format(62.5, preciseRaw: false), "6")
        XCTAssertEqual(StatusBarIQDisplayMode.dividedBy10Decimal.format(62.5, preciseRaw: false), "6.3")
    }

    func testTimeProportionalQuotaPacingUsesElapsedResetWindow() throws {
        let response = try JSONDecoder().decode(RateLimitResponse.self, from: sampleRateLimitData)
        let dashboard = RateLimitDashboard(response: response)
        let resetAt = 1_781_140_743
        let windowSeconds = 10_080 * 60
        let halfway = Date(timeIntervalSince1970: TimeInterval(resetAt - windowSeconds / 2))

        let pacing = try XCTUnwrap(dashboard.quotaPacing(strategy: .timeProportional, now: halfway))

        XCTAssertEqual(pacing.roundedTargetUsedPercent, 50)
        XCTAssertEqual(pacing.roundedTargetRemainingPercent, 50)
        XCTAssertEqual(pacing.roundedCurrentUsedPercent, 2)
        XCTAssertEqual(pacing.roundedCurrentRemainingPercent, 98)
        XCTAssertEqual(pacing.roundedDeltaToTargetPercent, 48)
        XCTAssertEqual(pacing.roundedRemainingDeltaPercent, 48)
        XCTAssertEqual(pacing.roundedElapsedWindowPercent, 50)
        XCTAssertEqual(pacing.status, .underTarget)
    }

    func testSevenDayQuotaPacingStepsByElapsedDay() throws {
        let response = try JSONDecoder().decode(RateLimitResponse.self, from: sampleRateLimitData)
        let dashboard = RateLimitDashboard(response: response)
        let resetAt = 1_781_140_743
        let windowSeconds = 10_080 * 60
        let startAt = resetAt - windowSeconds
        let thirdDay = Date(timeIntervalSince1970: TimeInterval(startAt + 2 * 86_400 + 1))

        let pacing = try XCTUnwrap(dashboard.quotaPacing(strategy: .sevenDay, now: thirdDay))

        XCTAssertEqual(pacing.roundedTargetUsedPercent, 43)
        XCTAssertEqual(pacing.roundedTargetRemainingPercent, 57)
        XCTAssertEqual(pacing.roundedCurrentUsedPercent, 2)
        XCTAssertEqual(pacing.roundedCurrentRemainingPercent, 98)
        XCTAssertEqual(pacing.roundedDeltaToTargetPercent, 41)
        XCTAssertEqual(pacing.roundedRemainingDeltaPercent, 41)
        XCTAssertEqual(pacing.status, .underTarget)
    }

    func testReserveQuotaPacingKeepsTwentyPercentBufferUntilFinalDay() throws {
        let response = try JSONDecoder().decode(RateLimitResponse.self, from: sampleRateLimitData)
        let dashboard = RateLimitDashboard(response: response)
        let resetAt = 1_781_140_743
        let windowSeconds = 10_080 * 60
        let startAt = resetAt - windowSeconds
        let thirdDay = Date(timeIntervalSince1970: TimeInterval(startAt + 3 * 86_400))

        let pacing = try XCTUnwrap(dashboard.quotaPacing(strategy: .reserveTwenty, now: thirdDay))

        XCTAssertEqual(pacing.roundedTargetUsedPercent, 40)
        XCTAssertEqual(pacing.roundedTargetRemainingPercent, 60)
        XCTAssertEqual(pacing.status, .underTarget)
    }

    func testFrontLoadedQuotaPacingEncouragesEarlierUsage() throws {
        let response = try JSONDecoder().decode(RateLimitResponse.self, from: sampleRateLimitData)
        let dashboard = RateLimitDashboard(response: response)
        let resetAt = 1_781_140_743
        let windowSeconds = 10_080 * 60
        let halfway = Date(timeIntervalSince1970: TimeInterval(resetAt - windowSeconds / 2))

        let pacing = try XCTUnwrap(dashboard.quotaPacing(strategy: .frontLoaded, now: halfway))

        XCTAssertEqual(pacing.roundedTargetUsedPercent, 70)
        XCTAssertEqual(pacing.roundedTargetRemainingPercent, 30)
        XCTAssertEqual(pacing.status, .underTarget)
    }

    func testWorkdayWeightedQuotaPacingSpendsLessOnWeekends() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let start = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 6, day: 1)))
        XCTAssertEqual(calendar.component(.weekday, from: start), 2)
        let dashboard = try weeklyDashboard(usedPercent: 20, start: start)
        let saturdayStart = start.addingTimeInterval(5 * 86_400)

        let pacing = try XCTUnwrap(dashboard.quotaPacing(
            strategy: .workdayWeighted,
            now: saturdayStart,
            calendar: calendar
        ))

        XCTAssertEqual(pacing.roundedTargetUsedPercent, 88)
        XCTAssertEqual(pacing.roundedTargetRemainingPercent, 12)
        XCTAssertEqual(pacing.status, .underTarget)
    }
}

private func weeklyDashboard(usedPercent: Double, start: Date) throws -> RateLimitDashboard {
    let resetAt = Int(start.timeIntervalSince1970) + 10_080 * 60
    let json = """
    {
      "rateLimits": {
        "limitId": "codex",
        "limitName": null,
        "primary": { "usedPercent": \(usedPercent), "windowDurationMins": 10080, "resetsAt": \(resetAt) },
        "secondary": null,
        "credits": null,
        "planType": "pro",
        "rateLimitReachedType": null
      },
      "rateLimitsByLimitId": null
    }
    """
    let response = try JSONDecoder().decode(RateLimitResponse.self, from: Data(json.utf8))
    return RateLimitDashboard(response: response)
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
