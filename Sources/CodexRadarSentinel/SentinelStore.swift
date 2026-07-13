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

    @Published var debugPreview: DashboardPreview = .live {
        didSet {
            if debugPreview != .live {
                resetSpeedAlertDismissal()
            }
            updateTitleForStatusItem()
        }
    }

    @Published var debugPreviewSectionExpanded: Bool {
        didSet {
            defaults.set(debugPreviewSectionExpanded, forKey: DefaultsKey.debugPreviewSectionExpanded)
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
        static let resetCreditSnapshot = "resetCreditSnapshot"
        static let resetCreditAutoRefreshEnabled = "resetCreditAutoRefreshEnabled"
    }

    private static let defaultStatusMetrics: [StatusMetric] = [
        .weeklyQuota,
        .codexIQ,
        .signal,
    ]

    private let defaults: UserDefaults
    private let radarClient: CodexRadarClient
    private let appServerClient: CodexAppServerClient
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
    private var suppressResetCreditAutoRefreshSideEffects = false
    private var emphasizedSpeedAlertKey: String?
    private var speedAlertFirstSeenAt: Date?

    init(
        defaults: UserDefaults = .standard,
        radarClient: CodexRadarClient = CodexRadarClient(),
        appServerClient: CodexAppServerClient = CodexAppServerClient(),
        appUpdater: AppUpdater = AppUpdater(),
        resetCreditClient: ResetCreditClient = ResetCreditClient()
    ) {
        self.defaults = defaults
        self.radarClient = radarClient
        self.appServerClient = appServerClient
        self.appUpdater = appUpdater
        self.resetCreditClient = resetCreditClient
        let rawLanguage = defaults.string(forKey: DefaultsKey.appLanguage)
        self.appLanguage = rawLanguage.flatMap(AppLanguage.init(rawValue:)) ?? .zhHans
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
        let rawPreview = ProcessInfo.processInfo.environment[AppConstants.debugPreviewEnvironmentKey]
        self.debugPreview = rawPreview.flatMap(DashboardPreview.init(rawValue:)) ?? .live
        self.debugPreviewSectionExpanded = defaults.object(forKey: DefaultsKey.debugPreviewSectionExpanded) as? Bool ?? false
        self.predictionNotificationsEnabled = defaults.object(forKey: DefaultsKey.predictionNotificationsEnabled) as? Bool ?? true
        self.iqNotificationsEnabled = defaults.object(forKey: DefaultsKey.iqNotificationsEnabled) as? Bool ?? true
        self.notificationSoundEnabled = defaults.object(forKey: DefaultsKey.notificationSoundEnabled) as? Bool ?? false
        self.automaticUpdatesEnabled = defaults.object(forKey: DefaultsKey.automaticUpdatesEnabled) as? Bool ?? true
        self.resetCreditAutoRefreshEnabled = defaults.object(forKey: DefaultsKey.resetCreditAutoRefreshEnabled) as? Bool ?? true
        self.launchAtLoginEnabled = defaults.object(forKey: DefaultsKey.launchAtLoginEnabled) as? Bool ?? LaunchAtLoginController.isEnabled
        self.dismissedSpeedAlertKey = defaults.string(forKey: DefaultsKey.dismissedSpeedAlertKey)
        self.notificationMemory = Self.loadNotificationMemory(defaults: defaults)
        self.resetCreditSnapshot = Self.loadResetCreditSnapshot(defaults: defaults)
        super.init()
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

    func resetStatusBarAdvancedOptions() {
        let defaults = StatusBarDisplayOptions.defaultOptions
        statusBarPreciseIQEnabled = defaults.preciseIQ
        statusBarIQDisplayMode = defaults.iqDisplayMode
        statusBarPercentDisplayMode = defaults.percentDisplayMode
        statusBarSeparator = defaults.separator
        statusBarHorizontalPadding = defaults.horizontalPadding
        statusBarFontScale = defaults.fontScale
    }

    func start() {
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
        Task {
            await appServerClient.shutdown()
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

    func configureForDocumentation(language: AppLanguage) {
        appLanguage = language
        menuTextSize = .large
        resetStatusBarAdvancedOptions()
        quotaPacingStrategy = .timeProportional
        chinaHolidayCalendarEnabled = true
        quotaPacingOptionsExpanded = false
        statusBarAdvancedOptionsExpanded = false
        debugPreviewSectionExpanded = false
        selectedStatusMetrics = Self.defaultStatusMetrics
        debugPreview = .live
        predictionNotificationsEnabled = true
        iqNotificationsEnabled = true
        notificationSoundEnabled = false
        suppressResetCreditAutoRefreshSideEffects = true
        resetCreditAutoRefreshEnabled = true
        suppressResetCreditAutoRefreshSideEffects = false
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
        documentationState.lastUpdatedAt = Self.documentationUpdatedAt
        state = documentationState
        resetCreditSnapshot = Self.documentationResetCreditSnapshot()
        resetCreditPhase = .idle
    }

    private static let documentationUpdatedAt = Date(timeIntervalSince1970: 1_781_478_000)

    private static func documentationRateLimits() -> RateLimitDashboard? {
        let now = Int(Date().timeIntervalSince1970)
        let shortReset = now + 16_740
        let weeklyReset = now + 565_200
        guard let response: RateLimitResponse = decodeDocumentationJSON("""
        {
          "rateLimits": {
            "limitId": "codex",
            "limitName": null,
            "primary": { "usedPercent": 1, "windowDurationMins": 300, "resetsAt": \(shortReset) },
            "secondary": { "usedPercent": 4, "windowDurationMins": 10080, "resetsAt": \(weeklyReset) },
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

    private static func documentationResetCreditSnapshot() -> ResetCreditSnapshot {
        let checkedAt = Date(timeIntervalSince1970: 1_783_130_400)
        let credits = [
            ResetCredit(
                idSuffix: "578aba",
                title: "Full reset (Weekly + 5 hr)",
                status: "available",
                resetType: "codex_rate_limits",
                grantedAt: Date(timeIntervalSince1970: 1_781_229_309),
                expiresAt: Date(timeIntervalSince1970: 1_783_821_309)
            ),
            ResetCredit(
                idSuffix: "91f04e",
                title: "Full reset (Weekly + 5 hr)",
                status: "available",
                resetType: "codex_rate_limits",
                grantedAt: Date(timeIntervalSince1970: 1_781_416_800),
                expiresAt: Date(timeIntervalSince1970: 1_784_008_800)
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
          "updated_at": "2026-07-04T08:28:00+08:00",
          "latest": {
            "date": "2026-07-04-am",
            "tasks": 10,
            "passed": 7,
            "iq_score": 105,
            "status": "green",
            "wall_seconds": 1740,
            "wall_time_human": "29分钟",
            "input_tokens": 34478832,
            "cached_input_tokens": 32158592,
            "output_tokens": 325178,
            "cost_usd": 37.435836,
            "model": "gpt-5.5",
            "reasoning_effort": "xhigh"
          },
          "comparisons": {
            "gpt_55_high": {
              "label": "GPT-5.5 high",
              "model": "gpt-5.5",
              "reasoning_effort": "high",
              "latest": {
                "date": "2026-07-04-am",
                "tasks": 10,
                "passed": 7,
                "iq_score": 105,
                "status": "green",
                "wall_seconds": 1920,
                "wall_time_human": "32分钟",
                "input_tokens": 22100000,
                "cached_input_tokens": 20600000,
                "output_tokens": 240000,
                "cost_usd": 23.472451,
                "model": "gpt-5.5",
                "reasoning_effort": "high"
              }
            },
            "gpt_55_medium": {
              "label": "GPT-5.5 medium",
              "model": "gpt-5.5",
              "reasoning_effort": "medium",
              "latest": {
                "date": "2026-07-04-am",
                "tasks": 10,
                "passed": 4,
                "iq_score": 60,
                "status": "red",
                "wall_seconds": 1680,
                "wall_time_human": "28分钟",
                "input_tokens": 18700000,
                "cached_input_tokens": 17600000,
                "output_tokens": 210000,
                "cost_usd": 18.026109,
                "model": "gpt-5.5",
                "reasoning_effort": "medium"
              }
            },
            "gpt_55_low": {
              "label": "GPT-5.5 low",
              "model": "gpt-5.5",
              "reasoning_effort": "low",
              "latest": {
                "date": "2026-07-04-am",
                "tasks": 10,
                "passed": 6,
                "iq_score": 90,
                "status": "yellow",
                "wall_seconds": 1800,
                "wall_time_human": "30分钟",
                "input_tokens": 15100000,
                "cached_input_tokens": 13900000,
                "output_tokens": 168000,
                "cost_usd": 15.211229,
                "model": "gpt-5.5",
                "reasoning_effort": "low"
              }
            },
            "gpt_54_xhigh": {
              "label": "GPT-5.4 xhigh",
              "model": "gpt-5.4",
              "reasoning_effort": "xhigh",
              "latest": {
                "date": "2026-07-04-am",
                "tasks": 10,
                "passed": 6,
                "iq_score": 90,
                "status": "yellow",
                "wall_seconds": 1620,
                "wall_time_human": "27分钟",
                "input_tokens": 24100000,
                "cached_input_tokens": 23100000,
                "output_tokens": 255000,
                "cost_usd": 20.198679,
                "model": "gpt-5.4",
                "reasoning_effort": "xhigh"
              }
            },
            "gpt_54_high": {
              "label": "GPT-5.4 high",
              "model": "gpt-5.4",
              "reasoning_effort": "high",
              "latest": {
                "date": "2026-07-04-am",
                "tasks": 10,
                "passed": 4,
                "iq_score": 60,
                "status": "red",
                "wall_seconds": 1560,
                "wall_time_human": "26分钟",
                "input_tokens": 20500000,
                "cached_input_tokens": 19400000,
                "output_tokens": 188000,
                "cost_usd": 12.207529,
                "model": "gpt-5.4",
                "reasoning_effort": "high"
              }
            }
          },
          "quota_radar": {
            "date": "2026-07-04-am",
            "updated_at": "2026-07-04T08:28:21+08:00",
            "basis_date": "2026-07-04-am",
            "basis_window_label": "5h",
            "cost_usd": 126.551833,
            "total_tokens": 154872137,
            "rows": [
              { "tier": "20x Pro", "basis": "measured", "five_h": 301.31, "seven_d": 1807.86 },
              { "tier": "5x Pro", "basis": "model /4", "five_h": 75.33, "seven_d": 451.97 },
              { "tier": "Plus", "basis": "model /20", "five_h": 15.07, "seven_d": 90.39 }
            ],
            "trend": [
              { "date": "2026-07-03-pm", "seven_d_20x": 1498.92, "five_h_20x": 249.82 },
              { "date": "2026-07-04-am", "seven_d_20x": 1807.86, "five_h_20x": 301.31 }
            ]
          }
        }
        """)
    }

    private static func documentationModelRatings() -> ModelRatingsEnvelope? {
        decodeDocumentationJSON("""
        {
          "ok": true,
          "day": "2026-07-04",
          "timezone": "Asia/Shanghai",
          "refresh_seconds": 60,
          "updated_at": "2026-07-04T01:57:34.353Z",
          "models": [
            {
              "id": "gpt-5.5-xhigh",
              "label": "GPT-5.5 xhigh",
              "group": "GPT-5.5",
              "average": 6.4,
              "count": 109
            },
            {
              "id": "gpt-5.5-high",
              "label": "GPT-5.5 high",
              "group": "GPT-5.5",
              "average": 7.4,
              "count": 81
            },
            {
              "id": "gpt-5.5-medium",
              "label": "GPT-5.5 medium",
              "group": "GPT-5.5",
              "average": 7,
              "count": 29
            },
            {
              "id": "gpt-5.5-low",
              "label": "GPT-5.5 low",
              "group": "GPT-5.5",
              "average": 7.4,
              "count": 7
            },
            {
              "id": "gpt-5.4-xhigh",
              "label": "GPT-5.4 xhigh",
              "group": "GPT-5.4",
              "average": 6,
              "count": 12
            },
            {
              "id": "gpt-5.4-high",
              "label": "GPT-5.4 high",
              "group": "GPT-5.4",
              "average": 4.9,
              "count": 9
            }
          ],
          "source": "cache"
        }
        """)
    }

    private static func documentationCurrent(language: AppLanguage) -> RadarCurrent? {
        let title = language.text(
            "CodexRadar 重置雷达研判",
            "CodexRadar reset judgement"
        )
        let window = language.text("无窗", "none")
        let scope = language.text("重置雷达 / 额度雷达 / Model IQ", "reset radar / quota radar / Model IQ")
        let summary = language.text(
            "CodexRadar 当前公开 reset 研判、额度雷达与 Model IQ；旧速蹬窗口提醒仍按兼容路径处理。",
            "CodexRadar currently publishes reset judgement, quota radar, and Model IQ; legacy speed-window alerts remain supported through compatibility paths."
        )
        let resetUpdated = language.text("7月4日08:41研判", "Jul 4 08:41")
        let resetTitle = language.text("发卡路径占优", "Reset cards likely")
        let cardLabel = language.text("发重置卡", "Reset card")
        let cardLevel = language.text("高 · 基本已触发", "High · likely active")
        let cardSummary = language.text(
            "CodexRadar 记录到官方回复更像已经在发可保存的重置卡，而不是新的全量硬重置。",
            "CodexRadar records official wording that looks more like saved reset cards than a new global hard reset."
        )
        let hardResetLabel = language.text("硬重置", "Hard reset")
        let hardResetLevel = language.text("低到中低", "Low to medium-low")
        let hardResetSummary = language.text(
            "硬重置会直接改写所有人的当前额度窗口；当前证据更偏向发卡路径。",
            "A hard reset would rewrite everyone's active quota window; current evidence favors the card path."
        )
        let reasonOne = language.text(
            "官方信号强：Tibo 回复提到 reset 应在 little piggy bank 里，并且人人都有。",
            "Official signal is strong: Tibo says the reset should be in the little piggy bank and is for everyone."
        )
        let reasonTwo = language.text(
            "社区反证仍在：仍有人反馈按钮消失、未收到 banked reset 或额度窗口异常。",
            "Community counterexamples remain: some users still report missing buttons, no banked reset, or odd quota windows."
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
        let announcementLabel = language.text("公告", "Notice")
        let announcementMessage = language.text(
            "Polymarket GPT-5.6 具体发布日期概率：July 9 72%，July 10 8.1%，Not before Aug 5.1%。",
            "Polymarket GPT-5.6 release-date odds: July 9 72%, July 10 8.1%, Not before Aug 5.1%."
        )
        let announcementUpdated = language.text("数据更新时间 07-07 08:49", "Updated Jul 7 08:49")
        let fastTitle = language.text("Fast 雷达", "Fast Radar")
        let fastUpdated = language.text("7月12日16:32更新", "Jul 12 16:32")
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
          "checked_at": "2026-06-15T07:00:00+08:00",
          "status": "retired",
          "window_open": false,
          "recommended_action": "wait",
          "last_window": {
            "id": "documentation-homepage-fallback",
            "title": "\(title)",
            "status": "retired",
            "window_human": "\(window)",
            "scope": "\(scope)",
            "summary": "\(summary)"
          },
          "prediction": {
            "level": "low",
            "probability_24h": 0,
            "probability_48h": 0,
            "should_notify": false,
            "reasoning_summary": "\(summary)",
            "updated_at": "2026-06-15T07:00:00+08:00"
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
            "source_label": "Polymarket",
            "source_url": "https://polymarket.com/event/gpt-5pt6-released-onptptpt-20260623051439980"
          },
          "fast_radar": {
            "title": "\(fastTitle)",
            "updated_label": "\(fastUpdated)",
            "subtitle": "\(fastSubtitle)",
            "summary": [
              { "label": "\(language.text("体感加速", "E2E speedup"))", "value": "⚡️1.381×" },
              { "label": "\(language.text("首字延迟减少", "TTFT change"))", "value": "0.08s" },
              { "label": "\(language.text("Token 生成速度", "Token speed"))", "value": "⚡️1.504×" }
            ],
            "rows": [
              {
                "model": "Sol",
                "e2e": { "label": "E2E", "range": "47.26s → 33.79s", "value": "⚡️1.399×" },
                "ttft": { "label": "TTFT", "range": "9.98s → 9.08s", "value": "\(language.text("快 9.0%", "9.0% faster"))" },
                "tps": { "label": "TPS", "range": "55.75 → 84.23", "value": "⚡️1.511×" }
              },
              {
                "model": "Terra",
                "e2e": { "label": "E2E", "range": "44.61s → 34.10s", "value": "⚡️1.308×" },
                "ttft": { "label": "TTFT", "range": "7.17s → 9.10s", "value": "\(language.text("慢 26.9%", "26.9% slower"))" },
                "tps": { "label": "TPS", "range": "55.53 → 83.37", "value": "⚡️1.501×" }
              },
              {
                "model": "Luna",
                "e2e": { "label": "E2E", "range": "44.94s → 31.16s", "value": "⚡️1.442×" },
                "ttft": { "label": "TTFT", "range": "7.45s → 6.19s", "value": "\(language.text("快 17.0%", "17.0% faster"))" },
                "tps": { "label": "TPS", "range": "55.50 → 83.26", "value": "⚡️1.500×" }
              }
            ],
            "method": "\(fastMethod)"
          },
          "model_iq": {
            "updated_at": "2026-07-04T08:28:00+08:00",
            "latest": {
              "date": "2026-07-04-am",
              "model": "GPT-5.5",
              "reasoning_effort": "xhigh",
              "tasks": 10,
              "valid_tasks": 10,
              "passed": 7,
              "failed": 3,
              "pass_rate": 0.7,
              "iq_score": 105,
              "score": 105,
              "status": "green",
              "wall_seconds": 1740,
              "wall_time_human": "29分钟",
              "input_tokens": 34478832,
              "cached_input_tokens": 32158592,
              "output_tokens": 325178,
              "cost_usd": 37.435836
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
          "updated_at": "2026-06-15T07:00:00+08:00"
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
        apply(results.rateLimits, to: &next.rateLimits, errors: &errors)

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

    private func fetchRateLimitResult() async -> Result<RateLimitDashboard, Error> {
        await capture {
            let response = try await appServerClient.readRateLimits()
            return RateLimitDashboard(response: response)
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
