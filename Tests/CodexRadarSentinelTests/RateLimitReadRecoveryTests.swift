import XCTest
@testable import CodexRadarCore
@testable import CodexRadarSentinel

final class RateLimitReadRecoveryTests: XCTestCase {
    func testTransientNetworkFailureRetriesOnceAndRecovers() async throws {
        let service = RateLimitRecoveryTestService(
            failures: [
                .rpcError(
                    code: nil,
                    message: "failed to fetch codex rate limits: error sending request for url (https://chatgpt.com/backend-api/wham/usage)"
                ),
            ]
        )
        var observedDelay: UInt64?

        let response = try await RateLimitReadRecovery.read(
            from: service,
            sleep: { delay in
                observedDelay = delay
            }
        )

        XCTAssertEqual(response.rateLimits.planType, "pro")
        XCTAssertEqual(observedDelay, RateLimitReadRecovery.retryDelayNanoseconds)
        let readCount = await service.readCount
        XCTAssertEqual(readCount, 2)
    }

    func testAuthenticationFailureIsNotRetried() async throws {
        let service = RateLimitRecoveryTestService(
            failures: [
                .rpcError(
                    code: nil,
                    message: "codex account authentication required to read rate limits"
                ),
            ]
        )
        var slept = false

        do {
            _ = try await RateLimitReadRecovery.read(
                from: service,
                sleep: { _ in slept = true }
            )
            XCTFail("Expected the authentication error to be returned")
        } catch CodexAppServerClient.ClientError.rpcError(_, let message) {
            XCTAssertTrue(message.contains("authentication required"))
        }

        XCTAssertFalse(slept)
        let readCount = await service.readCount
        XCTAssertEqual(readCount, 1)
    }

    func testPersistentTransientFailureStopsAfterOneRetry() async throws {
        let failure = CodexAppServerClient.ClientError.rpcError(
            code: nil,
            message: "failed to fetch codex rate limits: error sending request for url (https://chatgpt.com/backend-api/wham/usage)"
        )
        let service = RateLimitRecoveryTestService(
            failures: [failure, failure]
        )

        do {
            _ = try await RateLimitReadRecovery.read(
                from: service,
                sleep: { _ in }
            )
            XCTFail("Expected the second network failure to be returned")
        } catch CodexAppServerClient.ClientError.rpcError(_, let message) {
            XCTAssertTrue(message.contains("failed to fetch codex rate limits"))
        }

        let readCount = await service.readCount
        XCTAssertEqual(readCount, 2)
    }

    func testCancellationDuringBackoffDoesNotSendAnotherRead() async throws {
        let service = RateLimitRecoveryTestService(
            failures: [.processUnavailable]
        )
        let task = Task {
            try await RateLimitReadRecovery.read(
                from: service,
                sleep: { _ in
                    try await Task.sleep(nanoseconds: 10_000_000_000)
                }
            )
        }
        while await service.readCount == 0 {
            try await Task.sleep(nanoseconds: 1_000_000)
        }

        task.cancel()
        do {
            _ = try await task.value
            XCTFail("Expected cancellation during retry backoff")
        } catch is CancellationError {
            // Expected.
        }

        let readCount = await service.readCount
        XCTAssertEqual(readCount, 1)
    }
}

private actor RateLimitRecoveryTestService:
    ResetCreditProtectionAppServerServing
{
    private var failures: [CodexAppServerClient.ClientError]
    private(set) var readCount = 0

    init(failures: [CodexAppServerClient.ClientError]) {
        self.failures = failures
    }

    func readRateLimits() async throws -> RateLimitResponse {
        readCount += 1
        if !failures.isEmpty {
            throw failures.removeFirst()
        }
        return RateLimitResponse(
            rateLimits: RateLimitSnapshot(
                limitId: AppConstants.codexLimitID,
                limitName: "Codex",
                primary: RateLimitWindow(
                    usedPercent: 2,
                    windowDurationMins: AppConstants.weeklyWindowMinutes,
                    resetsAt: nil
                ),
                secondary: nil,
                credits: nil,
                planType: "pro",
                rateLimitReachedType: nil
            ),
            rateLimitsByLimitId: nil,
            rateLimitResetCredits: nil
        )
    }

    func readAccount() async throws -> CodexAccountResponse {
        throw RateLimitRecoveryTestError.unexpectedCall
    }

    func consumeResetCredit(
        creditID: String,
        idempotencyKey: String,
        authorization: ResetCreditProtectionDispatchAuthorization
    ) async throws -> ResetCreditConsumeResponse {
        throw RateLimitRecoveryTestError.unexpectedCall
    }
}

private enum RateLimitRecoveryTestError: Error {
    case unexpectedCall
}
