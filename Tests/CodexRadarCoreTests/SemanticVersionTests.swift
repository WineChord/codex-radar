import CodexRadarCore
import XCTest

final class SemanticVersionTests: XCTestCase {
    func testParsesReleaseTags() {
        XCTAssertEqual(SemanticVersion("v0.1.4")?.description, "0.1.4")
        XCTAssertEqual(SemanticVersion("1.2")?.description, "1.2.0")
        XCTAssertEqual(SemanticVersion("2")?.description, "2.0.0")
    }

    func testComparesVersionsNumerically() {
        XCTAssertLessThan(SemanticVersion("0.1.9")!, SemanticVersion("0.1.10")!)
        XCTAssertLessThan(SemanticVersion("0.9.9")!, SemanticVersion("1.0.0")!)
        XCTAssertFalse(SemanticVersion("1.0.0")! < SemanticVersion("1.0.0")!)
    }

    func testRejectsInvalidVersions() {
        XCTAssertNil(SemanticVersion(""))
        XCTAssertNil(SemanticVersion("1.2.3.4"))
        XCTAssertNil(SemanticVersion("1.two.3"))
    }
}
