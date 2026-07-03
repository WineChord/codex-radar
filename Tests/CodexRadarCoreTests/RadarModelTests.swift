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
        XCTAssertEqual(iq.latest?.costUSD, 39.94)
        XCTAssertEqual(iq.latest?.cacheHitRateText, "95.0%")
        XCTAssertEqual(iq.latestRows.map(\.label), [
            "GPT-5.5 xhigh",
            "GPT-5.5 high",
            "GPT-5.4 high"
        ])
        XCTAssertEqual(iq.latestRows.compactMap { $0.snapshot.iqScore }, [62.5, 75.0, 87.5])
        XCTAssertEqual(iq.quotaRadar?.rows.count, 3)
        XCTAssertEqual(iq.quotaRadar?.rows.first?.tier, "20x Pro")
        XCTAssertEqual(iq.quotaRadar?.rows.first?.fiveHourUSD, 276.44)
        XCTAssertEqual(iq.quotaRadar?.rows.first?.sevenDayUSD, 1658.63)
        XCTAssertEqual(iq.quotaRadar?.sevenDayTrendDelta20x ?? 0, 24.35, accuracy: 0.001)

        let ratings = try decoder.decode(ModelRatingsEnvelope.self, from: Data(modelRatingsJSON.utf8))
        let rating = ratings.rating(for: iq.latest)
        XCTAssertEqual(rating?.average, 9.4)
        XCTAssertEqual(rating?.count, 10)
        XCTAssertEqual(ratings.rating(for: iq.latestRows.last?.snapshot)?.average, 8.1)
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

    func testBuildsFallbackCurrentFromHomepageHTML() throws {
        let current = try CodexRadarClient.currentFromHomepageHTML(homepageHTML, checkedAt: Date(timeIntervalSince1970: 1_781_510_400))

        XCTAssertEqual(current.schemaVersion, "homepage-fallback-v1")
        XCTAssertFalse(current.windowOpen)
        XCTAssertEqual(current.recommendedAction, "wait")
        XCTAssertEqual(current.lastWindow?.status, "retired")
        XCTAssertEqual(current.predictionDetail?.probability24h, 0)
        XCTAssertEqual(current.modelIQ?.latest?.date, "2026-06-14")
        XCTAssertEqual(current.modelIQ?.latest?.model, "GPT-5.5")
        XCTAssertEqual(current.modelIQ?.latest?.iqScore, 62.5)
        XCTAssertEqual(current.modelIQ?.latest?.passed, 5)
        XCTAssertEqual(current.modelIQ?.latest?.tasks, 12)
        XCTAssertEqual(current.modelIQ?.latest?.costUSD, 37.59)
        XCTAssertEqual(current.modelIQ?.latest?.wallTimeText, "183分钟")
        XCTAssertEqual(current.modelIQ?.latest?.cacheHitRateText, "94.3%")
        XCTAssertEqual(current.resetJudgement?.updatedLabel, "7月3日08:08研判")
        XCTAssertEqual(current.resetJudgement?.title, "发卡路径占优")
        XCTAssertEqual(current.resetJudgement?.cards.count, 2)
        XCTAssertEqual(current.resetJudgement?.cards.first?.label, "发重置卡")
        XCTAssertEqual(current.resetJudgement?.cards.first?.level, "高 · 基本已触发")
        XCTAssertEqual(current.resetJudgement?.reasons.count, 2)
    }

    func testMergesHomepageIQWhenCurrentPayloadOmitsModelIQ() throws {
        let current = try JSONDecoder().decode(RadarCurrent.self, from: Data(currentWithoutIQJSON.utf8))
        let merged = try CodexRadarClient.currentByMergingHomepageModelIQ(
            current,
            html: homepageDotDateHTML,
            checkedAt: Date(timeIntervalSince1970: 1_782_762_000)
        )

        XCTAssertTrue(merged.windowOpen)
        XCTAssertEqual(merged.status, "community_confirmed")
        XCTAssertEqual(merged.recommendedAction, "reset_completed")
        XCTAssertEqual(merged.lastWindow?.status, "community_confirmed")
        XCTAssertEqual(merged.modelIQ?.latest?.date, "2026-06-29-pm")
        XCTAssertEqual(merged.modelIQ?.latest?.model, "GPT-5.5")
        XCTAssertEqual(merged.modelIQ?.latest?.reasoningEffort, "xhigh")
        XCTAssertEqual(merged.modelIQ?.latest?.iqScore, 75)
        XCTAssertEqual(merged.modelIQ?.latestRows.map(\.label), [
            "GPT-5.5 xhigh",
            "GPT-5.5 high",
            "GPT-5.4 high"
        ])
        XCTAssertEqual(merged.modelIQ?.latestRows.compactMap { $0.snapshot.iqScore }, [75, 87.5, 75])
    }

    func testDashboardMapsCompoundPredictionLevels() throws {
        let prediction = try JSONDecoder().decode(RadarPrediction.self, from: Data("""
        {
          "level": "medium_low",
          "probability_24h": 0.15,
          "probability_48h": 0.31,
          "updated_at": "2026-06-21T10:00:00+08:00"
        }
        """.utf8))
        let state = DashboardState(prediction: prediction)

        XCTAssertEqual(state.predictionLevelLabel, "中低")
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

private let homepageHTML = """
<!doctype html>
<html>
<body>
<p>Tibo 的重置机制已转向“重置卡手工重置”，原重置预测、速蹬窗口提醒和历史窗口已下架。</p>
<section class="reset-judgement" aria-label="重置雷达研判">
  <div class="reset-judgement-head">
    <div>
      <span>重置雷达</span>
      <h2>重置雷达研判 <em>7月3日08:08研判</em></h2>
    </div>
    <strong>发卡路径占优</strong>
  </div>
  <div class="reset-judgement-grid">
    <article class="reset-judgement-card reset-judgement-card-high">
      <span>发重置卡</span>
      <strong>高 · 基本已触发</strong>
      <p>Tibo 最新回复明确说 reset 应该在用户的 little piggy bank 里，并且 it is for everyone。</p>
    </article>
    <article class="reset-judgement-card reset-judgement-card-low">
      <span>硬重置</span>
      <strong>低到中低</strong>
      <p>硬重置会直接改写所有人的当前额度窗口，短期更可能发卡而不是全员额度周期清零。</p>
    </article>
  </div>
  <ul class="reset-judgement-reasons">
    <li>官方信号强：Tibo 最新回复说 reset 应在 little piggy bank 里，并且人人都有。</li>
    <li>社区反证仍在：本轮仍有人反馈 reset 按钮消失、未收到 banked reset。</li>
  </ul>
</section>
<svg>
<title>6月13日 GPT-5.5 xhigh: IQ指数 87.5, 7/12, 费用 $42.41, 耗时 170分钟, cache命中率 94.5%</title>
<title>6月14日 GPT-5.4 xhigh: IQ指数 75.0, 6/12, 费用 $21.33, 耗时 206分钟, cache命中率 95.7%</title>
<title>6月14日 GPT-5.5 xhigh: IQ指数 62.5, 5/12, 费用 $37.59, 耗时 183分钟, cache命中率 94.3%</title>
</svg>
</body>
</html>
"""

private let homepageDotDateHTML = """
<!doctype html>
<html>
<body>
<svg>
<title>6.29_am GPT-5.5 xhigh: IQ指数 87.5, 7/12, 费用 $42.61, 耗时 156分钟, cache命中率 93.4%</title>
<title>6.29_pm GPT-5.5 xhigh: IQ指数 75.0, 6/12, 费用 $42.00, 耗时 204分钟, cache命中率 95.2%</title>
<title>6.29_pm GPT-5.5 high: IQ指数 87.5, 7/12, 费用 $26.31, 耗时 109分钟, cache命中率 93.8%</title>
<title>6.29_pm GPT-5.4 high: IQ指数 75.0, 6/12, 费用 $15.60, 耗时 154分钟, cache命中率 93.7%</title>
</svg>
</body>
</html>
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
    "wall_seconds": 2818,
    "input_tokens": 38991839,
    "cached_input_tokens": 37026944,
    "output_tokens": 386860,
    "cost_usd": 39.94
  },
  "comparisons": {
    "gpt_55_high": {
      "label": "GPT-5.5 high",
      "model": "gpt-5.5",
      "reasoning_effort": "high",
      "latest": {
        "date": "2026-06-04",
        "model": "gpt-5.5",
        "reasoning_effort": "high",
        "tasks": 12,
        "valid_tasks": 12,
        "passed": 6,
        "iq_score": 75,
        "status": "red"
      }
    },
    "gpt_54_high": {
      "label": "GPT-5.4 high",
      "model": "gpt-5.4",
      "reasoning_effort": "high",
      "latest": {
        "date": "2026-06-04",
        "model": "gpt-5.4",
        "reasoning_effort": "high",
        "tasks": 12,
        "valid_tasks": 12,
        "passed": 7,
        "iq_score": 87.5,
        "status": "yellow"
      }
    }
  },
  "quota_radar": {
    "date": "2026-07-01-am",
    "updated_at": "2026-06-30T22:27:57Z",
    "basis_date": "2026-07-01-am",
    "basis_window_label": "7d",
    "cost_usd": 132.690071,
    "total_tokens": 176492670,
    "rows": [
      { "tier": "20x Pro", "basis": "measured 7d", "five_h": 276.44, "seven_d": 1658.63 },
      { "tier": "5x Pro", "basis": "model /4", "five_h": 69.11, "seven_d": 414.66 },
      { "tier": "Plus", "basis": "model /20", "five_h": 13.82, "seven_d": 82.93 }
    ],
    "trend": [
      { "date": "2026-06-30-pm", "five_h_20x": 272.38, "seven_d_20x": 1634.28 },
      { "date": "2026-07-01-am", "five_h_20x": 276.44, "seven_d_20x": 1658.63 }
    ]
  }
}
"""

private let modelRatingsJSON = """
{
  "ok": true,
  "day": "2026-06-15",
  "timezone": "Asia/Shanghai",
  "refresh_seconds": 60,
  "updated_at": "2026-06-15T02:02:03.291Z",
  "models": [
    {
      "id": "gpt-5.5-xhigh",
      "label": "GPT-5.5 xhigh",
      "group": "GPT-5.5",
      "average": 9.4,
      "count": 10
    },
    {
      "id": "gpt-5.4-high",
      "label": "GPT-5.4 high",
      "group": "GPT-5.4",
      "average": 8.1,
      "count": 4
    }
  ],
  "source": "cache",
  "my_scores": {}
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

private let currentWithoutIQJSON = """
{
  "schema_version": "2.0",
  "service": "codex-reset-radar",
  "monitored_at": "2026-06-30T09:58:33.409085+08:00",
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
    "opened_at": "2026-06-30T07:39:41+08:00",
    "closed_at": null,
    "source_url": "https://x.com/thsottiaux/status/2071740419030053227"
  },
  "prediction": {
    "level": "high",
    "probability_24h": 0.4,
    "probability_48h": 0.53,
    "updated_at": "2026-06-30T05:17:30.069406+08:00"
  }
}
"""
