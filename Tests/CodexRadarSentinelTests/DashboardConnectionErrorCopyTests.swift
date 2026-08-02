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

    func testUnrelatedErrorsRemainExact() {
        let raw = "Codex app-server request timed out"

        XCTAssertEqual(
            DashboardConnectionErrorCopy.text(for: raw, language: .zhHans),
            raw
        )
    }
}
