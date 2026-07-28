import Foundation
import XCTest
@testable import CodexRadarCore
@testable import CodexRadarSentinel

@MainActor
final class ResetCreditProtectionOrchestrationTests: XCTestCase {
    func testDisableAfterAuthorizedDispatchReconcilesNothingToResetAsDisabled()
        async throws
    {
        let identifier = UUID().uuidString
        let suiteName = "com.codexradar.sentinel.tests.\(identifier)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "codex-radar-sentinel-tests-\(identifier)",
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: false
        )
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: directory)
        }

        let ledgerStore = ResetCreditProtectionLedgerStore(
            url: directory.appendingPathComponent("ledger.json")
        )
        let authorizationStore = ResetCreditProtectionAuthorizationStore(
            url: directory.appendingPathComponent("authorization.json"),
            dispatchLockURL: directory.appendingPathComponent(
                "authorization.lock"
            )
        )
        let processLockURL = directory.appendingPathComponent("process.lock")
        let appServer = SuspendedNothingToResetAppServer(
            creditID: "offline-test-credit",
            expiresAt: Date().addingTimeInterval(10 * 60)
        )
        let store = SentinelStore(
            defaults: defaults,
            appServerClient: appServer,
            resetCreditProtectionLedgerStore: ledgerStore,
            resetCreditProtectionAuthorizationStore: authorizationStore,
            resetCreditProtectionProcessLockURL: processLockURL
        )

        XCTAssertFalse(store.resetCreditProtectionEnabled)
        XCTAssertEqual(store.resetCreditProtectionStatus, .disabled)

        store.enableResetCreditExpiryProtection()
        do {
            try await waitUntil {
                let snapshot = await appServer.snapshot()
                return snapshot.authorizedDispatchCount == 1
            }
        } catch {
            await appServer.releaseConsume()
            throw error
        }

        XCTAssertTrue(store.resetCreditProtectionEnabled)
        guard case .loaded(let dispatchedLedger) = ledgerStore.load() else {
            await appServer.releaseConsume()
            return XCTFail("Expected a durable attempt journal before dispatch")
        }
        XCTAssertEqual(dispatchedLedger.activeAttempt?.phase, .sending)
        guard case .loaded = authorizationStore.load() else {
            await appServer.releaseConsume()
            return XCTFail("Expected authorization to exist at dispatch")
        }

        store.disableResetCreditExpiryProtection()
        XCTAssertFalse(store.resetCreditProtectionEnabled)
        XCTAssertEqual(authorizationStore.load(), .absent)

        await appServer.releaseConsume()
        try await waitUntil {
            let snapshot = await appServer.snapshot()
            return snapshot.consumeReturnCount == 1
                && store.resetCreditProtectionStatus == .disabled
        }

        XCTAssertEqual(store.resetCreditProtectionStatus, .disabled)
        guard case .loaded(let finalLedger) = ledgerStore.load() else {
            return XCTFail("Expected the empty ledger to remain durable")
        }
        XCTAssertNil(finalLedger.activeAttempt)
        XCTAssertTrue(finalLedger.tombstones.isEmpty)

        let snapshot = await appServer.snapshot()
        XCTAssertEqual(snapshot.consumeCallCount, 1)
        XCTAssertEqual(snapshot.authorizedDispatchCount, 1)
        XCTAssertEqual(snapshot.consumeReturnCount, 1)
        XCTAssertEqual(snapshot.rateLimitReadCount, 3)
        XCTAssertEqual(snapshot.accountReadCount, 9)
        XCTAssertTrue(FileManager.default.fileExists(atPath: processLockURL.path))
    }

    func testValidConsentDoesNotEnableWhenDesiredStateIsFalseAtStartup()
        async throws
    {
        let context = try OfflineStoreContext()
        defer { context.cleanup() }
        let creditID = "startup-disabled-credit"
        let account = accountResponse(email: "account-a@example.com")
        try context.authorizationStore.save(
            consent(account: account, creditIDs: [creditID])
        )
        context.defaults.set(false, forKey: "resetCreditProtectionEnabled")
        context.disableBackgroundFeatures()

        let response = rateLimitResponse(
            creditID: creditID,
            expiresAt: Date().addingTimeInterval(10 * 60)
        )
        let longLived = OfflineAppServer(
            account: account,
            response: response
        )
        let sessions = OfflineSessionFactoryRecorder {
            OfflineAppServer(account: account, response: response)
        }
        let store = context.makeStore(
            appServer: longLived,
            sessionFactory: sessions.factory
        )

        XCTAssertFalse(store.resetCreditProtectionEnabled)
        XCTAssertEqual(store.resetCreditProtectionStatus, .disabled)
        store.start()
        try await waitUntil {
            await longLived.snapshot().rateLimitReadCount >= 1
        }
        store.stop()

        XCTAssertFalse(store.resetCreditProtectionEnabled)
        XCTAssertFalse(
            context.defaults.bool(forKey: "resetCreditProtectionEnabled")
        )
        XCTAssertEqual(context.authorizationStore.load(), .absent)
        XCTAssertEqual(sessions.count, 0)
        let longLivedSnapshot = await longLived.snapshot()
        XCTAssertEqual(longLivedSnapshot.consumeCallCount, 0)
    }

    func testDisabledStartupReconcilesActiveJournalWithoutRetryingConsume()
        async throws
    {
        let context = try OfflineStoreContext()
        defer { context.cleanup() }
        let creditID = "disabled-journal-credit"
        let expiresAt = Date().addingTimeInterval(10 * 60)
        let account = accountResponse(email: "account-a@example.com")
        let accountFingerprint = try accountFingerprint(account)
        let creditFingerprint = ResetCreditPrivacy.fingerprint(creditID)
        try context.authorizationStore.save(
            consent(account: account, creditIDs: [creditID])
        )
        context.defaults.set(false, forKey: "resetCreditProtectionEnabled")
        let journal = ResetCreditProtectionAttemptJournal(
            accountFingerprint: accountFingerprint,
            creditFingerprint: creditFingerprint,
            idempotencyKey: UUID().uuidString,
            expiresAt: expiresAt,
            availableCountBefore: 1,
            phase: .sending,
            updatedAt: Date()
        )
        try context.ledgerStore.save(
            ResetCreditProtectionLedger(activeAttempt: journal)
        )

        let response = rateLimitResponse(
            creditID: creditID,
            expiresAt: expiresAt
        )
        let longLived = OfflineAppServer(
            account: account,
            response: response
        )
        let sessions = OfflineSessionFactoryRecorder {
            OfflineAppServer(account: account, response: response)
        }
        let store = context.makeStore(
            appServer: longLived,
            sessionFactory: sessions.factory
        )

        XCTAssertFalse(store.resetCreditProtectionEnabled)
        store.handleSystemClockChange()
        if case .blocked(.clockChanged, _) =
            store.resetCreditProtectionStatus {
            XCTFail("An absent authorization must not mask read-only reconciliation")
        }
        guard case .loaded(let preservedLedger) =
            context.ledgerStore.load() else {
            return XCTFail("Expected the unresolved journal to remain durable")
        }
        XCTAssertEqual(preservedLedger.activeAttempt, journal)
        store.refreshNow()
        try await waitUntil {
            guard let service = sessions.services.first else {
                return false
            }
            return await service.snapshot().shutdownCount == 1
        }

        XCTAssertFalse(store.resetCreditProtectionEnabled)
        XCTAssertEqual(
            store.resetCreditProtectionStatus,
            .reconciling(expiresAt: expiresAt)
        )
        XCTAssertFalse(
            context.defaults.bool(forKey: "resetCreditProtectionEnabled")
        )
        let service = try XCTUnwrap(sessions.services.first)
        let snapshot = await service.snapshot()
        XCTAssertEqual(snapshot.calls, ["account", "rate", "account"])
        XCTAssertEqual(snapshot.consumeCallCount, 0)
        XCTAssertEqual(snapshot.shutdownCount, 1)
        guard case .loaded(let ledger) = context.ledgerStore.load() else {
            return XCTFail("Expected the unresolved journal to remain durable")
        }
        XCTAssertEqual(ledger.activeAttempt, journal)
    }

    func testDisabledJournalSurvivesOrdinaryNetworkFailure() async throws {
        let context = try OfflineStoreContext()
        defer { context.cleanup() }
        let creditID = "disabled-network-failure-credit"
        let expiresAt = Date().addingTimeInterval(10 * 60)
        let account = accountResponse(email: "account-a@example.com")
        let journal = ResetCreditProtectionAttemptJournal(
            accountFingerprint: try accountFingerprint(account),
            creditFingerprint: ResetCreditPrivacy.fingerprint(creditID),
            idempotencyKey: UUID().uuidString,
            expiresAt: expiresAt,
            availableCountBefore: 1,
            phase: .sentUnknown,
            updatedAt: Date()
        )
        context.defaults.set(false, forKey: "resetCreditProtectionEnabled")
        context.disableBackgroundFeatures()
        try context.ledgerStore.save(
            ResetCreditProtectionLedger(activeAttempt: journal)
        )

        let response = rateLimitResponse(
            creditID: creditID,
            expiresAt: expiresAt
        )
        let longLived = OfflineAppServer(
            account: account,
            response: response
        )
        let failingService = NetworkFailingAppServer(account: account)
        let factory = ResetCreditProtectionAppServerSessionFactory {
            ResetCreditProtectionAppServerSession(
                service: failingService,
                shutdown: {
                    await failingService.recordShutdown()
                }
            )
        }
        let store = context.makeStore(
            appServer: longLived,
            sessionFactory: factory
        )

        XCTAssertFalse(store.resetCreditProtectionEnabled)
        XCTAssertTrue(store.hasUnresolvedResetCreditProtectionAttempt)
        XCTAssertEqual(context.authorizationStore.load(), .absent)
        store.handleSystemClockChange()
        try await waitUntil {
            guard case .blocked(.requestFailed, _) =
                store.resetCreditProtectionStatus else {
                return false
            }
            return await failingService.snapshot().shutdownCount >= 1
        }

        XCTAssertFalse(store.resetCreditProtectionEnabled)
        XCTAssertFalse(
            context.defaults.bool(forKey: "resetCreditProtectionEnabled")
        )
        XCTAssertTrue(store.hasUnresolvedResetCreditProtectionAttempt)
        XCTAssertEqual(context.authorizationStore.load(), .absent)
        guard case .loaded(let ledger) = context.ledgerStore.load() else {
            return XCTFail("Expected the unresolved journal to remain durable")
        }
        XCTAssertEqual(ledger.activeAttempt, journal)
        XCTAssertEqual(
            ledger.activeAttempt?.idempotencyKey,
            journal.idempotencyKey
        )
        let snapshot = await failingService.snapshot()
        XCTAssertGreaterThanOrEqual(snapshot.rateLimitReadCount, 1)
        XCTAssertEqual(snapshot.consumeCallCount, 0)
    }

    func testExplicitReenableReconcilesActiveJournalWithoutReplacingOrConsuming()
        async throws
    {
        let context = try OfflineStoreContext()
        defer { context.cleanup() }
        let creditID = "reenable-unresolved-credit"
        let expiresAt = Date().addingTimeInterval(10 * 60)
        let account = accountResponse(email: "account-a@example.com")
        let journal = ResetCreditProtectionAttemptJournal(
            accountFingerprint: try accountFingerprint(account),
            creditFingerprint: ResetCreditPrivacy.fingerprint(creditID),
            idempotencyKey: UUID().uuidString,
            expiresAt: expiresAt,
            availableCountBefore: 1,
            phase: .sentUnknown,
            updatedAt: Date()
        )
        context.defaults.set(false, forKey: "resetCreditProtectionEnabled")
        try context.ledgerStore.save(
            ResetCreditProtectionLedger(activeAttempt: journal)
        )

        let response = rateLimitResponse(
            creditID: creditID,
            expiresAt: expiresAt
        )
        let longLived = OfflineAppServer(
            account: account,
            response: response
        )
        let sessions = OfflineSessionFactoryRecorder {
            OfflineAppServer(account: account, response: response)
        }
        let store = context.makeStore(
            appServer: longLived,
            sessionFactory: sessions.factory
        )

        XCTAssertFalse(store.resetCreditProtectionEnabled)
        store.enableResetCreditExpiryProtection()
        try await waitUntil {
            guard let service = sessions.services.first else {
                return false
            }
            return await service.snapshot().shutdownCount == 1
        }

        XCTAssertFalse(store.resetCreditProtectionEnabled)
        XCTAssertFalse(
            context.defaults.bool(forKey: "resetCreditProtectionEnabled")
        )
        XCTAssertEqual(
            store.resetCreditProtectionStatus,
            .reconciling(expiresAt: expiresAt)
        )
        XCTAssertEqual(context.authorizationStore.load(), .absent)
        let service = try XCTUnwrap(sessions.services.first)
        let snapshot = await service.snapshot()
        XCTAssertEqual(snapshot.calls, ["account", "rate", "account"])
        XCTAssertEqual(snapshot.consumeCallCount, 0)
        XCTAssertEqual(snapshot.shutdownCount, 1)
        guard case .loaded(let ledger) = context.ledgerStore.load() else {
            return XCTFail("Expected the unresolved journal to remain durable")
        }
        XCTAssertEqual(ledger.activeAttempt, journal)
        XCTAssertEqual(
            ledger.activeAttempt?.idempotencyKey,
            journal.idempotencyKey
        )
    }

    func testFreshSessionAccountMismatchNeverConsumesAndClosesProtection()
        async throws
    {
        let context = try OfflineStoreContext()
        defer { context.cleanup() }
        let creditID = "account-bound-credit"
        let expiresAt = Date().addingTimeInterval(10 * 60)
        let accountA = accountResponse(email: "account-a@example.com")
        let accountB = accountResponse(email: "account-b@example.com")
        try context.authorizationStore.save(
            consent(account: accountA, creditIDs: [creditID])
        )
        context.defaults.set(true, forKey: "resetCreditProtectionEnabled")

        let response = rateLimitResponse(
            creditID: creditID,
            expiresAt: expiresAt
        )
        let longLived = OfflineAppServer(
            account: accountA,
            response: response
        )
        let sessions = OfflineSessionFactoryRecorder {
            OfflineAppServer(account: accountB, response: response)
        }
        let store = context.makeStore(
            appServer: longLived,
            sessionFactory: sessions.factory
        )

        XCTAssertTrue(store.resetCreditProtectionEnabled)
        store.refreshNow()
        try await waitUntil {
            guard let service = sessions.services.first else {
                return false
            }
            return await service.snapshot().shutdownCount == 1
                && !store.resetCreditProtectionEnabled
        }

        XCTAssertFalse(store.resetCreditProtectionEnabled)
        XCTAssertFalse(
            context.defaults.bool(forKey: "resetCreditProtectionEnabled")
        )
        XCTAssertEqual(
            store.resetCreditProtectionStatus,
            .blocked(.accountChanged, detail: nil)
        )
        XCTAssertEqual(context.authorizationStore.load(), .absent)
        let freshService = try XCTUnwrap(sessions.services.first)
        let freshSnapshot = await freshService.snapshot()
        XCTAssertEqual(freshSnapshot.calls, ["account"])
        XCTAssertEqual(freshSnapshot.consumeCallCount, 0)
        XCTAssertEqual(freshSnapshot.shutdownCount, 1)
        let longLivedSnapshot = await longLived.snapshot()
        XCTAssertEqual(longLivedSnapshot.consumeCallCount, 0)
    }

    func testFreshPreflightNewCreditClosesAuthorizationBeforeConsume()
        async throws
    {
        let now = Date()
        try await assertFreshPreflightCardSetChangeClosesAuthorization(
            consentCredits: [
                ("authorized-credit", now.addingTimeInterval(10 * 60)),
            ],
            freshCredits: [
                ("authorized-credit", now.addingTimeInterval(10 * 60)),
                ("new-later-credit", now.addingTimeInterval(2 * 60 * 60)),
            ]
        )
    }

    func testFreshPreflightMissingCreditClosesAuthorizationBeforeConsume()
        async throws
    {
        let now = Date()
        try await assertFreshPreflightCardSetChangeClosesAuthorization(
            consentCredits: [
                ("authorized-credit", now.addingTimeInterval(10 * 60)),
                ("missing-later-credit", now.addingTimeInterval(2 * 60 * 60)),
            ],
            freshCredits: [
                ("authorized-credit", now.addingTimeInterval(10 * 60)),
            ]
        )
    }

    func testTerminalCreditDoesNotBlockRemainingAuthorizedCredit()
        async throws
    {
        let context = try OfflineStoreContext()
        defer { context.cleanup() }
        let usedCreditID = "already-used-credit"
        let remainingCreditID = "remaining-credit"
        let account = accountResponse(email: "account-a@example.com")
        let remainingExpiry = Date().addingTimeInterval(2 * 60 * 60)
        try context.authorizationStore.save(
            consent(
                account: account,
                creditIDs: [usedCreditID, remainingCreditID]
            )
        )
        context.defaults.set(true, forKey: "resetCreditProtectionEnabled")
        let terminalJournal = ResetCreditProtectionAttemptJournal(
            accountFingerprint: try accountFingerprint(account),
            creditFingerprint: ResetCreditPrivacy.fingerprint(usedCreditID),
            idempotencyKey: UUID().uuidString,
            expiresAt: Date().addingTimeInterval(-60),
            availableCountBefore: 2,
            phase: .outcomeConfirmed,
            confirmedOutcome: .reset,
            updatedAt: Date()
        )
        try context.ledgerStore.save(
            ResetCreditProtectionLedger(
                tombstones: [
                    ResetCreditProtectionTombstone(
                        journal: terminalJournal,
                        disposition: .confirmedUsed
                    ),
                ]
            )
        )
        let response = rateLimitResponse(
            credits: [(remainingCreditID, remainingExpiry)]
        )
        let longLived = OfflineAppServer(
            account: account,
            response: response
        )
        let sessions = OfflineSessionFactoryRecorder {
            OfflineAppServer(account: account, response: response)
        }
        let store = context.makeStore(
            appServer: longLived,
            sessionFactory: sessions.factory
        )

        store.refreshNow()
        try await waitUntil {
            await longLived.snapshot().rateLimitReadCount >= 1
        }

        XCTAssertTrue(store.resetCreditProtectionEnabled)
        XCTAssertTrue(
            context.defaults.bool(forKey: "resetCreditProtectionEnabled")
        )
        guard case .loaded = context.authorizationStore.load() else {
            return XCTFail("Expected remaining authorization to stay active")
        }
        guard case .scheduled(
            _,
            let scheduledExpiry,
            let availableCount
        ) = store.resetCreditProtectionStatus else {
            return XCTFail("Expected the remaining credit to stay scheduled")
        }
        XCTAssertEqual(
            scheduledExpiry.timeIntervalSince1970,
            remainingExpiry.timeIntervalSince1970,
            accuracy: 1
        )
        XCTAssertEqual(availableCount, 1)
        XCTAssertEqual(sessions.count, 0)
        let snapshot = await longLived.snapshot()
        XCTAssertEqual(snapshot.consumeCallCount, 0)
    }

    func testTerminalCreditDoesNotMaskANewUnapprovedCredit()
        async throws
    {
        let context = try OfflineStoreContext()
        defer { context.cleanup() }
        let usedCreditID = "already-used-credit"
        let remainingCreditID = "remaining-credit"
        let newCreditID = "new-workspace-credit"
        let account = accountResponse(email: "same-email@example.com")
        let consent = try consent(
            account: account,
            creditIDs: [usedCreditID, remainingCreditID]
        )
        try context.authorizationStore.save(consent)
        context.defaults.set(true, forKey: "resetCreditProtectionEnabled")
        let terminalJournal = ResetCreditProtectionAttemptJournal(
            accountFingerprint: consent.accountFingerprint,
            creditFingerprint: ResetCreditPrivacy.fingerprint(usedCreditID),
            idempotencyKey: UUID().uuidString,
            expiresAt: Date().addingTimeInterval(-60),
            availableCountBefore: 2,
            phase: .outcomeConfirmed,
            confirmedOutcome: .reset,
            updatedAt: Date()
        )
        try context.ledgerStore.save(
            ResetCreditProtectionLedger(
                tombstones: [
                    ResetCreditProtectionTombstone(
                        journal: terminalJournal,
                        disposition: .confirmedUsed
                    ),
                ]
            )
        )
        let response = rateLimitResponse(
            credits: [
                (
                    remainingCreditID,
                    Date().addingTimeInterval(2 * 60 * 60)
                ),
                (newCreditID, Date().addingTimeInterval(60 * 60)),
            ]
        )
        let longLived = OfflineAppServer(
            account: account,
            response: response
        )
        let sessions = OfflineSessionFactoryRecorder {
            OfflineAppServer(account: account, response: response)
        }
        let store = context.makeStore(
            appServer: longLived,
            sessionFactory: sessions.factory
        )

        store.refreshNow()
        try await waitUntil {
            !store.resetCreditProtectionEnabled
        }

        XCTAssertFalse(
            context.defaults.bool(forKey: "resetCreditProtectionEnabled")
        )
        XCTAssertEqual(context.authorizationStore.load(), .absent)
        XCTAssertEqual(
            store.resetCreditProtectionStatus,
            .blocked(.creditNotAuthorized, detail: nil)
        )
        XCTAssertEqual(sessions.count, 0)
        let snapshot = await longLived.snapshot()
        XCTAssertEqual(snapshot.consumeCallCount, 0)
    }

    func testStaleInMemoryLedgerDoesNotRevokeAnotherProcessAuthorization()
        async throws
    {
        let context = try OfflineStoreContext()
        defer { context.cleanup() }
        let usedCreditID = "other-process-used-credit"
        let remainingCreditID = "other-process-remaining-credit"
        let account = accountResponse(email: "same-email@example.com")
        let consent = try consent(
            account: account,
            creditIDs: [usedCreditID, remainingCreditID]
        )
        try context.authorizationStore.save(consent)
        context.defaults.set(true, forKey: "resetCreditProtectionEnabled")
        let remainingExpiry = Date().addingTimeInterval(2 * 60 * 60)
        let response = rateLimitResponse(
            credits: [(remainingCreditID, remainingExpiry)]
        )
        let longLived = OfflineAppServer(
            account: account,
            response: response
        )
        let sessions = OfflineSessionFactoryRecorder {
            OfflineAppServer(account: account, response: response)
        }
        let store = context.makeStore(
            appServer: longLived,
            sessionFactory: sessions.factory
        )
        let terminalJournal = ResetCreditProtectionAttemptJournal(
            accountFingerprint: consent.accountFingerprint,
            creditFingerprint: ResetCreditPrivacy.fingerprint(usedCreditID),
            idempotencyKey: UUID().uuidString,
            expiresAt: Date().addingTimeInterval(-60),
            availableCountBefore: 2,
            phase: .outcomeConfirmed,
            confirmedOutcome: .reset,
            updatedAt: Date()
        )
        try context.ledgerStore.save(
            ResetCreditProtectionLedger(
                tombstones: [
                    ResetCreditProtectionTombstone(
                        journal: terminalJournal,
                        disposition: .confirmedUsed
                    ),
                ]
            )
        )

        store.refreshNow()
        try await waitUntil {
            await longLived.snapshot().rateLimitReadCount >= 1
        }

        XCTAssertTrue(store.resetCreditProtectionEnabled)
        XCTAssertTrue(
            context.defaults.bool(forKey: "resetCreditProtectionEnabled")
        )
        guard case .loaded = context.authorizationStore.load() else {
            return XCTFail("Expected shared authorization to remain active")
        }
        XCTAssertEqual(sessions.count, 0)
        let snapshot = await longLived.snapshot()
        XCTAssertEqual(snapshot.consumeCallCount, 0)
    }

    func testJournalAuthenticationErrorClosesAuthorizationAndPreservesJournal()
        async throws
    {
        let context = try OfflineStoreContext()
        defer { context.cleanup() }
        let creditID = "journal-auth-credit"
        let expiresAt = Date().addingTimeInterval(10 * 60)
        let account = accountResponse(email: "account-a@example.com")
        let consent = try consent(account: account, creditIDs: [creditID])
        try context.authorizationStore.save(consent)
        context.defaults.set(true, forKey: "resetCreditProtectionEnabled")
        let journal = ResetCreditProtectionAttemptJournal(
            accountFingerprint: consent.accountFingerprint,
            creditFingerprint: ResetCreditPrivacy.fingerprint(creditID),
            idempotencyKey: UUID().uuidString,
            expiresAt: expiresAt,
            availableCountBefore: 1,
            phase: .sentUnknown,
            updatedAt: Date()
        )
        try context.ledgerStore.save(
            ResetCreditProtectionLedger(activeAttempt: journal)
        )
        let response = rateLimitResponse(
            creditID: creditID,
            expiresAt: expiresAt
        )
        let longLived = OfflineAppServer(
            account: account,
            response: response
        )
        let signedOut = SignedOutAppServer(
            mode: .authenticationRPC,
            response: response
        )
        let factory = ResetCreditProtectionAppServerSessionFactory {
            ResetCreditProtectionAppServerSession(service: signedOut)
        }
        let store = context.makeStore(
            appServer: longLived,
            sessionFactory: factory
        )

        store.refreshNow()
        try await waitUntil {
            !store.resetCreditProtectionEnabled
                && store.resetCreditProtectionStatus
                    == .blocked(.signedOut, detail: nil)
        }

        XCTAssertFalse(
            context.defaults.bool(forKey: "resetCreditProtectionEnabled")
        )
        XCTAssertEqual(context.authorizationStore.load(), .absent)
        guard case .loaded(let ledger) = context.ledgerStore.load() else {
            return XCTFail("Expected the unresolved journal to remain durable")
        }
        XCTAssertEqual(ledger.activeAttempt, journal)
        let snapshot = await signedOut.snapshot()
        XCTAssertGreaterThanOrEqual(snapshot.accountReadCount, 1)
        XCTAssertEqual(snapshot.consumeCallCount, 0)
    }

    func testSystemClockChangeClosesProtectionAndPreventsLaterDispatch()
        async throws
    {
        let context = try OfflineStoreContext()
        defer { context.cleanup() }
        let creditID = "clock-change-credit"
        let account = accountResponse(email: "account-a@example.com")
        let anchor = ResetCreditProtectionClockSample(
            wallTime: Date(timeIntervalSince1970: 2_000_000_000),
            continuousTimeSeconds: 1_000
        )
        let storedConsent = try consent(
            account: account,
            creditIDs: [creditID],
            clockAnchor: anchor
        )
        try context.authorizationStore.save(storedConsent) {
            context.defaults.set(
                true,
                forKey: "resetCreditProtectionEnabled"
            )
        }

        let response = rateLimitResponse(
            creditID: creditID,
            expiresAt: Date().addingTimeInterval(10 * 60)
        )
        let longLived = OfflineAppServer(
            account: account,
            response: response
        )
        let sessions = OfflineSessionFactoryRecorder {
            OfflineAppServer(account: account, response: response)
        }
        let store = context.makeStore(
            appServer: longLived,
            sessionFactory: sessions.factory,
            clock: {
                ResetCreditProtectionClockSample(
                    wallTime: anchor.wallTime.addingTimeInterval(126),
                    continuousTimeSeconds: 1_120
                )
            }
        )

        XCTAssertFalse(store.resetCreditProtectionEnabled)
        guard case .blocked(.clockChanged, let detail) =
            store.resetCreditProtectionStatus else {
            return XCTFail("Expected a clock discontinuity at startup")
        }
        XCTAssertTrue(detail?.contains("6.000") == true)

        try context.authorizationStore.save(storedConsent) {
            context.defaults.set(
                true,
                forKey: "resetCreditProtectionEnabled"
            )
        }
        let enabledStore = context.makeStore(
            appServer: longLived,
            sessionFactory: sessions.factory,
            clock: {
                ResetCreditProtectionClockSample(
                    wallTime: anchor.wallTime.addingTimeInterval(120),
                    continuousTimeSeconds: 1_120
                )
            }
        )
        XCTAssertTrue(enabledStore.resetCreditProtectionEnabled)
        var changedClock = ResetCreditProtectionClockSample(
            wallTime: anchor.wallTime.addingTimeInterval(120),
            continuousTimeSeconds: 1_120
        )
        let handlerStore = context.makeStore(
            appServer: longLived,
            sessionFactory: sessions.factory,
            clock: { changedClock }
        )
        XCTAssertTrue(handlerStore.resetCreditProtectionEnabled)
        changedClock = ResetCreditProtectionClockSample(
            wallTime: anchor.wallTime.addingTimeInterval(126),
            continuousTimeSeconds: 1_120
        )
        handlerStore.handleSystemClockChange()
        try await waitUntil {
            await longLived.snapshot().rateLimitReadCount >= 1
        }
        handlerStore.refreshNow()
        try await waitUntil {
            await longLived.snapshot().rateLimitReadCount >= 2
        }

        XCTAssertFalse(handlerStore.resetCreditProtectionEnabled)
        XCTAssertFalse(
            context.defaults.bool(forKey: "resetCreditProtectionEnabled")
        )
        guard case .blocked(.clockChanged, let handlerDetail) =
            handlerStore.resetCreditProtectionStatus else {
            return XCTFail("Expected the handler to report a clock offset")
        }
        XCTAssertTrue(handlerDetail?.contains("6.000") == true)
        XCTAssertEqual(context.authorizationStore.load(), .absent)
        XCTAssertEqual(sessions.count, 0)
        let longLivedSnapshot = await longLived.snapshot()
        XCTAssertEqual(longLivedSnapshot.consumeCallCount, 0)
    }

    func testSystemClockChangeWhileEnablingCannotResumeIntoDispatch()
        async throws
    {
        let context = try OfflineStoreContext()
        defer { context.cleanup() }
        let creditID = "clock-race-credit"
        let account = accountResponse(email: "account-a@example.com")
        let response = rateLimitResponse(
            creditID: creditID,
            expiresAt: Date().addingTimeInterval(10 * 60)
        )
        let longLived = OfflineAppServer(
            account: account,
            response: response
        )
        let suspended = SuspendedEnableAppServer(
            account: account,
            response: response
        )
        let factory = ResetCreditProtectionAppServerSessionFactory {
            ResetCreditProtectionAppServerSession(
                service: suspended,
                shutdown: {
                    await suspended.recordShutdown()
                }
            )
        }
        let clockAnchor = ResetCreditProtectionClockSample.now()
        var currentClock = clockAnchor
        let store = context.makeStore(
            appServer: longLived,
            sessionFactory: factory,
            clock: { currentClock }
        )

        store.enableResetCreditExpiryProtection()
        try await waitUntil {
            await suspended.snapshot().accountReadCount == 1
        }
        XCTAssertEqual(store.resetCreditProtectionStatus, .enabling)

        currentClock = ResetCreditProtectionClockSample(
            wallTime: clockAnchor.wallTime.addingTimeInterval(126),
            continuousTimeSeconds:
                clockAnchor.continuousTimeSeconds + 120
        )
        store.handleSystemClockChange()
        await suspended.releaseAccountRead()
        try await waitUntil {
            await suspended.snapshot().shutdownCount == 1
        }

        XCTAssertFalse(store.resetCreditProtectionEnabled)
        XCTAssertFalse(
            context.defaults.bool(forKey: "resetCreditProtectionEnabled")
        )
        guard case .blocked(.clockChanged, let detail) =
            store.resetCreditProtectionStatus else {
            return XCTFail("Expected enabling to fail closed")
        }
        XCTAssertTrue(detail?.contains("6.000") == true)
        XCTAssertEqual(context.authorizationStore.load(), .absent)
        let snapshot = await suspended.snapshot()
        XCTAssertEqual(snapshot.rateLimitReadCount, 0)
        XCTAssertEqual(snapshot.consumeCallCount, 0)
    }

    func testBenignClockNotificationWhileEnablingDoesNotCancelAuthorization()
        async throws
    {
        let context = try OfflineStoreContext()
        defer { context.cleanup() }
        let creditID = "benign-enabling-clock-credit"
        let account = accountResponse(email: "account-a@example.com")
        let response = rateLimitResponse(
            creditID: creditID,
            expiresAt: Date().addingTimeInterval(2 * 60 * 60)
        )
        let longLived = OfflineAppServer(
            account: account,
            response: response
        )
        let suspended = SuspendedEnableAppServer(
            account: account,
            response: response
        )
        let factory = ResetCreditProtectionAppServerSessionFactory {
            ResetCreditProtectionAppServerSession(
                service: suspended,
                shutdown: {
                    await suspended.recordShutdown()
                }
            )
        }
        let clockAnchor = ResetCreditProtectionClockSample.now()
        var currentClock = clockAnchor
        let store = context.makeStore(
            appServer: longLived,
            sessionFactory: factory,
            clock: { currentClock }
        )

        store.enableResetCreditExpiryProtection()
        try await waitUntil {
            await suspended.snapshot().accountReadCount == 1
        }
        currentClock = ResetCreditProtectionClockSample(
            wallTime: clockAnchor.wallTime.addingTimeInterval(120.070),
            continuousTimeSeconds:
                clockAnchor.continuousTimeSeconds + 120
        )
        store.handleSystemClockChange()
        XCTAssertEqual(store.resetCreditProtectionStatus, .enabling)

        await suspended.releaseAccountRead()
        try await waitUntil {
            await suspended.snapshot().shutdownCount == 1
        }

        XCTAssertTrue(
            store.resetCreditProtectionEnabled,
            "Unexpected status: \(store.resetCreditProtectionStatus)"
        )
        XCTAssertTrue(
            context.defaults.bool(forKey: "resetCreditProtectionEnabled")
        )
        guard case .loaded(let savedConsent) =
            context.authorizationStore.load() else {
            return XCTFail("Expected enabling to persist authorization")
        }
        XCTAssertEqual(savedConsent.clockAnchor, clockAnchor)
        let snapshot = await suspended.snapshot()
        XCTAssertEqual(snapshot.consumeCallCount, 0)
        store.stop()
    }

    func testUnnotifiedClockJumpWhileEnablingFailsBeforeAuthorizationSave()
        async throws
    {
        let context = try OfflineStoreContext()
        defer { context.cleanup() }
        let creditID = "unnotified-enabling-clock-credit"
        let account = accountResponse(email: "account-a@example.com")
        let response = rateLimitResponse(
            creditID: creditID,
            expiresAt: Date().addingTimeInterval(2 * 60 * 60)
        )
        let longLived = OfflineAppServer(
            account: account,
            response: response
        )
        let suspended = SuspendedEnableAppServer(
            account: account,
            response: response
        )
        let factory = ResetCreditProtectionAppServerSessionFactory {
            ResetCreditProtectionAppServerSession(
                service: suspended,
                shutdown: {
                    await suspended.recordShutdown()
                }
            )
        }
        let clockAnchor = ResetCreditProtectionClockSample.now()
        var currentClock = clockAnchor
        let store = context.makeStore(
            appServer: longLived,
            sessionFactory: factory,
            clock: { currentClock }
        )

        store.enableResetCreditExpiryProtection()
        try await waitUntil {
            await suspended.snapshot().accountReadCount == 1
        }
        currentClock = ResetCreditProtectionClockSample(
            wallTime: clockAnchor.wallTime.addingTimeInterval(126),
            continuousTimeSeconds:
                clockAnchor.continuousTimeSeconds + 120
        )
        await suspended.releaseAccountRead()
        try await waitUntil {
            await suspended.snapshot().shutdownCount == 1
        }

        XCTAssertFalse(store.resetCreditProtectionEnabled)
        XCTAssertFalse(
            context.defaults.bool(forKey: "resetCreditProtectionEnabled")
        )
        XCTAssertEqual(context.authorizationStore.load(), .absent)
        guard case .blocked(.clockChanged, let detail) =
            store.resetCreditProtectionStatus else {
            return XCTFail("Expected the unnotified jump to fail closed")
        }
        XCTAssertTrue(detail?.contains("6.000") == true)
        let snapshot = await suspended.snapshot()
        XCTAssertEqual(snapshot.consumeCallCount, 0)
        store.stop()
    }

    func testPersistedClockDiscontinuityClosesProtectionAtStartup()
        throws
    {
        let context = try OfflineStoreContext()
        defer { context.cleanup() }
        let creditID = "restart-clock-credit"
        let account = accountResponse(email: "account-a@example.com")
        let current = ResetCreditProtectionClockSample.now()
        try context.authorizationStore.save(
            consent(
                account: account,
                creditIDs: [creditID],
                clockAnchor: ResetCreditProtectionClockSample(
                    wallTime: current.wallTime,
                    continuousTimeSeconds:
                        current.continuousTimeSeconds + 60
                )
            )
        )
        context.defaults.set(true, forKey: "resetCreditProtectionEnabled")
        let response = rateLimitResponse(
            creditID: creditID,
            expiresAt: Date().addingTimeInterval(10 * 60)
        )
        let longLived = OfflineAppServer(
            account: account,
            response: response
        )
        let sessions = OfflineSessionFactoryRecorder {
            OfflineAppServer(account: account, response: response)
        }

        let store = context.makeStore(
            appServer: longLived,
            sessionFactory: sessions.factory
        )

        XCTAssertFalse(store.resetCreditProtectionEnabled)
        XCTAssertFalse(
            context.defaults.bool(forKey: "resetCreditProtectionEnabled")
        )
        guard case .blocked(.clockChanged, let detail) =
            store.resetCreditProtectionStatus else {
            return XCTFail("Expected a persisted clock discontinuity")
        }
        XCTAssertTrue(detail?.contains("连续计时器") == true)
        XCTAssertEqual(context.authorizationStore.load(), .absent)
        XCTAssertEqual(sessions.count, 0)
    }

    func testBenignNTPClockNotificationsKeepProtectionEnabled()
        async throws
    {
        let context = try OfflineStoreContext()
        defer { context.cleanup() }
        let creditID = "benign-clock-credit"
        let account = accountResponse(email: "account-a@example.com")
        let anchor = ResetCreditProtectionClockSample(
            wallTime: Date(timeIntervalSince1970: 2_000_000_000),
            continuousTimeSeconds: 1_000
        )
        let storedConsent = try consent(
            account: account,
            creditIDs: [creditID],
            clockAnchor: anchor
        )
        try context.authorizationStore.save(storedConsent) {
            context.defaults.set(
                true,
                forKey: "resetCreditProtectionEnabled"
            )
        }
        let response = rateLimitResponse(
            creditID: creditID,
            expiresAt: Date().addingTimeInterval(2 * 60 * 60)
        )
        let appServer = OfflineAppServer(
            account: account,
            response: response
        )
        let sessions = OfflineSessionFactoryRecorder {
            OfflineAppServer(account: account, response: response)
        }
        let store = context.makeStore(
            appServer: appServer,
            sessionFactory: sessions.factory,
            clock: {
                ResetCreditProtectionClockSample(
                    wallTime: anchor.wallTime.addingTimeInterval(120.070),
                    continuousTimeSeconds: 1_120
                )
            }
        )

        XCTAssertTrue(store.resetCreditProtectionEnabled)
        for _ in 0..<3 {
            store.handleSystemClockChange()
        }

        XCTAssertTrue(store.resetCreditProtectionEnabled)
        XCTAssertTrue(
            context.defaults.bool(forKey: "resetCreditProtectionEnabled")
        )
        XCTAssertEqual(
            context.authorizationStore.load(),
            .loaded(storedConsent)
        )
        let snapshot = await appServer.snapshot()
        XCTAssertEqual(snapshot.consumeCallCount, 0)
        store.stop()
        try await Task.sleep(nanoseconds: 20_000_000)
    }

    func testClockDiscontinuityRevokesAuthorizationButPreservesActiveJournal()
        async throws
    {
        let context = try OfflineStoreContext()
        defer { context.cleanup() }
        let creditID = "clock-journal-credit"
        let expiresAt = Date().addingTimeInterval(10 * 60)
        let account = accountResponse(email: "account-a@example.com")
        let accountFingerprint = try accountFingerprint(account)
        let anchor = ResetCreditProtectionClockSample(
            wallTime: Date(timeIntervalSince1970: 2_000_000_000),
            continuousTimeSeconds: 1_000
        )
        let storedConsent = try consent(
            account: account,
            creditIDs: [creditID],
            clockAnchor: anchor
        )
        let journal = ResetCreditProtectionAttemptJournal(
            accountFingerprint: accountFingerprint,
            creditFingerprint: ResetCreditPrivacy.fingerprint(creditID),
            idempotencyKey: UUID().uuidString,
            expiresAt: expiresAt,
            availableCountBefore: 1,
            phase: .sending,
            updatedAt: Date()
        )
        try context.authorizationStore.save(storedConsent) {
            context.defaults.set(
                true,
                forKey: "resetCreditProtectionEnabled"
            )
        }
        try context.ledgerStore.save(
            ResetCreditProtectionLedger(activeAttempt: journal)
        )
        let response = rateLimitResponse(
            creditID: creditID,
            expiresAt: expiresAt
        )
        let appServer = OfflineAppServer(
            account: account,
            response: response
        )
        let sessions = OfflineSessionFactoryRecorder {
            OfflineAppServer(account: account, response: response)
        }
        var currentClock = ResetCreditProtectionClockSample(
            wallTime: anchor.wallTime.addingTimeInterval(120),
            continuousTimeSeconds: 1_120
        )
        let store = context.makeStore(
            appServer: appServer,
            sessionFactory: sessions.factory,
            clock: { currentClock }
        )
        XCTAssertTrue(store.resetCreditProtectionEnabled)

        currentClock = ResetCreditProtectionClockSample(
            wallTime: anchor.wallTime.addingTimeInterval(126),
            continuousTimeSeconds: 1_120
        )
        store.handleSystemClockChange()

        XCTAssertFalse(store.resetCreditProtectionEnabled)
        XCTAssertEqual(context.authorizationStore.load(), .absent)
        guard case .loaded(let preservedLedger) =
            context.ledgerStore.load() else {
            return XCTFail("Expected the unresolved journal to remain durable")
        }
        XCTAssertEqual(preservedLedger.activeAttempt, journal)
        store.refreshNow()
        try await waitUntil {
            guard let service = sessions.services.first else {
                return false
            }
            return await service.snapshot().shutdownCount == 1
        }
        let service = try XCTUnwrap(sessions.services.first)
        let snapshot = await service.snapshot()
        XCTAssertEqual(snapshot.consumeCallCount, 0)
        guard case .loaded(let reconciledLedger) =
            context.ledgerStore.load() else {
            return XCTFail("Expected reconciliation to preserve the journal")
        }
        XCTAssertEqual(reconciledLedger.activeAttempt, journal)
        store.stop()
    }

    func testClockHandlerUsesNewestAuthorizationGeneration()
        async throws
    {
        let context = try OfflineStoreContext()
        defer { context.cleanup() }
        let creditID = "new-clock-generation-credit"
        let account = accountResponse(email: "account-a@example.com")
        let oldAnchor = ResetCreditProtectionClockSample(
            wallTime: Date(timeIntervalSince1970: 1_000),
            continuousTimeSeconds: 100
        )
        let newAnchor = ResetCreditProtectionClockSample(
            wallTime: Date(timeIntervalSince1970: 2_000),
            continuousTimeSeconds: 1_500
        )
        let oldConsent = try consent(
            account: account,
            creditIDs: [creditID],
            clockAnchor: oldAnchor
        )
        let newConsent = try consent(
            account: account,
            creditIDs: [creditID],
            clockAnchor: newAnchor
        )
        try context.authorizationStore.save(oldConsent) {
            context.defaults.set(
                true,
                forKey: "resetCreditProtectionEnabled"
            )
        }
        var currentClock = ResetCreditProtectionClockSample(
            wallTime: oldAnchor.wallTime.addingTimeInterval(120),
            continuousTimeSeconds: 220
        )
        let response = rateLimitResponse(
            creditID: creditID,
            expiresAt: Date().addingTimeInterval(2 * 60 * 60)
        )
        let appServer = OfflineAppServer(
            account: account,
            response: response
        )
        let sessions = OfflineSessionFactoryRecorder {
            OfflineAppServer(account: account, response: response)
        }
        let store = context.makeStore(
            appServer: appServer,
            sessionFactory: sessions.factory,
            clock: { currentClock }
        )
        XCTAssertTrue(store.resetCreditProtectionEnabled)

        try context.authorizationStore.save(newConsent) {
            context.defaults.set(
                true,
                forKey: "resetCreditProtectionEnabled"
            )
        }
        currentClock = ResetCreditProtectionClockSample(
            wallTime: newAnchor.wallTime.addingTimeInterval(120.070),
            continuousTimeSeconds: 1_620
        )
        store.handleSystemClockChange()

        XCTAssertTrue(store.resetCreditProtectionEnabled)
        XCTAssertTrue(
            context.defaults.bool(forKey: "resetCreditProtectionEnabled")
        )
        XCTAssertEqual(
            context.authorizationStore.load(),
            .loaded(newConsent)
        )
        store.stop()
        try await Task.sleep(nanoseconds: 20_000_000)
    }

    func testBenignClockContinuitySurvivesStartup() throws {
        let context = try OfflineStoreContext()
        defer { context.cleanup() }
        let creditID = "startup-benign-clock-credit"
        let account = accountResponse(email: "account-a@example.com")
        let anchor = ResetCreditProtectionClockSample(
            wallTime: Date(timeIntervalSince1970: 2_000_000_000),
            continuousTimeSeconds: 1_000
        )
        let storedConsent = try consent(
            account: account,
            creditIDs: [creditID],
            clockAnchor: anchor
        )
        try context.authorizationStore.save(storedConsent) {
            context.defaults.set(
                true,
                forKey: "resetCreditProtectionEnabled"
            )
        }
        let response = rateLimitResponse(
            creditID: creditID,
            expiresAt: Date().addingTimeInterval(2 * 60 * 60)
        )
        let appServer = OfflineAppServer(
            account: account,
            response: response
        )
        let sessions = OfflineSessionFactoryRecorder {
            OfflineAppServer(account: account, response: response)
        }

        let store = context.makeStore(
            appServer: appServer,
            sessionFactory: sessions.factory,
            clock: {
                ResetCreditProtectionClockSample(
                    wallTime: anchor.wallTime.addingTimeInterval(120.070),
                    continuousTimeSeconds: 1_120
                )
            }
        )

        XCTAssertTrue(store.resetCreditProtectionEnabled)
        XCTAssertTrue(
            context.defaults.bool(forKey: "resetCreditProtectionEnabled")
        )
        XCTAssertEqual(
            context.authorizationStore.load(),
            .loaded(storedConsent)
        )
    }

    func testClockNotificationClearsAValidConsentWhenDesiredStateIsFalse()
        async throws
    {
        let context = try OfflineStoreContext()
        defer { context.cleanup() }
        let creditID = "clock-disabled-credit"
        let account = accountResponse(email: "account-a@example.com")
        let anchor = ResetCreditProtectionClockSample.now()
        let storedConsent = try consent(
            account: account,
            creditIDs: [creditID],
            clockAnchor: anchor
        )
        try context.authorizationStore.save(storedConsent) {
            context.defaults.set(
                true,
                forKey: "resetCreditProtectionEnabled"
            )
        }
        let response = rateLimitResponse(
            creditID: creditID,
            expiresAt: Date().addingTimeInterval(2 * 60 * 60)
        )
        let appServer = OfflineAppServer(
            account: account,
            response: response
        )
        let sessions = OfflineSessionFactoryRecorder {
            OfflineAppServer(account: account, response: response)
        }
        let store = context.makeStore(
            appServer: appServer,
            sessionFactory: sessions.factory
        )
        XCTAssertTrue(store.resetCreditProtectionEnabled)

        context.defaults.set(
            false,
            forKey: "resetCreditProtectionEnabled"
        )
        store.handleSystemClockChange()

        XCTAssertFalse(store.resetCreditProtectionEnabled)
        XCTAssertEqual(store.resetCreditProtectionStatus, .disabled)
        XCTAssertEqual(context.authorizationStore.load(), .absent)
        var dispatchCount = 0
        XCTAssertThrowsError(
            try context.authorizationStore.withAuthorizedDispatch(
                expected: storedConsent,
                creditFingerprint: ResetCreditPrivacy.fingerprint(creditID)
            ) {
                dispatchCount += 1
            }
        )
        XCTAssertEqual(dispatchCount, 0)
        store.stop()
        try await Task.sleep(nanoseconds: 20_000_000)
    }

    func testMissingAuthorizationDoesNotReportAClockDiscontinuity()
        async throws
    {
        let context = try OfflineStoreContext()
        defer { context.cleanup() }
        let creditID = "missing-clock-authorization-credit"
        let account = accountResponse(email: "account-a@example.com")
        let storedConsent = try consent(
            account: account,
            creditIDs: [creditID]
        )
        try context.authorizationStore.save(storedConsent) {
            context.defaults.set(
                true,
                forKey: "resetCreditProtectionEnabled"
            )
        }
        let response = rateLimitResponse(
            creditID: creditID,
            expiresAt: Date().addingTimeInterval(2 * 60 * 60)
        )
        let appServer = OfflineAppServer(
            account: account,
            response: response
        )
        let sessions = OfflineSessionFactoryRecorder {
            OfflineAppServer(account: account, response: response)
        }
        let store = context.makeStore(
            appServer: appServer,
            sessionFactory: sessions.factory
        )
        XCTAssertTrue(store.resetCreditProtectionEnabled)
        try context.authorizationStore.clear()
        context.defaults.set(
            true,
            forKey: "resetCreditProtectionEnabled"
        )

        store.handleSystemClockChange()

        XCTAssertFalse(store.resetCreditProtectionEnabled)
        guard case .blocked(.creditNotAuthorized, let detail) =
            store.resetCreditProtectionStatus else {
            return XCTFail("Missing authorization must not be a clock alert")
        }
        XCTAssertNotNil(detail)
        XCTAssertFalse(
            context.defaults.bool(forKey: "resetCreditProtectionEnabled")
        )
        XCTAssertEqual(context.authorizationStore.load(), .absent)
        let snapshot = await appServer.snapshot()
        XCTAssertEqual(snapshot.consumeCallCount, 0)
        store.stop()
        try await Task.sleep(nanoseconds: 20_000_000)
    }

    func testClockNotificationCannotArmANonDestructiveRuntime()
        async throws
    {
        let context = try OfflineStoreContext()
        defer { context.cleanup() }
        let creditID = "non-destructive-clock-credit"
        let account = accountResponse(email: "account-a@example.com")
        let anchor = ResetCreditProtectionClockSample.now()
        let storedConsent = try consent(
            account: account,
            creditIDs: [creditID],
            clockAnchor: anchor
        )
        try context.authorizationStore.save(storedConsent) {
            context.defaults.set(
                true,
                forKey: "resetCreditProtectionEnabled"
            )
        }
        let response = rateLimitResponse(
            creditID: creditID,
            expiresAt: Date().addingTimeInterval(2 * 60 * 60)
        )
        let appServer = OfflineAppServer(
            account: account,
            response: response
        )
        let sessions = OfflineSessionFactoryRecorder {
            OfflineAppServer(account: account, response: response)
        }
        let store = context.makeStore(
            appServer: appServer,
            sessionFactory: sessions.factory,
            clock: { anchor },
            destructiveActionsAllowed: false
        )
        XCTAssertFalse(store.resetCreditProtectionEnabled)

        store.handleSystemClockChange()

        XCTAssertFalse(store.resetCreditProtectionEnabled)
        XCTAssertEqual(store.resetCreditProtectionStatus, .disabled)
        XCTAssertTrue(
            context.defaults.bool(forKey: "resetCreditProtectionEnabled")
        )
        XCTAssertEqual(
            context.authorizationStore.load(),
            .loaded(storedConsent)
        )
        let snapshot = await appServer.snapshot()
        XCTAssertEqual(snapshot.consumeCallCount, 0)
        store.stop()
        try await Task.sleep(nanoseconds: 20_000_000)
    }

    func testSignedOutAccountClosesAuthorization() async throws {
        try await assertSignOutClosesAuthorization(mode: .accountUnavailable)
    }

    func testAuthenticationRPCErrorClosesAuthorization() async throws {
        try await assertSignOutClosesAuthorization(mode: .authenticationRPC)
    }

    func testFreshSessionKeepsPreflightConsumeAndPostflightTogether()
        async throws
    {
        let context = try OfflineStoreContext()
        defer { context.cleanup() }
        let creditID = "single-session-credit"
        let account = accountResponse(email: "account-a@example.com")
        let response = rateLimitResponse(
            creditID: creditID,
            expiresAt: Date().addingTimeInterval(10 * 60)
        )
        let longLived = OfflineAppServer(
            account: account,
            response: response
        )
        let sessions = OfflineSessionFactoryRecorder {
            OfflineAppServer(
                account: account,
                response: response,
                consumeOutcome: .reset
            )
        }
        let store = context.makeStore(
            appServer: longLived,
            sessionFactory: sessions.factory
        )

        store.enableResetCreditExpiryProtection()
        try await waitUntil {
            guard let service = sessions.services.first else {
                return false
            }
            return await service.snapshot().shutdownCount == 1
                && store.resetCreditProtectionStatus.isSucceeded
        }

        XCTAssertEqual(sessions.count, 1)
        let service = try XCTUnwrap(sessions.services.first)
        let snapshot = await service.snapshot()
        XCTAssertEqual(
            snapshot.calls,
            [
                "account",
                "account", "rate", "account",
                "account", "rate", "account",
                "account", "consume", "account",
                "account", "rate", "account",
            ]
        )
        XCTAssertEqual(snapshot.accountReadCount, 9)
        XCTAssertEqual(snapshot.rateLimitReadCount, 3)
        XCTAssertEqual(snapshot.consumeCallCount, 1)
        XCTAssertEqual(snapshot.shutdownCount, 1)
        let longLivedSnapshot = await longLived.snapshot()
        XCTAssertEqual(longLivedSnapshot.calls, [])
        guard case .loaded(let ledger) = context.ledgerStore.load() else {
            return XCTFail("Expected a durable terminal ledger")
        }
        XCTAssertNil(ledger.activeAttempt)
        XCTAssertEqual(ledger.tombstones.count, 1)
    }

    func testConfirmedNoOpAllowsANewLogicalAttemptWithANewIdempotencyKey()
        async throws
    {
        let context = try OfflineStoreContext()
        defer { context.cleanup() }
        let creditID = "confirmed-no-op-credit"
        let account = accountResponse(email: "account-a@example.com")
        let response = rateLimitResponse(
            creditID: creditID,
            expiresAt: Date().addingTimeInterval(10 * 60)
        )
        let firstLongLived = OfflineAppServer(
            account: account,
            response: response
        )
        let firstSessions = OfflineSessionFactoryRecorder {
            OfflineAppServer(
                account: account,
                response: response,
                consumeOutcome: .nothingToReset
            )
        }
        let firstStore = context.makeStore(
            appServer: firstLongLived,
            sessionFactory: firstSessions.factory
        )

        firstStore.enableResetCreditExpiryProtection()
        try await waitUntil {
            guard let service = firstSessions.services.first else {
                return false
            }
            return await service.snapshot().shutdownCount == 1
        }
        firstStore.stop()
        let firstService = try XCTUnwrap(firstSessions.services.first)
        let firstSnapshot = await firstService.snapshot()
        XCTAssertEqual(firstSnapshot.consumeCallCount, 1)
        let firstKey = try XCTUnwrap(firstSnapshot.idempotencyKeys.first)
        guard case .loaded(let firstLedger) = context.ledgerStore.load() else {
            return XCTFail("Expected the empty ledger to remain durable")
        }
        XCTAssertNil(firstLedger.activeAttempt)
        XCTAssertTrue(firstLedger.tombstones.isEmpty)
        guard case .loaded = context.authorizationStore.load() else {
            return XCTFail("Expected authorization after confirmed no-op")
        }

        let secondLongLived = OfflineAppServer(
            account: account,
            response: response
        )
        let secondSessions = OfflineSessionFactoryRecorder {
            OfflineAppServer(
                account: account,
                response: response,
                consumeOutcome: .nothingToReset
            )
        }
        let secondStore = context.makeStore(
            appServer: secondLongLived,
            sessionFactory: secondSessions.factory
        )
        XCTAssertTrue(secondStore.resetCreditProtectionEnabled)

        secondStore.refreshNow()
        try await waitUntil {
            guard let service = secondSessions.services.first else {
                return false
            }
            return await service.snapshot().shutdownCount == 1
        }
        secondStore.stop()
        let secondService = try XCTUnwrap(secondSessions.services.first)
        let secondSnapshot = await secondService.snapshot()
        XCTAssertEqual(secondSnapshot.consumeCallCount, 1)
        let secondKey = try XCTUnwrap(secondSnapshot.idempotencyKeys.first)
        XCTAssertNotEqual(firstKey, secondKey)
    }

    private func assertFreshPreflightCardSetChangeClosesAuthorization(
        consentCredits: [(String, Date)],
        freshCredits: [(String, Date)]
    ) async throws {
        let context = try OfflineStoreContext()
        defer { context.cleanup() }
        let account = accountResponse(email: "same-email@example.com")
        try context.authorizationStore.save(
            consent(
                account: account,
                creditIDs: consentCredits.map { $0.0 }
            )
        )
        context.defaults.set(true, forKey: "resetCreditProtectionEnabled")
        let longLivedResponse = rateLimitResponse(credits: consentCredits)
        let freshResponse = rateLimitResponse(credits: freshCredits)
        let longLived = OfflineAppServer(
            account: account,
            response: longLivedResponse
        )
        let sessions = OfflineSessionFactoryRecorder {
            OfflineAppServer(account: account, response: freshResponse)
        }
        let store = context.makeStore(
            appServer: longLived,
            sessionFactory: sessions.factory
        )

        store.refreshNow()
        try await waitUntil {
            guard let service = sessions.services.first else {
                return false
            }
            return await service.snapshot().shutdownCount == 1
                && !store.resetCreditProtectionEnabled
        }

        XCTAssertFalse(
            context.defaults.bool(forKey: "resetCreditProtectionEnabled")
        )
        XCTAssertEqual(context.authorizationStore.load(), .absent)
        XCTAssertEqual(
            store.resetCreditProtectionStatus,
            .blocked(.creditNotAuthorized, detail: nil)
        )
        let service = try XCTUnwrap(sessions.services.first)
        let snapshot = await service.snapshot()
        XCTAssertEqual(snapshot.calls, ["account", "rate", "account"])
        XCTAssertEqual(snapshot.consumeCallCount, 0)
        XCTAssertEqual(snapshot.shutdownCount, 1)
    }

    private func accountResponse(email: String) -> CodexAccountResponse {
        CodexAccountResponse(
            account: CodexAccount(
                type: "chatgpt",
                email: email,
                planType: "pro"
            ),
            requiresOpenaiAuth: false
        )
    }

    private func assertSignOutClosesAuthorization(
        mode: SignedOutAppServer.Mode
    ) async throws {
        let context = try OfflineStoreContext()
        defer { context.cleanup() }
        let creditID = "signed-out-credit"
        let account = accountResponse(email: "account-a@example.com")
        try context.authorizationStore.save(
            consent(account: account, creditIDs: [creditID])
        )
        context.defaults.set(true, forKey: "resetCreditProtectionEnabled")
        let response = rateLimitResponse(
            creditID: creditID,
            expiresAt: Date().addingTimeInterval(2 * 60 * 60)
        )
        let signedOut = SignedOutAppServer(
            mode: mode,
            response: response
        )
        let sessions = OfflineSessionFactoryRecorder {
            OfflineAppServer(account: account, response: response)
        }
        let store = context.makeStore(
            appServer: signedOut,
            sessionFactory: sessions.factory
        )

        XCTAssertTrue(store.resetCreditProtectionEnabled)
        store.refreshNow()
        try await waitUntil {
            !store.resetCreditProtectionEnabled
                && store.resetCreditProtectionStatus
                    == .blocked(.signedOut, detail: nil)
        }

        XCTAssertFalse(
            context.defaults.bool(forKey: "resetCreditProtectionEnabled")
        )
        XCTAssertEqual(context.authorizationStore.load(), .absent)
        XCTAssertEqual(sessions.count, 0)
        let snapshot = await signedOut.snapshot()
        XCTAssertGreaterThanOrEqual(snapshot.accountReadCount, 1)
        XCTAssertEqual(snapshot.consumeCallCount, 0)
    }

    private func accountFingerprint(
        _ response: CodexAccountResponse
    ) throws -> String {
        ResetCreditPrivacy.fingerprint(
            try XCTUnwrap(response.account?.protectionIdentitySeed)
        )
    }

    private func consent(
        account: CodexAccountResponse,
        creditIDs: [String],
        clockAnchor: ResetCreditProtectionClockSample = .now()
    ) throws -> ResetCreditProtectionConsent {
        ResetCreditProtectionConsent(
            version: AppConstants.resetCreditProtectionConsentVersion,
            accountFingerprint: try accountFingerprint(account),
            grantedAt: Date(),
            authorizedCreditFingerprints: Set(
                creditIDs.map(ResetCreditPrivacy.fingerprint)
            ),
            clockAnchor: clockAnchor
        )
    }

    private func rateLimitResponse(
        creditID: String,
        expiresAt: Date
    ) -> RateLimitResponse {
        rateLimitResponse(credits: [(creditID, expiresAt)])
    }

    private func rateLimitResponse(
        credits: [(String, Date)]
    ) -> RateLimitResponse {
        RateLimitResponse(
            rateLimits: RateLimitSnapshot(
                limitId: AppConstants.codexLimitID,
                limitName: "Codex",
                primary: nil,
                secondary: nil,
                credits: nil,
                planType: "pro",
                rateLimitReachedType: nil
            ),
            rateLimitsByLimitId: nil,
            rateLimitResetCredits: RateLimitResetCreditsSummary(
                availableCount: credits.count,
                credits: credits.map { credit in
                    RateLimitResetCredit(
                        id: credit.0,
                        resetType: "codexRateLimits",
                        status: "available",
                        grantedAt: Int64(
                            Date().addingTimeInterval(-3_600)
                                .timeIntervalSince1970
                        ),
                        expiresAt: Int64(credit.1.timeIntervalSince1970),
                        title: "Offline reset",
                        description: "Never leaves the test process"
                    )
                }
            )
        )
    }

    private func waitUntil(
        timeout: TimeInterval = 3,
        condition: () async -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if await condition() {
                return
            }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        throw WaitError.timedOut
    }
}

private enum WaitError: Error {
    case timedOut
}

private extension ResetCreditProtectionStatus {
    var isSucceeded: Bool {
        if case .succeeded = self {
            return true
        }
        return false
    }
}

private final class OfflineStoreContext {
    let suiteName: String
    let defaults: UserDefaults
    let directory: URL
    let ledgerStore: ResetCreditProtectionLedgerStore
    let authorizationStore: ResetCreditProtectionAuthorizationStore
    let processLockURL: URL
    private let radarSession: URLSession

    init() throws {
        let identifier = UUID().uuidString
        suiteName = "com.codexradar.sentinel.tests.\(identifier)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            throw OfflineStoreContextError.defaultsUnavailable
        }
        self.defaults = defaults
        defaults.removePersistentDomain(forName: suiteName)
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "codex-radar-sentinel-tests-\(identifier)",
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: false
        )
        ledgerStore = ResetCreditProtectionLedgerStore(
            url: directory.appendingPathComponent("ledger.json")
        )
        authorizationStore = ResetCreditProtectionAuthorizationStore(
            url: directory.appendingPathComponent("authorization.json"),
            dispatchLockURL: directory.appendingPathComponent(
                "authorization.lock"
            )
        )
        processLockURL = directory.appendingPathComponent("process.lock")
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [OfflineURLProtocol.self]
        radarSession = URLSession(configuration: configuration)
    }

    func disableBackgroundFeatures() {
        defaults.set(false, forKey: "automaticUpdatesEnabled")
        defaults.set(false, forKey: "resetCreditAutoRefreshEnabled")
        defaults.set(false, forKey: "predictionNotificationsEnabled")
        defaults.set(false, forKey: "iqNotificationsEnabled")
    }

    @MainActor
    func makeStore(
        appServer: any ResetCreditProtectionAppServerServing,
        sessionFactory: ResetCreditProtectionAppServerSessionFactory,
        clock: @escaping () -> ResetCreditProtectionClockSample = {
            .now()
        },
        destructiveActionsAllowed: Bool? = nil
    ) -> SentinelStore {
        SentinelStore(
            defaults: defaults,
            radarClient: CodexRadarClient(
                baseURL: URL(string: "https://offline.invalid/")!,
                radarInsightsURL: URL(
                    string: "https://offline.invalid/api/v1/radar-insights"
                )!,
                session: radarSession
            ),
            appServerClient: appServer,
            resetCreditProtectionSessionFactory: sessionFactory,
            resetCreditProtectionLedgerStore: ledgerStore,
            resetCreditProtectionAuthorizationStore: authorizationStore,
            resetCreditProtectionProcessLockURL: processLockURL,
            resetCreditProtectionClock: clock,
            resetCreditProtectionDestructiveActionsAllowed:
                destructiveActionsAllowed
        )
    }

    func cleanup() {
        // Refresh tasks are cancelled by their stores and can still be
        // unwinding when a test returns. The ephemeral session is released
        // with this context after those tasks finish; explicitly invalidating
        // it here can race a final request and raise an Objective-C exception.
        defaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: directory)
    }
}

private enum OfflineStoreContextError: Error {
    case defaultsUnavailable
}

private final class OfflineURLProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(
            self,
            didReceive: response,
            cacheStoragePolicy: .notAllowed
        )
        client?.urlProtocol(self, didLoad: Data("{}".utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private actor OfflineAppServer: ResetCreditProtectionAppServerServing {
    struct Snapshot {
        let calls: [String]
        let accountReadCount: Int
        let rateLimitReadCount: Int
        let consumeCallCount: Int
        let idempotencyKeys: [String]
        let shutdownCount: Int
    }

    private let account: CodexAccountResponse
    private let response: RateLimitResponse
    private let consumeOutcome: ResetCreditConsumeOutcome
    private var calls: [String] = []
    private var accountReadCount = 0
    private var rateLimitReadCount = 0
    private var consumeCallCount = 0
    private var idempotencyKeys: [String] = []
    private var shutdownCount = 0

    init(
        account: CodexAccountResponse,
        response: RateLimitResponse,
        consumeOutcome: ResetCreditConsumeOutcome = .nothingToReset
    ) {
        self.account = account
        self.response = response
        self.consumeOutcome = consumeOutcome
    }

    func readRateLimits() async throws -> RateLimitResponse {
        calls.append("rate")
        rateLimitReadCount += 1
        return response
    }

    func readAccount() async throws -> CodexAccountResponse {
        calls.append("account")
        accountReadCount += 1
        return account
    }

    func consumeResetCredit(
        creditID: String,
        idempotencyKey: String,
        authorization: ResetCreditProtectionDispatchAuthorization
    ) async throws -> ResetCreditConsumeResponse {
        precondition(!creditID.isEmpty)
        precondition(UUID(uuidString: idempotencyKey) != nil)
        calls.append("consume")
        consumeCallCount += 1
        idempotencyKeys.append(idempotencyKey)
        return try authorization.perform(creditID: creditID) {
            ResetCreditConsumeResponse(outcome: consumeOutcome)
        }
    }

    func recordShutdown() {
        shutdownCount += 1
    }

    func snapshot() -> Snapshot {
        Snapshot(
            calls: calls,
            accountReadCount: accountReadCount,
            rateLimitReadCount: rateLimitReadCount,
            consumeCallCount: consumeCallCount,
            idempotencyKeys: idempotencyKeys,
            shutdownCount: shutdownCount
        )
    }
}

private final class OfflineSessionFactoryRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private let makeService: @Sendable () -> OfflineAppServer
    private var recordedServices: [OfflineAppServer] = []

    init(makeService: @escaping @Sendable () -> OfflineAppServer) {
        self.makeService = makeService
    }

    var factory: ResetCreditProtectionAppServerSessionFactory {
        ResetCreditProtectionAppServerSessionFactory { [self] in
            let service = makeService()
            lock.lock()
            recordedServices.append(service)
            lock.unlock()
            return ResetCreditProtectionAppServerSession(
                service: service,
                shutdown: {
                    await service.recordShutdown()
                }
            )
        }
    }

    var services: [OfflineAppServer] {
        lock.lock()
        defer { lock.unlock() }
        return recordedServices
    }

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return recordedServices.count
    }
}

private actor SuspendedNothingToResetAppServer:
    ResetCreditProtectionAppServerServing
{
    struct Snapshot {
        let accountReadCount: Int
        let rateLimitReadCount: Int
        let consumeCallCount: Int
        let authorizedDispatchCount: Int
        let consumeReturnCount: Int
    }

    private let account: CodexAccountResponse
    private let response: RateLimitResponse
    private var accountReadCount = 0
    private var rateLimitReadCount = 0
    private var consumeCallCount = 0
    private var authorizedDispatchCount = 0
    private var consumeReturnCount = 0
    private var releaseContinuation: CheckedContinuation<Void, Never>?
    private var consumeReleased = false

    init(creditID: String, expiresAt: Date) {
        account = CodexAccountResponse(
            account: CodexAccount(
                type: "chatgpt",
                email: "offline-test@example.com",
                planType: "pro"
            ),
            requiresOpenaiAuth: false
        )
        response = RateLimitResponse(
            rateLimits: RateLimitSnapshot(
                limitId: AppConstants.codexLimitID,
                limitName: "Codex",
                primary: nil,
                secondary: nil,
                credits: nil,
                planType: "pro",
                rateLimitReachedType: nil
            ),
            rateLimitsByLimitId: nil,
            rateLimitResetCredits: RateLimitResetCreditsSummary(
                availableCount: 1,
                credits: [
                    RateLimitResetCredit(
                        id: creditID,
                        resetType: "codexRateLimits",
                        status: "available",
                        grantedAt: Int64(
                            Date().addingTimeInterval(-3_600)
                                .timeIntervalSince1970
                        ),
                        expiresAt: Int64(expiresAt.timeIntervalSince1970),
                        title: "Offline test reset",
                        description: "Never leaves the test process"
                    ),
                ]
            )
        )
    }

    func readRateLimits() async throws -> RateLimitResponse {
        rateLimitReadCount += 1
        return response
    }

    func readAccount() async throws -> CodexAccountResponse {
        accountReadCount += 1
        return account
    }

    func consumeResetCredit(
        creditID: String,
        idempotencyKey: String,
        authorization: ResetCreditProtectionDispatchAuthorization
    ) async throws -> ResetCreditConsumeResponse {
        precondition(!creditID.isEmpty)
        precondition(UUID(uuidString: idempotencyKey) != nil)
        consumeCallCount += 1
        try authorization.perform(creditID: creditID) {
            authorizedDispatchCount += 1
        }
        await withCheckedContinuation { continuation in
            if consumeReleased {
                continuation.resume()
            } else {
                releaseContinuation = continuation
            }
        }
        consumeReturnCount += 1
        return ResetCreditConsumeResponse(outcome: .nothingToReset)
    }

    func releaseConsume() {
        consumeReleased = true
        releaseContinuation?.resume()
        releaseContinuation = nil
    }

    func snapshot() -> Snapshot {
        Snapshot(
            accountReadCount: accountReadCount,
            rateLimitReadCount: rateLimitReadCount,
            consumeCallCount: consumeCallCount,
            authorizedDispatchCount: authorizedDispatchCount,
            consumeReturnCount: consumeReturnCount
        )
    }
}

private actor SuspendedEnableAppServer:
    ResetCreditProtectionAppServerServing
{
    struct Snapshot {
        let accountReadCount: Int
        let rateLimitReadCount: Int
        let consumeCallCount: Int
        let shutdownCount: Int
    }

    private let account: CodexAccountResponse
    private let response: RateLimitResponse
    private var accountReadCount = 0
    private var rateLimitReadCount = 0
    private var consumeCallCount = 0
    private var shutdownCount = 0
    private var accountReadReleased = false
    private var accountReadContinuation: CheckedContinuation<Void, Never>?

    init(account: CodexAccountResponse, response: RateLimitResponse) {
        self.account = account
        self.response = response
    }

    func readRateLimits() async throws -> RateLimitResponse {
        rateLimitReadCount += 1
        return response
    }

    func readAccount() async throws -> CodexAccountResponse {
        accountReadCount += 1
        if accountReadCount == 1, !accountReadReleased {
            await withCheckedContinuation { continuation in
                accountReadContinuation = continuation
            }
        }
        return account
    }

    func consumeResetCredit(
        creditID: String,
        idempotencyKey: String,
        authorization: ResetCreditProtectionDispatchAuthorization
    ) async throws -> ResetCreditConsumeResponse {
        consumeCallCount += 1
        return try authorization.perform(creditID: creditID) {
            ResetCreditConsumeResponse(outcome: .nothingToReset)
        }
    }

    func releaseAccountRead() {
        accountReadReleased = true
        accountReadContinuation?.resume()
        accountReadContinuation = nil
    }

    func recordShutdown() {
        shutdownCount += 1
    }

    func snapshot() -> Snapshot {
        Snapshot(
            accountReadCount: accountReadCount,
            rateLimitReadCount: rateLimitReadCount,
            consumeCallCount: consumeCallCount,
            shutdownCount: shutdownCount
        )
    }
}

private actor SignedOutAppServer: ResetCreditProtectionAppServerServing {
    enum Mode {
        case accountUnavailable
        case authenticationRPC
    }

    struct Snapshot {
        let accountReadCount: Int
        let consumeCallCount: Int
    }

    private let mode: Mode
    private let response: RateLimitResponse
    private var accountReadCount = 0
    private var consumeCallCount = 0

    init(mode: Mode, response: RateLimitResponse) {
        self.mode = mode
        self.response = response
    }

    func readRateLimits() async throws -> RateLimitResponse {
        response
    }

    func readAccount() async throws -> CodexAccountResponse {
        accountReadCount += 1
        switch mode {
        case .accountUnavailable:
            throw ResetCreditProtectionAccountBindingError.accountUnavailable
        case .authenticationRPC:
            throw CodexAppServerClient.ClientError.rpcError(
                code: -32600,
                message: "authentication required"
            )
        }
    }

    func consumeResetCredit(
        creditID: String,
        idempotencyKey: String,
        authorization: ResetCreditProtectionDispatchAuthorization
    ) async throws -> ResetCreditConsumeResponse {
        consumeCallCount += 1
        return ResetCreditConsumeResponse(outcome: .nothingToReset)
    }

    func snapshot() -> Snapshot {
        Snapshot(
            accountReadCount: accountReadCount,
            consumeCallCount: consumeCallCount
        )
    }
}

private actor NetworkFailingAppServer:
    ResetCreditProtectionAppServerServing
{
    struct Snapshot {
        let rateLimitReadCount: Int
        let consumeCallCount: Int
        let shutdownCount: Int
    }

    private let account: CodexAccountResponse
    private var rateLimitReadCount = 0
    private var consumeCallCount = 0
    private var shutdownCount = 0

    init(account: CodexAccountResponse) {
        self.account = account
    }

    func readRateLimits() async throws -> RateLimitResponse {
        rateLimitReadCount += 1
        throw URLError(.notConnectedToInternet)
    }

    func readAccount() async throws -> CodexAccountResponse {
        account
    }

    func consumeResetCredit(
        creditID: String,
        idempotencyKey: String,
        authorization: ResetCreditProtectionDispatchAuthorization
    ) async throws -> ResetCreditConsumeResponse {
        consumeCallCount += 1
        throw URLError(.notConnectedToInternet)
    }

    func recordShutdown() {
        shutdownCount += 1
    }

    func snapshot() -> Snapshot {
        Snapshot(
            rateLimitReadCount: rateLimitReadCount,
            consumeCallCount: consumeCallCount,
            shutdownCount: shutdownCount
        )
    }
}
