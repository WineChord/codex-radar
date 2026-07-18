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

    private static let documentationUpdatedAt = Date(timeIntervalSince1970: 1_784_270_280)

    private static func documentationRateLimits() -> RateLimitDashboard? {
        let now = Int(Date().timeIntervalSince1970)
        let weeklyReset = now + 565_200
        guard let response: RateLimitResponse = decodeDocumentationJSON("""
        {
          "rateLimits": {
            "limitId": "codex",
            "limitName": null,
            "primary": { "usedPercent": 4, "windowDurationMins": 10080, "resetsAt": \(weeklyReset) },
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
          "updated_at": "2026-07-17T14:35:21+08:00",
          "data_source": {
            "type": "distributed_community_runs",
            "url": "https://deng.codexradar.com",
            "checked_at": "2026-07-17T14:35:21+08:00",
            "valid_cells": 984
          },
          "latest": {
            "date": "2026-07-17T14:35:21+08:00",
            "tasks": 109,
            "passed": 76,
            "iq_score": 105.1,
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
            "cost_usd_basis": "total_selected_tasks",
            "model": "gpt-5.6-sol",
            "reasoning_effort": "max"
          },
          "comparisons": {
            "gpt_56_sol_xhigh": { "label": "GPT-5.6 Sol xhigh", "model": "gpt-5.6-sol", "reasoning_effort": "xhigh", "latest": { "tasks": 103, "passed": 64, "score": 93.6, "status": "green", "average_task_seconds": 1620, "average_task_time_human": "27分钟", "average_cost_usd": 6.817724, "cache_hit_rate": 97.5, "model": "gpt-5.6-sol", "reasoning_effort": "xhigh" } },
            "gpt_56_sol_high": { "label": "GPT-5.6 Sol high", "model": "gpt-5.6-sol", "reasoning_effort": "high", "latest": { "tasks": 104, "passed": 62, "score": 89.8, "status": "yellow", "average_task_seconds": 1440, "average_task_time_human": "24分钟", "average_cost_usd": 5.203014, "cache_hit_rate": 97.3, "model": "gpt-5.6-sol", "reasoning_effort": "high" } },
            "gpt_56_sol_medium": { "label": "GPT-5.6 Sol medium", "model": "gpt-5.6-sol", "reasoning_effort": "medium", "latest": { "tasks": 107, "passed": 60, "score": 84.5, "status": "yellow", "average_task_seconds": 960, "average_task_time_human": "16分钟", "average_cost_usd": 3.262042, "cache_hit_rate": 96.7, "model": "gpt-5.6-sol", "reasoning_effort": "medium" } },
            "gpt_56_sol_low": { "label": "GPT-5.6 Sol low", "model": "gpt-5.6-sol", "reasoning_effort": "low", "latest": { "tasks": 101, "passed": 49, "score": 73.1, "status": "yellow", "average_task_seconds": 660, "average_task_time_human": "11分钟", "average_cost_usd": 1.908764, "cache_hit_rate": 95.6, "model": "gpt-5.6-sol", "reasoning_effort": "low" } },
            "gpt_56_terra_max": { "label": "GPT-5.6 Terra max", "model": "gpt-5.6-terra", "reasoning_effort": "max", "latest": { "tasks": 85, "passed": 54, "score": 95.7, "status": "green", "average_task_seconds": 1860, "average_task_time_human": "31分钟", "average_cost_usd": 4.842206, "cache_hit_rate": 97.7, "model": "gpt-5.6-terra", "reasoning_effort": "max" } },
            "gpt_56_terra_high": { "label": "GPT-5.6 Terra high", "model": "gpt-5.6-terra", "reasoning_effort": "high", "latest": { "tasks": 89, "passed": 46, "score": 77.9, "status": "yellow", "average_task_seconds": 840, "average_task_time_human": "14分钟", "average_cost_usd": 1.320583, "cache_hit_rate": 96.2, "model": "gpt-5.6-terra", "reasoning_effort": "high" } },
            "gpt_56_luna_max": { "label": "GPT-5.6 Luna max", "model": "gpt-5.6-luna", "reasoning_effort": "max", "latest": { "tasks": 94, "passed": 58, "score": 93.0, "status": "green", "average_task_seconds": 1980, "average_task_time_human": "33分钟", "average_cost_usd": 2.328072, "cache_hit_rate": 97.7, "model": "gpt-5.6-luna", "reasoning_effort": "max" } },
            "gpt_56_luna_high": { "label": "GPT-5.6 Luna high", "model": "gpt-5.6-luna", "reasoning_effort": "high", "latest": { "tasks": 82, "passed": 34, "score": 62.5, "status": "yellow", "average_task_seconds": 1080, "average_task_time_human": "18分钟", "average_cost_usd": 1.123607, "cache_hit_rate": 97.2, "model": "gpt-5.6-luna", "reasoning_effort": "high" } },
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
