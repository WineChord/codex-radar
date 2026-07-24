import XCTest
@testable import CodexRadarCore

final class ResetCreditProtectionAppServerSessionTests: XCTestCase {
    func testConcurrentShutdownRunsOperationOnceAndEveryCallerWaits() async {
        let shutdownSpy = BlockingShutdownSpy()
        let completionCounter = CompletionCounter()
        let session = ResetCreditProtectionAppServerSession(
            service: OfflineAppServerStub(),
            shutdown: {
                await shutdownSpy.run()
            }
        )

        let callerCount = 32
        let tasks = (0..<callerCount).map { _ in
            Task {
                await session.shutdown()
                await completionCounter.increment()
            }
        }

        for _ in 0..<1_000 {
            if await shutdownSpy.callCount == 1 {
                break
            }
            await Task.yield()
        }

        let callsBeforeRelease = await shutdownSpy.callCount
        let completionsBeforeRelease = await completionCounter.value
        XCTAssertEqual(callsBeforeRelease, 1)
        XCTAssertEqual(completionsBeforeRelease, 0)

        await shutdownSpy.release()
        for task in tasks {
            await task.value
        }

        let callsAfterRelease = await shutdownSpy.callCount
        let completionsAfterRelease = await completionCounter.value
        XCTAssertEqual(callsAfterRelease, 1)
        XCTAssertEqual(completionsAfterRelease, callerCount)

        await session.shutdown()
        let callsAfterRepeatedShutdown = await shutdownSpy.callCount
        XCTAssertEqual(callsAfterRepeatedShutdown, 1)
    }

    func testSharedFactoryWrapsAnExistingServiceWithNoOpShutdown() async {
        let service = OfflineAppServerStub()
        let factory = ResetCreditProtectionAppServerSessionFactory.shared(
            service: service
        )

        let first = factory.makeSession()
        let second = factory.makeSession()

        XCTAssertTrue(first.underlyingService as AnyObject === service)
        XCTAssertTrue(second.underlyingService as AnyObject === service)
        await first.shutdown()
        await second.shutdown()
    }

    func testLiveFactoryCreatesAnIndependentClientForEverySession() async throws {
        let first = ResetCreditProtectionAppServerSessionFactory.live.makeSession()
        let second = ResetCreditProtectionAppServerSessionFactory.live.makeSession()
        let firstClient = try XCTUnwrap(
            first.underlyingService as? CodexAppServerClient
        )
        let secondClient = try XCTUnwrap(
            second.underlyingService as? CodexAppServerClient
        )

        XCTAssertFalse(firstClient === secondClient)

        await first.shutdown()
        await second.shutdown()
    }
}

private actor BlockingShutdownSpy {
    private(set) var callCount = 0
    private var isReleased = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func run() async {
        callCount += 1
        guard !isReleased else {
            return
        }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func release() {
        isReleased = true
        let pending = waiters
        waiters.removeAll()
        for continuation in pending {
            continuation.resume()
        }
    }
}

private actor CompletionCounter {
    private(set) var value = 0

    func increment() {
        value += 1
    }
}

private actor OfflineAppServerStub: ResetCreditProtectionAppServerServing {
    private enum StubError: Error {
        case unexpectedCall
    }

    func readRateLimits() async throws -> RateLimitResponse {
        throw StubError.unexpectedCall
    }

    func readAccount() async throws -> CodexAccountResponse {
        throw StubError.unexpectedCall
    }

    func consumeResetCredit(
        creditID: String,
        idempotencyKey: String,
        authorization: ResetCreditProtectionDispatchAuthorization
    ) async throws -> ResetCreditConsumeResponse {
        throw StubError.unexpectedCall
    }
}
