import XCTest
@testable import CodexRadarCore
@testable import CodexRadarSentinel

final class StaleQuotaPresentationTests: XCTestCase {
    func testRetainedQuotaDisplaysNormallyAndPausesPacing() {
        var state = DashboardPreviewFactory.state(for: .resetConfirmed, live: DashboardState())
        let fresh = StatusMetric.weeklyQuota.statusBarValue(
            for: state, language: .en, options: StatusBarDisplayOptions.defaultOptions
        )
        state.rateLimitError = "token_expired"
        for language in AppLanguage.allCases {
            XCTAssertEqual(StatusMetric.weeklyQuota.statusBarValue(
                for: state, language: language, options: StatusBarDisplayOptions.defaultOptions
            ), fresh)
            XCTAssertEqual(StatusMetric.quotaPace.value(for: state, language: language), "—")
            XCTAssertEqual(StatusMetric.quotaPace.statusBarValue(
                for: state, language: language, options: StatusBarDisplayOptions.defaultOptions
            ), "—")
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
