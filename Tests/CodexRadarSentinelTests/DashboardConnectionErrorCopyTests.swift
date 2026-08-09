import XCTest
@testable import CodexRadarSentinel

final class DashboardConnectionErrorCopyTests: XCTestCase {
    func testAuthenticationErrorIsActionableInBothLanguages() {
        let raw = "codex account authentication required to read rate limits"

        XCTAssertEqual(
            DashboardConnectionErrorCopy.text(for: raw, language: .zhHans),
            "Codex 尚未登录。请先打开 Codex 完成登录，再点“刷新”。"
        )
        XCTAssertEqual(
            DashboardConnectionErrorCopy.text(for: raw, language: .en),
            "Codex is signed out. Open Codex and sign in, then choose Refresh."
        )
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
