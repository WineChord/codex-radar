import Foundation

public protocol ResetCreditProtectionReadOnlyAppServerServing: Sendable {
    func readRateLimits() async throws -> RateLimitResponse
    func readAccount() async throws -> CodexAccountResponse
}

public protocol ResetCreditProtectionAppServerServing:
    ResetCreditProtectionReadOnlyAppServerServing
{
    func consumeResetCredit(
        creditID: String,
        idempotencyKey: String,
        authorization: ResetCreditProtectionDispatchAuthorization
    ) async throws -> ResetCreditConsumeResponse
}

public enum ResetCreditProtectionAccountBindingError: LocalizedError, Equatable {
    case accountChanged
    case accountUnavailable
    case destructiveActionsDisabled

    public var errorDescription: String? {
        switch self {
        case .accountChanged:
            return "The Codex account changed during reset-credit protection"
        case .accountUnavailable:
            return "The current Codex account could not be verified"
        case .destructiveActionsDisabled:
            return "Destructive reset-credit actions are disabled in this runtime"
        }
    }
}

public struct ResetCreditProtectionBoundAppServer: Sendable {
    private let service: any ResetCreditProtectionAppServerServing
    private let destructiveActionsAllowed: Bool

    public init(
        service: any ResetCreditProtectionAppServerServing,
        destructiveActionsAllowed: Bool = true
    ) {
        self.service = service
        self.destructiveActionsAllowed = destructiveActionsAllowed
    }

    public func readRateLimits(
        boundTo accountFingerprint: String
    ) async throws -> RateLimitResponse {
        try await verifyAccount(accountFingerprint)
        let response = try await service.readRateLimits()
        try await verifyAccount(accountFingerprint)
        return response
    }

    public func consumeResetCredit(
        creditID: String,
        idempotencyKey: String,
        authorization: ResetCreditProtectionDispatchAuthorization,
        boundTo accountFingerprint: String
    ) async throws -> ResetCreditConsumeResponse {
        guard destructiveActionsAllowed else {
            throw ResetCreditProtectionAccountBindingError
                .destructiveActionsDisabled
        }
        try await verifyAccount(accountFingerprint)
        let result: Result<ResetCreditConsumeResponse, Error>
        do {
            result = .success(
                try await service.consumeResetCredit(
                    creditID: creditID,
                    idempotencyKey: idempotencyKey,
                    authorization: authorization
                )
            )
        } catch {
            result = .failure(error)
        }
        try await verifyAccount(accountFingerprint)
        return try result.get()
    }

    public func verifyAccount(_ accountFingerprint: String) async throws {
        let account = try await service.readAccount()
        guard let identitySeed = account.account?.protectionIdentitySeed else {
            throw ResetCreditProtectionAccountBindingError.accountUnavailable
        }
        guard ResetCreditPrivacy.fingerprint(identitySeed) == accountFingerprint else {
            throw ResetCreditProtectionAccountBindingError.accountChanged
        }
    }
}
