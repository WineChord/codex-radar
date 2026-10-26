import XCTest
@testable import CodexRadarCore

final class QuotaDepletionForecastTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func sample(minutesAgo: Double, remaining: Double, reset: Date? = nil) -> QuotaHistorySample {
        QuotaHistorySample(
            timestamp: now.addingTimeInterval(-minutesAgo * 60),
            remainingPercent: remaining,
            resetsAt: reset ?? now.addingTimeInterval(7 * 86_400)
        )
    }

    private func history(current: Double, rate: Double = 6) -> [QuotaHistorySample] {
        stride(from: 300, through: 0, by: -5).map {
            sample(minutesAgo: Double($0), remaining: current + Double($0) / 60 * rate)
        }
    }

    func testEachWindowUsesItsOwnConsumptionRate() throws {
        let current = sample(minutesAgo: 0, remaining: 15)
        let samples = stride(from: 300, through: 0, by: -5).map { minutes -> QuotaHistorySample in
            let hours = Double(minutes) / 60
            let consumed = min(hours, 0.5) * 6
                + min(max(hours - 0.5, 0), 0.5) * 4
                + min(max(hours - 1, 0), 1) * 2
                + max(hours - 2, 0)
            return sample(minutesAgo: Double(minutes), remaining: 15 + consumed)
        }
        let estimates = QuotaDepletionForecast.estimates(timeline: .init(samples: samples), current: current)
        XCTAssertEqual(estimates.map(\.window), [.minutes30, .hour1, .hours2, .hours5])
        for (estimate, expectedRate) in zip(estimates, [6.0, 5, 3.5, 2]) {
            XCTAssertEqual(try XCTUnwrap(estimate.hourlyConsumption), expectedRate, accuracy: 0.00001)
            guard case .depletes(let at) = estimate.outcome else { return XCTFail("Expected a depletion date") }
            XCTAssertEqual(at.timeIntervalSince(now), 15 / expectedRate * 3600, accuracy: 0.001)
        }
    }

    func testWindowBoundaryIsInterpolatedInsteadOfRoundedToASample() throws {
        let samples = [35.0, 25, 15, 5, 0].map {
            sample(minutesAgo: $0, remaining: 40 + $0 / 60 * 2)
        }
        let estimate = QuotaDepletionForecast.estimates(timeline: .init(samples: samples), current: samples.last!)[0]
        XCTAssertEqual(try XCTUnwrap(estimate.hourlyConsumption), 2, accuracy: 0.00001)
        XCTAssertEqual(estimate.outcome, .depletes(at: now.addingTimeInterval(20 * 3600)))
    }

    func testPartialWindowsUseActualElapsedTimeWithoutDilutingConsumption() throws {
        let current = sample(minutesAgo: 0, remaining: 40)
        let timeline = QuotaHistoryTimeline(samples: [sample(minutesAgo: 29, remaining: 43), current])
        for estimate in QuotaDepletionForecast.estimates(timeline: timeline, current: current) {
            XCTAssertEqual(try XCTUnwrap(estimate.hourlyConsumption), 3 * 60 / 29, accuracy: 0.00001)
            XCTAssertEqual(estimate.observationDuration, 29 * 60)
            guard case .depletes = estimate.outcome else { return XCTFail("Expected an estimate from partial history") }
        }
    }

    func testTooLittleHistoryAndSingleReadingsWaitForAnotherPoll() {
        let current = sample(minutesAgo: 0, remaining: 40)
        for samples in [[current], [sample(minutesAgo: 0.5, remaining: 41), current]] {
            XCTAssertTrue(QuotaDepletionForecast.estimates(timeline: .init(samples: samples), current: current)
                .allSatisfy { $0.outcome == .insufficientData })
        }
        let samples = [sample(minutesAgo: 1, remaining: 40.1), current]
        XCTAssertTrue(QuotaDepletionForecast.estimates(timeline: .init(samples: samples), current: current)
            .allSatisfy { $0.hourlyConsumption != nil })
    }

    func testRefillAndResetBoundaryExcludeEarlierConsumption() {
        let current = sample(minutesAgo: 0, remaining: 60)
        var samples = history(current: 60)
        samples = samples.map { reading in
            if reading.timestamp < now.addingTimeInterval(-45 * 60) {
                return QuotaHistorySample(timestamp: reading.timestamp, remainingPercent: 20, resetsAt: reading.resetsAt)
            }
            return reading
        }
        let estimates = QuotaDepletionForecast.estimates(timeline: .init(samples: samples), current: current)
        XCTAssertEqual(estimates[0].hourlyConsumption, 6)
        XCTAssertTrue(estimates.dropFirst().allSatisfy {
            $0.hourlyConsumption == 6 && $0.observationDuration == 45 * 60
        })

        let changedBoundary = history(current: 60).map { reading in
            QuotaHistorySample(timestamp: reading.timestamp, remainingPercent: reading.remainingPercent,
                resetsAt: reading.timestamp < now.addingTimeInterval(-45 * 60)
                    ? now.addingTimeInterval(86_400) : current.resetsAt)
        }
        let changed = QuotaDepletionForecast.estimates(timeline: .init(samples: changedBoundary), current: current)
        XCTAssertTrue(changed.dropFirst().allSatisfy {
            $0.hourlyConsumption == 6 && $0.observationDuration == 45 * 60
        })
    }

    func testGapsWithinTheWindowAreInterpolated() {
        let current = sample(minutesAgo: 0, remaining: 40)
        let samples = history(current: 40).filter {
            let age = now.timeIntervalSince($0.timestamp) / 60
            return age <= 60 || age >= 100
        }
        let estimates = QuotaDepletionForecast.estimates(timeline: .init(samples: samples), current: current)
        XCTAssertEqual(estimates[0].hourlyConsumption, 6)
        XCTAssertEqual(estimates[1].hourlyConsumption, 6)
        XCTAssertEqual(estimates[2].hourlyConsumption, 6)
        XCTAssertEqual(estimates[3].hourlyConsumption, 6)
    }

    func testSparseReadingsInterpolateInsideMultiHourGaps() throws {
        let samples = [sample(minutesAgo: 300, remaining: 80),
                       sample(minutesAgo: 95, remaining: 55), sample(minutesAgo: 0, remaining: 50)]
        let estimates = QuotaDepletionForecast.estimates(timeline: .init(samples: samples), current: samples.last!)
        let expectedRates = [5 * 60.0 / 95, 5 * 60.0 / 95, (5 + 25 * 25.0 / 205) / 2, 6]
        for (estimate, expected) in zip(estimates, expectedRates) {
            XCTAssertEqual(try XCTUnwrap(estimate.hourlyConsumption), expected, accuracy: 0.00001)
        }
    }

    func testOvernightGapsUseOnlyTheNewReadings() throws {
        let current = sample(minutesAgo: 0, remaining: 40)
        let samples = [sample(minutesAgo: 400, remaining: 80),
                       sample(minutesAgo: 10, remaining: 41), current]
        for estimate in QuotaDepletionForecast.estimates(timeline: .init(samples: samples), current: current) {
            XCTAssertEqual(try XCTUnwrap(estimate.hourlyConsumption), 6, accuracy: 0.00001)
            XCTAssertEqual(estimate.observationDuration, 10 * 60)
        }
    }

    func testAnUnobservedResetCannotBeBridged() {
        let reset = now.addingTimeInterval(-15 * 60)
        let samples = [sample(minutesAgo: 60, remaining: 90, reset: reset),
                       sample(minutesAgo: 10, remaining: 41), sample(minutesAgo: 0, remaining: 40)]
        let estimates = QuotaDepletionForecast.estimates(timeline: .init(samples: samples), current: samples.last!)
        XCTAssertTrue(estimates.allSatisfy { $0.hourlyConsumption == 6 && $0.observationDuration == 600 })
    }

    func testZeroConsumptionEmptyQuotaAndResetBeforeDepletionAreDistinct() {
        let idle = history(current: 50, rate: 0)
        for readings in [idle, [sample(minutesAgo: 10, remaining: 50), idle.last!]] {
            XCTAssertTrue(QuotaDepletionForecast.estimates(timeline: .init(samples: readings), current: readings.last!)
                .allSatisfy { $0.outcome == .noConsumption && $0.hourlyConsumption == 0 })
        }
        XCTAssertTrue(QuotaDepletionForecast.estimates(timeline: .init(), current: sample(minutesAgo: 0, remaining: 0))
            .allSatisfy { $0.outcome == .alreadyDepleted })
        let reset = now.addingTimeInterval(3600)
        let slow = history(current: 50, rate: 1).map {
            QuotaHistorySample(timestamp: $0.timestamp, remainingPercent: $0.remainingPercent, resetsAt: reset)
        }
        XCTAssertTrue(QuotaDepletionForecast.estimates(timeline: .init(samples: slow), current: slow.last!)
            .allSatisfy { $0.outcome == .resetsFirst })
    }

    func testFutureSamplesDoNotAffectTheCurrentForecastAndInvalidReadingsAreRejected() {
        let current = sample(minutesAgo: 0, remaining: 50)
        var samples = history(current: 50)
        samples.append(sample(minutesAgo: -5, remaining: 0))
        let estimates = QuotaDepletionForecast.estimates(timeline: .init(samples: samples), current: current)
        XCTAssertTrue(estimates.allSatisfy { $0.hourlyConsumption == 6 })
        let invalid = sample(minutesAgo: 0, remaining: .nan)
        XCTAssertTrue(QuotaDepletionForecast.estimates(timeline: .init(samples: samples), current: invalid)
            .allSatisfy { $0.outcome == .insufficientData })
    }
}
