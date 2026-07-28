import CryptoKit
import Darwin
import Foundation

public struct CodexAccountResponse: Decodable, Equatable {
    public let account: CodexAccount?
    public let requiresOpenaiAuth: Bool
}

public struct CodexAccount: Decodable, Equatable {
    public let type: String
    public let email: String?
    public let planType: String?

    public var protectionIdentitySeed: String? {
        guard type == "chatgpt",
              let email = email?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              !email.isEmpty else {
            return nil
        }
        return "chatgpt:\(email)"
    }
}

public enum ResetCreditPrivacy {
    public static func fingerprint(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }

    public static func isValidFingerprint(_ value: String) -> Bool {
        value.utf8.count == 64
            && value.utf8.allSatisfy {
                ($0 >= 48 && $0 <= 57) || ($0 >= 97 && $0 <= 102)
            }
    }
}

public struct ResetCreditProtectionClockSample: Codable, Equatable {
    public let wallTime: Date
    public let continuousTimeSeconds: TimeInterval

    public init(
        wallTime: Date,
        continuousTimeSeconds: TimeInterval
    ) {
        self.wallTime = wallTime
        self.continuousTimeSeconds = continuousTimeSeconds
    }

    public static func now(wallTime: Date = Date()) -> Self {
        var timebase = mach_timebase_info_data_t()
        guard mach_timebase_info(&timebase) == KERN_SUCCESS,
              timebase.denom != 0 else {
            return Self(
                wallTime: wallTime,
                continuousTimeSeconds: .nan
            )
        }
        let nanoseconds = Double(mach_continuous_time())
            * Double(timebase.numer)
            / Double(timebase.denom)
        return Self(
            wallTime: wallTime,
            continuousTimeSeconds: nanoseconds / 1_000_000_000
        )
    }
}

public struct ResetCreditProtectionTarget: Equatable {
    public let creditID: String
    public let creditFingerprint: String
    public let idSuffix: String
    public let expiresAt: Date
    public let actionAt: Date
    public let availableCount: Int

    public init(
        creditID: String,
        creditFingerprint: String,
        idSuffix: String,
        expiresAt: Date,
        actionAt: Date,
        availableCount: Int
    ) {
        self.creditID = creditID
        self.creditFingerprint = creditFingerprint
        self.idSuffix = idSuffix
        self.expiresAt = expiresAt
        self.actionAt = actionAt
        self.availableCount = availableCount
    }
}

public enum ResetCreditProtectionDecision: Equatable {
    case noCredits
    case detailsUnavailable(availableCount: Int)
    case detailsIncomplete(availableCount: Int, availableDetails: Int)
    case noSupportedExpiringCredits(availableCount: Int)
    case scheduled(ResetCreditProtectionTarget)
    case ready(ResetCreditProtectionTarget)
}

public struct ResetCreditExpiryProtectionPolicy {
    public let leadTime: TimeInterval

    public init(leadTime: TimeInterval = AppConstants.resetCreditProtectionLeadTimeSeconds) {
        self.leadTime = leadTime
    }

    public func decision(
        summary: RateLimitResetCreditsSummary,
        now: Date = Date(),
        excludingCreditFingerprints: Set<String> = []
    ) -> ResetCreditProtectionDecision {
        let availableCount = max(0, summary.availableCount)
        guard availableCount > 0 else {
            return .noCredits
        }
        guard let details = summary.credits else {
            return .detailsUnavailable(availableCount: availableCount)
        }

        let available = details.filter(\.isAvailable)
        let uniqueAvailableIDs = Set(available.map(\.id))
        guard available.count == availableCount,
              available.allSatisfy({ !$0.id.isEmpty }),
              uniqueAvailableIDs.count == availableCount else {
            return .detailsIncomplete(
                availableCount: availableCount,
                availableDetails: uniqueAvailableIDs.count
            )
        }

        let eligible = available.compactMap { credit -> (RateLimitResetCredit, Date)? in
            guard !credit.id.isEmpty,
                  !excludingCreditFingerprints.contains(
                      ResetCreditPrivacy.fingerprint(credit.id)
                  ),
                  credit.isSupportedCodexReset,
                  let expiresAt = credit.expiresAtDate,
                  expiresAt > now else {
                return nil
            }
            return (credit, expiresAt)
        }
        guard let selected = eligible.min(by: { lhs, rhs in
            if lhs.1 != rhs.1 {
                return lhs.1 < rhs.1
            }
            return lhs.0.id < rhs.0.id
        }) else {
            return .noSupportedExpiringCredits(availableCount: availableCount)
        }

        let actionAt = selected.1.addingTimeInterval(-leadTime)
        let target = ResetCreditProtectionTarget(
            creditID: selected.0.id,
            creditFingerprint: ResetCreditPrivacy.fingerprint(selected.0.id),
            idSuffix: String(selected.0.id.suffix(6)),
            expiresAt: selected.1,
            actionAt: actionAt,
            availableCount: availableCount
        )
        return now >= actionAt ? .ready(target) : .scheduled(target)
    }
}

public struct ResetCreditProtectionConsent: Codable, Equatable {
    public let version: Int
    public let accountFingerprint: String
    public let authorizationID: String
    public let grantedAt: Date
    public let authorizedCreditFingerprints: Set<String>
    public let clockAnchor: ResetCreditProtectionClockSample

    public init(
        version: Int,
        accountFingerprint: String,
        authorizationID: String = UUID().uuidString,
        grantedAt: Date,
        authorizedCreditFingerprints: Set<String> = [],
        clockAnchor: ResetCreditProtectionClockSample = .now()
    ) {
        self.version = version
        self.accountFingerprint = accountFingerprint
        self.authorizationID = authorizationID
        self.grantedAt = grantedAt
        self.authorizedCreditFingerprints = authorizedCreditFingerprints
        self.clockAnchor = clockAnchor
    }
}

public enum ResetCreditProtectionAuthorization {
    public static let clockToleranceSeconds: TimeInterval = 5

    public enum ClockDiscontinuityReason: Equatable {
        case wallClockOffset(seconds: TimeInterval)
        case continuousClockReset
        case invalidSample
    }

    static func isStructurallyValid(
        consent: ResetCreditProtectionConsent?
    ) -> Bool {
        consent?.version == AppConstants.resetCreditProtectionConsentVersion
            && consent?.accountFingerprint.isEmpty == false
            && UUID(uuidString: consent?.authorizationID ?? "") != nil
            && consent?.authorizedCreditFingerprints.isEmpty == false
            && consent?.authorizedCreditFingerprints.allSatisfy(
                ResetCreditPrivacy.isValidFingerprint
            ) == true
            && consent?.clockAnchor.wallTime
                .timeIntervalSinceReferenceDate.isFinite == true
            && consent?.clockAnchor.continuousTimeSeconds.isFinite == true
            && (consent?.clockAnchor.continuousTimeSeconds ?? -1) >= 0
    }

    public static func isClockContinuous(
        consent: ResetCreditProtectionConsent?,
        current: ResetCreditProtectionClockSample = .now()
    ) -> Bool {
        clockDiscontinuityReason(consent: consent, current: current) == nil
    }

    public static func clockDiscontinuityReason(
        consent: ResetCreditProtectionConsent?,
        current: ResetCreditProtectionClockSample = .now()
    ) -> ClockDiscontinuityReason? {
        guard isStructurallyValid(consent: consent),
              let anchor = consent?.clockAnchor else {
            return .invalidSample
        }
        return clockDiscontinuityReason(
            anchor: anchor,
            current: current
        )
    }

    public static func clockDiscontinuityReason(
        anchor: ResetCreditProtectionClockSample,
        current: ResetCreditProtectionClockSample = .now()
    ) -> ClockDiscontinuityReason? {
        guard anchor.wallTime.timeIntervalSinceReferenceDate.isFinite,
              anchor.continuousTimeSeconds.isFinite,
              anchor.continuousTimeSeconds >= 0,
              current.wallTime.timeIntervalSinceReferenceDate.isFinite,
              current.continuousTimeSeconds.isFinite,
              current.continuousTimeSeconds >= 0 else {
            return .invalidSample
        }
        let continuousElapsed = current.continuousTimeSeconds
            - anchor.continuousTimeSeconds
        guard continuousElapsed >= 0 else {
            return .continuousClockReset
        }
        let wallElapsed = current.wallTime.timeIntervalSince(anchor.wallTime)
        let offset = wallElapsed - continuousElapsed
        guard abs(offset) <= clockToleranceSeconds else {
            return .wallClockOffset(seconds: offset)
        }
        return nil
    }

    public static func isEnabled(
        requested: Bool?,
        consent: ResetCreditProtectionConsent?,
        currentClock: ResetCreditProtectionClockSample = .now()
    ) -> Bool {
        requested == true
            && isStructurallyValid(consent: consent)
            && isClockContinuous(consent: consent, current: currentClock)
    }

    public static func authorizes(
        requested: Bool?,
        consent: ResetCreditProtectionConsent?,
        creditFingerprint: String
    ) -> Bool {
        isEnabled(requested: requested, consent: consent)
            && ResetCreditPrivacy.isValidFingerprint(creditFingerprint)
            && consent?.authorizedCreditFingerprints.contains(creditFingerprint) == true
    }

    public static func authorizes(
        requested: Bool?,
        consent: ResetCreditProtectionConsent?,
        target: ResetCreditProtectionTarget
    ) -> Bool {
        authorizes(
            requested: requested,
            consent: consent,
            creditFingerprint: target.creditFingerprint
        )
    }
}

public struct ResetCreditProtectionAttemptJournal: Codable, Equatable {
    public enum Phase: String, Codable {
        case sending
        case sentUnknown
        case outcomeConfirmed
    }

    public let version: Int
    public let accountFingerprint: String
    public let creditFingerprint: String
    public let idempotencyKey: String
    public let expiresAt: Date
    public let availableCountBefore: Int
    public var phase: Phase
    public var confirmedOutcome: ResetCreditConsumeOutcome?
    public var updatedAt: Date

    public init(
        version: Int = AppConstants.resetCreditProtectionJournalVersion,
        accountFingerprint: String,
        creditFingerprint: String,
        idempotencyKey: String,
        expiresAt: Date,
        availableCountBefore: Int,
        phase: Phase,
        confirmedOutcome: ResetCreditConsumeOutcome? = nil,
        updatedAt: Date
    ) {
        self.version = version
        self.accountFingerprint = accountFingerprint
        self.creditFingerprint = creditFingerprint
        self.idempotencyKey = idempotencyKey
        self.expiresAt = expiresAt
        self.availableCountBefore = availableCountBefore
        self.phase = phase
        self.confirmedOutcome = confirmedOutcome
        self.updatedAt = updatedAt
    }
}

public struct ResetCreditProtectionTombstone: Codable, Equatable {
    public enum Disposition: String, Codable {
        case confirmedUsed
        case ambiguous
    }

    public let accountFingerprint: String
    public let creditFingerprint: String
    public let idempotencyKey: String
    public let expiresAt: Date
    public let disposition: Disposition
    public let terminalAt: Date

    public init(
        accountFingerprint: String,
        creditFingerprint: String,
        idempotencyKey: String,
        expiresAt: Date,
        disposition: Disposition,
        terminalAt: Date
    ) {
        self.accountFingerprint = accountFingerprint
        self.creditFingerprint = creditFingerprint
        self.idempotencyKey = idempotencyKey
        self.expiresAt = expiresAt
        self.disposition = disposition
        self.terminalAt = terminalAt
    }

    public init(
        journal: ResetCreditProtectionAttemptJournal,
        disposition: Disposition,
        terminalAt: Date = Date()
    ) {
        self.init(
            accountFingerprint: journal.accountFingerprint,
            creditFingerprint: journal.creditFingerprint,
            idempotencyKey: journal.idempotencyKey,
            expiresAt: journal.expiresAt,
            disposition: disposition,
            terminalAt: terminalAt
        )
    }
}

public struct ResetCreditProtectionLedger: Codable, Equatable {
    public let version: Int
    public var activeAttempt: ResetCreditProtectionAttemptJournal?
    public var tombstones: [ResetCreditProtectionTombstone]

    public init(
        version: Int = AppConstants.resetCreditProtectionLedgerVersion,
        activeAttempt: ResetCreditProtectionAttemptJournal? = nil,
        tombstones: [ResetCreditProtectionTombstone] = []
    ) {
        self.version = version
        self.activeAttempt = activeAttempt
        self.tombstones = tombstones
    }

    public var excludedCreditFingerprints: Set<String> {
        Set(tombstones.map(\.creditFingerprint))
    }
}

public enum ResetCreditProtectionRecoveryDecision: Equatable {
    case confirmedUsed
    case confirmedNotConsumed(expiresAt: Date)
    case reconciling
    case missed
    case retry(ResetCreditProtectionTarget)
}

public struct ResetCreditProtectionRecoveryPolicy {
    public init() {}

    public func decision(
        journal: ResetCreditProtectionAttemptJournal,
        summary: RateLimitResetCreditsSummary?,
        now: Date = Date(),
        protectionEnabled: Bool,
        retryAt: Date?
    ) -> ResetCreditProtectionRecoveryDecision {
        if journal.phase == .outcomeConfirmed {
            switch journal.confirmedOutcome {
            case .reset, .alreadyRedeemed:
                return .confirmedUsed
            case .nothingToReset, .noCredit:
                break
            case .none:
                return .reconciling
            }
        }
        guard let summary else {
            return now >= journal.expiresAt
                ? .missed
                : .reconciling
        }
        guard let details = summary.credits else {
            return now >= journal.expiresAt
                ? .missed
                : .reconciling
        }

        let matching = details.filter {
            ResetCreditPrivacy.fingerprint($0.id) == journal.creditFingerprint
        }
        if matching.count == 1, let credit = matching.first {
            switch credit.status {
            case "redeemed":
                return .confirmedUsed
            case "redeeming":
                return now >= journal.expiresAt ? .missed : .reconciling
            case "available":
                let availableIDs = details.filter(\.isAvailable).map(\.id)
                let uniqueAvailableIDs = Set(availableIDs)
                guard credit.isSupportedCodexReset,
                      let expiresAt = credit.expiresAtDate,
                      expiresAt > now,
                      summary.availableCount > 0,
                      availableIDs.allSatisfy({ !$0.isEmpty }),
                      availableIDs.count == uniqueAvailableIDs.count,
                      uniqueAvailableIDs.count == summary.availableCount else {
                    return now >= journal.expiresAt ? .missed : .reconciling
                }
                if journal.phase == .outcomeConfirmed,
                   journal.confirmedOutcome == .nothingToReset
                    || journal.confirmedOutcome == .noCredit {
                    return .confirmedNotConsumed(expiresAt: expiresAt)
                }
                guard protectionEnabled else {
                    return .reconciling
                }
                if let retryAt, retryAt > now {
                    return .reconciling
                }
                let target = ResetCreditProtectionTarget(
                    creditID: credit.id,
                    creditFingerprint: journal.creditFingerprint,
                    idSuffix: String(credit.id.suffix(6)),
                    expiresAt: expiresAt,
                    actionAt: expiresAt.addingTimeInterval(
                        -AppConstants.resetCreditProtectionLeadTimeSeconds
                    ),
                    availableCount: summary.availableCount
                )
                guard now >= target.actionAt else {
                    return .reconciling
                }
                return .retry(target)
            default:
                return now >= journal.expiresAt
                    ? .missed
                    : .reconciling
            }
        }
        return now >= journal.expiresAt
            ? .missed
            : .reconciling
    }
}

public enum ResetCreditProtectionStorageError: LocalizedError {
    case cannotPrepareDirectory
    case cannotEncode
    case cannotCreateTemporaryFile
    case cannotWrite
    case cannotSync
    case cannotReplace
    case cannotRemove
    case authorizationRevoked
    case authorizationUnavailable

    public var errorDescription: String? {
        switch self {
        case .cannotPrepareDirectory:
            return "Reset-credit auto-use storage is unavailable"
        case .cannotEncode:
            return "Reset-credit auto-use state could not be encoded"
        case .cannotCreateTemporaryFile:
            return "Reset-credit auto-use state could not be prepared"
        case .cannotWrite:
            return "Reset-credit auto-use state could not be written"
        case .cannotSync:
            return "Reset-credit auto-use state could not be synchronized"
        case .cannotReplace:
            return "Reset-credit auto-use state could not be committed"
        case .cannotRemove:
            return "Reset-credit auto-use state could not be cleared"
        case .authorizationRevoked:
            return "Reset-credit auto-use authorization was revoked"
        case .authorizationUnavailable:
            return "Reset-credit auto-use authorization cannot be verified"
        }
    }
}

public struct ResetCreditProtectionLedgerStore {
    public enum LoadResult: Equatable {
        case absent
        case loaded(ResetCreditProtectionLedger)
        case corrupt
    }

    public let url: URL

    public init(url: URL) {
        self.url = url
    }

    public func load() -> LoadResult {
        guard let data = try? Data(contentsOf: url) else {
            return FileManager.default.fileExists(atPath: url.path)
                ? .corrupt
                : .absent
        }
        if let ledger = try? JSONDecoder().decode(
            ResetCreditProtectionLedger.self,
            from: data
        ), Self.isValidLedger(ledger) {
            return .loaded(ledger)
        }
        if let legacyJournal = try? JSONDecoder().decode(
            ResetCreditProtectionAttemptJournal.self,
            from: data
        ), Self.isValidJournal(legacyJournal) {
            return .loaded(
                ResetCreditProtectionLedger(activeAttempt: legacyJournal)
            )
        }
        return .corrupt
    }

    public func save(_ ledger: ResetCreditProtectionLedger) throws {
        guard Self.isValidLedger(ledger),
              let data = try? JSONEncoder().encode(ledger) else {
            throw ResetCreditProtectionStorageError.cannotEncode
        }
        try ResetCreditProtectionAtomicFile.write(data, to: url)
    }

    public func clear() throws {
        try ResetCreditProtectionAtomicFile.clear(url)
    }

    private static func isValidLedger(_ ledger: ResetCreditProtectionLedger) -> Bool {
        guard ledger.version == AppConstants.resetCreditProtectionLedgerVersion else {
            return false
        }
        if let activeAttempt = ledger.activeAttempt,
           !isValidJournal(activeAttempt) {
            return false
        }

        var keys: [String: String] = [:]
        for tombstone in ledger.tombstones {
            guard !tombstone.accountFingerprint.isEmpty,
                  !tombstone.creditFingerprint.isEmpty,
                  UUID(uuidString: tombstone.idempotencyKey) != nil else {
                return false
            }
            let credit = tombstone.creditFingerprint
            if let existing = keys[credit], existing != tombstone.idempotencyKey {
                return false
            }
            guard keys[credit] == nil else {
                return false
            }
            keys[credit] = tombstone.idempotencyKey
        }
        if let activeAttempt = ledger.activeAttempt {
            guard keys[activeAttempt.creditFingerprint] == nil else {
                return false
            }
        }
        return true
    }

    private static func isValidJournal(
        _ journal: ResetCreditProtectionAttemptJournal
    ) -> Bool {
        guard journal.version == AppConstants.resetCreditProtectionJournalVersion,
              !journal.accountFingerprint.isEmpty,
              !journal.creditFingerprint.isEmpty,
              UUID(uuidString: journal.idempotencyKey) != nil,
              journal.availableCountBefore >= 0 else {
            return false
        }
        switch journal.phase {
        case .outcomeConfirmed:
            return journal.confirmedOutcome != nil
        case .sending, .sentUnknown:
            return journal.confirmedOutcome == nil
        }
    }
}

public struct ResetCreditProtectionAuthorizationStore {
    public enum LoadResult: Equatable {
        case absent
        case loaded(ResetCreditProtectionConsent)
        case corrupt
    }

    public enum ClockValidationResult: Equatable {
        case continuous(ResetCreditProtectionConsent)
        case absent
        case revoked(
            ResetCreditProtectionConsent,
            ResetCreditProtectionAuthorization.ClockDiscontinuityReason
        )
        case corrupt
    }

    public enum ConditionalClearResult: Equatable {
        case cleared
        case alreadyRevoked
        case superseded
    }

    private struct RevocationMarker: Codable, Equatable {
        let version: Int
        let revoked: Bool

        static let current = RevocationMarker(version: 1, revoked: true)
    }

    public let url: URL
    public let dispatchLockURL: URL

    public init(url: URL, dispatchLockURL: URL) {
        self.url = url
        self.dispatchLockURL = dispatchLockURL
    }

    public func load() -> LoadResult {
        guard let data = try? Data(contentsOf: url) else {
            return FileManager.default.fileExists(atPath: url.path)
                ? .corrupt
                : .absent
        }
        if let marker = try? JSONDecoder().decode(
            RevocationMarker.self,
            from: data
        ), marker == .current {
            return .absent
        }
        guard let consent = try? JSONDecoder().decode(
            ResetCreditProtectionConsent.self,
            from: data
        ), ResetCreditProtectionAuthorization.isStructurallyValid(
            consent: consent
        ) else {
            return .corrupt
        }
        return .loaded(consent)
    }

    public func save(
        _ consent: ResetCreditProtectionConsent,
        onSaved: () -> Void = {}
    ) throws {
        guard ResetCreditProtectionAuthorization.isStructurallyValid(
            consent: consent
        ), let data = try? JSONEncoder().encode(consent) else {
            throw ResetCreditProtectionStorageError.cannotEncode
        }
        let lock = try ResetCreditProtectionProcessLock(
            url: dispatchLockURL,
            nonBlocking: false
        )
        defer {
            lock.release()
        }
        try ResetCreditProtectionAtomicFile.write(data, to: url)
        onSaved()
    }

    public func clear(onCleared: () -> Void = {}) throws {
        let lock = try ResetCreditProtectionProcessLock(
            url: dispatchLockURL,
            nonBlocking: false
        )
        defer {
            lock.release()
        }
        try writeRevocationMarker()
        onCleared()
    }

    public func clear(
        ifCurrent expectedConsent: ResetCreditProtectionConsent,
        onCleared: () -> Void = {}
    ) throws -> ConditionalClearResult {
        let lock = try ResetCreditProtectionProcessLock(
            url: dispatchLockURL,
            nonBlocking: false
        )
        defer {
            lock.release()
        }
        switch load() {
        case .loaded(let current) where current == expectedConsent:
            try writeRevocationMarker()
            onCleared()
            return .cleared
        case .absent:
            onCleared()
            return .alreadyRevoked
        case .loaded:
            return .superseded
        case .corrupt:
            throw ResetCreditProtectionStorageError.authorizationUnavailable
        }
    }

    public func validateCurrentClockOrRevoke(
        currentClock: ResetCreditProtectionClockSample = .now(),
        onInvalidAuthorization: () -> Void = {}
    ) throws -> ClockValidationResult {
        let lock = try ResetCreditProtectionProcessLock(
            url: dispatchLockURL,
            nonBlocking: false
        )
        defer {
            lock.release()
        }
        switch load() {
        case .loaded(let consent):
            guard let reason = ResetCreditProtectionAuthorization
                .clockDiscontinuityReason(
                consent: consent,
                current: currentClock
            ) else {
                return .continuous(consent)
            }
            try writeRevocationMarker()
            onInvalidAuthorization()
            return .revoked(consent, reason)
        case .absent:
            onInvalidAuthorization()
            return .absent
        case .corrupt:
            try writeRevocationMarker()
            onInvalidAuthorization()
            return .corrupt
        }
    }

    public func withAuthorizedDispatch<T>(
        expected consent: ResetCreditProtectionConsent,
        creditFingerprint: String,
        _ body: () throws -> T
    ) throws -> T {
        let lock = try ResetCreditProtectionProcessLock(
            url: dispatchLockURL,
            nonBlocking: false
        )
        defer {
            lock.release()
        }
        switch load() {
        case .loaded(let current)
            where current == consent
                && ResetCreditProtectionAuthorization.authorizes(
                    requested: true,
                    consent: current,
                    creditFingerprint: creditFingerprint
                ):
            return try body()
        case .absent, .loaded:
            throw ResetCreditProtectionStorageError.authorizationRevoked
        case .corrupt:
            throw ResetCreditProtectionStorageError.authorizationUnavailable
        }
    }

    private func writeRevocationMarker() throws {
        guard let data = try? JSONEncoder().encode(RevocationMarker.current) else {
            throw ResetCreditProtectionStorageError.cannotEncode
        }
        try ResetCreditProtectionAtomicFile.write(data, to: url)
    }
}

public struct ResetCreditProtectionDispatchAuthorization {
    public let store: ResetCreditProtectionAuthorizationStore
    public let consent: ResetCreditProtectionConsent

    public init(
        store: ResetCreditProtectionAuthorizationStore,
        consent: ResetCreditProtectionConsent
    ) {
        self.store = store
        self.consent = consent
    }

    public func perform<T>(
        creditID: String,
        _ body: () throws -> T
    ) throws -> T {
        try store.withAuthorizedDispatch(
            expected: consent,
            creditFingerprint: ResetCreditPrivacy.fingerprint(creditID),
            body
        )
    }
}

private enum ResetCreditProtectionAtomicFile {
    static func write(_ data: Data, to url: URL) throws {
        let directory = url.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o700],
                ofItemAtPath: directory.path
            )
        } catch {
            throw ResetCreditProtectionStorageError.cannotPrepareDirectory
        }

        let temporaryURL = directory.appendingPathComponent(
            ".\(url.lastPathComponent).\(UUID().uuidString).tmp"
        )
        let descriptor = temporaryURL.path.withCString {
            Darwin.open(
                $0,
                O_CREAT | O_EXCL | O_WRONLY | O_CLOEXEC,
                S_IRUSR | S_IWUSR
            )
        }
        guard descriptor >= 0 else {
            throw ResetCreditProtectionStorageError.cannotCreateTemporaryFile
        }

        var descriptorIsOpen = true
        var temporaryFileExists = true
        defer {
            if descriptorIsOpen {
                _ = Darwin.close(descriptor)
            }
            if temporaryFileExists {
                temporaryURL.path.withCString { _ = Darwin.unlink($0) }
            }
        }

        try data.withUnsafeBytes { bytes in
            guard let baseAddress = bytes.baseAddress else {
                throw ResetCreditProtectionStorageError.cannotWrite
            }
            var offset = 0
            while offset < bytes.count {
                let written = Darwin.write(
                    descriptor,
                    baseAddress.advanced(by: offset),
                    bytes.count - offset
                )
                if written < 0, errno == EINTR {
                    continue
                }
                guard written > 0 else {
                    throw ResetCreditProtectionStorageError.cannotWrite
                }
                offset += written
            }
        }
        guard Darwin.fsync(descriptor) == 0 else {
            throw ResetCreditProtectionStorageError.cannotSync
        }
        let closeResult = Darwin.close(descriptor)
        descriptorIsOpen = false
        guard closeResult == 0 else {
            throw ResetCreditProtectionStorageError.cannotSync
        }

        let replaced = temporaryURL.path.withCString { temporaryPath in
            url.path.withCString { destinationPath in
                Darwin.rename(temporaryPath, destinationPath)
            }
        }
        guard replaced == 0 else {
            throw ResetCreditProtectionStorageError.cannotReplace
        }
        temporaryFileExists = false
        try syncDirectory(directory)
    }

    static func clear(_ url: URL) throws {
        let removed = url.path.withCString { Darwin.unlink($0) }
        guard removed == 0 || errno == ENOENT else {
            throw ResetCreditProtectionStorageError.cannotRemove
        }
        if removed == 0 {
            try syncDirectory(url.deletingLastPathComponent())
        }
    }

    private static func syncDirectory(_ directory: URL) throws {
        let descriptor = directory.path.withCString {
            Darwin.open($0, O_RDONLY | O_CLOEXEC)
        }
        guard descriptor >= 0 else {
            throw ResetCreditProtectionStorageError.cannotSync
        }
        defer {
            _ = Darwin.close(descriptor)
        }
        guard Darwin.fsync(descriptor) == 0 else {
            throw ResetCreditProtectionStorageError.cannotSync
        }
    }
}

public final class ResetCreditProtectionProcessLock {
    public enum LockError: LocalizedError {
        case unavailable

        public var errorDescription: String? {
            "Another Codex Radar process is already handling reset-credit auto-use"
        }
    }

    private var descriptor: Int32 = -1

    public init(url: URL, nonBlocking: Bool = true) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: url.deletingLastPathComponent().path
        )
        descriptor = url.path.withCString {
            Darwin.open($0, O_CREAT | O_RDWR | O_CLOEXEC, S_IRUSR | S_IWUSR)
        }
        guard descriptor >= 0,
              Darwin.fchmod(descriptor, S_IRUSR | S_IWUSR) == 0 else {
            release()
            throw LockError.unavailable
        }
        let operation = LOCK_EX | (nonBlocking ? LOCK_NB : 0)
        while flock(descriptor, operation) != 0 {
            if !nonBlocking, errno == EINTR {
                continue
            }
            release()
            throw LockError.unavailable
        }
    }

    deinit {
        release()
    }

    public func release() {
        guard descriptor >= 0 else {
            return
        }
        _ = flock(descriptor, LOCK_UN)
        _ = Darwin.close(descriptor)
        descriptor = -1
    }
}
