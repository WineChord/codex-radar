import Foundation
import XCTest
@testable import CodexRadarCore

final class QuotaHistoryTests: XCTestCase {
    func testRecordingKeepsChangesResetBoundariesAndFiveMinuteHeartbeats() {
        let start = date(0)
        let firstReset = date(7 * 86_400)
        let secondReset = date(14 * 86_400)
        var timeline = QuotaHistoryTimeline()

        XCTAssertTrue(timeline.record(
            sample(at: start, remaining: 90, resetsAt: firstReset),
            endingAt: start
        ))
        XCTAssertFalse(timeline.record(
            sample(at: date(60), remaining: 90, resetsAt: firstReset),
            endingAt: date(60)
        ))
        XCTAssertTrue(timeline.record(
            sample(at: date(120), remaining: 89.7, resetsAt: firstReset),
            endingAt: date(120)
        ))
        XCTAssertFalse(timeline.record(
            sample(at: date(180), remaining: 89.6, resetsAt: firstReset),
            endingAt: date(180)
        ))
        XCTAssertTrue(timeline.record(
            sample(at: date(420), remaining: 89.6, resetsAt: firstReset),
            endingAt: date(420)
        ))
        XCTAssertTrue(timeline.record(
            sample(at: date(480), remaining: 89.6, resetsAt: secondReset),
            endingAt: date(480)
        ))

        XCTAssertEqual(
            timeline.samples.map(\.timestamp),
            [start, date(120), date(420), date(480)]
        )
    }

    func testRecordingRejectsInvalidAndOutOfOrderSamples() {
        let start = date(100)
        var timeline = QuotaHistoryTimeline(
            samples: [sample(at: start, remaining: 80)]
        )

        XCTAssertFalse(timeline.record(
            sample(at: date(99), remaining: 79),
            endingAt: date(101)
        ))
        XCTAssertFalse(timeline.record(
            sample(at: date(101), remaining: 101),
            endingAt: date(101)
        ))
        XCTAssertFalse(timeline.record(
            sample(at: date(10_000), remaining: 79),
            endingAt: date(101)
        ))
        XCTAssertEqual(timeline.samples.count, 1)
    }

    func testRetentionKeepsOnlyThirtyOneDays() {
        let now = date(40 * 86_400)
        var timeline = QuotaHistoryTimeline(
            samples: [
                sample(at: date(0), remaining: 100),
                sample(at: date(8 * 86_400), remaining: 80),
                sample(at: date(9 * 86_400), remaining: 70),
                sample(at: now, remaining: 60),
            ]
        )

        timeline.prune(endingAt: now)

        XCTAssertEqual(
            timeline.samples.map(\.timestamp),
            [date(9 * 86_400), now]
        )
    }

    func testResetDetectionRequiresAResetBoundaryOrLargeRestore() {
        let now = date(10_000)
        let oldReset = date(20_000)
        let newReset = date(20_000 + 7 * 86_400)
        let timeline = QuotaHistoryTimeline(samples: [
            QuotaHistorySample(
                timestamp: date(9_600),
                remainingPercent: 25,
                resetsAt: oldReset
            ),
            QuotaHistorySample(
                timestamp: date(9_700),
                remainingPercent: 31,
                resetsAt: oldReset
            ),
            QuotaHistorySample(
                timestamp: date(9_800),
                remainingPercent: 37,
                resetsAt: newReset
            ),
            QuotaHistorySample(
                timestamp: date(9_900),
                remainingPercent: 92,
                resetsAt: newReset
            ),
        ])

        let events = timeline.resetEvents(
            in: .hours24,
            endingAt: now
        )

        XCTAssertEqual(events.count, 2)
        XCTAssertEqual(events[0].timestamp, date(9_800))
        XCTAssertEqual(events[0].increase, 6, accuracy: 0.001)
        XCTAssertEqual(events[1].timestamp, date(9_900))
        XCTAssertEqual(events[1].increase, 55, accuracy: 0.001)
    }

    func testSummaryCountsObservedConsumptionWithoutSubtractingResets() {
        let now = date(10_000)
        let timeline = QuotaHistoryTimeline(samples: [
            sample(at: date(9_600), remaining: 90),
            sample(at: date(9_700), remaining: 70),
            sample(at: date(9_800), remaining: 100),
            sample(at: date(9_900), remaining: 92),
        ])

        let summary = timeline.summary(
            in: .hours24,
            endingAt: now
        )

        XCTAssertEqual(summary.observedConsumption, 28, accuracy: 0.001)
        XCTAssertEqual(summary.resetCount, 1)
        XCTAssertEqual(summary.sampleCount, 4)
    }

    func testNearestSampleSelectsClosestVisiblePoint() {
        let now = date(10_000)
        let timeline = QuotaHistoryTimeline(samples: [
            sample(at: date(9_700), remaining: 80),
            sample(at: date(9_800), remaining: 70),
            sample(at: date(9_900), remaining: 60),
        ])

        XCTAssertEqual(
            timeline.nearestSample(
                to: date(9_760),
                in: .hours24,
                endingAt: now
            )?.timestamp,
            date(9_800)
        )
        XCTAssertEqual(
            timeline.nearestSample(
                to: date(9_740),
                in: .hours24,
                endingAt: now
            )?.timestamp,
            date(9_700)
        )
    }

    func testDownsamplingKeepsExtremaEndpointsAndResetSamples() {
        let now = date(86_400)
        var samples: [QuotaHistorySample] = []
        for index in 0..<120 {
            let remaining = index == 40
                ? 12.0
                : (index == 41 ? 100.0 : 80.0 - Double(index) * 0.1)
            samples.append(
                sample(
                    at: date(Double(index) * 60),
                    remaining: remaining
                )
            )
        }
        let timeline = QuotaHistoryTimeline(samples: samples)

        let display = timeline.displaySamples(
            in: .hours24,
            endingAt: now
        )

        XCTAssertTrue(display.contains { $0.timestamp == date(0) })
        XCTAssertTrue(display.contains { $0.timestamp == date(40 * 60) })
        XCTAssertTrue(display.contains { $0.timestamp == date(41 * 60) })
        XCTAssertTrue(display.contains { $0.timestamp == date(119 * 60) })
        XCTAssertLessThan(display.count, samples.count)
    }

    func testStoreRoundTripsAndRefusesToOverwriteCorruptArchive() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "quota-history-tests-\(UUID().uuidString)",
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: false
        )
        defer {
            try? FileManager.default.removeItem(at: directory)
        }
        let url = directory.appendingPathComponent("history.json")
        let store = QuotaHistoryStore(url: url)
        let now = date(10_000)

        let result = try store.record(
            sample(at: now, remaining: 64),
            endingAt: now
        )
        XCTAssertTrue(result.didChange)
        XCTAssertEqual(
            store.load(endingAt: now),
            .loaded(result.timeline)
        )
        let permissions = try XCTUnwrap(
            FileManager.default.attributesOfItem(
                atPath: url.path
            )[.posixPermissions] as? NSNumber
        )
        XCTAssertEqual(permissions.intValue & 0o777, 0o600)
        let directoryPermissions = try XCTUnwrap(
            FileManager.default.attributesOfItem(
                atPath: directory.path
            )[.posixPermissions] as? NSNumber
        )
        XCTAssertEqual(directoryPermissions.intValue & 0o777, 0o700)
        let lockURL = url
            .deletingPathExtension()
            .appendingPathExtension("lock")
        let lockPermissions = try XCTUnwrap(
            FileManager.default.attributesOfItem(
                atPath: lockURL.path
            )[.posixPermissions] as? NSNumber
        )
        XCTAssertEqual(lockPermissions.intValue & 0o777, 0o600)

        try Data("not-json".utf8).write(to: url)
        XCTAssertEqual(store.load(endingAt: now), .corrupt)
        XCTAssertThrowsError(
            try store.record(
                sample(at: date(10_100), remaining: 63),
                endingAt: date(10_100)
            )
        )
        XCTAssertEqual(
            try Data(contentsOf: url),
            Data("not-json".utf8)
        )
    }

    private func date(_ offset: TimeInterval) -> Date {
        Date(timeIntervalSince1970: 1_700_000_000 + offset)
    }

    private func sample(
        at timestamp: Date,
        remaining: Double,
        resetsAt: Date? = nil
    ) -> QuotaHistorySample {
        QuotaHistorySample(
            timestamp: timestamp,
            remainingPercent: remaining,
            resetsAt: resetsAt
        )
    }
}
