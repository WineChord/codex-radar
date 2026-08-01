import XCTest
@testable import CodexRadarCore

final class RadarModelTests: XCTestCase {
    func testDecodesRadarInsightsWrapperAliasesAndValidItems() throws {
        let insights = try JSONDecoder().decode(
            RadarInsightsEnvelope.self,
            from: Data(
                """
                {
                  "schema": 1,
                  "generated_at": "2026-07-26T02:11:28+00:00",
                  "source_updated_at": {
                    "quality": "2026-07-26T01:58:00+00:00",
                    "cost": "2026-07-26T02:04:17.123Z"
                  },
                  "data": {
                    "station_recs": [
                      {
                        "id": "daily_development",
                        "title": "日常开发",
                        "description": "按综合成本推荐",
                        "models": [
                          {
                            "model": "gpt-5.6-sol",
                            "effort": "medium",
                            "current_iq": "93.75",
                            "average_price_usd": "3.810228",
                            "average_minutes": "15.95",
                            "trend_48h": [{"unexpected": {"shape": true}}]
                          },
                          {
                            "model": " ",
                            "effort": "high",
                            "iq": 99
                          },
                          {
                            "model": "gpt-5.6-terra",
                            "effort": "low",
                            "iq": 45,
                            "price": -1
                          }
                        ]
                      }
                    ],
                    "alerts": {
                      "rule": "只显示自身历史下降",
                      "alerts": [
                        {
                          "model": "gpt-5.6-sol",
                          "effort": "low",
                          "current_iq": 71,
                          "drop_24h": 5.3,
                          "drop48h": 8.2,
                          "trend": "ignored"
                        },
                        {
                          "model": "gpt-5.6-sol",
                          "effort": "high",
                          "iq": 91
                        },
                        {
                          "model": "gpt-5.6-terra",
                          "effort": "medium",
                          "iq": 72,
                          "drop_24h": -3,
                          "drop_48h": 5
                        }
                      ]
                    }
                  }
                }
                """.utf8
            )
        )

        XCTAssertEqual(insights.generatedAt, "2026-07-26T02:11:28+00:00")
        XCTAssertEqual(
            insights.sourceUpdatedAt,
            "2026-07-26T02:04:17.123Z"
        )
        XCTAssertEqual(insights.recommendations.count, 1)
        let group = try XCTUnwrap(insights.recommendations.first)
        XCTAssertEqual(group.key, "daily_development")
        XCTAssertEqual(group.title, "日常开发")
        XCTAssertEqual(group.rule, "按综合成本推荐")
        XCTAssertEqual(group.validItems.count, 1)
        let recommendation = try XCTUnwrap(group.validItems.first)
        XCTAssertEqual(recommendation.model, "gpt-5.6-sol")
        XCTAssertEqual(recommendation.effort, "medium")
        XCTAssertEqual(recommendation.iq, 93.75)
        XCTAssertEqual(recommendation.averageCostUSD, 3.810228)
        XCTAssertEqual(recommendation.averageDurationMinutes, 15.95)

        XCTAssertEqual(
            insights.degradationAlerts.rule,
            "只显示自身历史下降"
        )
        XCTAssertEqual(insights.degradationAlerts.validItems.count, 1)
        let alert = try XCTUnwrap(
            insights.degradationAlerts.validItems.first
        )
        XCTAssertEqual(alert.model, "gpt-5.6-sol")
        XCTAssertEqual(alert.effort, "low")
        XCTAssertEqual(alert.iq, 71)
        XCTAssertEqual(alert.from24HourHighIQ, 5.3)
        XCTAssertEqual(alert.from48HourHighIQ, 8.2)
        XCTAssertEqual(alert.largestDrop, 8.2)
    }

    func testDecodesRadarInsightsArrayDegradationAndSecondaryAliases() throws {
        let insights = try JSONDecoder().decode(
            RadarInsightsEnvelope.self,
            from: Data(
                """
                {
                  "schema": "1",
                  "generated_at": "2026-07-26T02:11:28Z",
                  "source_updated_at": "2026-07-26T02:04:17Z",
                  "station_recommendations": [
                    {
                      "key": "background_automation",
                      "rule": "最低费用",
                      "recommendations": [
                        {
                          "model": "gpt-5.6-terra",
                          "effort": "xhigh",
                          "iq": 88.4,
                          "price_usd": 2.5,
                          "minutes": 19
                        }
                      ]
                    }
                  ],
                  "degradation": [
                    {
                      "model": "gpt-5.6-sol",
                      "effort": "ultra",
                      "iq": 92,
                      "degradation_24h_iq": 5.8,
                      "degradation_48h_iq": 9.8,
                      "trend_48h": [1, 2, 3]
                    }
                  ]
                }
                """.utf8
            )
        )

        XCTAssertEqual(insights.sourceUpdatedAt, "2026-07-26T02:04:17Z")
        XCTAssertEqual(
            insights.recommendations.first?.validItems.first?.averageCostUSD,
            2.5
        )
        XCTAssertEqual(
            insights.recommendations.first?.validItems.first?
                .averageDurationMinutes,
            19
        )
        XCTAssertEqual(
            insights.degradationAlerts.validItems.first?.largestDrop,
            9.8
        )
    }

    func testRadarInsightsAllowsEmptyCollectionsAndRejectsOtherSchemas()
        throws
    {
        let empty = try JSONDecoder().decode(
            RadarInsightsEnvelope.self,
            from: Data(
                """
                {
                  "schema": 1,
                  "recommendations": [],
                  "degradation_alerts": []
                }
                """.utf8
            )
        )

        XCTAssertTrue(empty.recommendations.isEmpty)
        XCTAssertTrue(empty.degradationAlerts.validItems.isEmpty)
        XCTAssertThrowsError(
            try JSONDecoder().decode(
                RadarInsightsEnvelope.self,
                from: Data(
                    """
                    {
                      "schema": 2,
                      "recommendations": [],
                      "degradation_alerts": []
                    }
                    """.utf8
                )
            )
        )
        for malformedSchema in ["null", #""bad""#, "1.5"] {
            XCTAssertThrowsError(
                try JSONDecoder().decode(
                    RadarInsightsEnvelope.self,
                    from: Data(
                        """
                        {
                          "schema": \(malformedSchema),
                          "data": {
                            "schema": 1,
                            "recommendations": [],
                            "degradation_alerts": []
                          }
                        }
                        """.utf8
                    )
                )
            )
        }
        XCTAssertThrowsError(
            try JSONDecoder().decode(
                RadarInsightsEnvelope.self,
                from: Data(
                    """
                    {
                      "schema": 2,
                      "data": {
                        "schema": 1,
                        "recommendations": [],
                        "degradation_alerts": []
                      }
                    }
                    """.utf8
                )
            )
        )
        XCTAssertThrowsError(
            try JSONDecoder().decode(
                RadarInsightsEnvelope.self,
                from: Data(
                    """
                    {
                      "schema": 1,
                      "data": "malformed"
                    }
                    """.utf8
                )
            )
        )
        XCTAssertThrowsError(
            try JSONDecoder().decode(
                RadarInsightsEnvelope.self,
                from: Data(
                    """
                    {
                      "schema": 1,
                      "recommendations": {},
                      "degradation_alerts": []
                    }
                    """.utf8
                )
            )
        )
    }

    func testFetchRadarInsightsUsesInjectedURLAndFifteenSecondTimeout()
        async throws
    {
        let expectedURL = URL(string: "https://example.test/radar-insights")!
        RadarInsightsURLProtocol.handler = { request in
            XCTAssertEqual(request.url, expectedURL)
            XCTAssertEqual(
                request.timeoutInterval,
                TimeInterval(AppConstants.requestTimeoutSeconds)
            )
            XCTAssertEqual(request.cachePolicy, .useProtocolCachePolicy)
            XCTAssertFalse(request.httpShouldHandleCookies)
            XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
            XCTAssertNil(request.value(forHTTPHeaderField: "Cookie"))
            let response = HTTPURLResponse(
                url: expectedURL,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            return (
                response,
                Data(
                    """
                    {
                      "schema": 1,
                      "recommendations": [],
                      "degradation_alerts": []
                    }
                    """.utf8
                )
            )
        }
        defer {
            RadarInsightsURLProtocol.handler = nil
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RadarInsightsURLProtocol.self]
        let client = CodexRadarClient(
            radarInsightsURL: expectedURL,
            session: URLSession(configuration: configuration)
        )

        let insights = try await client.fetchRadarInsights()

        XCTAssertEqual(AppConstants.requestTimeoutSeconds, 15)
        XCTAssertEqual(
            AppConstants.radarInsightsRefreshIntervalSeconds,
            600
        )
        XCTAssertTrue(insights.recommendations.isEmpty)
    }

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
        XCTAssertNil(ratings.rating(for: iq.latestRows[1].snapshot))
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

    func testDecodesDistributedModelIQAveragesAndSource() throws {
        let iq = try JSONDecoder().decode(
            ModelIQEnvelope.self,
            from: Data(distributedModelIQJSON.utf8)
        )

        XCTAssertEqual(iq.latest?.iqScore, 105.1)
        XCTAssertEqual(iq.latest?.passed, 76)
        XCTAssertEqual(iq.latest?.tasks, 109)
        XCTAssertEqual(iq.latest?.costUSD, 1_047.309802)
        XCTAssertEqual(iq.latest?.averageCostUSD, 9.608347)
        XCTAssertEqual(iq.latest?.displayedCostUSD, 9.608347)
        XCTAssertEqual(iq.latest?.averageTaskSeconds, 2_217.055)
        XCTAssertEqual(iq.latest?.averageTaskTimeHuman, "37分钟")
        XCTAssertTrue(iq.latest?.usesPerTaskAverages == true)
        XCTAssertTrue(iq.dataSource?.isDistributedCommunityRuns == true)
        XCTAssertEqual(iq.dataSource?.validCells, 984)
        XCTAssertEqual(iq.dataSource?.linkURL?.host, "deng.codexradar.com")
        XCTAssertEqual(iq.latestRows.map(\.label), [
            "GPT-5.6 Sol max",
            "GPT-5.6 Sol high",
            "GPT-5.6 Terra max",
            "GPT-5.6 Luna high",
            "GPT-5.5 high"
        ])

        let legacyRatings = try JSONDecoder().decode(
            ModelRatingsEnvelope.self,
            from: Data(modelRatingsJSON.utf8)
        )
        XCTAssertNil(legacyRatings.rating(for: iq.latest))
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
        XCTAssertEqual(current.siteAnnouncement?.label, "公告 📣")
        XCTAssertTrue(current.siteAnnouncement?.message?.contains("Polymarket GPT-5.6") == true)
        XCTAssertEqual(current.siteAnnouncement?.updatedLabel, "数据更新时间 2026-07-07 08:49:36 北京时间")
        XCTAssertEqual(current.siteAnnouncement?.sourceURL, "https://polymarket.com/event/gpt-5pt6-released-onptptpt-20260623051439980")
        XCTAssertEqual(current.resetJudgement?.updatedLabel, "7月3日08:08研判")
        XCTAssertEqual(current.resetJudgement?.title, "发卡路径占优")
        XCTAssertEqual(current.resetJudgement?.cards.count, 2)
        XCTAssertEqual(current.resetJudgement?.cards.first?.label, "发重置卡")
        XCTAssertEqual(current.resetJudgement?.cards.first?.level, "高 · 基本已触发")
        XCTAssertEqual(current.resetJudgement?.reasons.count, 2)
        XCTAssertEqual(current.communityKnowledge?.title, "重置卡过期时间自查")
        XCTAssertEqual(current.communityKnowledges.count, 1)
        XCTAssertTrue(current.communityKnowledge?.prompt?.contains("rate-limit reset credits") == true)
        XCTAssertTrue(current.communityKnowledge?.prompt?.contains("不要打印 access_token") == true)
    }

    func testBuildsResetJudgementFromCurrentHomepageCardMarkup() throws {
        let current = try CodexRadarClient.currentFromHomepageHTML(
            currentResetJudgementHTML,
            checkedAt: Date(timeIntervalSince1970: 1_785_438_400)
        )

        XCTAssertEqual(current.resetJudgement?.updatedLabel, "事件更新 7月29日 13:42")
        XCTAssertEqual(current.resetJudgement?.title, "官方源快车")
        XCTAssertEqual(current.resetJudgement?.cards.count, 2)
        XCTAssertEqual(current.resetJudgement?.cards.first?.label, "发重置卡")
        XCTAssertEqual(current.resetJudgement?.cards.first?.level, "未宣布")
        XCTAssertEqual(
            current.resetJudgement?.cards.first?.summary,
            "本轮是直接重置 — 本轮官方信号指向直接用量重置，不代表新增可储存的 banked reset。"
        )
        XCTAssertEqual(current.resetJudgement?.cards.last?.label, "硬重置")
        XCTAssertEqual(current.resetJudgement?.cards.last?.level, "已落地")
        XCTAssertEqual(
            current.resetJudgement?.cards.last?.summary,
            "官方重置完成 — 7月29日 12:09，Tibo 确认直接用量重置已完成；当前没有开启的速蹬窗口。"
        )
        XCTAssertTrue(current.resetJudgement?.reasons.isEmpty == true)
    }

    func testBuildsDistributedModelIQFromHomepageHTML() throws {
        let html = """
        <html><body>
          <div class="model-iq-chart-view" data-model-iq-chart-view="iq">
            <svg>
              <circle data-model-key="gpt_56_sol_max" data-model-iq-tooltip-key="iq|2026-07-17T13:03:49+08:00|103.200000" aria-label="17日13时 Sol max: IQ指数 103.2, 74/108, 平均费用 $9.92, 平均耗时 38分钟, cache命中率 97.8%"></circle>
              <circle data-model-key="gpt_56_sol_max" data-model-iq-tooltip-key="iq|2026-07-17T14:35:21+08:00|105.100000" aria-label="17日14时 Sol max: IQ指数 105.1, 76/109, 平均费用 $9.61, 平均耗时 37分钟, cache命中率 97.9%"></circle>
              <circle data-model-key="gpt_56_terra_high" data-model-iq-tooltip-key="iq|2026-07-17T14:35:21+08:00|77.900000" aria-label="17日14时 Terra high: IQ指数 77.9, 46/89, 平均费用 $1.32, 平均耗时 14分钟, cache命中率 96.2%"></circle>
            </svg>
          </div>
          <div class="model-iq-chart-view" data-model-iq-chart-view="value" hidden>
            <circle data-model-key="gpt_56_sol_max" data-model-iq-tooltip-key="value|2026-07-17T14:35:21+08:00|104.619184" aria-label="17日14时 Sol max: IQ指数 105.1, 76/109, 平均费用 $9.61, 平均耗时 37分钟, cache命中率 97.9%"></circle>
          </div>
        </body></html>
        """

        let current = try CodexRadarClient.currentFromHomepageHTML(
            html,
            checkedAt: Date(timeIntervalSince1970: 1_784_256_000)
        )

        XCTAssertEqual(current.modelIQ?.latest?.date, "2026-07-17T14:35:21+08:00")
        XCTAssertEqual(current.modelIQ?.latest?.model, "gpt-5.6-sol")
        XCTAssertEqual(current.modelIQ?.latest?.reasoningEffort, "max")
        XCTAssertEqual(current.modelIQ?.latest?.iqScore, 105.1)
        XCTAssertEqual(current.modelIQ?.latest?.passed, 76)
        XCTAssertEqual(current.modelIQ?.latest?.tasks, 109)
        XCTAssertNil(current.modelIQ?.latest?.costUSD)
        XCTAssertEqual(current.modelIQ?.latest?.averageCostUSD, 9.61)
        XCTAssertEqual(current.modelIQ?.latest?.averageTaskSeconds, 2_220)
        XCTAssertEqual(current.modelIQ?.latest?.cacheHitRateText, "97.9%")
        XCTAssertEqual(current.modelIQ?.comparisons.count, 1)
        XCTAssertTrue(current.modelIQ?.dataSource?.isDistributedCommunityRuns == true)
    }

    func testMergesIntelligenceEfficiencyPointsIntoDistributedModelIQ() throws {
        let decoder = JSONDecoder()
        let current = try decoder.decode(ModelIQEnvelope.self, from: Data(distributedModelIQJSON.utf8))
        let efficiency = try decoder.decode(
            IntelligenceEfficiencyEnvelope.self,
            from: Data(intelligenceEfficiencyJSON.utf8)
        )

        let merged = current.merging(intelligenceEfficiency: efficiency)

        XCTAssertEqual(merged.updatedAt, "2026-07-22T10:02:00+08:00")
        XCTAssertEqual(merged.latest?.iqScore, 104.5)
        XCTAssertEqual(merged.latest?.passed, 78)
        XCTAssertEqual(merged.latest?.tasks, 112)
        XCTAssertEqual(merged.latest?.averageCostUSD, 9.2)
        XCTAssertEqual(merged.latest?.averageTaskSeconds, 2_160)
        XCTAssertEqual(merged.latest?.costUSD, 1_047.309802)
        XCTAssertEqual(
            merged.dataSource?.validCells,
            merged.latestRows.compactMap {
                $0.snapshot.validTasks ?? $0.snapshot.tasks
            }.reduce(0, +)
        )
        XCTAssertEqual(merged.dataSource?.validCells, 717)
        XCTAssertEqual(merged.latestRows.count, 7)
        XCTAssertTrue(merged.latestRows.contains { $0.label == "GPT-5.6 Sol ultra" })
        XCTAssertTrue(merged.latestRows.contains { $0.label == "GPT-5.6 Luna low" })
    }

    func testHomepageFallbackUsesDynamicIntelligenceEfficiencyData() throws {
        let efficiency = try JSONDecoder().decode(
            IntelligenceEfficiencyEnvelope.self,
            from: Data(intelligenceEfficiencyJSON.utf8)
        )

        let current = try CodexRadarClient.currentFromHomepageHTML(
            "<html><body><h1>Codex Radar</h1></body></html>",
            checkedAt: Date(timeIntervalSince1970: 1_784_256_000),
            intelligenceEfficiency: efficiency
        )

        XCTAssertEqual(current.schemaVersion, "homepage-fallback-v1")
        XCTAssertEqual(current.modelIQ?.latest?.model, "gpt-5.6-sol")
        XCTAssertEqual(current.modelIQ?.latest?.reasoningEffort, "max")
        XCTAssertEqual(current.modelIQ?.latestRows.count, 3)
        XCTAssertEqual(current.modelIQ?.dataSource?.validCells, 336)
        XCTAssertTrue(current.modelIQ?.dataSource?.isDistributedCommunityRuns == true)
        XCTAssertEqual(current.modelIQ?.dataSource?.linkURL?.host, "deng.codexradar.com")
    }

    func testBuildsCommunityKnowledgeFromGuideDiv() throws {
        let html = """
        <html>
          <head>
            <title>7月12日 Sol max: IQ指数 105.0, 7/10, 费用 $58.4, 耗时 30分钟, cache命中率 97.6%</title>
          </head>
          <body>
            <section class="community-knowledge" aria-label="Codex 社区知识分享">
              <div class="community-knowledge-grid">
                <article class="community-knowledge-card">
                  <div class="community-knowledge-card-main">
                    <h2>如何开启 Max 推理强度</h2>
                  </div>
                  <div class="community-knowledge-guide" data-site-announcement-prompt hidden>
                    <p>打开 Codex 设置 → Configuration → Model features → Available reasoning efforts，勾选 Max。</p>
                    <img src="assets/codex-enable-max-reasoning-20260711.png" alt="在 Codex Configuration 的 Available reasoning efforts 中开启 Max">
                  </div>
                </article>
              </div>
            </section>
          </body>
        </html>
        """

        let current = try CodexRadarClient.currentFromHomepageHTML(
            html,
            checkedAt: Date(timeIntervalSince1970: 1_783_824_000)
        )

        XCTAssertEqual(current.communityKnowledge?.title, "如何开启 Max 推理强度")
        XCTAssertEqual(current.communityKnowledges.count, 1)
        XCTAssertTrue(current.communityKnowledge?.prompt?.contains("Available reasoning efforts") == true)
    }

    func testBuildsFastRadarFromHomepageHTML() throws {
        let html = """
        <html>
          <head>
            <title>7月13日 Sol max: IQ指数 150.0, 10/10, 费用 $34.9, 耗时 27分钟, cache命中率 95.6%</title>
          </head>
          <body>
            <section class="fast-radar" id="fast-radar" aria-label="Fast 雷达">
              <div class="fast-radar-head">
                <div>
                  <h2>Fast 雷达 <em>7月12日16:32更新</em></h2>
                </div>
                <span>从标准改成 Fast，以 2.5 倍的成本到底快了多少？</span>
              </div>
              <div class="fast-radar-summary" aria-label="Fast 模式速览">
                <div><span>体感加速</span><strong>⚡️1.381 倍</strong></div>
                <div><span>首字延迟减少</span><strong>0.08 秒</strong></div>
                <div><span>Token 生成速度加速</span><strong>⚡️1.504 倍</strong></div>
              </div>
              <div class="fast-radar-table" role="table" aria-label="Fast 雷达">
                <div class="fast-radar-row fast-radar-row-head" role="row">
                  <span>模型</span>
                  <span>体感加速 · E2E</span>
                  <span>首字延迟减少 · TTFT</span>
                  <span>Token 生成速度加速 · TPS</span>
                </div>
                <div class="fast-radar-row" role="row">
                  <div class="fast-radar-model"><strong>Sol</strong></div>
                  <div class="fast-radar-metric fast-radar-metric-e2e" data-label="体感加速"><span>47.26s → 33.79s</span><strong>⚡️1.399×</strong></div>
                  <div class="fast-radar-metric fast-radar-metric-ttft" data-label="首字延迟减少"><span>9.98s → 9.08s</span><strong>快 9.0%</strong></div>
                  <div class="fast-radar-metric fast-radar-metric-tps" data-label="Token 生成速度加速"><span>55.75 → 84.23</span><strong>⚡️1.511×</strong></div>
                </div>
                <div class="fast-radar-row" role="row">
                  <div class="fast-radar-model"><strong>Terra</strong></div>
                  <div class="fast-radar-metric fast-radar-metric-e2e" data-label="体感加速"><span>44.61s → 34.10s</span><strong>⚡️1.308×</strong></div>
                  <div class="fast-radar-metric fast-radar-metric-ttft is-regression" data-label="首字延迟减少"><span>7.17s → 9.10s</span><strong>慢 26.9%</strong></div>
                  <div class="fast-radar-metric fast-radar-metric-tps" data-label="Token 生成速度加速"><span>55.53 → 83.37</span><strong>⚡️1.501×</strong></div>
                </div>
              </div>
              <div class="fast-radar-explain">
                <p>测试方法：Standard 与 Fast 各独立运行 3 次并取算术平均。</p>
              </div>
            </section>
          </body>
        </html>
        """

        let current = try CodexRadarClient.currentFromHomepageHTML(
            html,
            checkedAt: Date(timeIntervalSince1970: 1_783_910_400)
        )

        XCTAssertEqual(current.fastRadar?.title, "Fast 雷达")
        XCTAssertEqual(current.fastRadar?.updatedLabel, "7月12日16:32更新")
        XCTAssertEqual(current.fastRadar?.summary.count, 3)
        XCTAssertEqual(current.fastRadar?.rows.count, 2)
        XCTAssertEqual(current.fastRadar?.rows.first?.model, "Sol")
        XCTAssertEqual(current.fastRadar?.rows.first?.e2e?.value, "⚡️1.399×")
        XCTAssertEqual(current.fastRadar?.rows.last?.ttft?.value, "慢 26.9%")
        XCTAssertTrue(current.fastRadar?.method?.contains("Standard 与 Fast") == true)
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
<section class="site-announcement" aria-label="雷达规划公告">
  <span>公告 📣</span>
  <p>Polymarket GPT-5.6 具体发布日期概率：July 9 <strong class="site-announcement-odds">72%</strong>，July 10 <strong class="site-announcement-odds">8.1%</strong>。 <a class="site-announcement-source" href="https://polymarket.com/event/gpt-5pt6-released-onptptpt-20260623051439980" target="_blank" rel="noreferrer">来源：Polymarket ↗</a><br><span class="site-announcement-updated">数据更新时间 2026-07-07 08:49:36 北京时间</span></p>
</section>
<section class="community-knowledge" aria-label="Codex 社区知识分享">
  <div class="community-knowledge-grid">
    <article class="community-knowledge-card">
      <div class="community-knowledge-card-main">
        <h2>重置卡过期时间自查</h2>
      </div>
      <code class="site-announcement-prompt community-knowledge-prompt" data-site-announcement-prompt hidden>帮我用本机 Codex 凭证查一下 rate-limit reset credits，读取 ~/.codex/auth.json 里的 tokens.access_token
要求:
1. 如果 401，说明是凭证失效或没带对 Authorization header
2. 不要打印 access_token、refresh_token、cookie 或完整唯一 ID</code>
    </article>
  </div>
</section>
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

private let currentResetJudgementHTML = """
<!doctype html>
<html>
<body>
<section class="reset-judgement" aria-label="重置雷达">
  <div class="reset-judgement-head">
    <div>
      <h2>重置雷达 <em>事件更新 7月29日 13:42</em></h2>
    </div>
    <strong>官方源快车</strong>
  </div>
  <div class="reset-judgement-grid">
    <article class="reset-judgement-card" data-reset-track="banked_reset" data-reset-track-state="not_announced">
      <div class="reset-judgement-card-head">
        <span>发重置卡</span>
        <em class="reset-judgement-state">未宣布</em>
      </div>
      <strong>本轮是直接重置</strong>
      <p>本轮官方信号指向直接用量重置，不代表新增可储存的 banked reset。</p>
    </article>
    <article class="reset-judgement-card" data-reset-track="hard_reset" data-reset-track-state="completed">
      <div class="reset-judgement-card-head">
        <span>硬重置</span>
        <em class="reset-judgement-state">已落地</em>
      </div>
      <strong>官方重置完成</strong>
      <p>7月29日 12:09，Tibo 确认直接用量重置已完成；当前没有开启的速蹬窗口。</p>
    </article>
  </div>
</section>
<svg>
  <title>7月29日 GPT-5.6 Sol max: IQ指数 103.1, 77/112, 费用 $9.63, 耗时 33分钟, cache命中率 97.5%</title>
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

private let distributedModelIQJSON = """
{
  "updated_at": "2026-07-17T14:35:21+08:00",
  "data_source": {
    "type": "distributed_community_runs",
    "url": "https://deng.codexradar.com",
    "checked_at": "2026-07-17T14:35:21+08:00",
    "valid_cells": 984
  },
  "latest": {
    "date": "2026-07-17T14:35:21+08:00",
    "model": "gpt-5.6-sol",
    "reasoning_effort": "max",
    "score": 105.1,
    "status": "green",
    "passed": 76,
    "tasks": 109,
    "valid_tasks": 109,
    "wall_seconds": 241659,
    "wall_time_human": "67小时8分",
    "average_task_seconds": 2217.055,
    "average_task_time_human": "37分钟",
    "cost_usd": 1047.309802,
    "average_cost_usd": 9.608347,
    "cost_usd_basis": "total_selected_tasks"
  },
  "comparisons": {
    "gpt_56_sol_high": {
      "label": "GPT-5.6 Sol high",
      "model": "gpt-5.6-sol",
      "reasoning_effort": "high",
      "latest": { "score": 89.8, "passed": 62, "tasks": 104, "model": "gpt-5.6-sol", "reasoning_effort": "high" }
    },
    "gpt_56_terra_max": {
      "label": "GPT-5.6 Terra max",
      "model": "gpt-5.6-terra",
      "reasoning_effort": "max",
      "latest": { "score": 95.7, "passed": 54, "tasks": 85, "model": "gpt-5.6-terra", "reasoning_effort": "max" }
    },
    "gpt_56_luna_high": {
      "label": "GPT-5.6 Luna high",
      "model": "gpt-5.6-luna",
      "reasoning_effort": "high",
      "latest": { "score": 62.5, "passed": 34, "tasks": 82, "model": "gpt-5.6-luna", "reasoning_effort": "high" }
    },
    "gpt_55_high_distributed": {
      "label": "GPT-5.5 high",
      "model": "gpt-5.5",
      "reasoning_effort": "high",
      "latest": { "score": 84.9, "passed": 62, "tasks": 110, "model": "gpt-5.5", "reasoning_effort": "high" }
    }
  }
}
"""

private let intelligenceEfficiencyJSON = """
{
  "schema": 2,
  "type": "distributed_intelligence_efficiency",
  "source_updated_at": "2026-07-22T10:02:00+08:00",
  "points": [
    {
      "model": "gpt-5.6-sol",
      "effort": "max",
      "iq": 104.5,
      "passed": 78,
      "valid_tasks": 112,
      "average_price_usd": 9.2,
      "average_minutes": 36.0,
      "latest_graded_at": "2026-07-22T02:01:00+00:00"
    },
    {
      "model": "gpt-5.6-sol",
      "effort": "ultra",
      "iq": 97.8,
      "passed": 73,
      "valid_tasks": 112,
      "average_price_usd": 25.9,
      "average_minutes": 56.0,
      "latest_graded_at": "2026-07-22T01:58:00+00:00"
    },
    {
      "model": "gpt-5.6-luna",
      "effort": "low",
      "iq": 8.0,
      "passed": 6,
      "valid_tasks": 112,
      "average_price_usd": 0.2,
      "average_minutes": 8.0,
      "latest_graded_at": "2026-07-22T01:55:00+00:00"
    }
  ]
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

private final class RadarInsightsURLProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(
        for request: URLRequest
    ) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(
                self,
                didFailWithError: URLError(.resourceUnavailable)
            )
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(
                self,
                didReceive: response,
                cacheStoragePolicy: .notAllowed
            )
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
