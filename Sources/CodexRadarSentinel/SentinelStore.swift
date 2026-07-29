import AppKit
import CodexRadarCore
import Foundation

enum ResetCreditLoadPhase: Equatable {
    case idle
    case loading(Date, automatic: Bool)
    case failed(ResetCreditFailure)

    var isLoading: Bool {
        if case .loading = self {
            return true
        }
        return false
    }
}

struct ResetCreditFailure: Equatable {
    enum Kind: Equatable {
        case authFileMissing
        case invalidAuthFile
        case accessTokenMissing
        case unauthorized(Int)
        case network
        case service(Int)
        case responseChanged
        case unknown
    }

    let kind: Kind
    let detail: String
    let occurredAt: Date
    let automatic: Bool
}

enum ResetCreditProtectionStatus: Equatable {
    enum BlockReason: Equatable {
        case accountIdentityUnavailable
        case accountChanged
        case detailsUnavailable(Int)
        case detailsIncomplete(availableCount: Int, availableDetails: Int)
        case noSupportedExpiringCredits(Int)
        case codexUnavailable
        case signedOut
        case unsupportedCodex
        case anotherProcess
        case journalUnavailable
        case creditNotAuthorized
        case clockChanged
        case requestFailed
    }

    case disabled
    case enabling
    case checking
    case noCredits(Date)
    case preview(actionAt: Date, expiresAt: Date, availableCount: Int, readyNow: Bool)
    case previewNoCredits(Date)
    case scheduled(actionAt: Date, expiresAt: Date, availableCount: Int)
    case waitingForUsage(expiresAt: Date)
    case using(expiresAt: Date)
    case reconciling(expiresAt: Date)
    case succeeded(usedAt: Date, expiresAt: Date)
    case unavailable(checkedAt: Date, expiresAt: Date?)
    case missed(expiresAt: Date)
    case blocked(BlockReason, detail: String?)

    var isBusy: Bool {
        switch self {
        case .enabling, .checking, .using, .reconciling:
            return true
        default:
            return false
        }
    }
}

private struct RateLimitReadPayload {
    let response: RateLimitResponse
    let dashboard: RateLimitDashboard
}

private enum ResetCreditProtectionJournalLoadResult {
    case absent
    case loaded(ResetCreditProtectionAttemptJournal)
    case corrupt
}

@MainActor
final class SentinelStore: NSObject, ObservableObject {
    @objc dynamic private(set) var titleForStatusItem: String = DashboardState().statusTitle

    @Published private(set) var state = DashboardState() {
        didSet {
            updateTitleForStatusItem()
        }
    }

    @Published var menuTextSize: DashboardTextSize {
        didSet {
            defaults.set(menuTextSize.rawValue, forKey: DefaultsKey.menuTextSize)
        }
    }

    @Published var appLanguage: AppLanguage {
        didSet {
            defaults.set(appLanguage.rawValue, forKey: DefaultsKey.appLanguage)
            updateTitleForStatusItem()
        }
    }

    @Published var statusBarPreciseIQEnabled: Bool {
        didSet {
            defaults.set(statusBarPreciseIQEnabled, forKey: DefaultsKey.statusBarPreciseIQEnabled)
            updateTitleForStatusItem()
        }
    }

    @Published var statusBarAdvancedOptionsExpanded: Bool {
        didSet {
            defaults.set(statusBarAdvancedOptionsExpanded, forKey: DefaultsKey.statusBarAdvancedOptionsExpanded)
        }
    }

    @Published var statusBarIQDisplayMode: StatusBarIQDisplayMode {
        didSet {
            defaults.set(statusBarIQDisplayMode.rawValue, forKey: DefaultsKey.statusBarIQDisplayMode)
            updateTitleForStatusItem()
        }
    }

    @Published var statusBarPercentDisplayMode: StatusBarPercentDisplayMode {
        didSet {
            defaults.set(statusBarPercentDisplayMode.rawValue, forKey: DefaultsKey.statusBarPercentDisplayMode)
            updateTitleForStatusItem()
        }
    }

    @Published var statusBarSeparator: StatusBarSeparator {
        didSet {
            defaults.set(statusBarSeparator.rawValue, forKey: DefaultsKey.statusBarSeparator)
            updateTitleForStatusItem()
        }
    }

    @Published var statusBarHorizontalPadding: StatusBarHorizontalPadding {
        didSet {
            defaults.set(statusBarHorizontalPadding.rawValue, forKey: DefaultsKey.statusBarHorizontalPadding)
            updateTitleForStatusItem()
        }
    }

    @Published var statusBarFontScale: StatusBarFontScale {
        didSet {
            defaults.set(statusBarFontScale.rawValue, forKey: DefaultsKey.statusBarFontScale)
            updateTitleForStatusItem()
        }
    }

    @Published var quotaPacingStrategy: QuotaPacingStrategy {
        didSet {
            defaults.set(quotaPacingStrategy.rawValue, forKey: DefaultsKey.quotaPacingStrategy)
            updateTitleForStatusItem()
        }
    }

    @Published var chinaHolidayCalendarEnabled: Bool {
        didSet {
            defaults.set(chinaHolidayCalendarEnabled, forKey: DefaultsKey.chinaHolidayCalendarEnabled)
            updateTitleForStatusItem()
        }
    }

    @Published var quotaPacingOptionsExpanded: Bool {
        didSet {
            defaults.set(quotaPacingOptionsExpanded, forKey: DefaultsKey.quotaPacingOptionsExpanded)
        }
    }

    @Published private(set) var selectedStatusMetrics: [StatusMetric] {
        didSet {
            defaults.set(selectedStatusMetrics.map(\.rawValue), forKey: DefaultsKey.selectedStatusMetrics)
            updateTitleForStatusItem()
        }
    }

    @Published private(set) var dashboardLayout: DashboardLayout {
        didSet {
            dashboardLayout.save(to: defaults)
        }
    }

    @Published var modelIQDetailsExpanded: Bool {
        didSet {
            defaults.set(
                modelIQDetailsExpanded,
                forKey: DefaultsKey.modelIQDetailsExpanded
            )
        }
    }

    @Published var radarInsightsDetailsExpanded: Bool {
        didSet {
            defaults.set(
                radarInsightsDetailsExpanded,
                forKey: DefaultsKey.radarInsightsDetailsExpanded
            )
        }
    }

    @Published var debugPreview: DashboardPreview = .live {
        didSet {
            if debugPreview != .live {
                resetSpeedAlertDismissal()
                if resetCreditProtectionEnabled {
                    disableResetCreditExpiryProtection()
                }
            }
            updateTitleForStatusItem()
        }
    }

    @Published private(set) var dismissedSpeedAlertKey: String? {
        didSet {
            defaults.set(dismissedSpeedAlertKey, forKey: DefaultsKey.dismissedSpeedAlertKey)
        }
    }

    @Published var predictionNotificationsEnabled: Bool {
        didSet {
            defaults.set(predictionNotificationsEnabled, forKey: DefaultsKey.predictionNotificationsEnabled)
        }
    }

    @Published var iqNotificationsEnabled: Bool {
        didSet {
            defaults.set(iqNotificationsEnabled, forKey: DefaultsKey.iqNotificationsEnabled)
        }
    }

    @Published var notificationSoundEnabled: Bool {
        didSet {
            defaults.set(notificationSoundEnabled, forKey: DefaultsKey.notificationSoundEnabled)
        }
    }

    @Published var automaticUpdatesEnabled: Bool {
        didSet {
            defaults.set(automaticUpdatesEnabled, forKey: DefaultsKey.automaticUpdatesEnabled)
            if automaticUpdatesEnabled {
                startAutomaticUpdateChecks()
                checkForUpdatesNow(automatic: true)
            } else {
                automaticUpdateTask?.cancel()
                automaticUpdateTask = nil
            }
        }
    }

    @Published private(set) var updatePhase: AppUpdatePhase = .idle
    @Published private(set) var latestUpdate: AppUpdateInfo?
    @Published private(set) var resetCreditSnapshot: ResetCreditSnapshot?
    @Published private(set) var resetCreditPhase: ResetCreditLoadPhase = .idle
    @Published private(set) var resetCreditProtectionEnabled: Bool
    @Published private(set) var resetCreditProtectionStatus: ResetCreditProtectionStatus

    @Published var resetCreditAutoRefreshEnabled: Bool {
        didSet {
            defaults.set(resetCreditAutoRefreshEnabled, forKey: DefaultsKey.resetCreditAutoRefreshEnabled)
            guard !suppressResetCreditAutoRefreshSideEffects else {
                return
            }
            if resetCreditAutoRefreshEnabled {
                startResetCreditAutoRefresh()
                refreshResetCreditsIfNeeded(automatic: true)
            } else {
                resetCreditAutoRefreshTask?.cancel()
                resetCreditAutoRefreshTask = nil
            }
        }
    }

    @Published var launchAtLoginEnabled: Bool {
        didSet {
            LaunchAtLoginController.setEnabled(launchAtLoginEnabled)
            defaults.set(launchAtLoginEnabled, forKey: DefaultsKey.launchAtLoginEnabled)
        }
    }

    private enum DefaultsKey {
        static let appLanguage = "appLanguage"
        static let menuTextSize = "menuTextSize"
        static let statusBarPreciseIQEnabled = "statusBarPreciseIQEnabled"
        static let statusBarAdvancedOptionsExpanded = "statusBarAdvancedOptionsExpanded"
        static let statusBarIQDisplayMode = "statusBarIQDisplayMode"
        static let statusBarPercentDisplayMode = "statusBarPercentDisplayMode"
        static let statusBarSeparator = "statusBarSeparator"
        static let statusBarHorizontalPadding = "statusBarHorizontalPadding"
        static let statusBarFontScale = "statusBarFontScale"
        static let quotaPacingStrategy = "quotaPacingStrategy"
        static let chinaHolidayCalendarEnabled = "chinaHolidayCalendarEnabled"
        static let quotaPacingOptionsExpanded = "quotaPacingOptionsExpanded"
        static let selectedStatusMetrics = "selectedStatusMetrics"
        static let predictionNotificationsEnabled = "predictionNotificationsEnabled"
        static let iqNotificationsEnabled = "iqNotificationsEnabled"
        static let notificationSoundEnabled = "notificationSoundEnabled"
        static let automaticUpdatesEnabled = "automaticUpdatesEnabled"
        static let launchAtLoginEnabled = "launchAtLoginEnabled"
        static let notificationMemory = "notificationMemory"
        static let dismissedSpeedAlertKey = "dismissedSpeedAlertKey"
        static let debugPreviewSectionExpanded = "debugPreviewSectionExpanded"
        static let modelIQDetailsExpanded =
            "modelIQDetailsExpanded"
        static let radarInsightsDetailsExpanded =
            "radarInsightsDetailsExpanded"
        static let resetCreditSnapshot = "resetCreditSnapshot"
        static let resetCreditAutoRefreshEnabled = "resetCreditAutoRefreshEnabled"
        static let resetCreditProtectionEnabled = "resetCreditProtectionEnabled"
    }

    private static let defaultStatusMetrics: [StatusMetric] = [
        .weeklyQuota,
        .codexIQ,
        .signal,
    ]

    private let defaults: UserDefaults
    private let radarClient: CodexRadarClient
    private let appServerClient: any ResetCreditProtectionAppServerServing
    private let resetCreditProtectionHintAppServer:
        ResetCreditProtectionBoundAppServer
    private let resetCreditProtectionSessionFactory:
        ResetCreditProtectionAppServerSessionFactory
    private let resetCreditProtectionRuntimeAllowsDestructiveActions: Bool
    private let appUpdater: AppUpdater
    private let resetCreditClient: ResetCreditClient
    private let notificationPolicy = NotificationPolicy()
    private var notificationMemory: NotificationMemory
    private var pollingTask: Task<Void, Never>?
    private var refreshTask: Task<Void, Never>?
    private var updateTask: Task<Void, Never>?
    private var automaticUpdateTask: Task<Void, Never>?
    private var resetCreditTask: Task<Void, Never>?
    private var resetCreditAutoRefreshTask: Task<Void, Never>?
    private var radarInsightsTask: Task<Void, Never>?
    private var resetCreditProtectionTask: Task<Void, Never>?
    private var resetCreditProtectionConsent: ResetCreditProtectionConsent?
    private var resetCreditProtectionLedger: ResetCreditProtectionLedger
    private var resetCreditProtectionJournalCorrupt: Bool
    private var resetCreditProtectionNextRetryAt: Date?
    private var resetCreditProtectionClockGeneration: UInt64 = 0
    private var resetCreditProtectionEnablingClockAnchor:
        ResetCreditProtectionClockSample?
    private let resetCreditProtectionLedgerStore: ResetCreditProtectionLedgerStore
    private let resetCreditProtectionAuthorizationStore:
        ResetCreditProtectionAuthorizationStore
    private let resetCreditProtectionProcessLockURL: URL
    private let resetCreditProtectionClock:
        () -> ResetCreditProtectionClockSample
    private let radarInsightsUptime: () -> TimeInterval
    private var lifecycleObservers: [(NotificationCenter, NSObjectProtocol)] = []
    private var suppressResetCreditAutoRefreshSideEffects = false
    private var emphasizedSpeedAlertKey: String?
    private var speedAlertFirstSeenAt: Date?
    private var lastRadarInsightsFetchUptime: TimeInterval?

    init(
        defaults: UserDefaults = .standard,
        radarClient: CodexRadarClient = CodexRadarClient(),
        appServerClient: (any ResetCreditProtectionAppServerServing)? = nil,
        resetCreditProtectionSessionFactory:
            ResetCreditProtectionAppServerSessionFactory? = nil,
        appUpdater: AppUpdater = AppUpdater(),
        resetCreditClient: ResetCreditClient = ResetCreditClient(),
        resetCreditProtectionLedgerStore: ResetCreditProtectionLedgerStore? = nil,
        resetCreditProtectionAuthorizationStore:
            ResetCreditProtectionAuthorizationStore? = nil,
        resetCreditProtectionProcessLockURL: URL? = nil,
        resetCreditProtectionClock:
            @escaping () -> ResetCreditProtectionClockSample = {
                .now()
            },
        radarInsightsUptime: @escaping () -> TimeInterval = {
            ProcessInfo.processInfo.systemUptime
        },
        resetCreditProtectionDestructiveActionsAllowed: Bool? = nil
    ) {
        let rawPreview = ProcessInfo.processInfo.environment[
            AppConstants.debugPreviewEnvironmentKey
        ]
        let initialPreview = rawPreview.flatMap(DashboardPreview.init(rawValue:))
            ?? .live
        let rendersDocumentation = ProcessInfo.processInfo.environment[
            AppConstants.documentationScreenshotEnvironmentKey
        ] != nil
        let capturesStatusScreenshot = ProcessInfo.processInfo.environment[
            AppConstants.screenshotModeEnvironmentKey
        ] == "1"
        let destructiveActionsAllowed =
            resetCreditProtectionDestructiveActionsAllowed
            ?? (
                initialPreview == .live
                    && !rendersDocumentation
                    && !capturesStatusScreenshot
            )
        let resolvedAppServerClient = appServerClient ?? CodexAppServerClient()

        self.defaults = defaults
        self.radarClient = radarClient
        self.appServerClient = resolvedAppServerClient
        self.resetCreditProtectionHintAppServer = ResetCreditProtectionBoundAppServer(
            service: resolvedAppServerClient,
            destructiveActionsAllowed: destructiveActionsAllowed
        )
        if let resetCreditProtectionSessionFactory {
            self.resetCreditProtectionSessionFactory =
                resetCreditProtectionSessionFactory
        } else if appServerClient == nil {
            self.resetCreditProtectionSessionFactory = .live
        } else {
            self.resetCreditProtectionSessionFactory = .shared(
                service: resolvedAppServerClient
            )
        }
        self.resetCreditProtectionRuntimeAllowsDestructiveActions =
            destructiveActionsAllowed
        self.appUpdater = appUpdater
        self.resetCreditClient = resetCreditClient
        let protectionLedgerStore = resetCreditProtectionLedgerStore
            ?? ResetCreditProtectionLedgerStore(url: Self.resetCreditProtectionJournalURL)
        self.resetCreditProtectionLedgerStore = protectionLedgerStore
        let protectionAuthorizationStore = resetCreditProtectionAuthorizationStore
            ?? ResetCreditProtectionAuthorizationStore(
                url: Self.resetCreditProtectionAuthorizationURL,
                dispatchLockURL: Self.resetCreditProtectionDispatchLockURL
            )
        self.resetCreditProtectionAuthorizationStore = protectionAuthorizationStore
        self.resetCreditProtectionProcessLockURL =
            resetCreditProtectionProcessLockURL
            ?? Self.resetCreditProtectionLockURL
        self.resetCreditProtectionClock = resetCreditProtectionClock
        self.radarInsightsUptime = radarInsightsUptime
        let rawLanguage = defaults.string(forKey: DefaultsKey.appLanguage)
        let resolvedAppLanguage = rawLanguage
            .flatMap(AppLanguage.init(rawValue:)) ?? .zhHans
        self.appLanguage = resolvedAppLanguage
        let rawTextSize = defaults.string(forKey: DefaultsKey.menuTextSize)
        self.menuTextSize = rawTextSize.flatMap(DashboardTextSize.init(rawValue:)) ?? .large
        self.statusBarPreciseIQEnabled = defaults.object(forKey: DefaultsKey.statusBarPreciseIQEnabled) as? Bool ?? false
        self.statusBarAdvancedOptionsExpanded = defaults.object(forKey: DefaultsKey.statusBarAdvancedOptionsExpanded) as? Bool ?? false
        self.statusBarIQDisplayMode = defaults.string(forKey: DefaultsKey.statusBarIQDisplayMode)
            .flatMap(StatusBarIQDisplayMode.init(rawValue:)) ?? .raw
        self.statusBarPercentDisplayMode = defaults.string(forKey: DefaultsKey.statusBarPercentDisplayMode)
            .flatMap(StatusBarPercentDisplayMode.init(rawValue:)) ?? .symbol
        self.statusBarSeparator = defaults.string(forKey: DefaultsKey.statusBarSeparator)
            .flatMap(StatusBarSeparator.init(rawValue:)) ?? .slash
        self.statusBarHorizontalPadding = defaults.string(forKey: DefaultsKey.statusBarHorizontalPadding)
            .flatMap(StatusBarHorizontalPadding.init(rawValue:)) ?? .system
        self.statusBarFontScale = defaults.string(forKey: DefaultsKey.statusBarFontScale)
            .flatMap(StatusBarFontScale.init(rawValue:)) ?? .normal
        self.quotaPacingStrategy = defaults.string(forKey: DefaultsKey.quotaPacingStrategy)
            .flatMap(QuotaPacingStrategy.init(rawValue:)) ?? .timeProportional
        self.chinaHolidayCalendarEnabled = defaults.object(forKey: DefaultsKey.chinaHolidayCalendarEnabled) as? Bool ?? true
        self.quotaPacingOptionsExpanded = defaults.object(forKey: DefaultsKey.quotaPacingOptionsExpanded) as? Bool ?? false
        self.selectedStatusMetrics = Self.loadSelectedStatusMetrics(defaults: defaults)
        var dashboardLayout = DashboardLayout.load(from: defaults)
        if defaults.object(
            forKey: DashboardLayout.expandedDefaultsKey
        ) == nil,
           defaults.object(
               forKey: DefaultsKey.debugPreviewSectionExpanded
           ) as? Bool == true {
            dashboardLayout.setExpanded(.preview, expanded: true)
        }
        self.dashboardLayout = dashboardLayout
        self.modelIQDetailsExpanded = defaults.object(
            forKey: DefaultsKey.modelIQDetailsExpanded
        ) as? Bool
            ?? DashboardDisclosure.modelIQDetails.isExpandedByDefault
        self.radarInsightsDetailsExpanded = defaults.object(
            forKey: DefaultsKey.radarInsightsDetailsExpanded
        ) as? Bool
            ?? DashboardDisclosure.radarInsightsDetails.isExpandedByDefault
        self.debugPreview = initialPreview
        self.predictionNotificationsEnabled = defaults.object(forKey: DefaultsKey.predictionNotificationsEnabled) as? Bool ?? true
        self.iqNotificationsEnabled = defaults.object(forKey: DefaultsKey.iqNotificationsEnabled) as? Bool ?? true
        self.notificationSoundEnabled = defaults.object(forKey: DefaultsKey.notificationSoundEnabled) as? Bool ?? false
        self.automaticUpdatesEnabled = defaults.object(forKey: DefaultsKey.automaticUpdatesEnabled) as? Bool ?? true
        self.resetCreditAutoRefreshEnabled = defaults.object(forKey: DefaultsKey.resetCreditAutoRefreshEnabled) as? Bool ?? true
        var protectionConsent: ResetCreditProtectionConsent?
        var protectionRequested = defaults.object(
            forKey: DefaultsKey.resetCreditProtectionEnabled
        ) as? Bool ?? false
        var authorizationCorrupt = false
        var protectionClockDiscontinuity = false
        var protectionClockDiscontinuityReason:
            ResetCreditProtectionAuthorization.ClockDiscontinuityReason?
        let initialProtectionClock = resetCreditProtectionClock()
        if protectionRequested {
            do {
                let clockValidation = try protectionAuthorizationStore
                    .validateCurrentClockOrRevoke(
                        currentClock: initialProtectionClock
                    ) {
                        defaults.set(
                            false,
                            forKey: DefaultsKey.resetCreditProtectionEnabled
                        )
                    }
                switch clockValidation {
                case .continuous(let consent):
                    protectionConsent = consent
                case .absent:
                    protectionConsent = nil
                    protectionRequested = false
                case .revoked(_, let reason):
                    protectionConsent = nil
                    protectionRequested = false
                    protectionClockDiscontinuity = true
                    protectionClockDiscontinuityReason = reason
                case .corrupt:
                    protectionConsent = nil
                    protectionRequested = false
                    authorizationCorrupt = true
                }
            } catch {
                authorizationCorrupt = true
                protectionConsent = nil
                protectionRequested = false
                defaults.set(
                    false,
                    forKey: DefaultsKey.resetCreditProtectionEnabled
                )
            }
        } else {
            switch protectionAuthorizationStore.load() {
            case .absent:
                protectionConsent = nil
            case .loaded(let consent):
                do {
                    _ = try protectionAuthorizationStore.clear(
                        ifCurrent: consent
                    ) {
                        defaults.set(
                            false,
                            forKey: DefaultsKey.resetCreditProtectionEnabled
                        )
                    }
                    protectionConsent = nil
                } catch {
                    protectionConsent = nil
                    authorizationCorrupt = true
                }
            case .corrupt:
                protectionConsent = nil
                authorizationCorrupt = true
            }
        }
        let protectionEnabled = ResetCreditProtectionAuthorization.isEnabled(
            requested: protectionRequested,
            consent: protectionConsent,
            currentClock: initialProtectionClock
        )
        let journalLoad = protectionLedgerStore.load()
        let loadedLedger: ResetCreditProtectionLedger
        let journalCorrupt: Bool
        switch journalLoad {
        case .absent:
            loadedLedger = ResetCreditProtectionLedger()
            journalCorrupt = false
        case .loaded(let ledger):
            loadedLedger = ledger
            journalCorrupt = false
        case .corrupt:
            loadedLedger = ResetCreditProtectionLedger()
            journalCorrupt = true
        }
        let protectionStorageCorrupt = journalCorrupt || authorizationCorrupt
        let protectionAvailableInThisRuntime = destructiveActionsAllowed
            && protectionEnabled
            && !protectionStorageCorrupt
        self.resetCreditProtectionEnabled = protectionAvailableInThisRuntime
        self.resetCreditProtectionStatus = !destructiveActionsAllowed
            ? .disabled
            : (protectionStorageCorrupt
            ? .blocked(.journalUnavailable, detail: nil)
            : (protectionClockDiscontinuity
            ? .blocked(
                .clockChanged,
                detail: protectionClockDiscontinuityReason.map {
                    Self.resetCreditProtectionClockDiscontinuityDetail(
                        $0,
                        language: resolvedAppLanguage
                    )
                }
            )
            : ((protectionEnabled || loadedLedger.activeAttempt != nil)
                ? .checking
                : .disabled)))
        self.resetCreditProtectionConsent = destructiveActionsAllowed
            && protectionEnabled
            ? protectionConsent
            : nil
        self.resetCreditProtectionLedger = loadedLedger
        self.resetCreditProtectionJournalCorrupt = protectionStorageCorrupt
        self.launchAtLoginEnabled = defaults.object(forKey: DefaultsKey.launchAtLoginEnabled) as? Bool ?? LaunchAtLoginController.isEnabled
        self.dismissedSpeedAlertKey = defaults.string(forKey: DefaultsKey.dismissedSpeedAlertKey)
        self.notificationMemory = Self.loadNotificationMemory(defaults: defaults)
        self.resetCreditSnapshot = Self.loadResetCreditSnapshot(defaults: defaults)
        super.init()
    }

    private var resetCreditProtectionJournal: ResetCreditProtectionAttemptJournal? {
        resetCreditProtectionLedger.activeAttempt
    }

    var hasUnresolvedResetCreditProtectionAttempt: Bool {
        resetCreditProtectionJournal != nil
    }

    private func withFreshResetCreditProtectionSession<T>(
        _ operation: (
            ResetCreditProtectionAppServerSession,
            ResetCreditProtectionBoundAppServer
        ) async throws -> T
    ) async rethrows -> T {
        let session = resetCreditProtectionSessionFactory.makeSession()
        let appServer = ResetCreditProtectionBoundAppServer(
            service: session,
            destructiveActionsAllowed:
                resetCreditProtectionRuntimeAllowsDestructiveActions
        )
        do {
            let result = try await operation(session, appServer)
            await session.shutdown()
            return result
        } catch {
            await session.shutdown()
            throw error
        }
    }

    var dashboardState: DashboardState {
        DashboardPreviewFactory.state(for: debugPreview, live: state)
    }

    var statusBarDisplayOptions: StatusBarDisplayOptions {
        StatusBarDisplayOptions(
            preciseIQ: statusBarPreciseIQEnabled,
            iqDisplayMode: statusBarIQDisplayMode,
            percentDisplayMode: statusBarPercentDisplayMode,
            separator: statusBarSeparator,
            horizontalPadding: statusBarHorizontalPadding,
            fontScale: statusBarFontScale,
            quotaPacingStrategy: quotaPacingStrategy,
            usesChinaHolidayCalendar: chinaHolidayCalendarEnabled
        )
    }

    var quotaPacingHolidayCalendar: HolidayCalendar? {
        chinaHolidayCalendarEnabled ? .chinaMainland2026 : nil
    }

    var shouldEmphasizeSpeedAlert: Bool {
        guard let key = dashboardState.speedAlertKey else {
            return false
        }
        guard dismissedSpeedAlertKey != key else {
            return false
        }
        guard emphasizedSpeedAlertKey == key,
              let speedAlertFirstSeenAt else {
            return true
        }
        return Date().timeIntervalSince(speedAlertFirstSeenAt) <= AppConstants.speedAlertEmphasisSeconds
    }

    func dismissCurrentSpeedAlert() {
        guard let key = dashboardState.speedAlertKey else {
            return
        }
        dismissedSpeedAlertKey = key
        updateTitleForStatusItem()
    }

    func resetSpeedAlertDismissal() {
        dismissedSpeedAlertKey = nil
        updateTitleForStatusItem()
    }

    func isStatusMetricEnabled(_ metric: StatusMetric) -> Bool {
        selectedStatusMetrics.contains(metric)
    }

    func setStatusMetric(_ metric: StatusMetric, enabled: Bool) {
        var next = Set(selectedStatusMetrics)
        if enabled {
            next.insert(metric)
        } else {
            next.remove(metric)
        }
        guard !next.isEmpty else {
            return
        }
        selectedStatusMetrics = StatusMetric.allCases.filter { next.contains($0) }
    }

    func isDashboardSectionExpanded(_ section: DashboardSection) -> Bool {
        dashboardLayout.expandedSections.contains(section)
    }

    func setDashboardSection(
        _ section: DashboardSection,
        expanded: Bool
    ) {
        var next = dashboardLayout
        next.setExpanded(section, expanded: expanded)
        guard next != dashboardLayout else {
            return
        }
        dashboardLayout = next
    }

    func isDashboardDisclosureExpanded(
        _ disclosure: DashboardDisclosure
    ) -> Bool {
        switch disclosure {
        case .modelIQDetails:
            return modelIQDetailsExpanded
        case .radarInsightsDetails:
            return radarInsightsDetailsExpanded
        }
    }

    func setDashboardDisclosure(
        _ disclosure: DashboardDisclosure,
        expanded: Bool
    ) {
        switch disclosure {
        case .modelIQDetails:
            modelIQDetailsExpanded = expanded
        case .radarInsightsDetails:
            radarInsightsDetailsExpanded = expanded
        }
    }

    func moveDashboardSection(
        _ section: DashboardSection,
        to targetIndex: Int
    ) {
        var next = dashboardLayout
        next.move(section, to: targetIndex)
        guard next != dashboardLayout else {
            return
        }
        dashboardLayout = next
    }

    func setDashboardSectionOrder(_ order: [DashboardSection]) {
        var next = dashboardLayout
        next.setOrder(order)
        guard next != dashboardLayout else {
            return
        }
        dashboardLayout = next
    }

    func resetDashboardLayout() {
        guard dashboardLayout != .default
                || DashboardDisclosure.allCases.contains(where: {
                    isDashboardDisclosureExpanded($0)
                        != $0.isExpandedByDefault
                }) else {
            return
        }
        if dashboardLayout != .default {
            dashboardLayout = .default
        }
        for disclosure in DashboardDisclosure.allCases {
            setDashboardDisclosure(
                disclosure,
                expanded: disclosure.isExpandedByDefault
            )
        }
    }

    func resetStatusBarAdvancedOptions() {
        let defaults = StatusBarDisplayOptions.defaultOptions
        statusBarPreciseIQEnabled = defaults.preciseIQ
        statusBarIQDisplayMode = defaults.iqDisplayMode
        statusBarPercentDisplayMode = defaults.percentDisplayMode
        statusBarSeparator = defaults.separator
        statusBarHorizontalPadding = defaults.horizontalPadding
        statusBarFontScale = defaults.fontScale
    }

    func configureForStatusScreenshot(
        language: AppLanguage,
        metrics: [StatusMetric]
    ) {
        precondition(!metrics.isEmpty)
        appLanguage = language
        menuTextSize = .large
        let options = StatusBarDisplayOptions.defaultOptions
        statusBarPreciseIQEnabled = options.preciseIQ
        statusBarIQDisplayMode = options.iqDisplayMode
        statusBarPercentDisplayMode = options.percentDisplayMode
        statusBarSeparator = options.separator
        statusBarHorizontalPadding = options.horizontalPadding
        statusBarFontScale = options.fontScale
        quotaPacingStrategy = options.quotaPacingStrategy
        chinaHolidayCalendarEnabled = options.usesChinaHolidayCalendar
        quotaPacingOptionsExpanded = false
        statusBarAdvancedOptionsExpanded = false
        selectedStatusMetrics = metrics
    }

    func start() {
        startLifecycleObservation()
        if resetCreditProtectionJournalCorrupt {
            deliverResetCreditProtectionFailure(
                identifier: "reset-credit-protection-journal-unavailable",
                body: appLanguage.text(
                    "本地自动使用记录无法可靠读取。为避免重复使用，自动使用已关闭且不会发送请求。",
                    "The local auto-use record cannot be read reliably. Auto-use is off and no request will be sent to avoid duplicate use."
                )
            )
        }
        refreshNow()
        startAutomaticUpdateChecks()
        startResetCreditAutoRefresh()
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: AppConstants.defaultPollIntervalSeconds * 1_000_000_000)
                await self?.refresh()
            }
        }
    }

    func stop() {
        pollingTask?.cancel()
        refreshTask?.cancel()
        updateTask?.cancel()
        automaticUpdateTask?.cancel()
        resetCreditTask?.cancel()
        resetCreditAutoRefreshTask?.cancel()
        radarInsightsTask?.cancel()
        radarInsightsTask = nil
        resetCreditProtectionTask?.cancel()
        resetCreditProtectionEnablingClockAnchor = nil
        stopLifecycleObservation()
        Task {
            if let client = appServerClient as? CodexAppServerClient {
                await client.shutdown()
            }
        }
    }

    func refreshNow() {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            await self?.refresh()
        }
    }

    func openCodexRadar() {
        NSWorkspace.shared.open(AppConstants.codexRadarBaseURL)
    }

    func openURL(_ url: URL) {
        NSWorkspace.shared.open(url)
    }

    func openLatestReleaseNotes() {
        NSWorkspace.shared.open(latestUpdate?.releaseURL ?? AppConstants.githubReleasesURL)
    }

    func openGitHubRepository() {
        NSWorkspace.shared.open(AppConstants.githubRepositoryURL)
    }

    func openPromptLog() {
        NSWorkspace.shared.open(AppConstants.githubPromptLogURL)
    }

    func openCodexApp() {
        NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: "/Applications/Codex.app"), configuration: NSWorkspace.OpenConfiguration())
    }

    func quit() {
        NSApplication.shared.terminate(nil)
    }

    func refreshResetCredits() {
        refreshResetCredits(automatic: false)
    }

    func enableResetCreditExpiryProtection() {
        guard resetCreditProtectionRuntimeAllowsDestructiveActions,
              debugPreview == .live else {
            resetCreditProtectionStatus = .disabled
            return
        }
        guard !resetCreditProtectionJournalCorrupt else {
            resetCreditProtectionStatus = .blocked(.journalUnavailable, detail: nil)
            return
        }
        guard !resetCreditProtectionEnabled,
              resetCreditProtectionTask == nil else {
            return
        }
        let clockGeneration = resetCreditProtectionClockGeneration
        let clockAnchor = resetCreditProtectionClock()
        resetCreditProtectionEnablingClockAnchor = clockAnchor
        resetCreditProtectionStatus = .enabling
        resetCreditProtectionTask = Task { [weak self] in
            guard let self else {
                return
            }
            await self.armResetCreditExpiryProtection(
                clockGeneration: clockGeneration,
                clockAnchor: clockAnchor
            )
            if self.resetCreditProtectionEnablingClockAnchor == clockAnchor {
                self.resetCreditProtectionEnablingClockAnchor = nil
            }
            self.resetCreditProtectionTask = nil
        }
    }

    func disableResetCreditExpiryProtection() {
        resetCreditProtectionTask?.cancel()
        resetCreditProtectionEnablingClockAnchor = nil
        do {
            try resetCreditProtectionAuthorizationStore.clear { [defaults] in
                defaults.set(
                    false,
                    forKey: DefaultsKey.resetCreditProtectionEnabled
                )
            }
        } catch {
            failClosedForResetCreditProtectionJournal()
            return
        }
        resetCreditProtectionEnabled = false
        resetCreditProtectionConsent = nil
        resetCreditProtectionNextRetryAt = nil
        if resetCreditProtectionJournal == nil {
            resetCreditProtectionStatus = .disabled
        }
    }

    func handleSystemClockChange() {
        let requestedBeforeValidation = defaults.object(
            forKey: DefaultsKey.resetCreditProtectionEnabled
        ) as? Bool ?? false
        let protectionWasRelevant = resetCreditProtectionEnabled
            || resetCreditProtectionJournal != nil
            || resetCreditProtectionStatus == .enabling
            || requestedBeforeValidation
        guard protectionWasRelevant else {
            refreshNow()
            return
        }

        let currentClock = resetCreditProtectionClock()
        let clockValidation: ResetCreditProtectionAuthorizationStore
            .ClockValidationResult
        do {
            clockValidation = try resetCreditProtectionAuthorizationStore
                .validateCurrentClockOrRevoke(
                    currentClock: currentClock
                ) { [defaults] in
                    defaults.set(
                        false,
                        forKey: DefaultsKey.resetCreditProtectionEnabled
                    )
                }
        } catch {
            resetCreditProtectionClockGeneration &+= 1
            resetCreditProtectionTask?.cancel()
            resetCreditProtectionEnablingClockAnchor = nil
            resetCreditProtectionEnabled = false
            resetCreditProtectionConsent = nil
            resetCreditProtectionNextRetryAt = nil
            resetCreditProtectionJournalCorrupt = true
            defaults.set(false, forKey: DefaultsKey.resetCreditProtectionEnabled)
            resetCreditProtectionStatus = .blocked(
                .journalUnavailable,
                detail: nil
            )
            refreshNow()
            return
        }

        if case .continuous(let consent) = clockValidation {
            guard resetCreditProtectionRuntimeAllowsDestructiveActions,
                  debugPreview == .live else {
                resetCreditProtectionEnablingClockAnchor = nil
                resetCreditProtectionEnabled = false
                resetCreditProtectionConsent = nil
                resetCreditProtectionNextRetryAt = nil
                if resetCreditProtectionJournal == nil {
                    resetCreditProtectionStatus = .disabled
                }
                refreshNow()
                return
            }
            let requested = defaults.object(
                forKey: DefaultsKey.resetCreditProtectionEnabled
            ) as? Bool ?? false
            guard requested else {
                resetCreditProtectionClockGeneration &+= 1
                resetCreditProtectionTask?.cancel()
                resetCreditProtectionEnablingClockAnchor = nil
                do {
                    _ = try resetCreditProtectionAuthorizationStore.clear(
                        ifCurrent: consent
                    ) { [defaults] in
                        defaults.set(
                            false,
                            forKey: DefaultsKey.resetCreditProtectionEnabled
                        )
                    }
                } catch {
                    resetCreditProtectionEnabled = false
                    resetCreditProtectionConsent = nil
                    resetCreditProtectionNextRetryAt = nil
                    resetCreditProtectionJournalCorrupt = true
                    resetCreditProtectionStatus = .blocked(
                        .journalUnavailable,
                        detail: nil
                    )
                    refreshNow()
                    return
                }
                resetCreditProtectionEnabled = false
                resetCreditProtectionConsent = nil
                resetCreditProtectionNextRetryAt = nil
                if let journal = resetCreditProtectionJournal {
                    resetCreditProtectionStatus = .reconciling(
                        expiresAt: journal.expiresAt
                    )
                } else {
                    resetCreditProtectionStatus = .disabled
                }
                refreshNow()
                return
            }
            if resetCreditProtectionStatus == .enabling
                || resetCreditProtectionConsent != consent {
                resetCreditProtectionClockGeneration &+= 1
                resetCreditProtectionTask?.cancel()
                resetCreditProtectionEnablingClockAnchor = nil
            }
            resetCreditProtectionEnabled = true
            resetCreditProtectionConsent = consent
            if resetCreditProtectionStatus == .enabling {
                resetCreditProtectionStatus = .checking
            }
            refreshNow()
            return
        }

        var enablingDiscontinuityReason:
            ResetCreditProtectionAuthorization.ClockDiscontinuityReason?
        if clockValidation == .absent,
           resetCreditProtectionStatus == .enabling,
           let clockAnchor = resetCreditProtectionEnablingClockAnchor {
            enablingDiscontinuityReason = ResetCreditProtectionAuthorization
                .clockDiscontinuityReason(
                    anchor: clockAnchor,
                    current: currentClock
                )
            if enablingDiscontinuityReason == nil {
                refreshNow()
                return
            }
        }

        if clockValidation == .absent,
           let journal = resetCreditProtectionJournal,
           resetCreditProtectionStatus != .enabling {
            resetCreditProtectionClockGeneration &+= 1
            resetCreditProtectionTask?.cancel()
            resetCreditProtectionEnablingClockAnchor = nil
            resetCreditProtectionEnabled = false
            resetCreditProtectionConsent = nil
            resetCreditProtectionNextRetryAt = nil
            resetCreditProtectionStatus = .reconciling(
                expiresAt: journal.expiresAt
            )
            refreshNow()
            return
        }

        if clockValidation == .absent,
           resetCreditProtectionStatus != .enabling {
            let protectionExpectedAuthorization =
                requestedBeforeValidation || resetCreditProtectionEnabled
            resetCreditProtectionClockGeneration &+= 1
            resetCreditProtectionTask?.cancel()
            resetCreditProtectionEnablingClockAnchor = nil
            resetCreditProtectionEnabled = false
            resetCreditProtectionConsent = nil
            resetCreditProtectionNextRetryAt = nil
            if protectionExpectedAuthorization {
                resetCreditProtectionStatus = .blocked(
                    .creditNotAuthorized,
                    detail: appLanguage.text(
                        "本地授权记录不存在，自动使用已安全关闭；请重新显式开启。",
                        "The local authorization record is missing. Auto-use was safely turned off; enable it again explicitly."
                    )
                )
                deliverResetCreditProtectionFailure(
                    identifier:
                        "reset-credit-protection-authorization-missing",
                    body: appLanguage.text(
                        "重置卡自动使用的本地授权记录不存在。未发送用卡请求；请重新显式开启。",
                        "The local authorization for reset-credit auto-use is missing. No consume request was sent; enable auto-use again explicitly."
                    )
                )
            } else {
                resetCreditProtectionStatus = .disabled
            }
            refreshNow()
            return
        }

        resetCreditProtectionClockGeneration &+= 1
        resetCreditProtectionTask?.cancel()
        resetCreditProtectionEnablingClockAnchor = nil
        resetCreditProtectionEnabled = false
        resetCreditProtectionConsent = nil
        resetCreditProtectionNextRetryAt = nil
        if clockValidation == .corrupt {
            resetCreditProtectionJournalCorrupt = true
            resetCreditProtectionStatus = .blocked(
                .journalUnavailable,
                detail: nil
            )
        } else {
            let wasAlreadyBlocked: Bool
            if case .blocked(.clockChanged, _) =
                resetCreditProtectionStatus {
                wasAlreadyBlocked = true
            } else {
                wasAlreadyBlocked = false
            }
            let detail: String?
            if case .revoked(_, let reason) = clockValidation {
                detail = Self.resetCreditProtectionClockDiscontinuityDetail(
                    reason,
                    language: appLanguage
                )
            } else if let enablingDiscontinuityReason {
                detail = Self.resetCreditProtectionClockDiscontinuityDetail(
                    enablingDiscontinuityReason,
                    language: appLanguage
                )
            } else {
                detail = appLanguage.text(
                    "时钟变化发生在自动使用启用完成前，未建立稳定授权。",
                    "The clock changed before auto-use finished enabling, so no stable authorization was established."
                )
            }
            resetCreditProtectionStatus = .blocked(
                .clockChanged,
                detail: detail
            )
            if !wasAlreadyBlocked {
                deliverResetCreditProtectionFailure(
                    identifier: "reset-credit-protection-clock-changed",
                    body: appLanguage.text(
                        "检测到系统时间与连续计时偏差超过 5 秒，或连续计时器已重置。为避免提前使用，自动使用已关闭；核对系统时间与只读计划后再显式开启。",
                        "The system clock differed from continuous time by more than 5 seconds, or the continuous clock reset. Auto-use was turned off to avoid an early use; verify the clock and read-only plan before enabling again."
                    )
                )
            }
        }
        refreshNow()
    }

    func previewResetCreditExpiryProtectionPlan() {
        guard !resetCreditProtectionJournalCorrupt else {
            resetCreditProtectionStatus = .blocked(.journalUnavailable, detail: nil)
            return
        }
        guard !resetCreditProtectionEnabled,
              resetCreditProtectionTask == nil else {
            return
        }
        resetCreditProtectionStatus = .checking
        resetCreditProtectionTask = Task { [weak self] in
            guard let self else {
                return
            }
            await self.loadResetCreditProtectionPreview()
            self.resetCreditProtectionTask = nil
        }
    }

    func refreshResetCreditsIfNeeded(automatic: Bool) {
        guard resetCreditAutoRefreshEnabled else {
            return
        }
        guard resetCreditSnapshotIsStale() else {
            return
        }
        refreshResetCredits(automatic: automatic)
    }

    private func refreshResetCredits(automatic: Bool) {
        guard !resetCreditPhase.isLoading else {
            return
        }
        let client = resetCreditClient
        resetCreditTask?.cancel()
        resetCreditPhase = .loading(Date(), automatic: automatic)
        resetCreditTask = Task { [weak self, client] in
            do {
                let snapshot = try await client.fetch()
                await MainActor.run {
                    guard let self else {
                        return
                    }
                    self.resetCreditSnapshot = snapshot
                    self.saveResetCreditSnapshot(snapshot)
                    self.resetCreditPhase = .idle
                }
            } catch {
                await MainActor.run {
                    guard let self else {
                        return
                    }
                    self.resetCreditPhase = .failed(
                        self.resetCreditFailure(from: error, automatic: automatic)
                    )
                }
            }
        }
    }

    func checkForUpdatesNow(automatic: Bool = false) {
        guard !updatePhase.isActive else {
            return
        }
        updateTask?.cancel()
        updateTask = Task { [weak self] in
            await self?.checkForUpdates(automatic: automatic)
        }
    }

    func configureForDocumentation(
        language: AppLanguage,
        textSize: DashboardTextSize = .large
    ) {
        appLanguage = language
        menuTextSize = textSize
        resetStatusBarAdvancedOptions()
        quotaPacingStrategy = .timeProportional
        chinaHolidayCalendarEnabled = true
        quotaPacingOptionsExpanded = false
        statusBarAdvancedOptionsExpanded = false
        dashboardLayout = .default
        for disclosure in DashboardDisclosure.allCases {
            setDashboardDisclosure(
                disclosure,
                expanded: disclosure.isExpandedByDefault
            )
        }
        selectedStatusMetrics = Self.defaultStatusMetrics
        debugPreview = .live
        predictionNotificationsEnabled = true
        iqNotificationsEnabled = true
        notificationSoundEnabled = false
        suppressResetCreditAutoRefreshSideEffects = true
        resetCreditAutoRefreshEnabled = true
        suppressResetCreditAutoRefreshSideEffects = false
        resetCreditProtectionEnabled = false
        resetCreditProtectionStatus = .disabled
        updatePhase = .upToDate(Date())

        var documentationState = DashboardPreviewFactory.state(
            for: .resetConfirmed,
            live: DashboardState()
        )
        documentationState.rateLimits = Self.documentationRateLimits()
        documentationState.current = Self.documentationCurrent(language: language)
        documentationState.prediction = Self.documentationPrediction(language: language)
        documentationState.modelIQ = Self.documentationModelIQ()
        documentationState.modelRatings = Self.documentationModelRatings()
        documentationState.radarInsights = Self.documentationRadarInsights()
        documentationState.lastUpdatedAt = Self.documentationUpdatedAt
        state = documentationState
        resetCreditSnapshot = Self.documentationResetCreditSnapshot()
        resetCreditPhase = .idle
    }

    func configureForDocumentationAttention() {
        resetCreditProtectionStatus = .blocked(
            .requestFailed,
            detail: nil
        )
        updatePhase = .failed(
            appLanguage.text(
                "校验失败，请重新检查",
                "Verification failed; check again"
            )
        )
    }

    private static let documentationUpdatedAt = Date(timeIntervalSince1970: 1_784_270_280)

    private static func documentationRateLimits() -> RateLimitDashboard? {
        let now = Int(Date().timeIntervalSince1970)
        let weeklyReset = now + Int(
            AppConstants.weeklyWindowMinutes * 60 * 0.48
        )
        guard let response: RateLimitResponse = decodeDocumentationJSON("""
        {
          "rateLimits": {
            "limitId": "codex",
            "limitName": null,
            "primary": { "usedPercent": 85, "windowDurationMins": 10080, "resetsAt": \(weeklyReset) },
            "secondary": null,
            "credits": null,
            "planType": "pro",
            "rateLimitReachedType": null
          },
          "rateLimitsByLimitId": null
        }
        """) else {
            return nil
        }
        return RateLimitDashboard(response: response)
    }

    private static func documentationRadarInsights() -> RadarInsightsEnvelope? {
        decodeDocumentationJSON("""
        {
          "schema": 1,
          "mode": "latest_valid_per_task",
          "generated_at": "2026-07-26T02:01:27+00:00",
          "source_updated_at": "2026-07-26T01:58:07+00:00",
          "recommendations": [
            {
              "key": "daily_development",
              "title": "日常开发",
              "rule": "性价比位优先兼顾智力、费用和耗时。",
              "items": [
                {
                  "model": "gpt-5.6-sol",
                  "effort": "medium",
                  "iq": 92.4,
                  "average_cost_usd": 3.82,
                  "average_duration_minutes": 15.98
                }
              ]
            },
            {
              "key": "hard_problems",
              "title": "难题攻坚",
              "rule": "优先选择当前实测 IQ 最高的档位。",
              "items": [
                {
                  "model": "gpt-5.6-sol",
                  "effort": "xhigh",
                  "iq": 95.1,
                  "average_cost_usd": 6.89,
                  "average_duration_minutes": 25.18
                }
              ]
            },
            {
              "key": "background_automation",
              "title": "后台自动化",
              "rule": "满足智力要求后优先选择费用更低的档位。",
              "items": [
                {
                  "model": "gpt-5.6-terra",
                  "effort": "xhigh",
                  "iq": 88.4,
                  "average_cost_usd": 2.48,
                  "average_duration_minutes": 19.27
                }
              ]
            },
            {
              "key": "lobster_tasks",
              "title": "跑龙虾类任务",
              "rule": "轻量长任务优先考虑综合性价比。",
              "items": [
                {
                  "model": "gpt-5.6-terra",
                  "effort": "high",
                  "iq": 73.7,
                  "average_cost_usd": 1.34,
                  "average_duration_minutes": 12.45
                }
              ]
            }
          ],
          "degradation_alerts": {
            "rule": "每个模型档位只与自身历史比较。",
            "items": [
              {
                "model": "gpt-5.6-sol",
                "effort": "low",
                "iq": 71.0,
                "from_24h_high_iq": 5.3,
                "from_48h_high_iq": 8.0
              },
              {
                "model": "gpt-5.6-terra",
                "effort": "medium",
                "iq": 50.0,
                "from_24h_high_iq": 4.9,
                "from_48h_high_iq": 7.6
              }
            ]
          }
        }
        """)
    }

    private static func documentationResetCreditSnapshot() -> ResetCreditSnapshot {
        let checkedAt = Date()
        let credits = [
            ResetCredit(
                idSuffix: "578aba",
                title: "Full reset (Weekly + 5 hr)",
                status: "available",
                resetType: "codex_rate_limits",
                grantedAt: checkedAt.addingTimeInterval(-7 * 86_400),
                expiresAt: checkedAt.addingTimeInterval(3 * 86_400)
            ),
            ResetCredit(
                idSuffix: "91f04e",
                title: "Full reset (Weekly + 5 hr)",
                status: "available",
                resetType: "codex_rate_limits",
                grantedAt: checkedAt.addingTimeInterval(-5 * 86_400),
                expiresAt: checkedAt.addingTimeInterval(5 * 86_400)
            ),
        ]
        return ResetCreditSnapshot(
            checkedAt: checkedAt,
            credits: credits,
            availableCount: credits.count,
            totalEarnedCount: credits.count
        )
    }


    private static func documentationModelIQ() -> ModelIQEnvelope? {
        decodeDocumentationJSON("""
        {
          "updated_at": "2026-07-22T10:02:00+08:00",
          "data_source": {
            "type": "distributed_community_runs",
            "url": "https://deng.codexradar.com",
            "checked_at": "2026-07-22T10:02:00+08:00",
            "valid_cells": 1995
          },
          "latest": {
            "date": "2026-07-22T10:02:00+08:00",
            "tasks": 112,
            "passed": 78,
            "iq_score": 104.5,
            "status": "green",
            "wall_seconds": 241659,
            "wall_time_human": "67小时8分",
            "average_task_seconds": 2160,
            "average_task_time_human": "36分钟",
            "input_tokens": 1412468252,
            "cached_input_tokens": 1382173696,
            "output_tokens": 6026231,
            "cost_usd": 1047.309802,
            "average_cost_usd": 9.2,
            "cost_usd_basis": "total_selected_tasks",
            "model": "gpt-5.6-sol",
            "reasoning_effort": "max"
          },
          "comparisons": {
            "gpt_56_sol_ultra": { "label": "GPT-5.6 Sol ultra", "model": "gpt-5.6-sol", "reasoning_effort": "ultra", "latest": { "tasks": 112, "passed": 73, "score": 97.8, "status": "green", "average_task_seconds": 3360, "average_task_time_human": "56分钟", "average_cost_usd": 25.9, "model": "gpt-5.6-sol", "reasoning_effort": "ultra" } },
            "gpt_56_sol_xhigh": { "label": "GPT-5.6 Sol xhigh", "model": "gpt-5.6-sol", "reasoning_effort": "xhigh", "latest": { "tasks": 103, "passed": 64, "score": 93.6, "status": "green", "average_task_seconds": 1620, "average_task_time_human": "27分钟", "average_cost_usd": 6.817724, "cache_hit_rate": 97.5, "model": "gpt-5.6-sol", "reasoning_effort": "xhigh" } },
            "gpt_56_sol_high": { "label": "GPT-5.6 Sol high", "model": "gpt-5.6-sol", "reasoning_effort": "high", "latest": { "tasks": 104, "passed": 62, "score": 89.8, "status": "yellow", "average_task_seconds": 1440, "average_task_time_human": "24分钟", "average_cost_usd": 5.203014, "cache_hit_rate": 97.3, "model": "gpt-5.6-sol", "reasoning_effort": "high" } },
            "gpt_56_sol_medium": { "label": "GPT-5.6 Sol medium", "model": "gpt-5.6-sol", "reasoning_effort": "medium", "latest": { "tasks": 107, "passed": 60, "score": 84.5, "status": "yellow", "average_task_seconds": 960, "average_task_time_human": "16分钟", "average_cost_usd": 3.262042, "cache_hit_rate": 96.7, "model": "gpt-5.6-sol", "reasoning_effort": "medium" } },
            "gpt_56_sol_low": { "label": "GPT-5.6 Sol low", "model": "gpt-5.6-sol", "reasoning_effort": "low", "latest": { "tasks": 101, "passed": 49, "score": 73.1, "status": "yellow", "average_task_seconds": 660, "average_task_time_human": "11分钟", "average_cost_usd": 1.908764, "cache_hit_rate": 95.6, "model": "gpt-5.6-sol", "reasoning_effort": "low" } },
            "gpt_56_terra_ultra": { "label": "GPT-5.6 Terra ultra", "model": "gpt-5.6-terra", "reasoning_effort": "ultra", "latest": { "tasks": 112, "passed": 75, "score": 100.4, "status": "green", "average_task_seconds": 2520, "average_task_time_human": "42分钟", "average_cost_usd": 13.4, "model": "gpt-5.6-terra", "reasoning_effort": "ultra" } },
            "gpt_56_terra_max": { "label": "GPT-5.6 Terra max", "model": "gpt-5.6-terra", "reasoning_effort": "max", "latest": { "tasks": 85, "passed": 54, "score": 95.7, "status": "green", "average_task_seconds": 1860, "average_task_time_human": "31分钟", "average_cost_usd": 4.842206, "cache_hit_rate": 97.7, "model": "gpt-5.6-terra", "reasoning_effort": "max" } },
            "gpt_56_terra_xhigh": { "label": "GPT-5.6 Terra xhigh", "model": "gpt-5.6-terra", "reasoning_effort": "xhigh", "latest": { "tasks": 112, "passed": 68, "score": 92.4, "status": "green", "average_task_seconds": 1200, "average_task_time_human": "20分钟", "average_cost_usd": 2.4, "model": "gpt-5.6-terra", "reasoning_effort": "xhigh" } },
            "gpt_56_terra_high": { "label": "GPT-5.6 Terra high", "model": "gpt-5.6-terra", "reasoning_effort": "high", "latest": { "tasks": 89, "passed": 46, "score": 77.9, "status": "yellow", "average_task_seconds": 840, "average_task_time_human": "14分钟", "average_cost_usd": 1.320583, "cache_hit_rate": 96.2, "model": "gpt-5.6-terra", "reasoning_effort": "high" } },
            "gpt_56_terra_medium": { "label": "GPT-5.6 Terra medium", "model": "gpt-5.6-terra", "reasoning_effort": "medium", "latest": { "tasks": 112, "passed": 45, "score": 60.3, "status": "yellow", "average_task_seconds": 600, "average_task_time_human": "10分钟", "average_cost_usd": 0.8, "model": "gpt-5.6-terra", "reasoning_effort": "medium" } },
            "gpt_56_terra_low": { "label": "GPT-5.6 Terra low", "model": "gpt-5.6-terra", "reasoning_effort": "low", "latest": { "tasks": 112, "passed": 33, "score": 44.2, "status": "red", "average_task_seconds": 480, "average_task_time_human": "8分钟", "average_cost_usd": 0.6, "model": "gpt-5.6-terra", "reasoning_effort": "low" } },
            "gpt_56_luna_max": { "label": "GPT-5.6 Luna max", "model": "gpt-5.6-luna", "reasoning_effort": "max", "latest": { "tasks": 94, "passed": 58, "score": 93.0, "status": "green", "average_task_seconds": 1980, "average_task_time_human": "33分钟", "average_cost_usd": 2.328072, "cache_hit_rate": 97.7, "model": "gpt-5.6-luna", "reasoning_effort": "max" } },
            "gpt_56_luna_xhigh": { "label": "GPT-5.6 Luna xhigh", "model": "gpt-5.6-luna", "reasoning_effort": "xhigh", "latest": { "tasks": 112, "passed": 59, "score": 79.0, "status": "yellow", "average_task_seconds": 1500, "average_task_time_human": "25分钟", "average_cost_usd": 1.6, "model": "gpt-5.6-luna", "reasoning_effort": "xhigh" } },
            "gpt_56_luna_high": { "label": "GPT-5.6 Luna high", "model": "gpt-5.6-luna", "reasoning_effort": "high", "latest": { "tasks": 82, "passed": 34, "score": 62.5, "status": "yellow", "average_task_seconds": 1080, "average_task_time_human": "18分钟", "average_cost_usd": 1.123607, "cache_hit_rate": 97.2, "model": "gpt-5.6-luna", "reasoning_effort": "high" } },
            "gpt_56_luna_medium": { "label": "GPT-5.6 Luna medium", "model": "gpt-5.6-luna", "reasoning_effort": "medium", "latest": { "tasks": 112, "passed": 27, "score": 36.2, "status": "red", "average_task_seconds": 660, "average_task_time_human": "11分钟", "average_cost_usd": 0.4, "model": "gpt-5.6-luna", "reasoning_effort": "medium" } },
            "gpt_56_luna_low": { "label": "GPT-5.6 Luna low", "model": "gpt-5.6-luna", "reasoning_effort": "low", "latest": { "tasks": 112, "passed": 6, "score": 8.0, "status": "red", "average_task_seconds": 480, "average_task_time_human": "8分钟", "average_cost_usd": 0.2, "model": "gpt-5.6-luna", "reasoning_effort": "low" } },
            "gpt_55_xhigh_distributed": { "label": "GPT-5.5 xhigh", "model": "gpt-5.5", "reasoning_effort": "xhigh", "latest": { "tasks": 112, "passed": 72, "score": 96.4, "status": "green", "average_task_seconds": 1380, "average_task_time_human": "23分钟", "average_cost_usd": 5.8, "model": "gpt-5.5", "reasoning_effort": "xhigh" } },
            "gpt_55_high_distributed": { "label": "GPT-5.5 high", "model": "gpt-5.5", "reasoning_effort": "high", "latest": { "tasks": 110, "passed": 62, "score": 84.9, "status": "yellow", "average_task_seconds": 1620, "average_task_time_human": "27分钟", "average_cost_usd": 3.521559, "cache_hit_rate": 97.0, "model": "gpt-5.5", "reasoning_effort": "high" } }
          },
          "quota_radar": {
            "date": "2026-07-16-am",
            "updated_at": "2026-07-16T09:47:00+08:00",
            "basis_date": "2026-07-16-am",
            "basis_window_label": "7d",
            "cost_usd": 214.26,
            "total_tokens": 0,
            "rows": [
              { "tier": "20x Pro", "basis": "measured 7d", "seven_d": 1428.41 },
              { "tier": "5x Pro", "basis": "model /4", "seven_d": 357.10 },
              { "tier": "Plus", "basis": "model /20", "seven_d": 71.42 }
            ],
            "trend": [
              { "date": "2026-07-15-pm", "seven_d_20x": 1922.96 },
              { "date": "2026-07-16-am", "seven_d_20x": 1428.41 }
            ]
          }
        }
        """)
    }

    private static func documentationModelRatings() -> ModelRatingsEnvelope? {
        decodeDocumentationJSON("""
        {
          "ok": true,
          "day": "2026-07-17",
          "timezone": "Asia/Shanghai",
          "refresh_seconds": 300,
          "updated_at": "2026-07-17T07:42:59.369Z",
          "models": [
            { "id": "gpt-5.6-sol-max", "label": "GPT-5.6 Sol max", "group": "GPT-5.6 Sol", "average": 6.4, "count": 46 },
            { "id": "gpt-5.6-sol-xhigh", "label": "GPT-5.6 Sol xhigh", "group": "GPT-5.6 Sol", "average": 7.2, "count": 61 },
            { "id": "gpt-5.6-sol-high", "label": "GPT-5.6 Sol high", "group": "GPT-5.6 Sol", "average": 7.0, "count": 43 },
            { "id": "gpt-5.6-sol-medium", "label": "GPT-5.6 Sol medium", "group": "GPT-5.6 Sol", "average": 8.7, "count": 135 },
            { "id": "gpt-5.6-sol-low", "label": "GPT-5.6 Sol low", "group": "GPT-5.6 Sol", "average": 7.3, "count": 20 },
            { "id": "gpt-5.6-terra-max", "label": "GPT-5.6 Terra max", "group": "GPT-5.6 Terra", "average": 6.0, "count": 7 },
            { "id": "gpt-5.6-terra-high", "label": "GPT-5.6 Terra high", "group": "GPT-5.6 Terra", "average": 6.9, "count": 11 },
            { "id": "gpt-5.6-luna-max", "label": "GPT-5.6 Luna max", "group": "GPT-5.6 Luna", "average": 7.9, "count": 71 },
            { "id": "gpt-5.6-luna-high", "label": "GPT-5.6 Luna high", "group": "GPT-5.6 Luna", "average": 8.0, "count": 10 }
          ],
          "source": "cache"
        }
        """)
    }

    private static func documentationCurrent(language: AppLanguage) -> RadarCurrent? {
        let title = language.text(
            "CodexRadar 重置、额度与模型雷达",
            "CodexRadar reset, quota, and model radar"
        )
        let window = language.text("无窗", "none")
        let scope = language.text(
            "重置雷达 / 额度雷达 / Fast / 分布式 Model IQ",
            "reset radar / quota radar / Fast / distributed Model IQ"
        )
        let summary = language.text(
            "CodexRadar 当前公开重置研判、7d 额度、Fast 实测与分布式社区 Model IQ。",
            "CodexRadar currently publishes reset judgement, 7d quota, Fast benchmarks, and distributed community Model IQ."
        )
        let resetUpdated = language.text("7月17日14:38研判", "Jul 17 14:38")
        let resetTitle = language.text("本轮硬重置已落地，进入冷却", "Latest hard reset complete; cooldown")
        let cardLabel = language.text("发重置卡", "Reset card")
        let cardLevel = language.text("低 · 本轮不是发卡", "Low · not a card rollout")
        let cardSummary = language.text(
            "9M 节点直接把周额度恢复到 100%，并未新增可自行兑换的 banked reset；其后也没有新的官方发卡信号。",
            "The 9M milestone restored weekly quota directly to 100% without issuing redeemable banked resets; no newer official card signal followed."
        )
        let hardResetLabel = language.text("硬重置", "Hard reset")
        let hardResetLevel = language.text("低 · 9M 重置已落地", "Low · 9M reset complete")
        let hardResetSummary = language.text(
            "Tibo 已宣布并完成本轮 Codex 与 ChatGPT Work 周额度硬重置；随后未出现新的重置承诺，下一轮进入冷却。",
            "Tibo announced and completed this Codex and ChatGPT Work weekly quota hard reset; no newer reset commitment followed, so the next round is in cooldown."
        )
        let reasonOne = language.text(
            "9M 重置的机制是直接恢复周额度到 100%，不是新增可兑换卡；已有多名用户报告额度恢复。",
            "The 9M reset restored weekly quota directly to 100% instead of issuing redeemable cards; multiple users reported recovery."
        )
        let reasonTwo = language.text(
            "连续两次里程碑重置已经落地，相关服务事故也已解决，短期内再次重置的必要性下降。",
            "Two milestone resets have landed and related service incidents are resolved, reducing the near-term need for another reset."
        )
        let communityTitle = language.text("重置卡过期时间自查", "Reset credit expiry check")
        let communityPrompt = language.text(
            "帮我用本机 Codex 凭证查一下 rate-limit reset credits，读取 ~/.codex/auth.json 里的 tokens.access_token，请求 https://chatgpt.com/backend-api/wham/rate-limit-reset-credits。要求：如果 401，说明是凭证失效或没带对 Authorization header；不要打印 access_token、refresh_token、cookie 或完整唯一 ID；只要展示每张重置卡发放时间和过期时间，从 UTC 转成北京时间，用中文回复。",
            "Use my local Codex credentials to check rate-limit reset credits from ~/.codex/auth.json tokens.access_token via https://chatgpt.com/backend-api/wham/rate-limit-reset-credits. If it returns 401, explain that the credential is expired or the Authorization header is missing. Do not print access_token, refresh_token, cookies, or full unique IDs. Show only each reset credit issue time and expiry time, converted to local time."
        )
        let maxReasoningTitle = language.text("如何开启 Max 推理强度", "How to enable Max reasoning")
        let maxReasoningGuide = language.text(
            "打开 Codex 设置 → Configuration → Model features → Available reasoning efforts，勾选 Max。之后即可在支持 Max 的模型控制中选择。",
            "Open Codex Settings → Configuration → Model features → Available reasoning efforts, then enable Max. After that, Max appears in supported model controls."
        )
        let announcementLabel = language.text("CodexRadar 公告", "CodexRadar notice")
        let announcementMessage = language.text(
            "分布式雷达 Codex 站上线：社区任务共同汇总 Model IQ、单题成本与耗时。",
            "The distributed Codex radar is live, aggregating community tasks into Model IQ, per-task cost, and duration."
        )
        let announcementUpdated = language.text("7月17日14:38更新", "Updated Jul 17 14:38")
        let fastTitle = language.text("Fast 雷达", "Fast Radar")
        let fastUpdated = language.text("7月14日18:01更新", "Jul 14 18:01")
        let fastSubtitle = language.text(
            "从标准改成 Fast，以 2.5 倍的成本到底快了多少？",
            "How much faster is Fast at 2.5x the cost?"
        )
        let fastMethod = language.text(
            "测试方法：Sol、Terra、Luna 均使用 low 推理强度，固定输出任务为从 1 数到 1024。Standard 与 Fast 各独立运行 3 次并取算术平均。",
            "Method: Sol, Terra, and Luna use low reasoning effort and a fixed count-to-1024 output task. Standard and Fast each run three times and use arithmetic averages."
        )
        return decodeDocumentationJSON("""
        {
          "schema_version": "homepage-fallback-v1",
          "checked_at": "2026-07-17T14:38:00+08:00",
          "status": "community_confirmed",
          "window_open": false,
          "recommended_action": "wait",
          "last_window": {
            "id": "documentation-homepage-fallback",
            "title": "\(title)",
            "status": "closed",
            "window_human": "\(window)",
            "scope": "\(scope)",
            "summary": "\(summary)",
            "closed_at": "2026-07-11T14:13:00+08:00"
          },
          "prediction": {
            "level": "low",
            "probability_24h": 0,
            "probability_48h": 0,
            "should_notify": false,
            "reasoning_summary": "\(summary)",
            "updated_at": "2026-07-17T14:38:00+08:00"
          },
          "reset_judgement": {
            "updated_label": "\(resetUpdated)",
            "title": "\(resetTitle)",
            "cards": [
              { "label": "\(cardLabel)", "level": "\(cardLevel)", "summary": "\(cardSummary)" },
              { "label": "\(hardResetLabel)", "level": "\(hardResetLevel)", "summary": "\(hardResetSummary)" }
            ],
            "reasons": [
              "\(reasonOne)",
              "\(reasonTwo)"
            ]
          },
          "community_knowledge": {
            "title": "\(communityTitle)",
            "prompt": "\(communityPrompt)"
          },
          "community_knowledges": [
            { "title": "\(communityTitle)", "prompt": "\(communityPrompt)" },
            { "title": "\(maxReasoningTitle)", "prompt": "\(maxReasoningGuide)" }
          ],
          "site_announcement": {
            "label": "\(announcementLabel)",
            "message": "\(announcementMessage)",
            "updated_label": "\(announcementUpdated)",
            "source_label": "\(language.text("分布式雷达", "Distributed radar"))",
            "source_url": "https://deng.codexradar.com"
          },
          "fast_radar": {
            "title": "\(fastTitle)",
            "updated_label": "\(fastUpdated)",
            "subtitle": "\(fastSubtitle)",
            "summary": [
              { "label": "\(language.text("体感加速", "E2E speedup"))", "value": "⚡️1.357×" },
              { "label": "\(language.text("首字延迟减少", "TTFT change"))", "value": "2.19s" },
              { "label": "\(language.text("Token 生成速度", "Token speed"))", "value": "⚡️1.477×" }
            ],
            "rows": [
              {
                "model": "Sol",
                "e2e": { "label": "E2E", "range": "56.29s → 40.35s", "value": "⚡️1.395×" },
                "ttft": { "label": "TTFT", "range": "19.17s → 15.53s", "value": "\(language.text("快 19.0%", "19.0% faster"))" },
                "tps": { "label": "TPS", "range": "55.93 → 83.75", "value": "⚡️1.498×" }
              },
              {
                "model": "Terra",
                "e2e": { "label": "E2E", "range": "59.64s → 41.87s", "value": "⚡️1.425×" },
                "ttft": { "label": "TTFT", "range": "18.14s → 13.92s", "value": "\(language.text("快 23.2%", "23.2% faster"))" },
                "tps": { "label": "TPS", "range": "50.74 → 75.40", "value": "⚡️1.486×" }
              },
              {
                "model": "Luna",
                "e2e": { "label": "E2E", "range": "50.68s → 40.56s", "value": "⚡️1.250×" },
                "ttft": { "label": "TTFT", "range": "13.19s → 14.47s", "value": "\(language.text("慢 9.7%", "9.7% slower"))" },
                "tps": { "label": "TPS", "range": "55.43 → 80.21", "value": "⚡️1.447×" }
              }
            ],
            "method": "\(fastMethod)"
          },
          "model_iq": {
            "updated_at": "2026-07-17T14:35:21+08:00",
            "data_source": {
              "type": "distributed_community_runs",
              "url": "https://deng.codexradar.com",
              "checked_at": "2026-07-17T14:35:21+08:00",
              "valid_cells": 984
            },
            "latest": {
              "date": "2026-07-17T14:35:21+08:00",
              "model": "gpt-5.6-sol",
              "reasoning_effort": "max",
              "tasks": 109,
              "valid_tasks": 109,
              "passed": 76,
              "iq_score": 105.1,
              "score": 105.1,
              "status": "green",
              "wall_seconds": 241659,
              "wall_time_human": "67小时8分",
              "average_task_seconds": 2217.055,
              "average_task_time_human": "37分钟",
              "input_tokens": 1412468252,
              "cached_input_tokens": 1382173696,
              "output_tokens": 6026231,
              "cost_usd": 1047.309802,
              "average_cost_usd": 9.608347,
              "cost_usd_basis": "total_selected_tasks"
            }
          }
        }
        """)
    }

    private static func documentationPrediction(language: AppLanguage) -> RadarPrediction? {
        let summary = language.text(
            "CodexRadar 当前已下架 reset 预测和速蹬窗口提醒；live 模式按低风险处理，并继续展示首页 Model IQ。",
            "CodexRadar has retired reset prediction and speed-window alerts; live mode treats this as low risk and keeps showing homepage Model IQ."
        )
        return decodeDocumentationJSON("""
        {
          "level": "low",
          "probability_24h": 0,
          "probability_48h": 0,
          "should_notify": false,
          "reasoning_summary": "\(summary)",
          "updated_at": "2026-07-17T14:38:00+08:00"
        }
        """)
    }

    private static func decodeDocumentationJSON<T: Decodable>(_ json: String) -> T? {
        try? JSONDecoder().decode(T.self, from: Data(json.utf8))
    }

    private func updateTitleForStatusItem() {
        updateSpeedAlertLifetime()
        titleForStatusItem = StatusTitleFormatter.plainTitle(
            for: dashboardState,
            metrics: selectedStatusMetrics,
            language: appLanguage,
            options: statusBarDisplayOptions
        )
    }

    private func updateSpeedAlertLifetime() {
        guard let key = dashboardState.speedAlertKey else {
            emphasizedSpeedAlertKey = nil
            speedAlertFirstSeenAt = nil
            return
        }
        guard emphasizedSpeedAlertKey != key else {
            return
        }
        emphasizedSpeedAlertKey = key
        speedAlertFirstSeenAt = Date()
    }

    private func refresh() async {
        startRadarInsightsRefreshIfNeeded()
        async let currentResult = fetchCurrentResult()
        async let modelRatingsResult = fetchModelRatingsResult()
        async let rateLimitResult = fetchRateLimitResult()

        let results = await (
            current: currentResult,
            modelRatings: modelRatingsResult,
            rateLimits: rateLimitResult
        )

        let previous = state
        var next = previous
        var errors: [String] = []

        applyCurrent(results.current, to: &next, errors: &errors)
        if case .success(let modelRatings) = results.modelRatings {
            next.modelRatings = modelRatings
        }
        switch results.rateLimits {
        case .success(let payload):
            next.rateLimits = payload.dashboard
            cacheResetCreditsFromAppServer(payload.response.rateLimitResetCredits)
            scheduleResetCreditProtectionEvaluation()
        case .failure(let error):
            errors.append(error.localizedDescription)
        }

        next.lastUpdatedAt = Date()
        next.lastError = errors.isEmpty ? nil : errors.joined(separator: "\n")
        let events = notificationPolicy.evaluate(
            previous: previous,
            current: next,
            memory: &notificationMemory
        )
        saveNotificationMemory()
        state = next
        deliver(events)
    }

    private func startRadarInsightsRefreshIfNeeded() {
        guard radarInsightsTask == nil else {
            return
        }
        radarInsightsTask = Task { [weak self] in
            guard let self else {
                return
            }
            defer {
                self.radarInsightsTask = nil
            }
            if case .success(let insights?) =
                await self.fetchRadarInsightsResult(),
               self.shouldAcceptRadarInsights(insights) {
                self.state.radarInsights = insights
            }
        }
    }

    private func fetchCurrentResult() async -> Result<RadarCurrent, Error> {
        await capture {
            try await radarClient.fetchCurrent()
        }
    }

    private func fetchModelRatingsResult() async -> Result<ModelRatingsEnvelope, Error> {
        await capture {
            try await radarClient.fetchModelRatings()
        }
    }

    private func fetchRadarInsightsResult()
        async -> Result<RadarInsightsEnvelope?, Error>
    {
        let uptime = radarInsightsUptime()
        if let lastRadarInsightsFetchUptime {
            let elapsed = uptime - lastRadarInsightsFetchUptime
            if elapsed >= 0,
               elapsed < AppConstants.radarInsightsRefreshIntervalSeconds {
                return .success(nil)
            }
        }
        lastRadarInsightsFetchUptime = uptime
        let result: Result<RadarInsightsEnvelope, Error> = await capture {
            try await radarClient.fetchRadarInsights()
        }
        switch result {
        case .success(let insights):
            return .success(insights)
        case .failure(let error):
            return .failure(error)
        }
    }

    private func shouldAcceptRadarInsights(
        _ candidate: RadarInsightsEnvelope
    ) -> Bool {
        guard let previous = state.radarInsights else {
            return true
        }
        let candidateDate = RadarDateParser.date(
            from: candidate.sourceUpdatedAt ?? candidate.generatedAt
        )
        let previousDate = RadarDateParser.date(
            from: previous.sourceUpdatedAt ?? previous.generatedAt
        )
        switch (candidateDate, previousDate) {
        case let (candidateDate?, previousDate?):
            return candidateDate >= previousDate
        case (nil, _?):
            return false
        default:
            return true
        }
    }

    private func fetchRateLimitResult() async -> Result<RateLimitReadPayload, Error> {
        await capture {
            let response = try await appServerClient.readRateLimits()
            return RateLimitReadPayload(
                response: response,
                dashboard: RateLimitDashboard(response: response)
            )
        }
    }

    private func capture<T>(_ operation: () async throws -> T) async -> Result<T, Error> {
        do {
            return .success(try await operation())
        } catch {
            return .failure(error)
        }
    }

    private func apply<T>(
        _ result: Result<T, Error>,
        to value: inout T?,
        errors: inout [String]
    ) {
        switch result {
        case .success(let newValue):
            value = newValue
        case .failure(let error):
            errors.append(error.localizedDescription)
        }
    }

    private func applyCurrent(
        _ result: Result<RadarCurrent, Error>,
        to state: inout DashboardState,
        errors: inout [String]
    ) {
        switch result {
        case .success(let current):
            state.current = current
            if let prediction = current.predictionDetail {
                state.prediction = prediction
            }
            if let modelIQ = current.modelIQ {
                state.modelIQ = modelIQ
            }
        case .failure(let error):
            errors.append(error.localizedDescription)
        }
    }

    private func deliver(_ events: [NotificationEvent]) {
        let filtered = events.filter { event in
            switch event.identifier {
            case let value where value.hasPrefix("prediction-"):
                return predictionNotificationsEnabled
            case let value where value.hasPrefix("model-iq-"):
                return iqNotificationsEnabled
            default:
                return true
            }
        }
        for event in filtered {
            NotificationService.shared.deliver(event, soundEnabled: notificationSoundEnabled)
        }
    }

    private func loadResetCreditProtectionPreview() async {
        do {
            try await withFreshResetCreditProtectionSession {
                session,
                appServer in
                let account = try await session.readAccount()
                guard let identitySeed = account.account?
                    .protectionIdentitySeed else {
                    resetCreditProtectionStatus = .blocked(
                        .accountIdentityUnavailable,
                        detail: nil
                    )
                    return
                }
                let accountFingerprint = ResetCreditPrivacy.fingerprint(
                    identitySeed
                )
                let response = try await appServer.readRateLimits(
                    boundTo: accountFingerprint
                )
                cacheResetCreditsFromAppServer(
                    response.rateLimitResetCredits,
                    force: true
                )
                guard let summary = response.rateLimitResetCredits else {
                    resetCreditProtectionStatus = .blocked(
                        .detailsUnavailable(0),
                        detail: nil
                    )
                    return
                }
                switch ResetCreditExpiryProtectionPolicy().decision(
                    summary: summary,
                    excludingCreditFingerprints: resetCreditProtectionLedger
                        .excludedCreditFingerprints
                ) {
                case .noCredits:
                    resetCreditProtectionStatus = .previewNoCredits(Date())
                case .detailsUnavailable(let availableCount):
                    resetCreditProtectionStatus = .blocked(
                        .detailsUnavailable(availableCount),
                        detail: nil
                    )
                case .detailsIncomplete(
                    let availableCount,
                    let availableDetails
                ):
                    resetCreditProtectionStatus = .blocked(
                        .detailsIncomplete(
                            availableCount: availableCount,
                            availableDetails: availableDetails
                        ),
                        detail: nil
                    )
                case .noSupportedExpiringCredits(let availableCount):
                    resetCreditProtectionStatus = .blocked(
                        .noSupportedExpiringCredits(availableCount),
                        detail: nil
                    )
                case .scheduled(let target):
                    resetCreditProtectionStatus = .preview(
                        actionAt: target.actionAt,
                        expiresAt: target.expiresAt,
                        availableCount: target.availableCount,
                        readyNow: false
                    )
                case .ready(let target):
                    resetCreditProtectionStatus = .preview(
                        actionAt: target.actionAt,
                        expiresAt: target.expiresAt,
                        availableCount: target.availableCount,
                        readyNow: true
                    )
                }
            }
        } catch ResetCreditProtectionAccountBindingError.accountChanged {
            resetCreditProtectionStatus = .blocked(
                .accountChanged,
                detail: nil
            )
        } catch {
            resetCreditProtectionStatus = protectionBlockedStatus(for: error)
        }
    }

    private func armResetCreditExpiryProtection(
        clockGeneration: UInt64,
        clockAnchor: ResetCreditProtectionClockSample
    ) async {
        guard !Task.isCancelled,
              clockGeneration == resetCreditProtectionClockGeneration else {
            return
        }
        if let reason = ResetCreditProtectionAuthorization
            .clockDiscontinuityReason(
                anchor: clockAnchor,
                current: resetCreditProtectionClock()
            ) {
            blockResetCreditProtectionEnableForClockDiscontinuity(reason)
            return
        }
        let processLock: ResetCreditProtectionProcessLock
        do {
            processLock = try ResetCreditProtectionProcessLock(
                url: resetCreditProtectionProcessLockURL
            )
        } catch {
            resetCreditProtectionStatus = .blocked(
                .anotherProcess,
                detail: nil
            )
            return
        }
        defer {
            processLock.release()
        }
        guard !Task.isCancelled,
              clockGeneration == resetCreditProtectionClockGeneration else {
            return
        }

        do {
            try await withFreshResetCreditProtectionSession {
                session,
                appServer in
                guard !Task.isCancelled,
                      clockGeneration
                        == resetCreditProtectionClockGeneration else {
                    return
                }
                switch reloadResetCreditProtectionJournal() {
                case .corrupt:
                    failClosedForResetCreditProtectionJournal()
                    return
                case .loaded(let journal):
                    await reconcileResetCreditProtectionJournalWhileLocked(
                        journal,
                        appServer: appServer
                    )
                    if clockGeneration
                        != resetCreditProtectionClockGeneration {
                        resetCreditProtectionStatus = .blocked(
                            .clockChanged,
                            detail: nil
                        )
                    }
                    return
                case .absent:
                    break
                }
                let account = try await session.readAccount()
                guard !Task.isCancelled,
                      clockGeneration
                        == resetCreditProtectionClockGeneration else {
                    return
                }
                guard let identitySeed = account.account?
                    .protectionIdentitySeed else {
                    resetCreditProtectionStatus = .blocked(
                        .accountIdentityUnavailable,
                        detail: nil
                    )
                    return
                }
                let accountFingerprint = ResetCreditPrivacy.fingerprint(
                    identitySeed
                )
                let response = try await appServer.readRateLimits(
                    boundTo: accountFingerprint
                )
                guard !Task.isCancelled,
                      clockGeneration
                        == resetCreditProtectionClockGeneration else {
                    return
                }
                cacheResetCreditsFromAppServer(
                    response.rateLimitResetCredits,
                    force: true
                )
                guard let summary = response.rateLimitResetCredits else {
                    resetCreditProtectionStatus = .blocked(
                        .detailsUnavailable(0),
                        detail: nil
                    )
                    return
                }
                let now = Date()
                let decision = ResetCreditExpiryProtectionPolicy().decision(
                    summary: summary,
                    now: now,
                    excludingCreditFingerprints: resetCreditProtectionLedger
                        .excludedCreditFingerprints
                )
                let target: ResetCreditProtectionTarget
                switch decision {
                case .scheduled(let scheduledTarget),
                     .ready(let scheduledTarget):
                    target = scheduledTarget
                default:
                    applyResetCreditProtectionDecisionStatus(decision)
                    return
                }
                guard let authorizedCreditFingerprints =
                    currentResetCreditProtectionFingerprints(
                        summary: summary,
                        now: now
                    ) else {
                    resetCreditProtectionStatus = .blocked(
                        .detailsIncomplete(
                            availableCount: summary.availableCount,
                            availableDetails: summary.credits?
                                .filter(\.isAvailable).count ?? 0
                        ),
                        detail: nil
                    )
                    return
                }
                guard !authorizedCreditFingerprints.isEmpty,
                      authorizedCreditFingerprints.contains(
                          target.creditFingerprint
                      ) else {
                    resetCreditProtectionStatus = .blocked(
                        .noSupportedExpiringCredits(summary.availableCount),
                        detail: nil
                    )
                    return
                }
                if let reason = ResetCreditProtectionAuthorization
                    .clockDiscontinuityReason(
                        anchor: clockAnchor,
                        current: resetCreditProtectionClock()
                    ) {
                    blockResetCreditProtectionEnableForClockDiscontinuity(
                        reason
                    )
                    return
                }
                let consent = ResetCreditProtectionConsent(
                    version: AppConstants.resetCreditProtectionConsentVersion,
                    accountFingerprint: accountFingerprint,
                    grantedAt: now,
                    authorizedCreditFingerprints:
                        authorizedCreditFingerprints,
                    clockAnchor: clockAnchor
                )
                guard !Task.isCancelled,
                      clockGeneration
                        == resetCreditProtectionClockGeneration else {
                    return
                }
                try resetCreditProtectionAuthorizationStore.save(
                    consent
                ) { [defaults] in
                    defaults.set(
                        true,
                        forKey: DefaultsKey.resetCreditProtectionEnabled
                    )
                }
                guard !Task.isCancelled,
                      clockGeneration
                        == resetCreditProtectionClockGeneration else {
                    _ = try resetCreditProtectionAuthorizationStore.clear(
                        ifCurrent: consent
                    ) { [defaults] in
                        defaults.set(
                            false,
                            forKey: DefaultsKey.resetCreditProtectionEnabled
                        )
                    }
                    return
                }
                resetCreditProtectionConsent = consent
                resetCreditProtectionEnabled = true
                switch decision {
                case .scheduled:
                    applyResetCreditProtectionDecisionStatus(decision)
                case .ready:
                    await attemptResetCreditProtectionWhileLocked(
                        target: target,
                        existingJournal: nil,
                        appServer: appServer
                    )
                    if clockGeneration
                        != resetCreditProtectionClockGeneration {
                        resetCreditProtectionStatus = .blocked(
                            .clockChanged,
                            detail: nil
                        )
                    }
                default:
                    break
                }
            }
        } catch ResetCreditProtectionAccountBindingError.accountChanged {
            resetCreditProtectionStatus = .blocked(
                .accountChanged,
                detail: nil
            )
        } catch {
            resetCreditProtectionStatus = protectionBlockedStatus(for: error)
        }
    }

    private func scheduleResetCreditProtectionEvaluation() {
        guard resetCreditProtectionRuntimeAllowsDestructiveActions,
              debugPreview == .live,
              resetCreditProtectionEnabled || resetCreditProtectionJournal != nil,
              resetCreditProtectionTask == nil else {
            return
        }
        resetCreditProtectionTask = Task { [weak self] in
            guard let self else {
                return
            }
            await self.evaluateResetCreditProtection()
            self.resetCreditProtectionTask = nil
        }
    }

    private func evaluateResetCreditProtection() async {
        guard resetCreditProtectionRuntimeAllowsDestructiveActions,
              debugPreview == .live else {
            resetCreditProtectionStatus = .disabled
            return
        }
        if resetCreditProtectionJournalCorrupt {
            resetCreditProtectionStatus = .blocked(.journalUnavailable, detail: nil)
            return
        }
        if resetCreditProtectionJournal != nil {
            await reconcilePersistedResetCreditProtectionJournal()
            return
        }
        guard resetCreditProtectionEnabled else {
            resetCreditProtectionStatus = .disabled
            return
        }
        let requested = defaults.object(
            forKey: DefaultsKey.resetCreditProtectionEnabled
        ) as? Bool ?? false
        guard let consent = resetCreditProtectionConsent,
              ResetCreditProtectionAuthorization.isEnabled(
                  requested: requested,
                  consent: consent
              ) else {
            disableResetCreditExpiryProtection()
            return
        }
        let response: RateLimitResponse
        do {
            response = try await resetCreditProtectionHintAppServer.readRateLimits(
                boundTo: consent.accountFingerprint
            )
        } catch ResetCreditProtectionAccountBindingError.accountChanged {
            invalidateResetCreditProtectionForAccountChange(
                preservingJournal: false,
                expectedConsent: consent
            )
            return
        } catch ResetCreditProtectionAccountBindingError.accountUnavailable {
            if revokeResetCreditProtectionAuthorization(
                expectedConsent: consent
            ) {
                resetCreditProtectionStatus = .blocked(
                    .signedOut,
                    detail: nil
                )
            }
            return
        } catch {
            if isAuthenticationError(error),
               revokeResetCreditProtectionAuthorization(
                   expectedConsent: consent
               ) {
                resetCreditProtectionStatus = .blocked(
                    .signedOut,
                    detail: nil
                )
                return
            }
            resetCreditProtectionStatus = protectionBlockedStatus(for: error)
            return
        }
        cacheResetCreditsFromAppServer(response.rateLimitResetCredits)
        guard let summary = response.rateLimitResetCredits else {
            resetCreditProtectionStatus = .blocked(.detailsUnavailable(0), detail: nil)
            return
        }

        let now = Date()
        let decision = ResetCreditExpiryProtectionPolicy().decision(
            summary: summary,
            now: now,
            excludingCreditFingerprints: resetCreditProtectionLedger
                .excludedCreditFingerprints
        )
        let selectedTarget: ResetCreditProtectionTarget?
        switch decision {
        case .scheduled(let target), .ready(let target):
            selectedTarget = target
        default:
            selectedTarget = nil
        }
        if let selectedTarget,
           !ResetCreditProtectionAuthorization.authorizes(
               requested: requested,
               consent: consent,
               target: selectedTarget
           ) {
            if revokeResetCreditProtectionAuthorization(
                expectedConsent: consent
            ) {
                resetCreditProtectionStatus = .blocked(
                    .creditNotAuthorized,
                    detail: nil
                )
            }
            return
        }
        switch decision {
        case .noCredits:
            resetCreditProtectionStatus = .noCredits(Date())
        case .detailsUnavailable(let availableCount):
            resetCreditProtectionStatus = .blocked(
                .detailsUnavailable(availableCount),
                detail: nil
            )
        case .detailsIncomplete(let availableCount, let availableDetails):
            resetCreditProtectionStatus = .blocked(
                .detailsIncomplete(
                    availableCount: availableCount,
                    availableDetails: availableDetails
                ),
                detail: nil
            )
        case .noSupportedExpiringCredits(let availableCount):
            resetCreditProtectionStatus = .blocked(
                .noSupportedExpiringCredits(availableCount),
                detail: nil
            )
        case .scheduled(let target):
            resetCreditProtectionStatus = .scheduled(
                actionAt: target.actionAt,
                expiresAt: target.expiresAt,
                availableCount: target.availableCount
            )
        case .ready(let target):
            if let retryAt = resetCreditProtectionNextRetryAt,
               retryAt > Date() {
                resetCreditProtectionStatus = .waitingForUsage(expiresAt: target.expiresAt)
                return
            }
            await attemptResetCreditProtection(target: target)
        }
    }

    private func reconcilePersistedResetCreditProtectionJournal() async {
        let processLock: ResetCreditProtectionProcessLock
        do {
            processLock = try ResetCreditProtectionProcessLock(
                url: resetCreditProtectionProcessLockURL
            )
        } catch {
            resetCreditProtectionNextRetryAt = Date().addingTimeInterval(
                AppConstants.resetCreditProtectionRetrySeconds
            )
            resetCreditProtectionStatus = .blocked(.anotherProcess, detail: nil)
            return
        }
        defer {
            processLock.release()
        }

        await withFreshResetCreditProtectionSession { _, appServer in
            switch reloadResetCreditProtectionJournal() {
            case .absent:
                if !resetCreditProtectionEnabled {
                    resetCreditProtectionStatus = .disabled
                }
            case .corrupt:
                failClosedForResetCreditProtectionJournal()
            case .loaded(let journal):
                await reconcileResetCreditProtectionJournalWhileLocked(
                    journal,
                    appServer: appServer
                )
            }
        }
    }

    private func reconcileResetCreditProtectionJournalWhileLocked(
        _ journal: ResetCreditProtectionAttemptJournal,
        appServer: ResetCreditProtectionBoundAppServer
    ) async {
        do {
            let response = try await appServer.readRateLimits(
                boundTo: journal.accountFingerprint
            )
            cacheResetCreditsFromAppServer(response.rateLimitResetCredits)
            await reconcileResetCreditProtectionJournal(
                journal,
                response: response,
                appServer: appServer
            )
        } catch ResetCreditProtectionAccountBindingError.accountChanged {
            handleResetCreditProtectionJournalAccountFailure(
                journal,
                accountChanged: true
            )
        } catch ResetCreditProtectionAccountBindingError.accountUnavailable {
            handleResetCreditProtectionJournalAccountFailure(
                journal,
                accountChanged: false
            )
        } catch {
            if isAuthenticationError(error) {
                handleResetCreditProtectionJournalAccountFailure(
                    journal,
                    accountChanged: false
                )
                return
            }
            resetCreditProtectionStatus = protectionBlockedStatus(for: error)
        }
    }

    private func reconcileResetCreditProtectionJournal(
        _ journal: ResetCreditProtectionAttemptJournal,
        response: RateLimitResponse,
        appServer: ResetCreditProtectionBoundAppServer
    ) async {
        let decision = ResetCreditProtectionRecoveryPolicy().decision(
            journal: journal,
            summary: response.rateLimitResetCredits,
            protectionEnabled: resetCreditProtectionEnabled,
            retryAt: resetCreditProtectionNextRetryAt
        )
        switch decision {
        case .confirmedUsed:
            finishVerifiedResetCreditProtection(journal: journal)
        case .confirmedNotConsumed(let expiresAt):
            guard clearResetCreditProtectionJournal() else {
                return
            }
            resetCreditProtectionNextRetryAt = Date().addingTimeInterval(
                AppConstants.resetCreditProtectionRetrySeconds
            )
            resetCreditProtectionStatus = resetCreditProtectionEnabled
                ? .waitingForUsage(expiresAt: expiresAt)
                : .disabled
        case .reconciling:
            resetCreditProtectionStatus = .reconciling(expiresAt: journal.expiresAt)
        case .missed:
            markResetCreditProtectionMissed(journal: journal)
        case .retry(let target):
            await attemptResetCreditProtectionWhileLocked(
                target: target,
                existingJournal: journal,
                appServer: appServer
            )
        }
    }

    private func attemptResetCreditProtection(
        target: ResetCreditProtectionTarget
    ) async {
        guard resetCreditProtectionRuntimeAllowsDestructiveActions,
              debugPreview == .live,
              resetCreditProtectionEnabled else {
            return
        }

        let processLock: ResetCreditProtectionProcessLock
        do {
            processLock = try ResetCreditProtectionProcessLock(
                url: resetCreditProtectionProcessLockURL
            )
        } catch {
            resetCreditProtectionNextRetryAt = Date().addingTimeInterval(
                AppConstants.resetCreditProtectionRetrySeconds
            )
            resetCreditProtectionStatus = .blocked(.anotherProcess, detail: nil)
            return
        }
        defer {
            processLock.release()
        }

        await withFreshResetCreditProtectionSession { _, appServer in
            switch reloadResetCreditProtectionJournal() {
            case .corrupt:
                failClosedForResetCreditProtectionJournal()
            case .loaded(let journal):
                await reconcileResetCreditProtectionJournalWhileLocked(
                    journal,
                    appServer: appServer
                )
            case .absent:
                await attemptResetCreditProtectionWhileLocked(
                    target: target,
                    existingJournal: nil,
                    appServer: appServer
                )
            }
        }
    }

    private func attemptResetCreditProtectionWhileLocked(
        target: ResetCreditProtectionTarget,
        existingJournal: ResetCreditProtectionAttemptJournal?,
        appServer: ResetCreditProtectionBoundAppServer
    ) async {
        guard resetCreditProtectionRuntimeAllowsDestructiveActions,
              debugPreview == .live else {
            resetCreditProtectionStatus = .disabled
            return
        }
        let requested = defaults.object(
            forKey: DefaultsKey.resetCreditProtectionEnabled
        ) as? Bool ?? false
        guard requested, resetCreditProtectionEnabled else {
            resetCreditProtectionEnabled = false
            resetCreditProtectionConsent = nil
            if let existingJournal {
                resetCreditProtectionStatus = .reconciling(
                    expiresAt: existingJournal.expiresAt
                )
            } else {
                resetCreditProtectionStatus = .disabled
            }
            return
        }
        let persistedConsent: ResetCreditProtectionConsent
        switch resetCreditProtectionAuthorizationStore.load() {
        case .loaded(let consent):
            persistedConsent = consent
        case .absent:
            resetCreditProtectionEnabled = false
            resetCreditProtectionConsent = nil
            if existingJournal == nil {
                resetCreditProtectionStatus = .disabled
            }
            return
        case .corrupt:
            failClosedForResetCreditProtectionJournal()
            return
        }
        guard ResetCreditProtectionAuthorization.authorizes(
            requested: requested,
            consent: persistedConsent,
            target: target
        ) else {
            resetCreditProtectionEnabled = false
            resetCreditProtectionConsent = nil
            defaults.set(
                false,
                forKey: DefaultsKey.resetCreditProtectionEnabled
            )
            if existingJournal == nil {
                resetCreditProtectionStatus = .blocked(
                    .creditNotAuthorized,
                    detail: nil
                )
            }
            return
        }
        let consent = persistedConsent
        resetCreditProtectionConsent = consent

        resetCreditProtectionStatus = .checking
        do {
            let accountFingerprint = consent.accountFingerprint
            let preflight = try await appServer.readRateLimits(
                boundTo: accountFingerprint
            )
            cacheResetCreditsFromAppServer(preflight.rateLimitResetCredits)
            guard resetCreditProtectionEnabled,
                  resetCreditProtectionConsent == consent,
                  let summary = preflight.rateLimitResetCredits else {
                resetCreditProtectionStatus = .blocked(
                    .detailsUnavailable(0),
                    detail: nil
                )
                return
            }

            let now = Date()
            let validatedTarget: ResetCreditProtectionTarget
            if let existingJournal {
                let recoveryDecision = ResetCreditProtectionRecoveryPolicy()
                    .decision(
                        journal: existingJournal,
                        summary: summary,
                        now: now,
                        protectionEnabled: true,
                        retryAt: nil
                    )
                guard case .retry(let currentTarget) = recoveryDecision,
                      currentTarget.creditFingerprint == target.creditFingerprint else {
                    await reconcileResetCreditProtectionJournal(
                        existingJournal,
                        response: preflight,
                        appServer: appServer
                    )
                    return
                }
                validatedTarget = currentTarget
            } else {
                let currentDecision = ResetCreditExpiryProtectionPolicy()
                    .decision(
                        summary: summary,
                        now: now,
                        excludingCreditFingerprints: resetCreditProtectionLedger
                            .excludedCreditFingerprints
                    )
                guard case .ready(let currentTarget) = currentDecision,
                      currentTarget.creditFingerprint == target.creditFingerprint else {
                    applyResetCreditProtectionDecisionStatus(currentDecision)
                    return
                }
                validatedTarget = currentTarget
            }
            guard ResetCreditProtectionAuthorization.authorizes(
                requested: defaults.object(
                    forKey: DefaultsKey.resetCreditProtectionEnabled
                ) as? Bool ?? false,
                consent: consent,
                target: validatedTarget
            ) else {
                if revokeResetCreditProtectionAuthorization(
                    expectedConsent: consent
                ) {
                    resetCreditProtectionStatus = .blocked(
                        .creditNotAuthorized,
                        detail: nil
                    )
                }
                return
            }
            guard let currentFingerprints =
                currentResetCreditProtectionFingerprints(
                    summary: summary,
                    now: now
                ),
                  currentFingerprints
                    == remainingAuthorizedResetCreditProtectionFingerprints(
                        consent: consent
                    ) else {
                if revokeResetCreditProtectionAuthorization(
                    expectedConsent: consent
                ) {
                    resetCreditProtectionStatus = .blocked(
                        .creditNotAuthorized,
                        detail: nil
                    )
                }
                return
            }
            guard let details = summary.credits else {
                resetCreditProtectionStatus = .blocked(
                    .detailsUnavailable(summary.availableCount),
                    detail: nil
                )
                return
            }
            let matchingCredits = details.filter {
                ResetCreditPrivacy.fingerprint($0.id)
                    == validatedTarget.creditFingerprint
            }
            guard matchingCredits.count == 1,
                  let currentCredit = matchingCredits.first else {
                resetCreditProtectionStatus = .blocked(
                    .detailsIncomplete(
                        availableCount: summary.availableCount,
                        availableDetails: details.filter(\.isAvailable).count
                    ),
                    detail: nil
                )
                return
            }
            let expiresAt = validatedTarget.expiresAt

            var journal = existingJournal ?? ResetCreditProtectionAttemptJournal(
                accountFingerprint: accountFingerprint,
                creditFingerprint: validatedTarget.creditFingerprint,
                idempotencyKey: UUID().uuidString,
                expiresAt: expiresAt,
                availableCountBefore: summary.availableCount,
                phase: .sending,
                updatedAt: now
            )
            guard journal.accountFingerprint == accountFingerprint,
                  journal.creditFingerprint == validatedTarget.creditFingerprint else {
                invalidateResetCreditProtectionForAccountChange(
                    preservingJournal: true,
                    expectedConsent: consent
                )
                return
            }
            journal.phase = .sending
            journal.confirmedOutcome = nil
            journal.updatedAt = now
            guard saveResetCreditProtectionJournal(journal) else {
                return
            }
            guard !Task.isCancelled,
                  resetCreditProtectionRuntimeAllowsDestructiveActions,
                  debugPreview == .live,
                  resetCreditProtectionEnabled,
                  resetCreditProtectionConsent == consent,
                  ResetCreditProtectionAuthorization.authorizes(
                      requested: defaults.object(
                          forKey: DefaultsKey.resetCreditProtectionEnabled
                      ) as? Bool,
                      consent: consent,
                      target: validatedTarget
                  ) else {
                if existingJournal == nil,
                   clearResetCreditProtectionJournal(),
                   !resetCreditProtectionEnabled {
                    resetCreditProtectionStatus = .disabled
                }
                return
            }
            resetCreditProtectionStatus = .using(expiresAt: expiresAt)

            let consumeResult: Result<ResetCreditConsumeResponse, Error>
            do {
                consumeResult = .success(
                    try await appServer.consumeResetCredit(
                        creditID: currentCredit.id,
                        idempotencyKey: journal.idempotencyKey,
                        authorization: ResetCreditProtectionDispatchAuthorization(
                            store: resetCreditProtectionAuthorizationStore,
                            consent: consent
                        ),
                        boundTo: accountFingerprint
                    )
                )
            } catch {
                consumeResult = .failure(error)
            }

            if case .failure(let error) = consumeResult,
               let bindingError = error
                as? ResetCreditProtectionAccountBindingError {
                switch bindingError {
                case .accountChanged:
                    invalidateResetCreditProtectionForAccountChange(
                        preservingJournal: true,
                        expectedConsent: consent
                    )
                case .accountUnavailable:
                    if revokeResetCreditProtectionAuthorization(
                        expectedConsent: consent
                    ) {
                        resetCreditProtectionStatus = .blocked(
                            .signedOut,
                            detail: nil
                        )
                    }
                case .destructiveActionsDisabled:
                    if let existingJournal {
                        _ = saveResetCreditProtectionJournal(existingJournal)
                    } else {
                        _ = clearResetCreditProtectionJournal()
                    }
                    if revokeResetCreditProtectionAuthorization(
                        expectedConsent: consent
                    ) {
                        resetCreditProtectionStatus = .disabled
                    }
                }
                return
            }

            if case .failure(let error) = consumeResult,
               isResetCreditPreDispatchFailure(error) {
                if let existingJournal {
                    guard saveResetCreditProtectionJournal(existingJournal) else {
                        return
                    }
                } else {
                    guard clearResetCreditProtectionJournal() else {
                        return
                    }
                }
                if case CodexAppServerClient.ClientError
                    .resetCreditDispatchAuthorizationUnavailable = error {
                    failClosedForResetCreditProtectionJournal()
                } else {
                    if revokeResetCreditProtectionAuthorization(
                        expectedConsent: consent
                    ) {
                        resetCreditProtectionStatus = .disabled
                    }
                }
                return
            }

            switch consumeResult {
            case .failure(let error):
                journal.phase = .sentUnknown
                journal.updatedAt = Date()
                guard saveResetCreditProtectionJournal(journal) else {
                    return
                }
                if isUnsupportedResetCreditRPC(error) {
                    if revokeResetCreditProtectionAuthorization(
                        expectedConsent: consent
                    ) {
                        resetCreditProtectionStatus = .blocked(
                            .unsupportedCodex,
                            detail: nil
                        )
                    }
                    return
                }
                if isAuthenticationError(error) {
                    if revokeResetCreditProtectionAuthorization(
                        expectedConsent: consent
                    ) {
                        resetCreditProtectionStatus = .blocked(
                            .signedOut,
                            detail: nil
                        )
                    }
                    return
                }
                resetCreditProtectionNextRetryAt = Date().addingTimeInterval(
                    AppConstants.resetCreditProtectionRetrySeconds
                )
                resetCreditProtectionStatus = .reconciling(expiresAt: expiresAt)
                if let refreshed = try? await appServer
                    .readRateLimits(
                        boundTo: accountFingerprint
                ) {
                    cacheResetCreditsFromAppServer(refreshed.rateLimitResetCredits)
                    await reconcileResetCreditProtectionJournal(
                        journal,
                        response: refreshed,
                        appServer: appServer
                    )
                }
                return
            case .success(let result):
                journal.phase = .outcomeConfirmed
                journal.confirmedOutcome = result.outcome
                journal.updatedAt = Date()
                guard saveResetCreditProtectionJournal(journal) else {
                    return
                }
                resetCreditProtectionStatus = .reconciling(expiresAt: expiresAt)
                do {
                    let refreshed = try await appServer
                        .readRateLimits(
                            boundTo: accountFingerprint
                    )
                    cacheResetCreditsFromAppServer(refreshed.rateLimitResetCredits)
                    await reconcileResetCreditProtectionJournal(
                        journal,
                        response: refreshed,
                        appServer: appServer
                    )
                } catch ResetCreditProtectionAccountBindingError.accountChanged {
                    invalidateResetCreditProtectionForAccountChange(
                        preservingJournal: true,
                        expectedConsent: consent
                    )
                } catch ResetCreditProtectionAccountBindingError
                    .accountUnavailable {
                    if revokeResetCreditProtectionAuthorization(
                        expectedConsent: consent
                    ) {
                        resetCreditProtectionStatus = .blocked(
                            .signedOut,
                            detail: nil
                        )
                    }
                } catch {
                    if isAuthenticationError(error),
                       revokeResetCreditProtectionAuthorization(
                           expectedConsent: consent
                       ) {
                        resetCreditProtectionStatus = .blocked(
                            .signedOut,
                            detail: nil
                        )
                    } else {
                        resetCreditProtectionNextRetryAt = Date()
                            .addingTimeInterval(
                                AppConstants.resetCreditProtectionRetrySeconds
                            )
                    }
                }
            }
        } catch ResetCreditProtectionAccountBindingError.accountChanged {
            invalidateResetCreditProtectionForAccountChange(
                preservingJournal: existingJournal != nil,
                expectedConsent: consent
            )
        } catch ResetCreditProtectionAccountBindingError.accountUnavailable {
            if revokeResetCreditProtectionAuthorization(
                expectedConsent: consent
            ) {
                resetCreditProtectionStatus = .blocked(
                    .signedOut,
                    detail: nil
                )
            }
        } catch {
            if isAuthenticationError(error),
               revokeResetCreditProtectionAuthorization(
                   expectedConsent: consent
               ) {
                resetCreditProtectionStatus = .blocked(
                    .signedOut,
                    detail: nil
                )
            } else {
                resetCreditProtectionStatus = protectionBlockedStatus(
                    for: error
                )
            }
        }
    }

    private func currentResetCreditProtectionFingerprints(
        summary: RateLimitResetCreditsSummary,
        now: Date
    ) -> Set<String>? {
        let availableCount = max(0, summary.availableCount)
        guard availableCount > 0 else {
            guard summary.credits?.contains(where: \.isAvailable) != true else {
                return nil
            }
            return []
        }
        guard let details = summary.credits else {
            return nil
        }
        let available = details.filter(\.isAvailable)
        let uniqueAvailableIDs = Set(available.map(\.id))
        guard available.count == availableCount,
              available.allSatisfy({ !$0.id.isEmpty }),
              uniqueAvailableIDs.count == availableCount else {
            return nil
        }
        let excluded = resetCreditProtectionLedger
            .excludedCreditFingerprints
        return Set(
            available.compactMap { credit -> String? in
                let fingerprint = ResetCreditPrivacy.fingerprint(credit.id)
                guard credit.isSupportedCodexReset,
                      credit.expiresAtDate.map({ $0 > now }) == true,
                      !excluded.contains(fingerprint) else {
                    return nil
                }
                return fingerprint
            }
        )
    }

    private func remainingAuthorizedResetCreditProtectionFingerprints(
        consent: ResetCreditProtectionConsent
    ) -> Set<String> {
        consent.authorizedCreditFingerprints.subtracting(
            resetCreditProtectionLedger.excludedCreditFingerprints
        )
    }

    private func applyResetCreditProtectionDecisionStatus(
        _ decision: ResetCreditProtectionDecision
    ) {
        switch decision {
        case .noCredits:
            resetCreditProtectionStatus = .noCredits(Date())
        case .detailsUnavailable(let availableCount):
            resetCreditProtectionStatus = .blocked(
                .detailsUnavailable(availableCount),
                detail: nil
            )
        case .detailsIncomplete(let availableCount, let availableDetails):
            resetCreditProtectionStatus = .blocked(
                .detailsIncomplete(
                    availableCount: availableCount,
                    availableDetails: availableDetails
                ),
                detail: nil
            )
        case .noSupportedExpiringCredits(let availableCount):
            resetCreditProtectionStatus = .blocked(
                .noSupportedExpiringCredits(availableCount),
                detail: nil
            )
        case .scheduled(let target):
            resetCreditProtectionStatus = .scheduled(
                actionAt: target.actionAt,
                expiresAt: target.expiresAt,
                availableCount: target.availableCount
            )
        case .ready:
            resetCreditProtectionStatus = .checking
        }
    }

    private func cacheResetCreditsFromAppServer(
        _ summary: RateLimitResetCreditsSummary?,
        force: Bool = false
    ) {
        guard force || resetCreditProtectionEnabled || resetCreditProtectionJournal != nil,
              let summary else {
            return
        }
        let snapshot = ResetCreditSnapshot(rateLimitResetCredits: summary)
        resetCreditSnapshot = snapshot
        saveResetCreditSnapshot(snapshot)
        resetCreditPhase = .idle
    }

    private func finishVerifiedResetCreditProtection(
        journal: ResetCreditProtectionAttemptJournal
    ) {
        guard archiveResetCreditProtectionJournal(
            journal,
            disposition: .confirmedUsed
        ) else {
            return
        }
        resetCreditProtectionNextRetryAt = nil
        let usedAt = Date()
        resetCreditProtectionStatus = .succeeded(
            usedAt: usedAt,
            expiresAt: journal.expiresAt
        )
        NotificationService.shared.deliver(
            NotificationEvent(
                identifier: "reset-credit-protection-success-\(journal.creditFingerprint)",
                title: appLanguage.text(
                    "已确认重置卡处于已使用状态",
                    "Reset credit confirmed as used"
                ),
                body: appLanguage.text(
                    "Codex 已确认该卡处于已使用状态，并已读取最新额度。",
                    "Codex confirmed that the credit is in the used state and the latest limits were read."
                ),
                severity: .active
            ),
            soundEnabled: notificationSoundEnabled
        )
    }

    private func markResetCreditProtectionMissed(
        journal: ResetCreditProtectionAttemptJournal
    ) {
        guard archiveResetCreditProtectionJournal(
            journal,
            disposition: .ambiguous
        ) else {
            return
        }
        resetCreditProtectionStatus = .missed(expiresAt: journal.expiresAt)
        deliverResetCreditProtectionFailure(
            identifier: "reset-credit-protection-missed-\(Int(journal.expiresAt.timeIntervalSince1970))",
            body: appLanguage.text(
                "重置卡已过期，未能确认自动使用是否完成。",
                "The reset credit expired before automatic use could be confirmed."
            )
        )
    }

    private func deliverResetCreditProtectionFailure(
        identifier: String,
        body: String
    ) {
        NotificationService.shared.deliver(
            NotificationEvent(
                identifier: identifier,
                title: appLanguage.text(
                    "重置卡自动使用需要检查",
                    "Reset credit auto-use needs attention"
                ),
                body: body,
                severity: .urgent
            ),
            soundEnabled: notificationSoundEnabled
        )
    }

    private static func resetCreditProtectionClockDiscontinuityDetail(
        _ reason: ResetCreditProtectionAuthorization.ClockDiscontinuityReason,
        language: AppLanguage
    ) -> String {
        switch reason {
        case .wallClockOffset(let seconds):
            let amount = String(format: "%.3f", abs(seconds))
            return language.text(
                seconds >= 0
                    ? "系统时间相对连续计时快了 \(amount) 秒，超过 5 秒安全阈值。"
                    : "系统时间相对连续计时慢了 \(amount) 秒，超过 5 秒安全阈值。",
                seconds >= 0
                    ? "The system clock was \(amount) seconds ahead of continuous time, exceeding the 5-second safety threshold."
                    : "The system clock was \(amount) seconds behind continuous time, exceeding the 5-second safety threshold."
            )
        case .continuousClockReset:
            return language.text(
                "连续计时器已重置，可能是系统重启。",
                "The continuous clock reset, which can indicate a system restart."
            )
        case .invalidSample:
            return language.text(
                "无法验证系统时钟与连续计时的连续性。",
                "System-clock continuity could not be verified."
            )
        }
    }

    private func blockResetCreditProtectionEnableForClockDiscontinuity(
        _ reason: ResetCreditProtectionAuthorization.ClockDiscontinuityReason
    ) {
        resetCreditProtectionClockGeneration &+= 1
        resetCreditProtectionEnablingClockAnchor = nil
        resetCreditProtectionEnabled = false
        resetCreditProtectionConsent = nil
        resetCreditProtectionNextRetryAt = nil
        defaults.set(false, forKey: DefaultsKey.resetCreditProtectionEnabled)
        resetCreditProtectionStatus = .blocked(
            .clockChanged,
            detail: Self.resetCreditProtectionClockDiscontinuityDetail(
                reason,
                language: appLanguage
            )
        )
        deliverResetCreditProtectionFailure(
            identifier: "reset-credit-protection-clock-changed",
            body: appLanguage.text(
                "启用期间检测到系统时间与连续计时偏差超过 5 秒，或连续计时器已重置。自动使用未启用，请核对系统时间与只读计划后重试。",
                "During enabling, the system clock differed from continuous time by more than 5 seconds, or the continuous clock reset. Auto-use was not enabled; verify the clock and read-only plan before trying again."
            )
        )
    }

    private func handleResetCreditProtectionJournalAccountFailure(
        _ journal: ResetCreditProtectionAttemptJournal,
        accountChanged: Bool
    ) {
        if Date() >= journal.expiresAt {
            markResetCreditProtectionMissed(journal: journal)
        } else {
            resetCreditProtectionStatus = .reconciling(
                expiresAt: journal.expiresAt
            )
        }

        guard let consent = resetCreditProtectionConsent,
              consent.accountFingerprint == journal.accountFingerprint else {
            resetCreditProtectionStatus = .blocked(
                accountChanged ? .accountChanged : .signedOut,
                detail: nil
            )
            return
        }
        if accountChanged {
            invalidateResetCreditProtectionForAccountChange(
                preservingJournal: Date() < journal.expiresAt,
                expectedConsent: consent
            )
        } else if revokeResetCreditProtectionAuthorization(
            expectedConsent: consent
        ) {
            resetCreditProtectionStatus = .blocked(.signedOut, detail: nil)
        }
    }

    private func invalidateResetCreditProtectionForAccountChange(
        preservingJournal: Bool,
        expectedConsent: ResetCreditProtectionConsent
    ) {
        guard revokeResetCreditProtectionAuthorization(
            expectedConsent: expectedConsent
        ) else {
            return
        }
        resetCreditProtectionStatus = .blocked(.accountChanged, detail: nil)
        deliverResetCreditProtectionFailure(
            identifier: "reset-credit-protection-account-changed",
            body: appLanguage.text(
                preservingJournal
                    ? "Codex 账号已变化。自动使用已关闭；切回原账号后会先对未决尝试进行只读对账。"
                    : "Codex 账号已变化。为避免误用其他账号的卡，自动使用已关闭，请重新确认开启。",
                preservingJournal
                    ? "The Codex account changed. Auto-use is off; switch back to the original account to reconcile the unresolved attempt."
                    : "The Codex account changed. Auto-use was turned off; enable it again to confirm the new account."
            )
        )
    }

    @discardableResult
    private func revokeResetCreditProtectionAuthorization(
        expectedConsent: ResetCreditProtectionConsent
    ) -> Bool {
        do {
            let result = try resetCreditProtectionAuthorizationStore.clear(
                ifCurrent: expectedConsent
            ) { [defaults] in
                defaults.set(
                    false,
                    forKey: DefaultsKey.resetCreditProtectionEnabled
                )
            }
            guard result != .superseded else {
                return false
            }
        } catch {
            resetCreditProtectionJournalCorrupt = true
            resetCreditProtectionStatus = .blocked(.journalUnavailable, detail: nil)
            return false
        }
        if resetCreditProtectionConsent == expectedConsent {
            resetCreditProtectionEnabled = false
            resetCreditProtectionConsent = nil
        }
        return true
    }

    private func protectionBlockedStatus(for error: Error) -> ResetCreditProtectionStatus {
        if let clientError = error as? CodexAppServerClient.ClientError {
            switch clientError {
            case .codexBinaryNotFound, .processUnavailable:
                return .blocked(.codexUnavailable, detail: nil)
            case .rpcError(let code, let message):
                if code == -32601 {
                    return .blocked(.unsupportedCodex, detail: nil)
                }
                if message.localizedCaseInsensitiveContains("authentication") {
                    return .blocked(.signedOut, detail: nil)
                }
                return .blocked(.requestFailed, detail: message)
            case .requestTimedOut,
                 .requestCancelledBeforeDispatch,
                 .resetCreditSessionUnavailableBeforeDispatch,
                 .resetCreditDispatchNotAuthorized,
                 .resetCreditDispatchAuthorizationUnavailable,
                 .responseMissingResult,
                 .invalidRequest:
                return .blocked(.requestFailed, detail: clientError.localizedDescription)
            }
        }
        return .blocked(.requestFailed, detail: error.localizedDescription)
    }

    private func isUnsupportedResetCreditRPC(_ error: Error) -> Bool {
        guard case .rpcError(let code, _) = error as? CodexAppServerClient.ClientError else {
            return false
        }
        return code == -32601
    }

    private func isAuthenticationError(_ error: Error) -> Bool {
        guard case .rpcError(_, let message)
            = error as? CodexAppServerClient.ClientError else {
            return false
        }
        return message.localizedCaseInsensitiveContains("authentication")
    }

    private func isResetCreditPreDispatchFailure(_ error: Error) -> Bool {
        guard let clientError = error as? CodexAppServerClient.ClientError else {
            return false
        }
        switch clientError {
        case .requestCancelledBeforeDispatch,
             .resetCreditSessionUnavailableBeforeDispatch,
             .resetCreditDispatchNotAuthorized,
             .resetCreditDispatchAuthorizationUnavailable:
            return true
        default:
            return false
        }
    }

    private func startLifecycleObservation() {
        guard lifecycleObservers.isEmpty else {
            return
        }
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        let wakeToken = workspaceCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refreshNow()
            }
        }
        lifecycleObservers.append((workspaceCenter, wakeToken))

        let center = NotificationCenter.default
        let activeToken = center.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refreshNow()
            }
        }
        lifecycleObservers.append((center, activeToken))

        let clockToken = center.addObserver(
            forName: Notification.Name.NSSystemClockDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleSystemClockChange()
            }
        }
        lifecycleObservers.append((center, clockToken))
    }

    private func stopLifecycleObservation() {
        for (center, token) in lifecycleObservers {
            center.removeObserver(token)
        }
        lifecycleObservers.removeAll()
    }

    private static var resetCreditProtectionSupportDirectory: URL {
        let base = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory
        return base
            .appendingPathComponent(AppConstants.bundleIdentifier, isDirectory: true)
    }

    private static var resetCreditProtectionLockURL: URL {
        resetCreditProtectionSupportDirectory
            .appendingPathComponent("reset-credit-protection.lock")
    }

    private static var resetCreditProtectionDispatchLockURL: URL {
        resetCreditProtectionSupportDirectory
            .appendingPathComponent("reset-credit-protection-dispatch.lock")
    }

    private static var resetCreditProtectionAuthorizationURL: URL {
        resetCreditProtectionSupportDirectory
            .appendingPathComponent("reset-credit-protection-authorization-v1.json")
    }

    private static var resetCreditProtectionJournalURL: URL {
        resetCreditProtectionSupportDirectory
            .appendingPathComponent("reset-credit-protection-journal-v1.json")
    }

    private func startAutomaticUpdateChecks() {
        guard automaticUpdatesEnabled else {
            return
        }
        automaticUpdateTask?.cancel()
        automaticUpdateTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: AppConstants.initialUpdateCheckDelaySeconds * 1_000_000_000)
            await self?.checkForUpdates(automatic: true)
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: AppConstants.updateCheckIntervalSeconds * 1_000_000_000)
                await self?.checkForUpdates(automatic: true)
            }
        }
    }

    private func startResetCreditAutoRefresh() {
        guard resetCreditAutoRefreshEnabled else {
            return
        }
        resetCreditAutoRefreshTask?.cancel()
        resetCreditAutoRefreshTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: AppConstants.resetCreditAutoRefreshInitialDelaySeconds * 1_000_000_000)
            self?.refreshResetCreditsIfNeeded(automatic: true)
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: AppConstants.resetCreditAutoRefreshIntervalSeconds * 1_000_000_000)
                self?.refreshResetCreditsIfNeeded(automatic: true)
            }
        }
    }

    private func resetCreditSnapshotIsStale(now: Date = Date()) -> Bool {
        guard let resetCreditSnapshot else {
            return true
        }
        return now.timeIntervalSince(resetCreditSnapshot.checkedAt) >= AppConstants.resetCreditCacheStaleSeconds
    }

    private func resetCreditFailure(from error: Error, automatic: Bool) -> ResetCreditFailure {
        if let clientError = error as? ResetCreditClient.ClientError {
            switch clientError {
            case .authFileNotFound:
                return ResetCreditFailure(
                    kind: .authFileMissing,
                    detail: clientError.localizedDescription,
                    occurredAt: Date(),
                    automatic: automatic
                )
            case .invalidAuthFile:
                return ResetCreditFailure(
                    kind: .invalidAuthFile,
                    detail: clientError.localizedDescription,
                    occurredAt: Date(),
                    automatic: automatic
                )
            case .accessTokenNotFound:
                return ResetCreditFailure(
                    kind: .accessTokenMissing,
                    detail: clientError.localizedDescription,
                    occurredAt: Date(),
                    automatic: automatic
                )
            case .unauthorized(let status):
                return ResetCreditFailure(
                    kind: .unauthorized(status),
                    detail: clientError.localizedDescription,
                    occurredAt: Date(),
                    automatic: automatic
                )
            case .httpStatus(let status):
                return ResetCreditFailure(
                    kind: .service(status),
                    detail: clientError.localizedDescription,
                    occurredAt: Date(),
                    automatic: automatic
                )
            case .emptyResponse:
                return ResetCreditFailure(
                    kind: .responseChanged,
                    detail: clientError.localizedDescription,
                    occurredAt: Date(),
                    automatic: automatic
                )
            }
        }
        if let urlError = error as? URLError {
            return ResetCreditFailure(
                kind: .network,
                detail: urlError.localizedDescription,
                occurredAt: Date(),
                automatic: automatic
            )
        }
        if error is DecodingError {
            return ResetCreditFailure(
                kind: .responseChanged,
                detail: error.localizedDescription,
                occurredAt: Date(),
                automatic: automatic
            )
        }
        return ResetCreditFailure(
            kind: .unknown,
            detail: error.localizedDescription,
            occurredAt: Date(),
            automatic: automatic
        )
    }

    private func checkForUpdates(automatic: Bool) async {
        guard !automatic || automaticUpdatesEnabled else {
            return
        }
        guard !updatePhase.isActive else {
            return
        }
        updatePhase = .checking
        do {
            guard let update = try await appUpdater.latestUpdate(currentVersion: AppConstants.appVersion) else {
                latestUpdate = nil
                updatePhase = .upToDate(Date())
                return
            }
            if automatic, shouldPauseAutomaticRetry(for: update.version) {
                latestUpdate = update
                updatePhase = .failed("automatic retry paused for \(update.version) after a recent install failure")
                return
            }
            latestUpdate = update
            updatePhase = .available(update.version)
            updatePhase = .downloading(update.version)
            try await appUpdater.install(update)
            updatePhase = .installing(update.version)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                NSApplication.shared.terminate(nil)
            }
        } catch is CancellationError {
            updatePhase = .idle
        } catch {
            updatePhase = .failed(error.localizedDescription)
        }
    }

    private func shouldPauseAutomaticRetry(for version: String) -> Bool {
        guard defaults.string(forKey: AppConstants.installerFailureVersionDefaultsKey) == version else {
            return false
        }
        let failedAt = defaults.double(forKey: AppConstants.installerFailureAtDefaultsKey)
        guard failedAt > 0 else {
            return false
        }
        let elapsed = Date().timeIntervalSince1970 - failedAt
        guard elapsed < AppConstants.failedInstallerRetryDelaySeconds else {
            defaults.removeObject(forKey: AppConstants.installerFailureVersionDefaultsKey)
            defaults.removeObject(forKey: AppConstants.installerFailureAtDefaultsKey)
            return false
        }
        return true
    }

    private static func loadSelectedStatusMetrics(defaults: UserDefaults) -> [StatusMetric] {
        guard let rawValues = defaults.stringArray(forKey: DefaultsKey.selectedStatusMetrics) else {
            return defaultStatusMetrics
        }
        let metrics = rawValues.compactMap(StatusMetric.init(rawValue:))
        if metrics.isEmpty {
            return defaultStatusMetrics
        }
        return StatusMetric.allCases.filter { metrics.contains($0) }
    }

    private static func loadNotificationMemory(defaults: UserDefaults) -> NotificationMemory {
        guard let data = defaults.data(forKey: DefaultsKey.notificationMemory),
              let memory = try? JSONDecoder().decode(PersistedNotificationMemory.self, from: data) else {
            return NotificationMemory()
        }
        return memory.value
    }

    private static func loadResetCreditSnapshot(defaults: UserDefaults) -> ResetCreditSnapshot? {
        guard let data = defaults.data(forKey: DefaultsKey.resetCreditSnapshot) else {
            return nil
        }
        return try? JSONDecoder().decode(ResetCreditSnapshot.self, from: data)
    }

    private func saveResetCreditSnapshot(_ snapshot: ResetCreditSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else {
            return
        }
        defaults.set(data, forKey: DefaultsKey.resetCreditSnapshot)
    }

    private func saveResetCreditProtectionJournal(
        _ journal: ResetCreditProtectionAttemptJournal
    ) -> Bool {
        do {
            var ledger = resetCreditProtectionLedger
            ledger.activeAttempt = journal
            try resetCreditProtectionLedgerStore.save(ledger)
            resetCreditProtectionLedger = ledger
            resetCreditProtectionJournalCorrupt = false
            return true
        } catch {
            failClosedForResetCreditProtectionJournal()
            return false
        }
    }

    private func clearResetCreditProtectionJournal() -> Bool {
        do {
            var ledger = resetCreditProtectionLedger
            ledger.activeAttempt = nil
            try resetCreditProtectionLedgerStore.save(ledger)
            resetCreditProtectionLedger = ledger
            resetCreditProtectionJournalCorrupt = false
            return true
        } catch {
            failClosedForResetCreditProtectionJournal()
            return false
        }
    }

    private func archiveResetCreditProtectionJournal(
        _ journal: ResetCreditProtectionAttemptJournal,
        disposition: ResetCreditProtectionTombstone.Disposition
    ) -> Bool {
        guard resetCreditProtectionLedger.activeAttempt == journal else {
            failClosedForResetCreditProtectionJournal()
            return false
        }
        var ledger = resetCreditProtectionLedger
        ledger.activeAttempt = nil
        ledger.tombstones.append(
            ResetCreditProtectionTombstone(
                journal: journal,
                disposition: disposition
            )
        )
        do {
            try resetCreditProtectionLedgerStore.save(ledger)
            resetCreditProtectionLedger = ledger
            resetCreditProtectionJournalCorrupt = false
            return true
        } catch {
            failClosedForResetCreditProtectionJournal()
            return false
        }
    }

    private func reloadResetCreditProtectionJournal(
    ) -> ResetCreditProtectionJournalLoadResult {
        let result = resetCreditProtectionLedgerStore.load()
        switch result {
        case .absent:
            resetCreditProtectionLedger = ResetCreditProtectionLedger()
            resetCreditProtectionJournalCorrupt = false
            return .absent
        case .loaded(let ledger):
            resetCreditProtectionLedger = ledger
            resetCreditProtectionJournalCorrupt = false
            if let journal = ledger.activeAttempt {
                return .loaded(journal)
            }
            return .absent
        case .corrupt:
            resetCreditProtectionLedger = ResetCreditProtectionLedger()
            resetCreditProtectionJournalCorrupt = true
            return .corrupt
        }
    }

    private func failClosedForResetCreditProtectionJournal() {
        resetCreditProtectionEnabled = false
        resetCreditProtectionConsent = nil
        resetCreditProtectionJournalCorrupt = true
        resetCreditProtectionStatus = .blocked(.journalUnavailable, detail: nil)
        do {
            try resetCreditProtectionAuthorizationStore.clear { [defaults] in
                defaults.set(
                    false,
                    forKey: DefaultsKey.resetCreditProtectionEnabled
                )
            }
        } catch {
            defaults.set(false, forKey: DefaultsKey.resetCreditProtectionEnabled)
            deliverResetCreditProtectionFailure(
                identifier: "reset-credit-protection-authorization-unavailable",
                body: appLanguage.text(
                    "本地授权记录无法写入撤销标记。请退出其他 Codex Radar 进程并检查磁盘权限后重试。",
                    "The local authorization record could not be marked as revoked. Quit other Codex Radar processes, check disk permissions, and try again."
                )
            )
        }
    }

    private func saveNotificationMemory() {
        let persisted = PersistedNotificationMemory(value: notificationMemory)
        guard let data = try? JSONEncoder().encode(persisted) else {
            return
        }
        defaults.set(data, forKey: DefaultsKey.notificationMemory)
    }
}

private struct PersistedNotificationMemory: Codable {
    let initialized: Bool
    let lastSpeedOpenKey: String?
    let lastResetCloseKey: String?
    let lastPredictionKey: String?
    let lastIQKey: String?
    let lastWeeklyWarningKey: String?
    let lastWeeklyCriticalKey: String?
    let lastWeeklyRestoreKey: String?
    let lastWeeklyWarningAt: Date?
    let lastWeeklyCriticalAt: Date?
    let pendingWeeklyRestoreKey: String?

    init(value: NotificationMemory) {
        self.initialized = value.initialized
        self.lastSpeedOpenKey = value.lastSpeedOpenKey
        self.lastResetCloseKey = value.lastResetCloseKey
        self.lastPredictionKey = value.lastPredictionKey
        self.lastIQKey = value.lastIQKey
        self.lastWeeklyWarningKey = value.lastWeeklyWarningKey
        self.lastWeeklyCriticalKey = value.lastWeeklyCriticalKey
        self.lastWeeklyRestoreKey = value.lastWeeklyRestoreKey
        self.lastWeeklyWarningAt = value.lastWeeklyWarningAt
        self.lastWeeklyCriticalAt = value.lastWeeklyCriticalAt
        self.pendingWeeklyRestoreKey = value.pendingWeeklyRestoreKey
    }

    var value: NotificationMemory {
        NotificationMemory(
            initialized: initialized,
            lastSpeedOpenKey: lastSpeedOpenKey,
            lastResetCloseKey: lastResetCloseKey,
            lastPredictionKey: lastPredictionKey,
            lastIQKey: lastIQKey,
            lastWeeklyWarningKey: lastWeeklyWarningKey,
            lastWeeklyCriticalKey: lastWeeklyCriticalKey,
            lastWeeklyRestoreKey: lastWeeklyRestoreKey,
            lastWeeklyWarningAt: lastWeeklyWarningAt,
            lastWeeklyCriticalAt: lastWeeklyCriticalAt,
            pendingWeeklyRestoreKey: pendingWeeklyRestoreKey
        )
    }
}
