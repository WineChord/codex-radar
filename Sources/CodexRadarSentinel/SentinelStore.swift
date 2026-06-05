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
        static let selectedStatusMetrics = "selectedStatusMetrics"
        static let predictionNotificationsEnabled = "predictionNotificationsEnabled"
        static let iqNotificationsEnabled = "iqNotificationsEnabled"
        static let notificationSoundEnabled = "notificationSoundEnabled"
        static let automaticUpdatesEnabled = "automaticUpdatesEnabled"
        static let launchAtLoginEnabled = "launchAtLoginEnabled"
        static let notificationMemory = "notificationMemory"
        static let dismissedSpeedAlertKey = "dismissedSpeedAlertKey"
    }

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
        self.selectedStatusMetrics = Self.loadSelectedStatusMetrics(defaults: defaults)
        let rawPreview = ProcessInfo.processInfo.environment[AppConstants.debugPreviewEnvironmentKey]
        self.debugPreview = rawPreview.flatMap(DashboardPreview.init(rawValue:)) ?? .live
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
        selectedStatusMetrics = StatusMetric.allCases
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
        documentationState.lastUpdatedAt = Self.documentationUpdatedAt
        state = documentationState
    }

    private static let documentationUpdatedAt = Date(timeIntervalSince1970: 1_780_573_080)

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

    private static func documentationCurrent(language: AppLanguage) -> RadarCurrent? {
        let title = language.text(
            "Codex 可靠性事故补偿重置",
            "Codex reliability incident compensation reset"
        )
        let window = language.text("无窗", "none")
        let scope = language.text("所有付费计划", "all paid plans")
        let summary = language.text(
            "Tibo 表示过去 24 小时内有三次影响 Codex 可靠性的小事故，并已为所有付费计划重置 Codex 使用限制。",
            "Tibo reported three minor Codex reliability incidents in the past 24 hours, and Codex usage limits were reset for all paid plans."
        )
        return decodeDocumentationJSON("""
        {
          "checked_at": "2026-06-04T19:38:00+08:00",
          "status": "none",
          "window_open": false,
          "recommended_action": "wait",
          "last_window": {
            "id": "documentation-reset-window",
            "title": "\(title)",
            "status": "closed",
            "opened_at": "2026-06-04T18:00:00+08:00",
            "closed_at": "2026-06-04T19:38:00+08:00",
            "window_minutes": 98,
            "window_human": "\(window)",
            "scope": "\(scope)",
            "summary": "\(summary)"
          },
          "prediction": {
            "level": "low",
            "probability_24h": 0.11,
            "probability_48h": 0.20,
            "should_notify": false
          }
        }
        """)
    }

    private static func documentationPrediction(language: AppLanguage) -> RadarPrediction? {
        let summary = language.text(
            "当前无官方开启窗口。Tibo 已在 2026-06-04 08:25:58 +0800 为过去 24 小时三次 Codex 可靠性小事故完成一次全付费计划限额重置。",
            "No official window is open. Tibo completed one all-paid-plan Codex limit reset at 2026-06-04 08:25:58 +0800 after three minor Codex reliability incidents in the prior 24 hours."
        )
        return decodeDocumentationJSON("""
        {
          "level": "low",
          "probability_24h": 0.11,
          "probability_48h": 0.20,
          "should_notify": false,
          "reasoning_summary": "\(summary)",
          "updated_at": "2026-06-04T19:38:00+08:00"
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
            language: appLanguage
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
        async let predictionResult = fetchPredictionResult()
        async let modelIQResult = fetchModelIQResult()
        async let rateLimitResult = fetchRateLimitResult()

        let results = await (
            current: currentResult,
            prediction: predictionResult,
            modelIQ: modelIQResult,
            rateLimits: rateLimitResult
        )

        let previous = state
        var next = previous
        var errors: [String] = []

        apply(results.current, to: &next.current, errors: &errors)
        apply(results.prediction, to: &next.prediction, errors: &errors)
        apply(results.modelIQ, to: &next.modelIQ, errors: &errors)
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

    private func fetchPredictionResult() async -> Result<RadarPrediction, Error> {
        await capture {
            try await radarClient.fetchPrediction()
        }
    }

    private func fetchModelIQResult() async -> Result<ModelIQEnvelope, Error> {
        await capture {
            try await radarClient.fetchModelIQ()
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
            return StatusMetric.allCases
        }
        let metrics = rawValues.compactMap(StatusMetric.init(rawValue:))
        if metrics.isEmpty {
            return StatusMetric.allCases
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

    init(value: NotificationMemory) {
        self.initialized = value.initialized
        self.lastSpeedOpenKey = value.lastSpeedOpenKey
        self.lastResetCloseKey = value.lastResetCloseKey
        self.lastPredictionKey = value.lastPredictionKey
        self.lastIQKey = value.lastIQKey
        self.lastWeeklyWarningKey = value.lastWeeklyWarningKey
        self.lastWeeklyCriticalKey = value.lastWeeklyCriticalKey
        self.lastWeeklyRestoreKey = value.lastWeeklyRestoreKey
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
            lastWeeklyRestoreKey: lastWeeklyRestoreKey
        )
    }
}
