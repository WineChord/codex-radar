import XCTest
@testable import CodexRadarSentinel

final class DashboardConnectionErrorCopyTests: XCTestCase {
    func testAuthenticationErrorIsActionableInBothLanguages() {
        let raw = "codex account authentication required to read rate limits"

        XCTAssertEqual(
            DashboardConnectionErrorCopy.text(for: raw, language: .zhHans),
            "Radar 的额度连接认证失败。请先点“刷新”；若仍失败，请检查 Codex 登录状态。"
        )
        XCTAssertEqual(
            DashboardConnectionErrorCopy.text(for: raw, language: .en),
            "Radar could not authenticate its quota connection. Choose Refresh; if it still fails, check your sign-in in Codex."
        )
    }

    func testMultilineExpiredTokenShowsRecoveryWithoutRawResponse() {
        let raw = """
        failed to fetch codex rate limits: HTTP 401
        {
          "error": {
            "message": "Your authentication token has expired. Please sign in again.",
            "code": "token_expired"
          }
        }
        """
        for language in AppLanguage.allCases {
            let copy = DashboardConnectionErrorCopy.text(
                for: raw, language: language, hasCachedQuota: true
            )
            XCTAssertTrue(copy.contains(language == .en ? "check your sign-in" : "检查 Codex 登录状态"))
            XCTAssertTrue(copy.contains(language == .en ? "last saved" : "上次保存"))
            XCTAssertFalse(copy.contains("{"))
            XCTAssertFalse(copy.contains("token_expired"))
            XCTAssertFalse(copy.contains(language == .en ? "retry automatically" : "自动重试"))
        }
    }

    func testAppServerTimeoutUsesRetryCopy() {
        let raw = "Codex app-server request timed out"

        XCTAssertEqual(
            DashboardConnectionErrorCopy.text(
                for: raw,
                language: .zhHans
            ),
            "暂时无法连接 Codex 额度服务，应用会自动重试。"
        )
    }

    func testTransientQuotaErrorKeepsCachedReadingWithoutLeakingURL() {
        let raw = "failed to fetch codex rate limits: error sending request for url (https://chatgpt.com/backend-api/wham/usage)"

        let chinese = DashboardConnectionErrorCopy.text(
            for: raw,
            language: .zhHans,
            hasCachedQuota: true
        )
        let english = DashboardConnectionErrorCopy.text(
            for: raw,
            language: .en,
            hasCachedQuota: true
        )

        XCTAssertEqual(
            chinese,
            "Codex 额度暂时未更新。下方仍是最近一次数据，应用会自动重试。"
        )
        XCTAssertEqual(
            english,
            "Codex quota is temporarily unavailable. The latest saved reading remains below, and the app will retry automatically."
        )
        XCTAssertFalse(chinese.contains("https://"))
        XCTAssertFalse(english.contains("https://"))
    }

    func testUnrelatedErrorsStillRemainExact() {
        let raw = "The public radar request timed out"

        XCTAssertEqual(
            DashboardConnectionErrorCopy.text(for: raw, language: .zhHans),
            raw
        )
    }
}
