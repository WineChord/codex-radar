import XCTest
@testable import CodexRadarCore

final class RadarModelTests: XCTestCase {
    func testDecodesCurrentPredictionAndIQPayloads() throws {
        let decoder = JSONDecoder()

        let current = try decoder.decode(RadarCurrent.self, from: Data(currentJSON.utf8))
        XCTAssertFalse(current.windowOpen)
        XCTAssertEqual(current.recommendedAction, "wait")
        XCTAssertEqual(current.lastWindow?.status, "closed")
        XCTAssertNotNil(current.checkedDate)

        let prediction = try decoder.decode(RadarPrediction.self, from: Data(predictionJSON.utf8))
        XCTAssertEqual(prediction.level, "low")
        XCTAssertEqual(prediction.probability24h, 0.11)

        let iq = try decoder.decode(ModelIQEnvelope.self, from: Data(modelIQJSON.utf8))
        XCTAssertEqual(iq.latest?.iqScore, 62.5)
        XCTAssertEqual(iq.latest?.passed, 6)
        XCTAssertEqual(iq.latest?.tasks, 12)
    }

    func testDecodesEmbeddedCurrentPayload() throws {
        let current = try JSONDecoder().decode(RadarCurrent.self, from: Data(currentV2JSON.utf8))

        XCTAssertEqual(current.schemaVersion, "2.0")
        XCTAssertEqual(current.checkedAt, "2026-06-08T10:52:35.324184+08:00")
        XCTAssertFalse(current.windowOpen)
        XCTAssertEqual(current.recommendedAction, "wait")
        XCTAssertEqual(current.lastWindow?.id, "codex-speed-window-2026-06-04-codex")
        XCTAssertEqual(current.lastWindow?.status, "closed")
        XCTAssertEqual(current.prediction?.level, "low")
        XCTAssertEqual(current.predictionDetail?.reasoningSummary, "官方关注点集中在个人 10X 用量奖励。")
        XCTAssertEqual(current.predictionDetail?.probability24h, 0.17)
        XCTAssertEqual(current.modelIQ?.latest?.iqScore, 62.5)
        XCTAssertEqual(current.modelIQ?.latest?.passed, 5)
        XCTAssertEqual(current.modelIQ?.latest?.tasks, 12)
    }
}

private let currentJSON = """
{
  "schema_version": "1.0",
  "checked_at": "2026-06-04T17:08:27.638865+08:00",
  "status": "none",
  "window_open": false,
  "recommended_action": "wait",
  "last_window": {
    "id": "codex-speed-window-2026-06-04-codex",
    "title": "Codex 可靠性事故补偿重置",
    "status": "closed",
    "opened_at": "2026-06-04T08:25:58+08:00",
    "closed_at": "2026-06-04T08:25:58+08:00",
    "window_minutes": 0,
    "window_human": "无窗",
    "scope": "所有付费计划",
    "summary": "Tibo 表示过去 24 小时内有三次影响 Codex 可靠性的小事故，并已为所有付费计划重置 Codex 使用限制。",
    "sources": [{ "type": "window_closed", "url": "https://x.com/thsottiaux/status/2062329981548802523" }]
  },
  "prediction": {
    "level": "low",
    "probability_24h": 0.11,
    "probability_48h": 0.2,
    "should_notify": false
  }
}
"""

private let predictionJSON = """
{
  "schema_version": "1.0",
  "level": "low",
  "probability_24h": 0.11,
  "probability_48h": 0.2,
  "should_notify": false,
  "expected_window": "未来 24-48 小时",
  "reasoning_summary": "当前无官方开启窗口。",
  "updated_at": "2026-06-04T17:08:27+08:00"
}
"""

private let modelIQJSON = """
{
  "schema_version": "1.0",
  "updated_at": "2026-06-04T17:08:27+08:00",
  "latest": {
    "date": "2026-06-04",
    "label": "Daily DeepSWE 12-task probe 2026-06-04",
    "model": "gpt-5.5",
    "reasoning_effort": "xhigh",
    "tasks": 12,
    "valid_tasks": 12,
    "passed": 6,
    "failed": 6,
    "pass_rate": 0.5,
    "baseline_pass_rate": 0.666667,
    "iq_score": 62.5,
    "status": "red",
    "wall_seconds": 2818
  }
}
"""

private let currentV2JSON = """
{
  "schema_version": "2.0",
  "service": "codex-reset-radar",
  "monitored_at": "2026-06-08T10:52:35.324184+08:00",
  "window_open": false,
  "status": "none",
  "recommended_action": "wait",
  "window": {
    "open": false,
    "status": "none",
    "action": "wait",
    "message": "当前没有开启的速蹬窗口",
    "title": "Codex 可靠性事故补偿重置",
    "scope": "所有付费计划",
    "opened_at": null,
    "closed_at": "2026-06-04T08:25:58+08:00",
    "source_url": "https://x.com/thsottiaux/status/2062329981548802523"
  },
  "prediction": {
    "level": "low",
    "probability_24h": 0.17,
    "probability_48h": 0.27,
    "expected_window": "未来 24-48 小时",
    "summary": "官方关注点集中在个人 10X 用量奖励。",
    "updated_at": "2026-06-08T10:52:35.082583+08:00"
  },
  "recent_windows": [
    {
      "id": "codex-speed-window-2026-06-04-codex",
      "title": "Codex 可靠性事故补偿重置",
      "status": "closed",
      "opened_at": "2026-06-04T08:25:00+08:00",
      "closed_at": "2026-06-04T08:25:00+08:00",
      "window_minutes": 0,
      "window_human": "无窗",
      "scope": "所有付费计划",
      "summary": "Tibo 表示过去 24 小时内有三次影响 Codex 可靠性的小事故。",
      "source_url": "https://x.com/thsottiaux/status/2062329981548802523"
    }
  ],
  "model_iq": {
    "latest": {
      "date": "2026-06-08",
      "score": 62.5,
      "status": "red",
      "passed": 5,
      "tasks": 12,
      "model": "gpt-5.5",
      "reasoning_effort": "xhigh",
      "valid_tasks": 12,
      "wall_seconds": 2605
    }
  }
}
"""
