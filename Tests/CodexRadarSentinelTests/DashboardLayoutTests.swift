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
        XCTAssertTrue(DashboardLayout.default.hiddenSections.isEmpty)
        XCTAssertTrue(DashboardLayout.default.hiddenDisclosures.isEmpty)
        for section in DashboardSection.allCases {
            XCTAssertTrue(DashboardLayout.default.isVisible(section))
        }
        for disclosure in DashboardDisclosure.allCases {
            XCTAssertTrue(DashboardLayout.default.isVisible(disclosure))
        }
    }

    func testNestedDisclosuresHaveOneRegisteredParentAndSafeDefaults() {
        XCTAssertEqual(
            DashboardDisclosure.children(of: .quota),
            [.quotaHistory]
        )
        XCTAssertEqual(
            DashboardDisclosure.children(of: .modelIQ),
            [.modelIQDetails]
        )
        XCTAssertEqual(
            DashboardDisclosure.children(of: .insights),
            [.radarInsightsDetails]
        )
        for section in DashboardSection.allCases
        where section != .quota
            && section != .modelIQ
            && section != .insights {
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
            DashboardDisclosure.quotaHistory.isExpandedByDefault
        )
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
        XCTAssertTrue(layout.hiddenSections.isEmpty)
        XCTAssertTrue(layout.hiddenDisclosures.isEmpty)
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
        context.defaults.set(
            "unexpected",
            forKey: DashboardLayout.visibilityDefaultsKey
        )
        context.defaults.set(
            42,
            forKey: DashboardLayout.disclosureVisibilityDefaultsKey
        )

        XCTAssertEqual(
            DashboardLayout.load(from: context.defaults),
            .default
        )
    }

    func testVisibilityLoadsExplicitHiddenValuesAndKeepsMissingItemsVisible()
        throws
    {
        let context = try LayoutTestContext()
        defer { context.cleanup() }
        context.defaults.set(
            [
                DashboardSection.quota.rawValue: false,
                DashboardSection.updates.rawValue: true,
                "future-unknown-section": false,
            ],
            forKey: DashboardLayout.visibilityDefaultsKey
        )
        context.defaults.set(
            [
                DashboardDisclosure.quotaHistory.rawValue: false,
                DashboardDisclosure.modelIQDetails.rawValue: true,
                "future-unknown-disclosure": false,
            ],
            forKey: DashboardLayout.disclosureVisibilityDefaultsKey
        )

        let layout = DashboardLayout.load(from: context.defaults)

        XCTAssertEqual(layout.hiddenSections, [.quota])
        XCTAssertEqual(layout.hiddenDisclosures, [.quotaHistory])
        XCTAssertFalse(layout.isVisible(.quota))
        XCTAssertTrue(layout.isVisible(.modelIQ))
        XCTAssertTrue(layout.isVisible(.updates))
        XCTAssertFalse(layout.isVisible(.quotaHistory))
        XCTAssertTrue(layout.isVisible(.modelIQDetails))
        XCTAssertTrue(layout.isVisible(.radarInsightsDetails))
    }

    func testVisibilityDoesNotChangeSavedExpansionPreference() {
        var layout = DashboardLayout.default
        layout.setExpanded(.quota, expanded: false)
        layout.setVisible(.quota, visible: false)
        layout.setVisible(.quotaHistory, visible: false)

        XCTAssertFalse(layout.isVisible(.quota))
        XCTAssertFalse(layout.isVisible(.quotaHistory))
        XCTAssertFalse(layout.expandedSections.contains(.quota))

        layout.setVisible(.quota, visible: true)
        layout.setVisible(.quotaHistory, visible: true)

        XCTAssertTrue(layout.isVisible(.quota))
        XCTAssertTrue(layout.isVisible(.quotaHistory))
        XCTAssertFalse(layout.expandedSections.contains(.quota))
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

        let hiddenResetResolution = DashboardSectionVisibilityPolicy.resolve(
            section: .resetCredits,
            preferredVisible: false,
            resetCreditStatus: forcedStatuses[0],
            hasUnresolvedResetCreditAttempt: false
        )
        XCTAssertEqual(
            hiddenResetResolution,
            .init(isVisible: true, canHide: false)
        )
        let releasedVisibilityResolution =
            DashboardSectionVisibilityPolicy.resolve(
                section: .resetCredits,
                preferredVisible: false,
                resetCreditStatus: .disabled,
                hasUnresolvedResetCreditAttempt: false
            )
        XCTAssertEqual(
            releasedVisibilityResolution,
            .init(isVisible: false, canHide: true)
        )
        let unrelatedVisibilityResolution =
            DashboardSectionVisibilityPolicy.resolve(
                section: .quota,
                preferredVisible: false,
                resetCreditStatus: forcedStatuses[0],
                hasUnresolvedResetCreditAttempt: true
            )
        XCTAssertEqual(
            unrelatedVisibilityResolution,
            .init(isVisible: false, canHide: true)
        )
        let hiddenUpdateResolution = DashboardSectionVisibilityPolicy.resolve(
            section: .updates,
            preferredVisible: false,
            resetCreditStatus: .disabled,
            hasUnresolvedResetCreditAttempt: false,
            requiresUpdateAttention: true
        )
        XCTAssertEqual(
            hiddenUpdateResolution,
            .init(isVisible: true, canHide: false)
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
            .quotaHistory,
            expanded: true
        )
        firstStore?.setDashboardDisclosure(
            .modelIQDetails,
            expanded: true
        )
        firstStore?.setDashboardDisclosure(
            .radarInsightsDetails,
            expanded: true
        )
        firstStore?.setDashboardSection(.quota, visible: false)
        firstStore?.setDashboardSection(.updates, visible: false)
        firstStore?.setDashboardDisclosure(
            .quotaHistory,
            visible: false
        )
        firstStore?.setDashboardDisclosure(
            .radarInsightsDetails,
            visible: false
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
                .quotaHistory
            )
        )
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
        XCTAssertFalse(secondStore.isDashboardSectionVisible(.quota))
        XCTAssertFalse(secondStore.isDashboardSectionVisible(.updates))
        XCTAssertFalse(
            secondStore.isDashboardDisclosureVisible(.quotaHistory)
        )
        XCTAssertFalse(
            secondStore.isDashboardDisclosureVisible(
                .radarInsightsDetails
            )
        )
        XCTAssertTrue(
            secondStore.isDashboardDisclosureVisible(.modelIQDetails)
        )
        XCTAssertEqual(secondStore.appLanguage, .en)
        XCTAssertEqual(secondStore.menuTextSize, .extraLarge)

        secondStore.resetDashboardLayout()

        XCTAssertEqual(secondStore.dashboardLayout, .default)
        XCTAssertEqual(secondStore.appLanguage, .en)
        XCTAssertEqual(secondStore.menuTextSize, .extraLarge)
        XCTAssertFalse(secondStore.automaticUpdatesEnabled)
        XCTAssertFalse(secondStore.resetCreditAutoRefreshEnabled)
        XCTAssertTrue(secondStore.dashboardLayout.hiddenSections.isEmpty)
        XCTAssertTrue(
            secondStore.dashboardLayout.hiddenDisclosures.isEmpty
        )

        let thirdStore = context.makeStore()
        XCTAssertEqual(thirdStore.dashboardLayout, .default)
        XCTAssertEqual(thirdStore.appLanguage, .en)
        XCTAssertEqual(thirdStore.menuTextSize, .extraLarge)
        XCTAssertFalse(thirdStore.automaticUpdatesEnabled)
        XCTAssertFalse(thirdStore.resetCreditAutoRefreshEnabled)
        XCTAssertFalse(
            thirdStore.isDashboardDisclosureExpanded(
                .quotaHistory
            )
        )
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
        for section in DashboardSection.allCases {
            XCTAssertTrue(thirdStore.isDashboardSectionVisible(section))
        }
        for disclosure in DashboardDisclosure.allCases {
            XCTAssertTrue(
                thirdStore.isDashboardDisclosureVisible(disclosure)
            )
        }
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
            quotaHistoryStore: QuotaHistoryStore(
                url: directory.appendingPathComponent(
                    "quota-history.json"
                )
            ),
            resetCreditProtectionDestructiveActionsAllowed: false
        )
    }

    func cleanup() {
        defaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: directory)
    }
}
