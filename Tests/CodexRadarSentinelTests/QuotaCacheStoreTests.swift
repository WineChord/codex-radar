import Foundation
import XCTest
@testable import CodexRadarCore
@testable import CodexRadarSentinel

final class QuotaCacheStoreTests: XCTestCase {
    func testQuotaSurvivesRestartAndAtomicReplacementWithPrivatePermissions() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("quota.json")
        let cache = QuotaCacheStore(url: url)
        XCTAssertNil(try cache.load())
        let quota = try XCTUnwrap(DashboardPreviewFactory.state(
            for: .resetConfirmed, live: DashboardState()
        ).rateLimits)
        let firstDate = Date().addingTimeInterval(-120)
        try cache.save(.init(quota: quota, updatedAt: firstDate))
        XCTAssertEqual(try QuotaCacheStore(url: url).load(), .init(quota: quota, updatedAt: firstDate))

        let nextDate = firstDate.addingTimeInterval(60)
        try cache.save(.init(quota: quota, updatedAt: nextDate))
        XCTAssertEqual(try QuotaCacheStore(url: url).load()?.updatedAt, nextDate)
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path), ["quota.json"])
        let contents = try String(contentsOf: url)
        XCTAssertFalse(contents.contains("rateLimitResetCredits"))
        XCTAssertFalse(contents.contains("token"))
    }

    func testCorruptUnsupportedOversizedAndFutureArchivesCannotBecomeReadings() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = QuotaCacheStore(url: directory.appendingPathComponent("quota.json"))
        try Data("broken".utf8).write(to: cache.url)
        XCTAssertThrowsError(try cache.load())
        try Data(repeating: 32, count: 256 * 1024 + 1).write(to: cache.url)
        XCTAssertThrowsError(try cache.load())
        let quota = try XCTUnwrap(DashboardPreviewFactory.state(
            for: .resetConfirmed, live: DashboardState()
        ).rateLimits)
        let date = Date()
        try cache.save(.init(quota: quota, updatedAt: date.addingTimeInterval(600)))
        XCTAssertThrowsError(try cache.load(now: date))
        try cache.save(.init(quota: quota, updatedAt: date))
        let encoded = try String(contentsOf: cache.url).replacingOccurrences(of: "\"version\":1", with: "\"version\":99")
        try Data(encoded.utf8).write(to: cache.url)
        XCTAssertThrowsError(try cache.load())
        // A fresh successful read can replace a broken archive.
        try cache.save(.init(quota: quota, updatedAt: date))
        XCTAssertEqual(try cache.load(now: date)?.quota, quota)
    }
}
