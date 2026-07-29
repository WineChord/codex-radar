import Foundation
import XCTest
@testable import CodexRadarCore
@testable import CodexRadarSentinel

@MainActor
final class DashboardLayoutTests: XCTestCase {
    func testDefaultLayoutIsCompleteUniqueAndPrioritizesCoreSections() {
        XCTAssertEqual(
            DashboardLayout.default.order,
            [
                .quota,
                .modelIQ,
                .resetCredits,
                .usagePace,
                .insights,
                .radarDetails,
                .menuBarGuide,
                .displayAndAlerts,
                .updates,
                .preview,
            ]
        )
        XCTAssertEqual(
            Set(DashboardLayout.default.order),
            Set(DashboardSection.allCases)
        )
        XCTAssertEqual(
            DashboardLayout.default.order.count,
            DashboardSection.allCases.count
        )
        XCTAssertEqual(
            DashboardLayout.default.expandedSections,
            [.quota, .modelIQ, .usagePace, .insights]
        )
    }

    func testNestedDisclosuresHaveOneRegisteredParentAndSafeDefaults() {
        XCTAssertEqual(
            DashboardDisclosure.children(of: .modelIQ),
            [.modelIQDetails]
        )
        XCTAssertEqual(
            DashboardDisclosure.children(of: .insights),
            [.radarInsightsDetails]
        )
        for section in DashboardSection.allCases
        where section != .modelIQ && section != .insights {
            XCTAssertTrue(
                DashboardDisclosure.children(of: section).isEmpty
            )
        }

        let registered = DashboardSection.allCases.flatMap {
            DashboardDisclosure.children(of: $0)
        }
        XCTAssertEqual(registered, DashboardDisclosure.allCases)
        XCTAssertEqual(Set(registered).count, registered.count)
        XCTAssertFalse(
            DashboardDisclosure.modelIQDetails.isExpandedByDefault
        )
        XCTAssertFalse(
            DashboardDisclosure.radarInsightsDetails
                .isExpandedByDefault
        )
    }

    func testMovingSectionsHandlesBothDirectionsAndBoundaries() {
        var layout = DashboardLayout.default

        layout.move(.quota, to: 4)
        XCTAssertEqual(
            Array(layout.order.prefix(5)),
            [.modelIQ, .resetCredits, .usagePace, .insights, .quota]
        )

        layout.move(.quota, to: 0)
        XCTAssertEqual(layout.order, DashboardLayout.default.order)

        layout.move(.preview, to: -10)
        XCTAssertEqual(layout.order.first, .preview)

        layout.move(.preview, to: 100)
        XCTAssertEqual(layout.order.last, .preview)
        XCTAssertEqual(Set(layout.order), Set(DashboardSection.allCases))
    }

    func testEverySourceTargetMoveUsesStableRemoveAndInsertSemantics() {
        let original = DashboardLayout.default.order

        for sourceIndex in original.indices {
            for targetIndex in original.indices {
                var layout = DashboardLayout.default
                let section = original[sourceIndex]
                var expected = original
                expected.remove(at: sourceIndex)
                expected.insert(
                    section,
                    at: min(targetIndex, expected.count)
                )

                layout.move(section, to: targetIndex)

                XCTAssertEqual(
                    layout.order,
                    expected,
                    "source \(sourceIndex), target \(targetIndex)"
                )
            }
        }
    }

    func testLoadingRepairsUnknownDuplicateAndMissingSections() throws {
        let context = try LayoutTestContext()
        defer { context.cleanup() }
        context.defaults.set(
            [
                DashboardSection.updates.rawValue,
                "future-unknown-section",
                DashboardSection.quota.rawValue,
                DashboardSection.updates.rawValue,
            ],
            forKey: DashboardLayout.orderDefaultsKey
        )
        context.defaults.set(
            [
                DashboardSection.resetCredits.rawValue,
                "future-unknown-section",
                DashboardSection.resetCredits.rawValue,
            ],
            forKey: DashboardLayout.expandedDefaultsKey
        )

        let layout = DashboardLayout.load(from: context.defaults)

        XCTAssertEqual(
            layout.order,
            [
                .updates,
                .preview,
                .quota,
                .modelIQ,
                .resetCredits,
                .usagePace,
                .insights,
                .radarDetails,
                .menuBarGuide,
                .displayAndAlerts,
            ]
        )
        XCTAssertEqual(layout.expandedSections, [.resetCredits])
    }

    func testMalformedStoredLayoutFallsBackToDefaults() throws {
        let context = try LayoutTestContext()
        defer { context.cleanup() }
        context.defaults.set(
            42,
            forKey: DashboardLayout.orderDefaultsKey
        )
        context.defaults.set(
            ["unexpected": true],
            forKey: DashboardLayout.expandedDefaultsKey
        )

        XCTAssertEqual(
            DashboardLayout.load(from: context.defaults),
            .default
        )
    }

    func testExplicitlyCollapsedLayoutStaysCollapsed() throws {
        let context = try LayoutTestContext()
        defer { context.cleanup() }
        context.defaults.set(
            DashboardLayout.defaultOrder.map(\.rawValue),
            forKey: DashboardLayout.orderDefaultsKey
        )
        context.defaults.set(
            Dictionary(
                uniqueKeysWithValues: DashboardSection.allCases.map {
                    ($0.rawValue, false)
                }
            ),
            forKey: DashboardLayout.expandedDefaultsKey
        )

        XCTAssertTrue(
            DashboardLayout.load(from: context.defaults)
                .expandedSections.isEmpty
        )
    }

    func testMissingExpansionFieldsUseCurrentSectionDefaults() throws {
        let context = try LayoutTestContext()
        defer { context.cleanup() }
        context.defaults.set(
            [DashboardSection.quota.rawValue: false],
            forKey: DashboardLayout.expandedDefaultsKey
        )

        let layout = DashboardLayout.load(from: context.defaults)

        XCTAssertEqual(
            layout.expandedSections,
            [.modelIQ, .usagePace, .insights]
        )
    }

    func testAttentionForcesOnlyResetCreditSectionOpenWithoutChangingLayout() {
        let now = Date()
        let forcedStatuses: [ResetCreditProtectionStatus] = [
            .blocked(.requestFailed, detail: nil),
            .missed(expiresAt: now),
            .using(expiresAt: now),
            .reconciling(expiresAt: now),
        ]
        for status in forcedStatuses {
            XCTAssertTrue(
                DashboardSectionExpansionPolicy.forcesExpansion(
                    of: .resetCredits,
                    resetCreditStatus: status,
                    hasUnresolvedResetCreditAttempt: false
                )
            )
        }

        let routineStatuses: [ResetCreditProtectionStatus] = [
            .disabled,
            .noCredits(now),
            .scheduled(
                actionAt: now,
                expiresAt: now,
                availableCount: 1
            ),
            .waitingForUsage(expiresAt: now),
            .succeeded(usedAt: now, expiresAt: now),
        ]
        for status in routineStatuses {
            XCTAssertFalse(
                DashboardSectionExpansionPolicy.forcesExpansion(
                    of: .resetCredits,
                    resetCreditStatus: status,
                    hasUnresolvedResetCreditAttempt: false
                )
            )
        }

        XCTAssertTrue(
            DashboardSectionExpansionPolicy.forcesExpansion(
                of: .resetCredits,
                resetCreditStatus: .disabled,
                hasUnresolvedResetCreditAttempt: true
            )
        )
        XCTAssertFalse(
            DashboardSectionExpansionPolicy.forcesExpansion(
                of: .quota,
                resetCreditStatus: .blocked(
                    .requestFailed,
                    detail: nil
                ),
                hasUnresolvedResetCreditAttempt: true
            )
        )
        XCTAssertFalse(
            DashboardLayout.default.expandedSections.contains(
                .resetCredits
            )
        )

        let forcedResolution = DashboardSectionExpansionPolicy.resolve(
            section: .resetCredits,
            preferredExpanded: false,
            resetCreditStatus: forcedStatuses[0],
            hasUnresolvedResetCreditAttempt: false
        )
        XCTAssertEqual(
            forcedResolution,
            .init(isExpanded: true, canCollapse: false)
        )
        let releasedResolution = DashboardSectionExpansionPolicy.resolve(
            section: .resetCredits,
            preferredExpanded: false,
            resetCreditStatus: .disabled,
            hasUnresolvedResetCreditAttempt: false
        )
        XCTAssertEqual(
            releasedResolution,
            .init(isExpanded: false, canCollapse: true)
        )
        let unrelatedResolution = DashboardSectionExpansionPolicy.resolve(
            section: .quota,
            preferredExpanded: false,
            resetCreditStatus: forcedStatuses[0],
            hasUnresolvedResetCreditAttempt: true
        )
        XCTAssertEqual(
            unrelatedResolution,
            .init(isExpanded: false, canCollapse: true)
        )
        let updateResolution = DashboardSectionExpansionPolicy.resolve(
            section: .updates,
            preferredExpanded: false,
            resetCreditStatus: .disabled,
            hasUnresolvedResetCreditAttempt: false,
            requiresUpdateAttention: true
        )
        XCTAssertEqual(
            updateResolution,
            .init(isExpanded: true, canCollapse: false)
        )
    }

    func testStorePersistsLayoutAndResetDoesNotChangeOtherSettings()
        throws
    {
        let context = try LayoutTestContext()
        defer { context.cleanup() }
        context.defaults.set(false, forKey: "automaticUpdatesEnabled")
        context.defaults.set(false, forKey: "resetCreditAutoRefreshEnabled")

        var firstStore: SentinelStore? = context.makeStore()
        firstStore?.appLanguage = .en
        firstStore?.menuTextSize = .extraLarge
        let reordered = [
            DashboardSection.resetCredits,
        ] + DashboardLayout.default.order.filter {
            $0 != .resetCredits
        }
        firstStore?.setDashboardSectionOrder(reordered)
        firstStore?.setDashboardSection(.resetCredits, expanded: true)
        firstStore?.setDashboardSection(.quota, expanded: false)
        firstStore?.setDashboardDisclosure(
            .modelIQDetails,
            expanded: true
        )
        firstStore?.setDashboardDisclosure(
            .radarInsightsDetails,
            expanded: true
        )

        XCTAssertEqual(firstStore?.dashboardLayout.order.first, .resetCredits)
        firstStore = nil

        let secondStore = context.makeStore()
        XCTAssertEqual(secondStore.dashboardLayout.order.first, .resetCredits)
        XCTAssertTrue(
            secondStore.isDashboardSectionExpanded(.resetCredits)
        )
        XCTAssertFalse(secondStore.isDashboardSectionExpanded(.quota))
        XCTAssertTrue(
            secondStore.isDashboardDisclosureExpanded(
                .modelIQDetails
            )
        )
        XCTAssertTrue(
            secondStore.isDashboardDisclosureExpanded(
                .radarInsightsDetails
            )
        )
        XCTAssertEqual(secondStore.appLanguage, .en)
        XCTAssertEqual(secondStore.menuTextSize, .extraLarge)

        secondStore.resetDashboardLayout()

        XCTAssertEqual(secondStore.dashboardLayout, .default)
        XCTAssertEqual(secondStore.appLanguage, .en)
        XCTAssertEqual(secondStore.menuTextSize, .extraLarge)
        XCTAssertFalse(secondStore.automaticUpdatesEnabled)
        XCTAssertFalse(secondStore.resetCreditAutoRefreshEnabled)

        let thirdStore = context.makeStore()
        XCTAssertEqual(thirdStore.dashboardLayout, .default)
        XCTAssertEqual(thirdStore.appLanguage, .en)
        XCTAssertEqual(thirdStore.menuTextSize, .extraLarge)
        XCTAssertFalse(thirdStore.automaticUpdatesEnabled)
        XCTAssertFalse(thirdStore.resetCreditAutoRefreshEnabled)
        XCTAssertFalse(
            thirdStore.isDashboardDisclosureExpanded(
                .modelIQDetails
            )
        )
        XCTAssertFalse(
            thirdStore.isDashboardDisclosureExpanded(
                .radarInsightsDetails
            )
        )
    }

    func testLayoutDiscoveryTipDismissalPersistsWithoutChangingLayout()
        throws
    {
        let context = try LayoutTestContext()
        defer { context.cleanup() }

        var firstStore: SentinelStore? = context.makeStore()
        XCTAssertFalse(firstStore?.layoutDiscoveryTipDismissed == true)
        XCTAssertEqual(firstStore?.dashboardLayout, .default)

        firstStore?.dismissLayoutDiscoveryTip()

        XCTAssertTrue(firstStore?.layoutDiscoveryTipDismissed == true)
        XCTAssertEqual(firstStore?.dashboardLayout, .default)
        firstStore = nil

        let secondStore = context.makeStore()
        XCTAssertTrue(secondStore.layoutDiscoveryTipDismissed)
        XCTAssertEqual(secondStore.dashboardLayout, .default)
    }

    func testLegacyPreviewExpansionMigratesOnlyUntilNewPreferenceExists()
        throws
    {
        let context = try LayoutTestContext()
        defer { context.cleanup() }
        context.defaults.set(
            true,
            forKey: "debugPreviewSectionExpanded"
        )

        var firstStore: SentinelStore? = context.makeStore()
        XCTAssertTrue(firstStore?.isDashboardSectionExpanded(.preview) == true)
        firstStore?.setDashboardSection(.preview, expanded: false)
        firstStore = nil

        let secondStore = context.makeStore()
        XCTAssertFalse(secondStore.isDashboardSectionExpanded(.preview))
    }

    func testExplicitNewExpansionPreferenceOverridesLegacyValue() throws {
        let context = try LayoutTestContext()
        defer { context.cleanup() }
        context.defaults.set(
            true,
            forKey: "debugPreviewSectionExpanded"
        )
        context.defaults.set(
            Dictionary(
                uniqueKeysWithValues: DashboardSection.allCases.map {
                    ($0.rawValue, false)
                }
            ),
            forKey: DashboardLayout.expandedDefaultsKey
        )

        let store = context.makeStore()

        XCTAssertTrue(store.dashboardLayout.expandedSections.isEmpty)
        XCTAssertFalse(store.isDashboardSectionExpanded(.preview))
    }
}

@MainActor
private final class LayoutTestContext {
    let suiteName: String
    let defaults: UserDefaults
    let directory: URL

    init() throws {
        let identifier = UUID().uuidString
        suiteName = "com.codexradar.sentinel.layout-tests.\(identifier)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "codex-radar-layout-tests-\(identifier)",
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: false
        )
    }

    func makeStore() -> SentinelStore {
        SentinelStore(
            defaults: defaults,
            resetCreditProtectionLedgerStore:
                ResetCreditProtectionLedgerStore(
                    url: directory.appendingPathComponent("ledger.json")
                ),
            resetCreditProtectionAuthorizationStore:
                ResetCreditProtectionAuthorizationStore(
                    url: directory.appendingPathComponent(
                        "authorization.json"
                    ),
                    dispatchLockURL: directory.appendingPathComponent(
                        "authorization.lock"
                    )
                ),
            resetCreditProtectionProcessLockURL: directory
                .appendingPathComponent("process.lock"),
            resetCreditProtectionDestructiveActionsAllowed: false
        )
    }

    func cleanup() {
        defaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: directory)
    }
}
