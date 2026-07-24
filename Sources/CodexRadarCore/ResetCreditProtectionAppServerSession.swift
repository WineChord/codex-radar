import Foundation

public final class ResetCreditProtectionAppServerSession:
    ResetCreditProtectionAppServerServing,
    @unchecked Sendable
{
    private let service: any ResetCreditProtectionAppServerServing
    private let shutdownOnce: ResetCreditProtectionAppServerShutdownOnce

    public init(
        service: any ResetCreditProtectionAppServerServing,
        shutdown: @escaping @Sendable () async -> Void = {}
    ) {
        self.service = service
        self.shutdownOnce = ResetCreditProtectionAppServerShutdownOnce(
            operation: shutdown
        )
    }

    public func readRateLimits() async throws -> RateLimitResponse {
        try await service.readRateLimits()
    }

    public func readAccount() async throws -> CodexAccountResponse {
        try await service.readAccount()
    }

    public func consumeResetCredit(
        creditID: String,
        idempotencyKey: String,
        authorization: ResetCreditProtectionDispatchAuthorization
    ) async throws -> ResetCreditConsumeResponse {
        try await service.consumeResetCredit(
            creditID: creditID,
            idempotencyKey: idempotencyKey,
            authorization: authorization
        )
    }

    public func shutdown() async {
        await shutdownOnce.run()
    }

    var underlyingService: any ResetCreditProtectionAppServerServing {
        service
    }
}

public struct ResetCreditProtectionAppServerSessionFactory: Sendable {
    private let makeSessionImplementation:
        @Sendable () -> ResetCreditProtectionAppServerSession

    public init(
        makeSession: @escaping @Sendable () -> ResetCreditProtectionAppServerSession
    ) {
        self.makeSessionImplementation = makeSession
    }

    public func makeSession() -> ResetCreditProtectionAppServerSession {
        makeSessionImplementation()
    }

    public static let live = ResetCreditProtectionAppServerSessionFactory {
        let client = CodexAppServerClient(allowsAutomaticRestart: false)
        return ResetCreditProtectionAppServerSession(
            service: client,
            shutdown: {
                await client.shutdown()
            }
        )
    }

    public static func shared(
        service: any ResetCreditProtectionAppServerServing,
        shutdown: @escaping @Sendable () async -> Void = {}
    ) -> ResetCreditProtectionAppServerSessionFactory {
        ResetCreditProtectionAppServerSessionFactory {
            ResetCreditProtectionAppServerSession(
                service: service,
                shutdown: shutdown
            )
        }
    }
}

private actor ResetCreditProtectionAppServerShutdownOnce {
    private let operation: @Sendable () async -> Void
    private var task: Task<Void, Never>?

    init(operation: @escaping @Sendable () async -> Void) {
        self.operation = operation
    }

    func run() async {
        if let task {
            await task.value
            return
        }
        let operation = self.operation
        let task = Task {
            await operation()
        }
        self.task = task
        await task.value
    }
}
