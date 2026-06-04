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
        static let launchAtLoginEnabled = "launchAtLoginEnabled"
        static let notificationMemory = "notificationMemory"
        static let dismissedSpeedAlertKey = "dismissedSpeedAlertKey"
    }

    private let defaults: UserDefaults
    private let radarClient: CodexRadarClient
    private let appServerClient: CodexAppServerClient
    private let notificationPolicy = NotificationPolicy()
    private var notificationMemory: NotificationMemory
    private var pollingTask: Task<Void, Never>?
    private var refreshTask: Task<Void, Never>?
    private var emphasizedSpeedAlertKey: String?
    private var speedAlertFirstSeenAt: Date?

    init(
        defaults: UserDefaults = .standard,
        radarClient: CodexRadarClient = CodexRadarClient(),
        appServerClient: CodexAppServerClient = CodexAppServerClient()
    ) {
        self.defaults = defaults
        self.radarClient = radarClient
        self.appServerClient = appServerClient
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

    func openCodexApp() {
        NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: "/Applications/Codex.app"), configuration: NSWorkspace.OpenConfiguration())
    }

    func quit() {
        NSApplication.shared.terminate(nil)
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
