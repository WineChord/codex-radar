import AppKit
import CodexRadarCore
import Foundation

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
    private let notificationPolicy = NotificationPolicy()
    private var notificationMemory: NotificationMemory
    private var pollingTask: Task<Void, Never>?
    private var refreshTask: Task<Void, Never>?
    private var updateTask: Task<Void, Never>?
    private var automaticUpdateTask: Task<Void, Never>?
    private var emphasizedSpeedAlertKey: String?
    private var speedAlertFirstSeenAt: Date?

    init(
        defaults: UserDefaults = .standard,
        radarClient: CodexRadarClient = CodexRadarClient(),
        appServerClient: CodexAppServerClient = CodexAppServerClient(),
        appUpdater: AppUpdater = AppUpdater()
    ) {
        self.defaults = defaults
        self.radarClient = radarClient
        self.appServerClient = appServerClient
        self.appUpdater = appUpdater
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
        self.quotaPacingOptionsExpanded = defaults.object(forKey: DefaultsKey.quotaPacingOptionsExpanded) as? Bool ?? false
        self.selectedStatusMetrics = Self.loadSelectedStatusMetrics(defaults: defaults)
        let rawPreview = ProcessInfo.processInfo.environment[AppConstants.debugPreviewEnvironmentKey]
        self.debugPreview = rawPreview.flatMap(DashboardPreview.init(rawValue:)) ?? .live
        self.debugPreviewSectionExpanded = defaults.object(forKey: DefaultsKey.debugPreviewSectionExpanded) as? Bool ?? false
        self.predictionNotificationsEnabled = defaults.object(forKey: DefaultsKey.predictionNotificationsEnabled) as? Bool ?? true
        self.iqNotificationsEnabled = defaults.object(forKey: DefaultsKey.iqNotificationsEnabled) as? Bool ?? true
        self.notificationSoundEnabled = defaults.object(forKey: DefaultsKey.notificationSoundEnabled) as? Bool ?? false
        self.automaticUpdatesEnabled = defaults.object(forKey: DefaultsKey.automaticUpdatesEnabled) as? Bool ?? true
        self.launchAtLoginEnabled = defaults.object(forKey: DefaultsKey.launchAtLoginEnabled) as? Bool ?? LaunchAtLoginController.isEnabled
        self.dismissedSpeedAlertKey = defaults.string(forKey: DefaultsKey.dismissedSpeedAlertKey)
        self.notificationMemory = Self.loadNotificationMemory(defaults: defaults)
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
            quotaPacingStrategy: quotaPacingStrategy
        )
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
        quotaPacingOptionsExpanded = false
        statusBarAdvancedOptionsExpanded = false
        debugPreviewSectionExpanded = false
        selectedStatusMetrics = Self.defaultStatusMetrics
        debugPreview = .live
        predictionNotificationsEnabled = true
        iqNotificationsEnabled = true
        notificationSoundEnabled = false
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

    private static func documentationModelIQ() -> ModelIQEnvelope? {
        decodeDocumentationJSON("""
        {
          "updated_at": "2026-06-15T08:25:00+08:00",
          "latest": {
            "date": "2026-06-15",
            "tasks": 12,
            "passed": 9,
            "iq_score": 112.5,
            "status": "green",
            "wall_seconds": 2944,
            "wall_time_human": "49分钟",
            "input_tokens": 38991839,
            "cached_input_tokens": 37026944,
            "output_tokens": 386860,
            "cost_usd": 39.943747,
            "model": "gpt-5.5",
            "reasoning_effort": "xhigh"
          }
        }
        """)
    }

    private static func documentationModelRatings() -> ModelRatingsEnvelope? {
        decodeDocumentationJSON("""
        {
          "ok": true,
          "day": "2026-06-15",
          "timezone": "Asia/Shanghai",
          "refresh_seconds": 60,
          "updated_at": "2026-06-15T02:02:03.291Z",
          "models": [
            {
              "id": "gpt-5.5-xhigh",
              "label": "GPT-5.5 xhigh",
              "group": "GPT-5.5",
              "average": 9.4,
              "count": 10
            }
          ],
          "source": "cache"
        }
        """)
    }

    private static func documentationCurrent(language: AppLanguage) -> RadarCurrent? {
        let title = language.text(
            "CodexRadar 已转向模型质量雷达",
            "CodexRadar has moved to model quality"
        )
        let window = language.text("无窗", "none")
        let scope = language.text("模型质量雷达", "model quality radar")
        let summary = language.text(
            "CodexRadar 当前聚焦 Model IQ；旧 reset 预测、速蹬窗口提醒和历史窗口已下架。",
            "CodexRadar currently focuses on Model IQ; legacy reset prediction, speed-window alerts, and historical windows are retired."
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
          "model_iq": {
            "updated_at": "2026-06-15T07:00:00+08:00",
            "latest": {
              "date": "2026-06-15",
              "model": "GPT-5.5",
              "reasoning_effort": "xhigh",
              "tasks": 12,
              "valid_tasks": 12,
              "passed": 9,
              "failed": 3,
              "pass_rate": 0.75,
              "iq_score": 112.5,
              "score": 112.5,
              "status": "green",
              "wall_seconds": 2944,
              "wall_time_human": "49分钟",
              "input_tokens": 38991839,
              "cached_input_tokens": 37026944,
              "output_tokens": 386860,
              "cost_usd": 39.943747
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
            lastWeeklyCriticalAt: lastWeeklyCriticalAt
        )
    }
}
