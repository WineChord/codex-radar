import XCTest
@testable import CodexRadarCore
@testable import CodexRadarSentinel

final class StaleQuotaPresentationTests: XCTestCase {
    func testFailedQuotaReadDoesNotPresentCachedPercentOrPaceAsCurrent() {
        var state = DashboardPreviewFactory.state(for: .resetConfirmed, live: DashboardState())
        let fresh = StatusMetric.weeklyQuota.statusBarValue(
            for: state, language: .en, options: StatusBarDisplayOptions.defaultOptions
        )
        state.rateLimitError = "token_expired"
        for language in AppLanguage.allCases {
            for metric in [StatusMetric.weeklyQuota, .shortQuota, .quotaPace] {
                XCTAssertEqual(metric.value(for: state, language: language), "—")
                XCTAssertEqual(metric.statusBarValue(
                    for: state, language: language, options: StatusBarDisplayOptions.defaultOptions
                ), "—")
            }
        }
        XCTAssertNotNil(state.rateLimits)
        state.rateLimitError = nil
        state.lastError = "Public Radar temporarily unavailable"
        XCTAssertEqual(StatusMetric.weeklyQuota.statusBarValue(
            for: state, language: .en, options: StatusBarDisplayOptions.defaultOptions
        ), fresh)
        XCTAssertNotEqual(fresh, "—")
    }
}
