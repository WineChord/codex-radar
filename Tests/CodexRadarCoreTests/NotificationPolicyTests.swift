import XCTest
@testable import CodexRadarCore

final class NotificationPolicyTests: XCTestCase {
    func testInitialOpenWindowStillNotifies() throws {
        var memory = NotificationMemory()
        let state = DashboardState(
            rateLimits: try sampleDashboard(weeklyUsed: 12),
            current: try current(windowOpen: true, status: "open"),
            prediction: nil,
            modelIQ: nil
        )

        let events = NotificationPolicy().evaluate(previous: nil, current: state, memory: &memory)

        XCTAssertEqual(events.map(\.title), ["速蹬窗口开启"])
        XCTAssertTrue(memory.initialized)
    }

    func testClosedHistoricalWindowIsSeededOnFirstRun() throws {
        var memory = NotificationMemory()
        let state = DashboardState(
            rateLimits: try sampleDashboard(weeklyUsed: 2),
            current: try current(windowOpen: false, status: "closed"),
            prediction: nil,
            modelIQ: nil
        )

        let events = NotificationPolicy().evaluate(previous: nil, current: state, memory: &memory)

        XCTAssertTrue(events.isEmpty)
        XCTAssertNotNil(memory.lastResetCloseKey)
    }

    func testWeeklyThresholdNotifiesOncePerResetWindow() throws {
        var memory = NotificationMemory(initialized: true)
        let state = DashboardState(
            rateLimits: try sampleDashboard(weeklyUsed: 86),
            current: nil,
            prediction: nil,
            modelIQ: nil
        )

        let first = NotificationPolicy().evaluate(previous: nil, current: state, memory: &memory)
        let second = NotificationPolicy().evaluate(previous: state, current: state, memory: &memory)

        XCTAssertEqual(first.map(\.title), ["Codex 周额度很低"])
        XCTAssertTrue(second.isEmpty)
    }

    func testWeeklyWarningCooldownIgnoresResetTimestampJitter() throws {
        var memory = NotificationMemory(initialized: true)
        let now = Date(timeIntervalSince1970: 1_000)
        let firstState = DashboardState(
            rateLimits: try sampleDashboard(weeklyUsed: 76, weeklyResetsAt: 1_781_140_743),
            current: nil,
            prediction: nil,
            modelIQ: nil
        )
        let jitteredState = DashboardState(
            rateLimits: try sampleDashboard(weeklyUsed: 76, weeklyResetsAt: 1_781_140_803),
            current: nil,
            prediction: nil,
            modelIQ: nil
        )

        let first = NotificationPolicy().evaluate(
            previous: nil,
            current: firstState,
            memory: &memory,
            now: now
        )
        let second = NotificationPolicy().evaluate(
            previous: firstState,
            current: jitteredState,
            memory: &memory,
            now: now.addingTimeInterval(60)
        )
        let third = NotificationPolicy().evaluate(
            previous: jitteredState,
            current: jitteredState,
            memory: &memory,
            now: now.addingTimeInterval(AppConstants.weeklyWarningNotificationCooldownSeconds + 1)
        )

        XCTAssertEqual(first.map(\.title), ["Codex 周额度偏低"])
        XCTAssertTrue(second.isEmpty)
        XCTAssertEqual(third.map(\.title), ["Codex 周额度偏低"])
    }

    func testRetiredCodexRadarPredictionDoesNotNotify() throws {
        var memory = NotificationMemory(initialized: true)
        let current = try JSONDecoder().decode(RadarCurrent.self, from: Data("""
        {
          "status": "retired",
          "window_open": false,
          "prediction": {
            "level": "high",
            "probability_24h": 1,
            "should_notify": true
          }
        }
        """.utf8))
        let state = DashboardState(
            rateLimits: try sampleDashboard(weeklyUsed: 12),
            current: current,
            prediction: current.predictionDetail,
            modelIQ: nil
        )

        let events = NotificationPolicy().evaluate(previous: nil, current: state, memory: &memory)

        XCTAssertTrue(events.isEmpty)
    }

    func testEntitlementEventDoesNotNotifyAsSpeedWindow() throws {
        var memory = NotificationMemory()
        let current = try JSONDecoder().decode(RadarCurrent.self, from: Data("""
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
        let state = DashboardState(
            rateLimits: try sampleDashboard(weeklyUsed: 12),
            current: current,
            prediction: nil,
            modelIQ: nil
        )

        let events = NotificationPolicy().evaluate(previous: nil, current: state, memory: &memory)

        XCTAssertTrue(events.isEmpty)
        XCTAssertNil(memory.lastSpeedOpenKey)
    }

    func testCommunityConfirmedResetNotifiesAfterInitialization() throws {
        var memory = NotificationMemory(initialized: true)
        let current = try JSONDecoder().decode(RadarCurrent.self, from: Data("""
        {
          "schema_version": "2.0",
          "monitored_at": "2026-06-30T09:58:33+08:00",
          "window_open": true,
          "status": "community_confirmed",
          "recommended_action": "reset_completed",
          "window": {
            "open": true,
            "status": "community_confirmed",
            "action": "reset_completed",
            "message": "社区反馈已完成重置",
            "title": "Codex 用量限制重置",
            "scope": "Codex 用户",
            "opened_at": "2026-06-30T07:39:41+08:00"
          }
        }
        """.utf8))
        let state = DashboardState(
            rateLimits: try sampleDashboard(weeklyUsed: 12),
            current: current,
            prediction: nil,
            modelIQ: nil
        )

        let first = NotificationPolicy().evaluate(previous: nil, current: state, memory: &memory)
        let second = NotificationPolicy().evaluate(previous: state, current: state, memory: &memory)

        XCTAssertFalse(state.activeSpeedWindow)
        XCTAssertTrue(state.activeEntitlementEvent)
        XCTAssertEqual(first.map(\.title), ["CodexRadar 记录到 reset"])
        XCTAssertTrue(second.isEmpty)
    }

    func testCurrentWindowPayloadMessageNotifiesAsSpeedWindow() throws {
        var memory = NotificationMemory()
        let current = try JSONDecoder().decode(RadarCurrent.self, from: Data("""
        {
          "schema_version": "2.0",
          "window_open": true,
          "status": "open",
          "recommended_action": "use_remaining_tokens",
          "window": {
            "open": true,
            "status": "open",
            "action": "use_remaining_tokens",
            "message": "当前速蹬窗口开启",
            "title": "Codex 用量限制重置",
            "scope": "所有计划",
            "opened_at": "2026-06-17T02:49:52+08:00"
          }
        }
        """.utf8))
        let state = DashboardState(
            rateLimits: try sampleDashboard(weeklyUsed: 12),
            current: current,
            prediction: nil,
            modelIQ: nil
        )

        let events = NotificationPolicy().evaluate(previous: nil, current: state, memory: &memory)

        XCTAssertTrue(state.activeSpeedWindow)
        XCTAssertEqual(state.statusTitle, "88%/--/速蹬")
        XCTAssertEqual(events.map(\.title), ["速蹬窗口开启"])
    }
}

private func current(windowOpen: Bool, status: String) throws -> RadarCurrent {
    let json = """
    {
      "schema_version": "1.0",
      "checked_at": "2026-06-04T17:08:27+08:00",
      "status": "\(status)",
      "window_open": \(windowOpen),
      "recommended_action": "wait",
      "last_window": {
        "id": "codex-speed-window-test",
        "title": "Test reset",
        "status": "\(status)",
        "opened_at": "2026-06-04T08:25:58+08:00",
        "closed_at": "2026-06-04T08:25:58+08:00",
        "window_minutes": 0,
        "window_human": "无窗",
        "scope": "所有付费计划",
        "summary": "Test"
      }
    }
    """
    let decoder = JSONDecoder()
    return try decoder.decode(RadarCurrent.self, from: Data(json.utf8))
}

private func sampleDashboard(
    weeklyUsed: Double,
    weeklyResetsAt: Int = 1_781_140_743
) throws -> RateLimitDashboard {
    let json = """
    {
      "rateLimits": {
        "limitId": "codex",
        "limitName": null,
        "primary": { "usedPercent": 10, "windowDurationMins": 300, "resetsAt": 1780571944 },
        "secondary": { "usedPercent": \(weeklyUsed), "windowDurationMins": 10080, "resetsAt": \(weeklyResetsAt) },
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
