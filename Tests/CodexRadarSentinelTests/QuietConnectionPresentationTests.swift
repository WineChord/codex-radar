import XCTest
@testable import CodexRadarCore
@testable import CodexRadarSentinel

final class QuietConnectionPresentationTests: XCTestCase {
    func testRetainedQuotaSuppressesTransientErrorsButKeepsInternalFailure() {
        for error in [
            "failed to fetch codex rate limits: connection reset",
            "Codex app-server request timed out",
            "Codex app-server is not available",
            "The operation couldn’t be completed. (NSURLErrorDomain error -1001.)",
            "The operation couldn’t be completed. (NSURLErrorDomain error -1009.)",
        ] {
            var state = DashboardPreviewFactory.state(for: .resetConfirmed, live: DashboardState())
            state.lastError = error
            state.rateLimitError = error
            XCTAssertNil(DashboardConnectionErrorCopy.visibleError(for: state), error)
            XCTAssertEqual(state.rateLimitError, error)
            state.rateLimits = nil
            XCTAssertEqual(DashboardConnectionErrorCopy.visibleError(for: state), error)
        }
    }

    func testActionableAndUnknownErrorsRemainVisibleWithRetainedData() {
        for error in ["token_expired", "failed to fetch codex rate limits: Unexpected response format"] {
            var state = DashboardPreviewFactory.state(for: .resetConfirmed, live: DashboardState())
            state.rateLimitError = error
            state.lastError = error
            XCTAssertEqual(DashboardConnectionErrorCopy.visibleError(for: state), error)
        }
    }

    func testEachDataSourceKeepsItsOwnNoDataAndActionableErrors() {
        let quotaError = "failed to fetch codex rate limits: timed out"
        let radarError = "The operation couldn’t be completed. (NSURLErrorDomain error -1001.)"
        var state = DashboardPreviewFactory.state(for: .resetConfirmed, live: DashboardState())
        state.lastError = radarError + "\n" + quotaError
        state.rateLimitError = quotaError
        state.current = nil
        XCTAssertEqual(DashboardConnectionErrorCopy.visibleError(for: state), radarError)
        state = DashboardPreviewFactory.state(for: .resetConfirmed, live: DashboardState())
        state.lastError = radarError + "\n" + "token_expired"
        state.rateLimitError = "token_expired"
        XCTAssertEqual(DashboardConnectionErrorCopy.visibleError(for: state), "token_expired")
        state.rateLimits = nil
        state.lastError = radarError + "\n" + quotaError
        state.rateLimitError = quotaError
        XCTAssertEqual(DashboardConnectionErrorCopy.visibleError(for: state), quotaError)
        state.current = nil
        state.rateLimits = DashboardPreviewFactory.state(for: .resetConfirmed, live: DashboardState()).rateLimits
        state.lastError = radarError + "\n" + radarError
        state.rateLimitError = radarError
        XCTAssertEqual(DashboardConnectionErrorCopy.visibleError(for: state), radarError)
    }

    func testRestartedQuotaUsesNormalLabelsInBothLanguages() {
        var state = DashboardPreviewFactory.state(for: .resetConfirmed, live: DashboardState())
        for language in AppLanguage.allCases {
            let normal = StatusTitleFormatter.plainTitle(
                for: state, metrics: [.weeklyQuota, .shortQuota], language: language,
                options: .defaultOptions
            )
            state.restoredQuota = true
            XCTAssertEqual(StatusTitleFormatter.plainTitle(
                for: state, metrics: [.weeklyQuota, .shortQuota], language: language,
                options: .defaultOptions
            ), normal)
            state.restoredQuota = false
        }
    }
}
