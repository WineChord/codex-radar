import XCTest
@testable import CodexRadarCore

final class ResetCreditExpiryProtectionTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 2_000_000_000)

    func testAuthorizationDefaultsOffAndRequiresCurrentConsent() {
        let authorizedCredit = ResetCreditPrivacy.fingerprint("authorized-credit")
        XCTAssertFalse(
            ResetCreditProtectionAuthorization.isEnabled(
                requested: nil,
                consent: nil
            )
        )
        XCTAssertFalse(
            ResetCreditProtectionAuthorization.isEnabled(
                requested: true,
                consent: nil
            )
        )
        XCTAssertFalse(
            ResetCreditProtectionAuthorization.isEnabled(
                requested: true,
                consent: ResetCreditProtectionConsent(
                    version: AppConstants.resetCreditProtectionConsentVersion - 1,
                    accountFingerprint: "account-fingerprint",
                    grantedAt: now,
                    authorizedCreditFingerprints: [authorizedCredit]
                )
            )
        )
        XCTAssertFalse(
            ResetCreditProtectionAuthorization.isEnabled(
                requested: true,
                consent: ResetCreditProtectionConsent(
                    version: AppConstants.resetCreditProtectionConsentVersion,
                    accountFingerprint: "account-fingerprint",
                    authorizationID: "not-a-uuid",
                    grantedAt: now,
                    authorizedCreditFingerprints: [authorizedCredit]
                )
            )
        )
        XCTAssertFalse(
            ResetCreditProtectionAuthorization.isEnabled(
                requested: true,
                consent: ResetCreditProtectionConsent(
                    version: AppConstants.resetCreditProtectionConsentVersion,
                    accountFingerprint: "account-fingerprint",
                    grantedAt: now
                )
            )
        )
        XCTAssertTrue(
            ResetCreditProtectionAuthorization.isEnabled(
                requested: true,
                consent: ResetCreditProtectionConsent(
                    version: AppConstants.resetCreditProtectionConsentVersion,
                    accountFingerprint: "account-fingerprint",
                    grantedAt: now,
                    authorizedCreditFingerprints: [authorizedCredit]
                )
            )
        )
    }

    func testConsentCodablePersistsADeDuplicatedCardFingerprintSet() throws {
        let first = ResetCreditPrivacy.fingerprint("first-credit")
        let second = ResetCreditPrivacy.fingerprint("second-credit")
        let consent = ResetCreditProtectionConsent(
            version: AppConstants.resetCreditProtectionConsentVersion,
            accountFingerprint: ResetCreditPrivacy.fingerprint("account"),
            authorizationID: "11111111-1111-4111-8111-111111111111",
            grantedAt: now,
            authorizedCreditFingerprints: [first, second, first]
        )

        let encoded = try JSONEncoder().encode(consent)
        let decoded = try JSONDecoder().decode(
            ResetCreditProtectionConsent.self,
            from: encoded
        )

        XCTAssertEqual(decoded, consent)
        XCTAssertEqual(decoded.authorizedCreditFingerprints, [first, second])
        XCTAssertTrue(
            ResetCreditProtectionAuthorization.isEnabled(
                requested: true,
                consent: decoded
            )
        )
    }

    func testClockContinuityAllowsElapsedTimeButRejectsJumpAndRestart() {
        let fingerprint = ResetCreditPrivacy.fingerprint("authorized-credit")
        let anchor = ResetCreditProtectionClockSample(
            wallTime: Date(timeIntervalSince1970: 1_000),
            continuousTimeSeconds: 500
        )
        let consent = ResetCreditProtectionConsent(
            version: AppConstants.resetCreditProtectionConsentVersion,
            accountFingerprint: ResetCreditPrivacy.fingerprint("account"),
            grantedAt: anchor.wallTime,
            authorizedCreditFingerprints: [fingerprint],
            clockAnchor: anchor
        )

        XCTAssertTrue(
            ResetCreditProtectionAuthorization.isEnabled(
                requested: true,
                consent: consent,
                currentClock: ResetCreditProtectionClockSample(
                    wallTime: Date(timeIntervalSince1970: 1_120),
                    continuousTimeSeconds: 620
                )
            )
        )
        XCTAssertFalse(
            ResetCreditProtectionAuthorization.isEnabled(
                requested: true,
                consent: consent,
                currentClock: ResetCreditProtectionClockSample(
                    wallTime: Date(timeIntervalSince1970: 1_240),
                    continuousTimeSeconds: 620
                )
            )
        )
        XCTAssertFalse(
            ResetCreditProtectionAuthorization.isEnabled(
                requested: true,
                consent: consent,
                currentClock: ResetCreditProtectionClockSample(
                    wallTime: Date(timeIntervalSince1970: 1_120),
                    continuousTimeSeconds: 20
                )
            )
        )
    }

    func testClockDiscontinuityBlocksFinalAuthorizedDispatch() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "codex-radar-clock-auth-\(UUID().uuidString)",
                isDirectory: true
            )
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ResetCreditProtectionAuthorizationStore(
            url: directory.appendingPathComponent("authorization.json"),
            dispatchLockURL: directory.appendingPathComponent("dispatch.lock")
        )
        let current = ResetCreditProtectionClockSample.now()
        let consent = ResetCreditProtectionConsent(
            version: AppConstants.resetCreditProtectionConsentVersion,
            accountFingerprint: ResetCreditPrivacy.fingerprint("account"),
            grantedAt: current.wallTime,
            authorizedCreditFingerprints: [
                ResetCreditPrivacy.fingerprint("credit-selected"),
            ],
            clockAnchor: ResetCreditProtectionClockSample(
                wallTime: current.wallTime,
                continuousTimeSeconds:
                    current.continuousTimeSeconds + 60
            )
        )
        try store.save(consent)

        var dispatchCount = 0
        XCTAssertThrowsError(
            try store.withAuthorizedDispatch(
                expected: consent,
                creditFingerprint: ResetCreditPrivacy.fingerprint(
                    "credit-selected"
                )
            ) {
                dispatchCount += 1
            }
        )
        XCTAssertEqual(dispatchCount, 0)
    }

    func testLegacyConsentWithoutCardFingerprintsFailsClosed() throws {
        let legacy = """
        {
          "version": 1,
          "accountFingerprint": "account-fingerprint",
          "authorizationID": "11111111-1111-4111-8111-111111111111",
          "grantedAt": 2000000000
        }
        """

        XCTAssertThrowsError(
            try JSONDecoder().decode(
                ResetCreditProtectionConsent.self,
                from: Data(legacy.utf8)
            )
        )
    }

    func testConsentWithoutClockAnchorFailsClosed() {
        let preClockConsent = """
        {
          "version": \(AppConstants.resetCreditProtectionConsentVersion),
          "accountFingerprint": "\(ResetCreditPrivacy.fingerprint("account"))",
          "authorizationID": "11111111-1111-4111-8111-111111111111",
          "grantedAt": 2000000000,
          "authorizedCreditFingerprints": [
            "\(ResetCreditPrivacy.fingerprint("credit-selected"))"
          ]
        }
        """

        XCTAssertThrowsError(
            try JSONDecoder().decode(
                ResetCreditProtectionConsent.self,
                from: Data(preClockConsent.utf8)
            )
        )
    }

    func testAuthorizationIsBoundToTheExplicitlyConfirmedCard() {
        let authorizedFingerprint = ResetCreditPrivacy.fingerprint("authorized-credit")
        let otherFingerprint = ResetCreditPrivacy.fingerprint("other-credit")
        let consent = ResetCreditProtectionConsent(
            version: AppConstants.resetCreditProtectionConsentVersion,
            accountFingerprint: ResetCreditPrivacy.fingerprint("account"),
            authorizationID: "11111111-1111-4111-8111-111111111111",
            grantedAt: now,
            authorizedCreditFingerprints: [authorizedFingerprint]
        )

        XCTAssertTrue(
            ResetCreditProtectionAuthorization.authorizes(
                requested: true,
                consent: consent,
                creditFingerprint: authorizedFingerprint
            )
        )
        XCTAssertFalse(
            ResetCreditProtectionAuthorization.authorizes(
                requested: true,
                consent: consent,
                creditFingerprint: otherFingerprint
            )
        )
        XCTAssertTrue(
            ResetCreditProtectionAuthorization.authorizes(
                requested: true,
                consent: consent,
                target: target(
                    id: "authorized-credit",
                    expiresAt: now.addingTimeInterval(1_800),
                    availableCount: 1
                )
            )
        )
        XCTAssertFalse(
            ResetCreditProtectionAuthorization.authorizes(
                requested: false,
                consent: consent,
                creditFingerprint: authorizedFingerprint
            )
        )
    }

    func testSchedulesEarliestSupportedCreditThirtyMinutesBeforeExpiry() {
        let summary = summary(
            availableCount: 2,
            credits: [
                credit(id: "later-credit", expiresAt: now.addingTimeInterval(7_200)),
                credit(id: "sooner-credit", expiresAt: now.addingTimeInterval(3_600)),
            ]
        )

        let decision = ResetCreditExpiryProtectionPolicy().decision(summary: summary, now: now)

        guard case .scheduled(let target) = decision else {
            return XCTFail("Expected a scheduled target, got \(decision)")
        }
        XCTAssertEqual(target.creditID, "sooner-credit")
        XCTAssertEqual(target.expiresAt, now.addingTimeInterval(3_600))
        XCTAssertEqual(target.actionAt, now.addingTimeInterval(1_800))
    }

    func testConfirmedCreditFingerprintIsExcludedWithoutBlockingAnotherCredit() {
        let summary = summary(
            availableCount: 2,
            credits: [
                credit(id: "confirmed-credit", expiresAt: now.addingTimeInterval(1_800)),
                credit(id: "next-credit", expiresAt: now.addingTimeInterval(3_600)),
            ]
        )

        let decision = ResetCreditExpiryProtectionPolicy().decision(
            summary: summary,
            now: now,
            excludingCreditFingerprints: [
                ResetCreditPrivacy.fingerprint("confirmed-credit"),
            ]
        )

        guard case .scheduled(let target) = decision else {
            return XCTFail("Expected the next untombstoned credit, got \(decision)")
        }
        XCTAssertEqual(target.creditID, "next-credit")
    }

    func testTombstoneExcludesTheSameCreditGloballyAcrossAccounts() {
        let creditID = "shared-credit"
        let creditFingerprint = ResetCreditPrivacy.fingerprint(creditID)
        let tombstone = ResetCreditProtectionTombstone(
            accountFingerprint: ResetCreditPrivacy.fingerprint("account-a"),
            creditFingerprint: creditFingerprint,
            idempotencyKey: "11111111-1111-4111-8111-111111111111",
            expiresAt: now.addingTimeInterval(1_800),
            disposition: .confirmedUsed,
            terminalAt: now
        )
        let ledger = ResetCreditProtectionLedger(tombstones: [tombstone])

        XCTAssertNotEqual(
            tombstone.accountFingerprint,
            ResetCreditPrivacy.fingerprint("account-b")
        )
        XCTAssertEqual(ledger.excludedCreditFingerprints, [creditFingerprint])
        XCTAssertEqual(
            ResetCreditExpiryProtectionPolicy().decision(
                summary: summary(
                    availableCount: 1,
                    credits: [
                        credit(
                            id: creditID,
                            expiresAt: now.addingTimeInterval(1_800)
                        ),
                    ]
                ),
                now: now,
                excludingCreditFingerprints: ledger.excludedCreditFingerprints
            ),
            .noSupportedExpiringCredits(availableCount: 1)
        )
    }

    func testBecomesReadyAtLeadTimeBoundaryButNeverAfterExpiry() {
        let expiresAt = now.addingTimeInterval(1_800)
        let summary = summary(
            availableCount: 1,
            credits: [credit(id: "ready-credit", expiresAt: expiresAt)]
        )

        let ready = ResetCreditExpiryProtectionPolicy().decision(summary: summary, now: now)
        XCTAssertEqual(
            ready,
            .ready(target(id: "ready-credit", expiresAt: expiresAt, availableCount: 1))
        )

        let expired = ResetCreditExpiryProtectionPolicy().decision(
            summary: summary,
            now: expiresAt
        )
        XCTAssertEqual(expired, .noSupportedExpiringCredits(availableCount: 1))
    }

    func testFailsClosedWhenDetailsAreMissingOrIncomplete() {
        let countOnly = RateLimitResetCreditsSummary(availableCount: 2, credits: nil)
        XCTAssertEqual(
            ResetCreditExpiryProtectionPolicy().decision(summary: countOnly, now: now),
            .detailsUnavailable(availableCount: 2)
        )

        let incomplete = summary(
            availableCount: 2,
            credits: [credit(id: "only-detail", expiresAt: now.addingTimeInterval(3_600))]
        )
        XCTAssertEqual(
            ResetCreditExpiryProtectionPolicy().decision(summary: incomplete, now: now),
            .detailsIncomplete(availableCount: 2, availableDetails: 1)
        )
    }

    func testFailsClosedWhenAnAvailableCreditHasAnEmptyID() {
        let decision = ResetCreditExpiryProtectionPolicy().decision(
            summary: summary(
                availableCount: 1,
                credits: [
                    credit(id: "", expiresAt: now.addingTimeInterval(3_600)),
                ]
            ),
            now: now
        )

        guard case .detailsIncomplete(let availableCount, _) = decision else {
            return XCTFail("Expected incomplete details, got \(decision)")
        }
        XCTAssertEqual(availableCount, 1)
    }

    func testFailsClosedWhenAnAvailableCountHasAnUnknownStatusRow() {
        let summary = summary(
            availableCount: 1,
            credits: [
                credit(
                    id: "unknown-status",
                    status: "unknown",
                    expiresAt: now.addingTimeInterval(3_600)
                ),
            ]
        )

        XCTAssertEqual(
            ResetCreditExpiryProtectionPolicy().decision(summary: summary, now: now),
            .detailsIncomplete(availableCount: 1, availableDetails: 0)
        )
    }

    func testRejectsUnknownTypeAndUnknownExpiryAfterCoverageIsComplete() {
        let summary = summary(
            availableCount: 2,
            credits: [
                credit(
                    id: "unknown-type",
                    resetType: "unknown",
                    expiresAt: now.addingTimeInterval(3_600)
                ),
                credit(id: "unknown-expiry", expiresAt: nil),
            ]
        )

        XCTAssertEqual(
            ResetCreditExpiryProtectionPolicy().decision(summary: summary, now: now),
            .noSupportedExpiringCredits(availableCount: 2)
        )
    }

    func testJournalNeverEncodesRawCreditOrAccountIdentity() throws {
        let rawCreditID = "RateLimitResetCredit_private-value"
        let rawAccount = "person@example.com"
        let journal = ResetCreditProtectionAttemptJournal(
            accountFingerprint: ResetCreditPrivacy.fingerprint(rawAccount),
            creditFingerprint: ResetCreditPrivacy.fingerprint(rawCreditID),
            idempotencyKey: UUID().uuidString,
            expiresAt: now.addingTimeInterval(1_800),
            availableCountBefore: 1,
            phase: .sending,
            updatedAt: now
        )

        let encoded = try XCTUnwrap(String(data: JSONEncoder().encode(journal), encoding: .utf8))

        XCTAssertFalse(encoded.contains(rawCreditID))
        XCTAssertFalse(encoded.contains(rawAccount))
    }

    func testProcessLockExcludesASecondProcessCoordinator() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-radar-lock-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("protection.lock")
        let first = try ResetCreditProtectionProcessLock(url: url)

        XCTAssertThrowsError(try ResetCreditProtectionProcessLock(url: url))

        first.release()
        let second = try ResetCreditProtectionProcessLock(url: url)
        second.release()
    }

    func testRecoveryTreatsConfirmedOutcomeAsUsedEvenAfterExpiry() {
        let journal = recoveryJournal(
            phase: .outcomeConfirmed,
            confirmedOutcome: .reset,
            expiresAt: now.addingTimeInterval(-1)
        )

        let decision = ResetCreditProtectionRecoveryPolicy().decision(
            journal: journal,
            summary: nil,
            now: now,
            protectionEnabled: true,
            retryAt: nil
        )

        XCTAssertEqual(decision, .confirmedUsed)
    }

    func testRecoveryRetriesSameAvailableCreditOnlyWhenEnabled() {
        let expiresAt = now.addingTimeInterval(900)
        let journal = recoveryJournal(
            phase: .sentUnknown,
            expiresAt: expiresAt
        )
        let credits = summary(
            availableCount: 1,
            credits: [credit(id: "same-credit", expiresAt: expiresAt)]
        )

        let decision = ResetCreditProtectionRecoveryPolicy().decision(
            journal: journal,
            summary: credits,
            now: now,
            protectionEnabled: true,
            retryAt: nil
        )

        guard case .retry(let target) = decision else {
            return XCTFail("Expected the original credit to be retried, got \(decision)")
        }
        XCTAssertEqual(target.creditID, "same-credit")
        XCTAssertEqual(target.creditFingerprint, journal.creditFingerprint)
        XCTAssertEqual(
            journal.idempotencyKey,
            "4d4d876e-506c-421c-8614-383e3c630211"
        )
    }

    func testRecoveryNeverRetriesWhenDisabled() {
        let expiresAt = now.addingTimeInterval(900)
        let journal = recoveryJournal(
            phase: .sentUnknown,
            expiresAt: expiresAt
        )
        let credits = summary(
            availableCount: 1,
            credits: [credit(id: "same-credit", expiresAt: expiresAt)]
        )

        XCTAssertEqual(
            ResetCreditProtectionRecoveryPolicy().decision(
                journal: journal,
                summary: credits,
                now: now,
                protectionEnabled: false,
                retryAt: nil
            ),
            .reconciling
        )
    }

    func testRecoveryConfirmsRedeemedTargetWhenAvailableCountIsZero() {
        let expiresAt = now.addingTimeInterval(900)
        let journal = recoveryJournal(phase: .sentUnknown, expiresAt: expiresAt)
        let credits = summary(
            availableCount: 0,
            credits: [
                credit(
                    id: "same-credit",
                    status: "redeemed",
                    expiresAt: expiresAt
                ),
            ]
        )

        XCTAssertEqual(
            ResetCreditProtectionRecoveryPolicy().decision(
                journal: journal,
                summary: credits,
                now: now,
                protectionEnabled: true,
                retryAt: nil
            ),
            .confirmedUsed
        )
    }

    func testRecoveryKeepsRedeemingTargetWhenAvailableCountIsZero() {
        let expiresAt = now.addingTimeInterval(900)
        let journal = recoveryJournal(phase: .sentUnknown, expiresAt: expiresAt)
        let credits = summary(
            availableCount: 0,
            credits: [
                credit(
                    id: "same-credit",
                    status: "redeeming",
                    expiresAt: expiresAt
                ),
            ]
        )

        XCTAssertEqual(
            ResetCreditProtectionRecoveryPolicy().decision(
                journal: journal,
                summary: credits,
                now: now,
                protectionEnabled: true,
                retryAt: nil
            ),
            .reconciling
        )
    }

    func testRecoveryMarksAnExpiredRedeemingTargetAsMissed() {
        let expiresAt = now.addingTimeInterval(-1)
        let journal = recoveryJournal(phase: .sentUnknown, expiresAt: expiresAt)
        let credits = summary(
            availableCount: 0,
            credits: [
                credit(
                    id: "same-credit",
                    status: "redeeming",
                    expiresAt: expiresAt
                ),
            ]
        )

        XCTAssertEqual(
            ResetCreditProtectionRecoveryPolicy().decision(
                journal: journal,
                summary: credits,
                now: now,
                protectionEnabled: true,
                retryAt: nil
            ),
            .missed
        )
    }

    func testRecoveryKeepsJournalWhenZeroCountHasNoDetails() {
        let expiresAt = now.addingTimeInterval(900)
        let journal = recoveryJournal(phase: .sentUnknown, expiresAt: expiresAt)

        XCTAssertEqual(
            ResetCreditProtectionRecoveryPolicy().decision(
                journal: journal,
                summary: summary(availableCount: 0, credits: nil),
                now: now,
                protectionEnabled: true,
                retryAt: nil
            ),
            .reconciling
        )
    }

    func testRecoveryFailsClosedOnContradictoryAvailableCount() {
        let expiresAt = now.addingTimeInterval(900)
        let journal = recoveryJournal(phase: .sentUnknown, expiresAt: expiresAt)

        XCTAssertEqual(
            ResetCreditProtectionRecoveryPolicy().decision(
                journal: journal,
                summary: summary(
                    availableCount: 0,
                    credits: [
                        credit(id: "same-credit", expiresAt: expiresAt),
                    ]
                ),
                now: now,
                protectionEnabled: true,
                retryAt: nil
            ),
            .reconciling
        )
    }

    func testRecoveryFailsClosedWhenAvailableDetailsAreTruncated() {
        let expiresAt = now.addingTimeInterval(900)
        let journal = recoveryJournal(phase: .sentUnknown, expiresAt: expiresAt)

        XCTAssertEqual(
            ResetCreditProtectionRecoveryPolicy().decision(
                journal: journal,
                summary: summary(
                    availableCount: 2,
                    credits: [
                        credit(id: "same-credit", expiresAt: expiresAt),
                    ]
                ),
                now: now,
                protectionEnabled: true,
                retryAt: nil
            ),
            .reconciling
        )
    }

    func testRecoveryFailsClosedWhenAnotherAvailableCreditHasAnEmptyID() {
        let expiresAt = now.addingTimeInterval(900)
        let journal = recoveryJournal(phase: .sentUnknown, expiresAt: expiresAt)

        XCTAssertEqual(
            ResetCreditProtectionRecoveryPolicy().decision(
                journal: journal,
                summary: summary(
                    availableCount: 2,
                    credits: [
                        credit(id: "same-credit", expiresAt: expiresAt),
                        credit(id: "", expiresAt: expiresAt),
                    ]
                ),
                now: now,
                protectionEnabled: true,
                retryAt: nil
            ),
            .reconciling
        )
    }

    func testConfirmedNonConsumptionRequiresSameCreditStillAvailable() {
        let expiresAt = now.addingTimeInterval(900)
        let journal = recoveryJournal(
            phase: .outcomeConfirmed,
            confirmedOutcome: .nothingToReset,
            expiresAt: expiresAt
        )
        let available = summary(
            availableCount: 1,
            credits: [credit(id: "same-credit", expiresAt: expiresAt)]
        )

        XCTAssertEqual(
            ResetCreditProtectionRecoveryPolicy().decision(
                journal: journal,
                summary: available,
                now: now,
                protectionEnabled: true,
                retryAt: nil
            ),
            .confirmedNotConsumed(expiresAt: expiresAt)
        )
        XCTAssertEqual(
            ResetCreditProtectionRecoveryPolicy().decision(
                journal: journal,
                summary: summary(availableCount: 0, credits: nil),
                now: now,
                protectionEnabled: true,
                retryAt: nil
            ),
            .reconciling
        )
    }

    func testRecoveryDoesNotClearAnIndeterminateExpiredJournal() {
        let journal = recoveryJournal(
            phase: .sentUnknown,
            expiresAt: now.addingTimeInterval(-1)
        )
        let incomplete = summary(availableCount: 1, credits: [])

        XCTAssertEqual(
            ResetCreditProtectionRecoveryPolicy().decision(
                journal: journal,
                summary: incomplete,
                now: now,
                protectionEnabled: true,
                retryAt: nil
            ),
            .missed
        )
    }

    func testLedgerStoreRoundTripsAtomicallyAndDetectsCorruption() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-radar-journal-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("journal.json")
        let store = ResetCreditProtectionLedgerStore(url: url)
        let journal = recoveryJournal(
            phase: .sentUnknown,
            expiresAt: now.addingTimeInterval(900)
        )
        let ledger = ResetCreditProtectionLedger(activeAttempt: journal)

        XCTAssertEqual(store.load(), .absent)
        try store.save(ledger)
        XCTAssertEqual(store.load(), .loaded(ledger))
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        XCTAssertEqual(attributes[.posixPermissions] as? NSNumber, NSNumber(value: 0o600))

        try Data(#"{"broken":true}"#.utf8).write(to: url)
        XCTAssertEqual(store.load(), .corrupt)

        try store.clear()
        XCTAssertEqual(store.load(), .absent)
    }

    func testLedgerMigratesLegacyAttemptWithoutChangingTheKey() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-radar-legacy-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("journal.json")
        let journal = recoveryJournal(
            phase: .sentUnknown,
            expiresAt: now.addingTimeInterval(900)
        )
        try JSONEncoder().encode(journal).write(to: url)

        XCTAssertEqual(
            ResetCreditProtectionLedgerStore(url: url).load(),
            .loaded(ResetCreditProtectionLedger(activeAttempt: journal))
        )
    }

    func testAuthorizationGenerationLinearizesDispatchAndRevocation() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-radar-auth-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ResetCreditProtectionAuthorizationStore(
            url: directory.appendingPathComponent("authorization.json"),
            dispatchLockURL: directory.appendingPathComponent("dispatch.lock")
        )
        let first = consent(authorizationID: "11111111-1111-4111-8111-111111111111")
        let second = consent(authorizationID: "22222222-2222-4222-8222-222222222222")
        try store.save(first)

        var dispatchCount = 0
        try store.withAuthorizedDispatch(
            expected: first,
            creditFingerprint: ResetCreditPrivacy.fingerprint("credit-selected")
        ) {
            dispatchCount += 1
        }
        try store.save(second)
        XCTAssertThrowsError(
            try store.withAuthorizedDispatch(
                expected: first,
                creditFingerprint: ResetCreditPrivacy.fingerprint("credit-selected")
            ) {
                dispatchCount += 1
            }
        )
        try store.withAuthorizedDispatch(
            expected: second,
            creditFingerprint: ResetCreditPrivacy.fingerprint("credit-selected")
        ) {
            dispatchCount += 1
        }
        try store.clear()
        XCTAssertThrowsError(
            try store.withAuthorizedDispatch(
                expected: second,
                creditFingerprint: ResetCreditPrivacy.fingerprint("credit-selected")
            ) {
                dispatchCount += 1
            }
        )
        XCTAssertEqual(dispatchCount, 2)
    }

    func testConditionalClearFromAnOldGenerationPreservesNewAuthorization() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-radar-auth-cas-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ResetCreditProtectionAuthorizationStore(
            url: directory.appendingPathComponent("authorization.json"),
            dispatchLockURL: directory.appendingPathComponent("dispatch.lock")
        )
        let oldConsent = consent(
            authorizationID: "11111111-1111-4111-8111-111111111111"
        )
        let newConsent = consent(
            authorizationID: "22222222-2222-4222-8222-222222222222"
        )
        try store.save(oldConsent)
        try store.save(newConsent)

        XCTAssertEqual(
            try store.clear(ifCurrent: oldConsent),
            .superseded
        )
        XCTAssertEqual(store.load(), .loaded(newConsent))
    }

    func testLedgerRejectsTwoKeysForTheSameAccountAndCredit() throws {
        let journal = recoveryJournal(
            phase: .sentUnknown,
            expiresAt: now.addingTimeInterval(900)
        )
        let first = ResetCreditProtectionTombstone(
            journal: journal,
            disposition: .ambiguous,
            terminalAt: now
        )
        let second = ResetCreditProtectionTombstone(
            accountFingerprint: journal.accountFingerprint,
            creditFingerprint: journal.creditFingerprint,
            idempotencyKey: "44444444-4444-4444-8444-444444444444",
            expiresAt: journal.expiresAt,
            disposition: .confirmedUsed,
            terminalAt: now
        )
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-radar-conflict-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ResetCreditProtectionLedgerStore(
            url: directory.appendingPathComponent("ledger.json")
        )

        XCTAssertThrowsError(
            try store.save(
                ResetCreditProtectionLedger(
                    tombstones: [first, second]
                )
            )
        )
        XCTAssertEqual(store.load(), .absent)
    }

    func testLedgerRejectsTheSameCreditInTombstonesAcrossAccounts() throws {
        let creditFingerprint = ResetCreditPrivacy.fingerprint("shared-credit")
        let first = ResetCreditProtectionTombstone(
            accountFingerprint: ResetCreditPrivacy.fingerprint("account-a"),
            creditFingerprint: creditFingerprint,
            idempotencyKey: "11111111-1111-4111-8111-111111111111",
            expiresAt: now.addingTimeInterval(900),
            disposition: .ambiguous,
            terminalAt: now
        )
        let second = ResetCreditProtectionTombstone(
            accountFingerprint: ResetCreditPrivacy.fingerprint("account-b"),
            creditFingerprint: creditFingerprint,
            idempotencyKey: "22222222-2222-4222-8222-222222222222",
            expiresAt: now.addingTimeInterval(900),
            disposition: .confirmedUsed,
            terminalAt: now
        )
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "codex-radar-cross-account-tombstones-\(UUID().uuidString)",
                isDirectory: true
            )
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ResetCreditProtectionLedgerStore(
            url: directory.appendingPathComponent("ledger.json")
        )

        XCTAssertThrowsError(
            try store.save(
                ResetCreditProtectionLedger(tombstones: [first, second])
            )
        )
        XCTAssertEqual(store.load(), .absent)
    }

    func testLedgerRejectsTheSameCreditInATombstoneAndActiveAttemptAcrossAccounts() throws {
        let creditFingerprint = ResetCreditPrivacy.fingerprint("shared-credit")
        let tombstone = ResetCreditProtectionTombstone(
            accountFingerprint: ResetCreditPrivacy.fingerprint("account-a"),
            creditFingerprint: creditFingerprint,
            idempotencyKey: "11111111-1111-4111-8111-111111111111",
            expiresAt: now.addingTimeInterval(900),
            disposition: .ambiguous,
            terminalAt: now
        )
        let activeAttempt = ResetCreditProtectionAttemptJournal(
            accountFingerprint: ResetCreditPrivacy.fingerprint("account-b"),
            creditFingerprint: creditFingerprint,
            idempotencyKey: "22222222-2222-4222-8222-222222222222",
            expiresAt: now.addingTimeInterval(900),
            availableCountBefore: 1,
            phase: .sending,
            updatedAt: now
        )
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "codex-radar-cross-account-active-\(UUID().uuidString)",
                isDirectory: true
            )
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ResetCreditProtectionLedgerStore(
            url: directory.appendingPathComponent("ledger.json")
        )

        XCTAssertThrowsError(
            try store.save(
                ResetCreditProtectionLedger(
                    activeAttempt: activeAttempt,
                    tombstones: [tombstone]
                )
            )
        )
        XCTAssertEqual(store.load(), .absent)
    }

    func testBoundAppServerVerifiesAccountBeforeAndAfterConsume() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-radar-bound-success-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let account = accountResponse(email: "current@example.com")
        let service = BoundAppServerSpy(accountResponses: [account, account])
        let server = ResetCreditProtectionBoundAppServer(service: service)

        let response = try await server.consumeResetCredit(
            creditID: "credit-selected",
            idempotencyKey: "33333333-3333-4333-8333-333333333333",
            authorization: try authorization(in: directory),
            boundTo: try accountFingerprint(account)
        )

        XCTAssertEqual(response.outcome, .reset)
        let snapshot = await service.snapshot()
        XCTAssertEqual(
            snapshot.calls,
            ["account/read", "consume", "account/read"]
        )
        XCTAssertEqual(snapshot.consumeCount, 1)
    }

    func testBoundAppServerDoesNotConsumeWhenPreflightAccountChanged() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-radar-bound-preflight-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let expectedAccount = accountResponse(email: "expected@example.com")
        let changedAccount = accountResponse(email: "changed@example.com")
        let service = BoundAppServerSpy(accountResponses: [changedAccount])
        let server = ResetCreditProtectionBoundAppServer(service: service)

        do {
            _ = try await server.consumeResetCredit(
                creditID: "credit-selected",
                idempotencyKey: "33333333-3333-4333-8333-333333333333",
                authorization: try authorization(in: directory),
                boundTo: try accountFingerprint(expectedAccount)
            )
            XCTFail("Expected an account-change error")
        } catch ResetCreditProtectionAccountBindingError.accountChanged {
            // Expected.
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        let snapshot = await service.snapshot()
        XCTAssertEqual(snapshot.calls, ["account/read"])
        XCTAssertEqual(snapshot.consumeCount, 0)
    }

    func testBoundAppServerReportsAccountChangeAfterConsume() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-radar-bound-postflight-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let expectedAccount = accountResponse(email: "expected@example.com")
        let changedAccount = accountResponse(email: "changed@example.com")
        let service = BoundAppServerSpy(
            accountResponses: [expectedAccount, changedAccount]
        )
        let server = ResetCreditProtectionBoundAppServer(service: service)

        do {
            _ = try await server.consumeResetCredit(
                creditID: "credit-selected",
                idempotencyKey: "33333333-3333-4333-8333-333333333333",
                authorization: try authorization(in: directory),
                boundTo: try accountFingerprint(expectedAccount)
            )
            XCTFail("Expected an account-change error")
        } catch ResetCreditProtectionAccountBindingError.accountChanged {
            // Expected.
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        let snapshot = await service.snapshot()
        XCTAssertEqual(
            snapshot.calls,
            ["account/read", "consume", "account/read"]
        )
        XCTAssertEqual(snapshot.consumeCount, 1)
    }

    func testBoundAppServerDisallowsConsumeWhenDestructiveActionsAreDisabled() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-radar-bound-disabled-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let account = accountResponse(email: "current@example.com")
        let service = BoundAppServerSpy(accountResponses: [account, account])
        let server = ResetCreditProtectionBoundAppServer(
            service: service,
            destructiveActionsAllowed: false
        )

        do {
            _ = try await server.consumeResetCredit(
                creditID: "credit-selected",
                idempotencyKey: "33333333-3333-4333-8333-333333333333",
                authorization: try authorization(in: directory),
                boundTo: try accountFingerprint(account)
            )
            XCTFail("Expected destructive actions to be rejected")
        } catch ResetCreditProtectionAccountBindingError.destructiveActionsDisabled {
            // Expected.
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        let snapshot = await service.snapshot()
        XCTAssertEqual(snapshot.consumeCount, 0)
        XCTAssertEqual(snapshot.calls, [])
    }

    func testRevokedAuthorizationWritesNoConsumeRequest() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-radar-revoked-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let executable = directory.appendingPathComponent("fake-codex")
        let transcript = directory.appendingPathComponent("requests.jsonl")
        let script = """
        #!/bin/sh
        IFS= read -r initialize_request
        printf '%s\\n' "$initialize_request" >> '\(transcript.path)'
        printf '%s\\n' '{"id":1,"result":{"userAgent":"fake","codexHome":"/tmp","platformFamily":"unix","platformOs":"macos"}}'
        IFS= read -r account_request
        printf '%s\\n' "$account_request" >> '\(transcript.path)'
        printf '%s\\n' '{"id":2,"result":{"account":{"type":"chatgpt","email":"offline@example.com","planType":"pro"},"requiresOpenaiAuth":false}}'
        while IFS= read -r request; do
          printf '%s\\n' "$request" >> '\(transcript.path)'
          printf '%s\\n' '{"id":3,"result":{"outcome":"reset"}}'
        done
        """
        try Data(script.utf8).write(to: executable)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: executable.path
        )
        let dispatchAuthorization = try authorization(in: directory)
        try dispatchAuthorization.store.clear()
        let client = CodexAppServerClient(binaryURLProvider: { executable })
        _ = try await client.readAccount()

        do {
            _ = try await client.consumeResetCredit(
                creditID: "credit-selected",
                idempotencyKey: UUID().uuidString,
                authorization: dispatchAuthorization
            )
            XCTFail("Expected dispatch authorization to reject the request")
        } catch CodexAppServerClient.ClientError.resetCreditDispatchNotAuthorized {
            // Expected: initialize is allowed, destructive RPC is not written.
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        await client.shutdown()

        let lines = try String(contentsOf: transcript, encoding: .utf8)
            .split(separator: "\n")
        XCTAssertEqual(lines.count, 2)
        let request = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: Data(lines[1].utf8)) as? [String: Any]
        )
        XCTAssertEqual(request["method"] as? String, "account/read")
    }

    func testConsumeUsesOfficialAppServerRPCWithoutARealBackend() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-radar-app-server-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let executable = directory.appendingPathComponent("fake-codex")
        let transcript = directory.appendingPathComponent("requests.jsonl")
        let script = """
        #!/bin/sh
        IFS= read -r initialize_request
        printf '%s\\n' "$initialize_request" >> '\(transcript.path)'
        printf '%s\\n' '{"id":1,"result":{"userAgent":"fake","codexHome":"/tmp","platformFamily":"unix","platformOs":"macos"}}'
        IFS= read -r account_request
        printf '%s\\n' "$account_request" >> '\(transcript.path)'
        printf '%s\\n' '{"id":2,"result":{"account":{"type":"chatgpt","email":"offline@example.com","planType":"pro"},"requiresOpenaiAuth":false}}'
        IFS= read -r consume_request
        printf '%s\\n' "$consume_request" >> '\(transcript.path)'
        printf '%s\\n' '{"id":3,"result":{"outcome":"reset"}}'
        while IFS= read -r _; do :; done
        """
        try Data(script.utf8).write(to: executable)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: executable.path
        )
        let client = CodexAppServerClient(
            binaryURLProvider: { executable },
            allowsAutomaticRestart: false
        )
        let dispatchAuthorization = try authorization(in: directory)
        _ = try await client.readAccount()

        let response = try await client.consumeResetCredit(
            creditID: "credit-selected",
            idempotencyKey: "4d4d876e-506c-421c-8614-383e3c630211",
            authorization: dispatchAuthorization
        )
        await client.shutdown()

        XCTAssertEqual(response.outcome, .reset)
        let lines = try String(contentsOf: transcript, encoding: .utf8)
            .split(separator: "\n")
        XCTAssertEqual(lines.count, 3)
        let request = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: Data(lines[2].utf8)) as? [String: Any]
        )
        XCTAssertEqual(request["method"] as? String, "account/rateLimitResetCredit/consume")
        let params = try XCTUnwrap(request["params"] as? [String: Any])
        XCTAssertEqual(params["creditId"] as? String, "credit-selected")
        XCTAssertEqual(
            params["idempotencyKey"] as? String,
            "4d4d876e-506c-421c-8614-383e3c630211"
        )
    }

    func testConsumeDoesNotRestartAfterVerifiedAppServerProcessExits()
        async throws
    {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "codex-radar-app-server-exit-\(UUID().uuidString)",
                isDirectory: true
            )
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let executable = directory.appendingPathComponent("fake-codex")
        let transcript = directory.appendingPathComponent("requests.jsonl")
        let script = """
        #!/bin/sh
        IFS= read -r initialize_request
        printf '%s\\n' "$initialize_request" >> '\(transcript.path)'
        printf '%s\\n' '{"id":1,"result":{"userAgent":"fake","codexHome":"/tmp","platformFamily":"unix","platformOs":"macos"}}'
        IFS= read -r account_request
        printf '%s\\n' "$account_request" >> '\(transcript.path)'
        printf '%s\\n' '{"id":2,"result":{"account":{"type":"chatgpt","email":"offline@example.com","planType":"pro"},"requiresOpenaiAuth":false}}'
        exit 0
        """
        try Data(script.utf8).write(to: executable)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: executable.path
        )
        let client = CodexAppServerClient(
            binaryURLProvider: { executable },
            allowsAutomaticRestart: false
        )
        let dispatchAuthorization = try authorization(in: directory)

        _ = try await client.readAccount()
        let deadline = Date().addingTimeInterval(2)
        while await client.hasLiveInitializedSession(), Date() < deadline {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        let hasLiveSession = await client.hasLiveInitializedSession()
        XCTAssertFalse(hasLiveSession)

        do {
            _ = try await client.readAccount()
            XCTFail("Expected one-shot reads to reject a replacement process")
        } catch CodexAppServerClient.ClientError.processUnavailable {
            // Expected: the one-shot session cannot cross process generations.
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        do {
            _ = try await client.consumeResetCredit(
                creditID: "credit-selected",
                idempotencyKey: UUID().uuidString,
                authorization: dispatchAuthorization
            )
            XCTFail("Expected the ended verified session to block dispatch")
        } catch CodexAppServerClient.ClientError
            .resetCreditSessionUnavailableBeforeDispatch {
            // Expected: a destructive call never starts a replacement process.
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        await client.shutdown()

        let lines = try String(contentsOf: transcript, encoding: .utf8)
            .split(separator: "\n")
        XCTAssertEqual(lines.count, 2)
        let request = try XCTUnwrap(
            try JSONSerialization.jsonObject(
                with: Data(lines[1].utf8)
            ) as? [String: Any]
        )
        XCTAssertEqual(request["method"] as? String, "account/read")
    }

    func testUnconfirmedCardWritesNoConsumeRequest() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "codex-radar-card-authorization-\(UUID().uuidString)",
                isDirectory: true
            )
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let executable = directory.appendingPathComponent("fake-codex")
        let transcript = directory.appendingPathComponent("requests.jsonl")
        let script = """
        #!/bin/sh
        IFS= read -r initialize_request
        printf '%s\\n' "$initialize_request" >> '\(transcript.path)'
        printf '%s\\n' '{"id":1,"result":{"userAgent":"fake","codexHome":"/tmp","platformFamily":"unix","platformOs":"macos"}}'
        IFS= read -r account_request
        printf '%s\\n' "$account_request" >> '\(transcript.path)'
        printf '%s\\n' '{"id":2,"result":{"account":{"type":"chatgpt","email":"offline@example.com","planType":"pro"},"requiresOpenaiAuth":false}}'
        while IFS= read -r request; do
          printf '%s\\n' "$request" >> '\(transcript.path)'
          printf '%s\\n' '{"id":3,"result":{"outcome":"reset"}}'
        done
        """
        try Data(script.utf8).write(to: executable)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: executable.path
        )
        let client = CodexAppServerClient(binaryURLProvider: { executable })
        let dispatchAuthorization = try authorization(in: directory)
        _ = try await client.readAccount()

        do {
            _ = try await client.consumeResetCredit(
                creditID: "not-confirmed",
                idempotencyKey: UUID().uuidString,
                authorization: dispatchAuthorization
            )
            XCTFail("Expected card-bound authorization to reject the request")
        } catch CodexAppServerClient.ClientError.resetCreditDispatchNotAuthorized {
            // Expected: initialize is allowed, an unconfirmed card is never written.
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        await client.shutdown()

        let lines = try String(contentsOf: transcript, encoding: .utf8)
            .split(separator: "\n")
        XCTAssertEqual(lines.count, 2)
        let request = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: Data(lines[1].utf8)) as? [String: Any]
        )
        XCTAssertEqual(request["method"] as? String, "account/read")
    }

    func testConsumeDecodesEveryOfficialOutcome() async throws {
        for outcome in ResetCreditConsumeOutcome.allCases {
            let fixture = try makeFakeCodex(
                response: #"{"id":3,"result":{"outcome":"\#(outcome.rawValue)"}}"#
            )
            defer { try? FileManager.default.removeItem(at: fixture.directory) }
            let client = CodexAppServerClient(binaryURLProvider: { fixture.executable })
            let dispatchAuthorization = try authorization(in: fixture.directory)
            _ = try await client.readAccount()

            let response = try await client.consumeResetCredit(
                creditID: "credit-selected",
                idempotencyKey: UUID().uuidString,
                authorization: dispatchAuthorization
            )
            await client.shutdown()

            XCTAssertEqual(response.outcome, outcome)
        }
    }

    func testConsumePreservesOfficialRPCErrorCodeAndMessage() async throws {
        let fixture = try makeFakeCodex(
            response: #"{"id":3,"error":{"code":-32601,"message":"Method not found"}}"#
        )
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let client = CodexAppServerClient(binaryURLProvider: { fixture.executable })
        let dispatchAuthorization = try authorization(in: fixture.directory)
        _ = try await client.readAccount()

        do {
            _ = try await client.consumeResetCredit(
                creditID: "credit-selected",
                idempotencyKey: UUID().uuidString,
                authorization: dispatchAuthorization
            )
            XCTFail("Expected the app-server error to be preserved")
        } catch let CodexAppServerClient.ClientError.rpcError(code, message) {
            XCTAssertEqual(code, -32601)
            XCTAssertEqual(message, "Method not found")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        await client.shutdown()
    }

    private func summary(
        availableCount: Int,
        credits: [RateLimitResetCredit]?
    ) -> RateLimitResetCreditsSummary {
        RateLimitResetCreditsSummary(availableCount: availableCount, credits: credits)
    }

    private func credit(
        id: String,
        resetType: String = "codexRateLimits",
        status: String = "available",
        expiresAt: Date?
    ) -> RateLimitResetCredit {
        RateLimitResetCredit(
            id: id,
            resetType: resetType,
            status: status,
            grantedAt: Int64(now.addingTimeInterval(-86_400).timeIntervalSince1970),
            expiresAt: expiresAt.map { Int64($0.timeIntervalSince1970) },
            title: "Full reset",
            description: "Reset current usage limits"
        )
    }

    private func target(
        id: String,
        expiresAt: Date,
        availableCount: Int
    ) -> ResetCreditProtectionTarget {
        ResetCreditProtectionTarget(
            creditID: id,
            creditFingerprint: ResetCreditPrivacy.fingerprint(id),
            idSuffix: String(id.suffix(6)),
            expiresAt: expiresAt,
            actionAt: expiresAt.addingTimeInterval(-1_800),
            availableCount: availableCount
        )
    }

    private func recoveryJournal(
        phase: ResetCreditProtectionAttemptJournal.Phase,
        confirmedOutcome: ResetCreditConsumeOutcome? = nil,
        expiresAt: Date
    ) -> ResetCreditProtectionAttemptJournal {
        ResetCreditProtectionAttemptJournal(
            accountFingerprint: ResetCreditPrivacy.fingerprint("account"),
            creditFingerprint: ResetCreditPrivacy.fingerprint("same-credit"),
            idempotencyKey: "4d4d876e-506c-421c-8614-383e3c630211",
            expiresAt: expiresAt,
            availableCountBefore: 1,
            phase: phase,
            confirmedOutcome: confirmedOutcome,
            updatedAt: now
        )
    }

    private func consent(authorizationID: String) -> ResetCreditProtectionConsent {
        ResetCreditProtectionConsent(
            version: AppConstants.resetCreditProtectionConsentVersion,
            accountFingerprint: ResetCreditPrivacy.fingerprint("account"),
            authorizationID: authorizationID,
            grantedAt: now,
            authorizedCreditFingerprints: [
                ResetCreditPrivacy.fingerprint("credit-selected"),
            ]
        )
    }

    private func authorization(
        in directory: URL
    ) throws -> ResetCreditProtectionDispatchAuthorization {
        let store = ResetCreditProtectionAuthorizationStore(
            url: directory.appendingPathComponent("authorization.json"),
            dispatchLockURL: directory.appendingPathComponent("dispatch.lock")
        )
        let current = consent(
            authorizationID: "33333333-3333-4333-8333-333333333333"
        )
        try store.save(current)
        return ResetCreditProtectionDispatchAuthorization(
            store: store,
            consent: current
        )
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

    private func accountFingerprint(
        _ response: CodexAccountResponse
    ) throws -> String {
        ResetCreditPrivacy.fingerprint(
            try XCTUnwrap(response.account?.protectionIdentitySeed)
        )
    }

    private func makeFakeCodex(
        response: String
    ) throws -> (directory: URL, executable: URL) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-radar-app-server-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let executable = directory.appendingPathComponent("fake-codex")
        let script = """
        #!/bin/sh
        IFS= read -r _
        printf '%s\\n' '{"id":1,"result":{"userAgent":"fake","codexHome":"/tmp","platformFamily":"unix","platformOs":"macos"}}'
        IFS= read -r _
        printf '%s\\n' '{"id":2,"result":{"account":{"type":"chatgpt","email":"offline@example.com","planType":"pro"},"requiresOpenaiAuth":false}}'
        IFS= read -r _
        printf '%s\\n' '\(response)'
        while IFS= read -r _; do :; done
        """
        try Data(script.utf8).write(to: executable)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: executable.path
        )
        return (directory, executable)
    }
}

private actor BoundAppServerSpy: ResetCreditProtectionAppServerServing {
    private enum StubError: Error {
        case missingAccountResponse
        case unexpectedRateLimitRead
    }

    private var accountResponses: [CodexAccountResponse]
    private var calls: [String] = []
    private var consumeCallCount = 0

    init(accountResponses: [CodexAccountResponse]) {
        self.accountResponses = accountResponses
    }

    func readRateLimits() async throws -> RateLimitResponse {
        calls.append("rateLimits/read")
        throw StubError.unexpectedRateLimitRead
    }

    func readAccount() async throws -> CodexAccountResponse {
        calls.append("account/read")
        guard !accountResponses.isEmpty else {
            throw StubError.missingAccountResponse
        }
        return accountResponses.removeFirst()
    }

    func consumeResetCredit(
        creditID: String,
        idempotencyKey: String,
        authorization: ResetCreditProtectionDispatchAuthorization
    ) async throws -> ResetCreditConsumeResponse {
        calls.append("consume")
        consumeCallCount += 1
        return ResetCreditConsumeResponse(outcome: .reset)
    }

    func snapshot() -> (calls: [String], consumeCount: Int) {
        (calls, consumeCallCount)
    }
}
