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
        let insights = try await CodexRadarClient().fetchRadarInsights()

        XCTAssertNotNil(current.checkedAt)
        XCTAssertNotNil(current.predictionDetail?.level)
        XCTAssertNotNil(current.modelIQ?.latest?.iqScore)
        XCTAssertNotEqual(DisplayFormatters.iqScore(current.modelIQ?.latest?.iqScore), DisplayFormatters.percentPlaceholder)
        XCTAssertGreaterThanOrEqual(current.modelIQ?.latestRows.count ?? 0, 19)
        XCTAssertTrue(current.modelIQ?.latestRows.contains {
            $0.snapshot.model == "gpt-5.6-sol" && $0.snapshot.reasoningEffort == "ultra"
        } == true)
        XCTAssertGreaterThanOrEqual(current.modelIQ?.quotaRadar?.rows.count ?? 0, 1)
        XCTAssertGreaterThanOrEqual(current.resetJudgement?.cards.count ?? 0, 1)
        XCTAssertNotNil(current.communityKnowledge?.prompt)
        XCTAssertGreaterThanOrEqual(current.communityKnowledges.count, 1)
        XCTAssertNotNil(current.siteAnnouncement?.message)
        XCTAssertGreaterThanOrEqual(current.fastRadar?.summary.count ?? 0, 1)
        XCTAssertGreaterThanOrEqual(current.fastRadar?.rows.count ?? 0, 1)
        if current.modelIQ?.latest?.costUSDBasis == "total_selected_tasks" {
            XCTAssertNotNil(current.modelIQ?.latest?.averageCostUSD)
            XCTAssertNotNil(current.modelIQ?.latest?.averageTaskSeconds)
            XCTAssertTrue(current.modelIQ?.latest?.usesPerTaskAverages == true)
        }
        if current.modelIQ?.dataSource?.isDistributedCommunityRuns == true {
            XCTAssertNotNil(current.modelIQ?.dataSource?.linkURL)
            let rows = current.modelIQ?.latestRows ?? []
            let validTasks = rows.compactMap {
                $0.snapshot.validTasks ?? $0.snapshot.tasks
            }
            XCTAssertEqual(validTasks.count, rows.count)
            XCTAssertEqual(
                current.modelIQ?.dataSource?.validCells,
                validTasks.reduce(0, +)
            )
        }
        if current.modelIQ?.comparisons.isEmpty == false {
            XCTAssertGreaterThan(current.modelIQ?.latestRows.count ?? 0, 1)
        }
        XCTAssertFalse(ratings.models.isEmpty)
        XCTAssertNotNil(ratings.rating(for: current.modelIQ?.latest)?.average)
        XCTAssertNotNil(insights.generatedAt)
        XCTAssertNotNil(insights.sourceUpdatedAt)
        XCTAssertFalse(insights.recommendations.isEmpty)
        XCTAssertTrue(
            insights.recommendations.allSatisfy {
                !$0.validItems.isEmpty
            }
        )
        XCTAssertTrue(
            insights.degradationAlerts.validItems.allSatisfy {
                $0.largestDrop > 0
            }
        )

        var homepageRequest = URLRequest(url: AppConstants.codexRadarBaseURL)
        homepageRequest.timeoutInterval = TimeInterval(AppConstants.requestTimeoutSeconds)
        let (homepageData, response) = try await URLSession.shared.data(for: homepageRequest)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        let html = try XCTUnwrap(String(data: homepageData, encoding: .utf8))

        let intelligenceEfficiencyURL = AppConstants.codexRadarBaseURL
            .appending(path: AppConstants.intelligenceEfficiencyPath)
        var intelligenceEfficiencyRequest = URLRequest(url: intelligenceEfficiencyURL)
        intelligenceEfficiencyRequest.timeoutInterval = TimeInterval(AppConstants.requestTimeoutSeconds)
        let (intelligenceEfficiencyData, intelligenceEfficiencyResponse) =
            try await URLSession.shared.data(for: intelligenceEfficiencyRequest)
        XCTAssertEqual((intelligenceEfficiencyResponse as? HTTPURLResponse)?.statusCode, 200)
        let intelligenceEfficiency = try JSONDecoder().decode(
            IntelligenceEfficiencyEnvelope.self,
            from: intelligenceEfficiencyData
        )
        XCTAssertGreaterThanOrEqual(intelligenceEfficiency.points.count, 19)

        let homepageCurrent = try CodexRadarClient.currentFromHomepageHTML(
            html,
            intelligenceEfficiency: intelligenceEfficiency
        )
        XCTAssertNotNil(homepageCurrent.modelIQ?.latest?.averageCostUSD)
        XCTAssertNotNil(homepageCurrent.modelIQ?.latest?.averageTaskSeconds)
        XCTAssertTrue(homepageCurrent.modelIQ?.dataSource?.isDistributedCommunityRuns == true)
        XCTAssertGreaterThanOrEqual(homepageCurrent.modelIQ?.latestRows.count ?? 0, 19)
        let homepageRows = homepageCurrent.modelIQ?.latestRows ?? []
        let homepageValidTasks = homepageRows.compactMap {
            $0.snapshot.validTasks ?? $0.snapshot.tasks
        }
        XCTAssertEqual(homepageValidTasks.count, homepageRows.count)
        XCTAssertEqual(
            homepageCurrent.modelIQ?.dataSource?.validCells,
            homepageValidTasks.reduce(0, +)
        )
        XCTAssertGreaterThanOrEqual(homepageCurrent.resetJudgement?.cards.count ?? 0, 1)
        XCTAssertGreaterThanOrEqual(homepageCurrent.communityKnowledges.count, 1)
        XCTAssertNotNil(homepageCurrent.siteAnnouncement?.message)
        XCTAssertGreaterThanOrEqual(homepageCurrent.fastRadar?.rows.count ?? 0, 1)
    }
}
