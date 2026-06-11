import XCTest
@testable import CodexRadarCore

final class GitHubRepositoryClientTests: XCTestCase {
    func testDecodeRepositoryStatsReadsStarCount() throws {
        let stats = try GitHubRepositoryClient.decodeStats(from: Data("""
        {
          "full_name": "WineChord/codex-radar",
          "stargazers_count": 123
        }
        """.utf8))

        XCTAssertEqual(stats.stargazersCount, 123)
    }
}
