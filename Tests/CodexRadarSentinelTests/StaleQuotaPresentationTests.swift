import XCTest
@testable import CodexRadarCore
@testable import CodexRadarSentinel

final class StaleQuotaPresentationTests: XCTestCase {
    func testFailedQuotaReadLabelsSavedPercentAndPausesPacing() {
        var state = DashboardPreviewFactory.state(for: .resetConfirmed, live: DashboardState())
        let fresh = StatusMetric.weeklyQuota.statusBarValue(
            for: state, language: .en, options: StatusBarDisplayOptions.defaultOptions
        )
        state.rateLimitError = "token_expired"
        for language in AppLanguage.allCases {
            let prefix = language.text("缓存", "Saved ")
            XCTAssertEqual(StatusMetric.weeklyQuota.statusBarValue(
                for: state, language: language, options: StatusBarDisplayOptions.defaultOptions
            ), prefix + fresh)
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
