import AppKit
import CodexRadarCore
import Combine
import SwiftUI
import UserNotifications

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private enum MenuMetrics {
        static let urgentCornerRadius: CGFloat = 5
    }

    private enum ScreenshotEnvironment {
        static let language = "CODEX_RADAR_SCREENSHOT_LANGUAGE"
        static let metrics = "CODEX_RADAR_SCREENSHOT_METRICS"
        static let output = "CODEX_RADAR_STATUS_SCREENSHOT_OUTPUT"
        static let defaultsSuitePrefix = "com.codexradar.sentinel.screenshot"
        static let temporaryDirectoryPrefix = "codex-radar-status-screenshot"
    }

    private struct ScreenshotConfiguration {
        let language: AppLanguage
        let metrics: [StatusMetric]
        let outputURL: URL

        init(environment: [String: String]) {
            guard let previewRaw = environment[
                AppConstants.debugPreviewEnvironmentKey
            ], let preview = DashboardPreview(rawValue: previewRaw),
                  preview != .live else {
                preconditionFailure(
                    "Screenshot mode requires a non-live CODEX_RADAR_PREVIEW."
                )
            }
            guard let languageRaw = environment[ScreenshotEnvironment.language],
                  let language = AppLanguage(rawValue: languageRaw) else {
                preconditionFailure(
                    "Screenshot mode requires a valid \(ScreenshotEnvironment.language)."
                )
            }
            guard let metricsRaw = environment[ScreenshotEnvironment.metrics] else {
                preconditionFailure(
                    "Screenshot mode requires \(ScreenshotEnvironment.metrics)."
                )
            }
            let rawMetrics = metricsRaw.split(
                separator: ",",
                omittingEmptySubsequences: false
            ).map(String.init)
            let metrics = rawMetrics.compactMap(StatusMetric.init(rawValue:))
            guard !metrics.isEmpty,
                  metrics.count == rawMetrics.count,
                  Set(rawMetrics).count == rawMetrics.count else {
                preconditionFailure(
                    "\(ScreenshotEnvironment.metrics) must contain unique, valid metrics."
                )
            }
            guard let outputPath = environment[ScreenshotEnvironment.output],
                  outputPath.hasPrefix("/") else {
                preconditionFailure(
                    "Screenshot mode requires an absolute \(ScreenshotEnvironment.output)."
                )
            }
            self.language = language
            self.metrics = metrics
            self.outputURL = URL(fileURLWithPath: outputPath)
        }
    }

    private final class ScreenshotIsolation {
        let suiteName: String
        let defaults: UserDefaults
        let directory: URL

        init() {
            let identifier = UUID().uuidString
            suiteName = "\(ScreenshotEnvironment.defaultsSuitePrefix).\(identifier)"
            guard let defaults = UserDefaults(suiteName: suiteName) else {
                preconditionFailure("Could not create isolated screenshot defaults.")
            }
            self.defaults = defaults
            defaults.removePersistentDomain(forName: suiteName)

            directory = FileManager.default.temporaryDirectory
                .appendingPathComponent(
                    "\(ScreenshotEnvironment.temporaryDirectoryPrefix)-\(identifier)",
                    isDirectory: true
                )
            do {
                try FileManager.default.createDirectory(
                    at: directory,
                    withIntermediateDirectories: false,
                    attributes: [.posixPermissions: 0o700]
                )
            } catch {
                defaults.removePersistentDomain(forName: suiteName)
                preconditionFailure(
                    "Could not create isolated screenshot storage: \(error.localizedDescription)"
                )
            }
        }

        func cleanup() {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: directory)
        }
    }

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let store: SentinelStore
    private let screenshotMode: Bool
    private let screenshotIsolation: ScreenshotIsolation?
    private let screenshotOutputURL: URL?
    private var cancellables = Set<AnyCancellable>()

    override init() {
        let environment = ProcessInfo.processInfo.environment
        let screenshotMode = environment[
            AppConstants.screenshotModeEnvironmentKey
        ] == "1"
        self.screenshotMode = screenshotMode

        let screenshotConfiguration: ScreenshotConfiguration?
        if screenshotMode {
            let configuration = ScreenshotConfiguration(environment: environment)
            let isolation = ScreenshotIsolation()
            screenshotConfiguration = configuration
            screenshotIsolation = isolation
            screenshotOutputURL = configuration.outputURL
            store = SentinelStore(
                defaults: isolation.defaults,
                resetCreditProtectionLedgerStore: ResetCreditProtectionLedgerStore(
                    url: isolation.directory.appendingPathComponent("ledger.json")
                ),
                resetCreditProtectionAuthorizationStore:
                    ResetCreditProtectionAuthorizationStore(
                        url: isolation.directory.appendingPathComponent(
                            "authorization.json"
                        ),
                        dispatchLockURL: isolation.directory.appendingPathComponent(
                            "authorization.lock"
                        )
                    ),
                resetCreditProtectionProcessLockURL: isolation.directory
                    .appendingPathComponent("process.lock")
            )
        } else {
            screenshotConfiguration = nil
            screenshotIsolation = nil
            screenshotOutputURL = nil
            store = SentinelStore()
        }

        super.init()
        if let screenshotConfiguration {
            store.configureForStatusScreenshot(
                language: screenshotConfiguration.language,
                metrics: screenshotConfiguration.metrics
            )
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        configureStatusItem()
        guard screenshotMode else {
            NotificationService.shared.requestAuthorization()
            store.start()
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.captureStatusScreenshotAndTerminate()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        guard !screenshotMode else {
            screenshotIsolation?.cleanup()
            return
        }
        store.stop()
    }

    private func configureStatusItem() {
        updateStatusButton()
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        store.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                DispatchQueue.main.async {
                    self?.updateStatusButton()
                }
            }
            .store(in: &cancellables)
        rebuildMenu(menu)
    }

    func menuWillOpen(_ menu: NSMenu) {
        rebuildMenu(menu)
    }

    private func rebuildMenu(_ menu: NSMenu) {
        menu.removeAllItems()
        let root = DashboardMenuView(store: store)
        let hostingView = NSHostingView(rootView: root)
        let metrics = store.menuTextSize.metrics
        hostingView.frame = NSRect(x: 0, y: 0, width: metrics.width, height: metrics.height)
        let item = NSMenuItem()
        item.view = hostingView
        menu.addItem(item)
    }

    private func updateStatusButton() {
        guard let button = statusItem.button else {
            return
        }
        let state = store.dashboardState
        let emphasized = store.shouldEmphasizeSpeedAlert
        let options = store.statusBarDisplayOptions
        let title = StatusTitleFormatter.plainTitle(
            for: state,
            metrics: store.selectedStatusMetrics,
            language: store.appLanguage,
            options: options
        )
        let attributedTitle = StatusTitleFormatter.attributedTitle(
            for: state,
            emphasized: emphasized,
            metrics: store.selectedStatusMetrics,
            language: store.appLanguage,
            options: options
        )
        button.attributedTitle = attributedTitle
        updateStatusItemLength(title: attributedTitle, options: options)
        button.toolTip = "\(AppConstants.appName) \(title)"
        button.setAccessibilityTitle(title)
        button.wantsLayer = true
        if emphasized {
            button.layer?.backgroundColor = NSColor.systemRed.cgColor
            button.layer?.cornerRadius = MenuMetrics.urgentCornerRadius
        } else {
            button.layer?.backgroundColor = NSColor.clear.cgColor
            button.layer?.cornerRadius = 0
        }
    }

    private func updateStatusItemLength(title: NSAttributedString, options: StatusBarDisplayOptions) {
        guard let extraWidth = options.horizontalPadding.fixedExtraWidth else {
            statusItem.length = NSStatusItem.variableLength
            return
        }
        statusItem.length = ceil(title.size().width + extraWidth)
    }

    private func captureStatusScreenshotAndTerminate() {
        do {
            guard let destination = screenshotOutputURL,
                  let button = statusItem.button,
                  let window = button.window else {
                throw StatusScreenshotError.statusItemUnavailable
            }
            button.layoutSubtreeIfNeeded()
            button.displayIfNeeded()
            window.displayIfNeeded()
            let bounds = button.bounds
            guard bounds.width > 0,
                  bounds.height > 0,
                  let bitmap = button.bitmapImageRepForCachingDisplay(
                      in: bounds
                  ) else {
                throw StatusScreenshotError.statusItemUnavailable
            }
            button.cacheDisplay(in: bounds, to: bitmap)
            guard let data = bitmap.representation(using: .png, properties: [:]) else {
                throw StatusScreenshotError.pngEncodingFailed
            }
            try data.write(to: destination, options: .atomic)
            let title = button.accessibilityTitle() ?? button.attributedTitle.string
            print("CODEX_RADAR_STATUS_TITLE=\(title)")
            let background = button.layer?.backgroundColor
                .flatMap(NSColor.init(cgColor:))?
                .usingColorSpace(.deviceRGB) ?? .clear
            let style = [
                background.redComponent,
                background.greenComponent,
                background.blueComponent,
                background.alphaComponent,
                button.layer?.cornerRadius ?? 0,
                bounds.height,
            ].map { String(format: "%.6f", $0) }
                .joined(separator: ",")
            print("CODEX_RADAR_STATUS_STYLE=\(style)")
            NSApplication.shared.terminate(nil)
        } catch {
            screenshotIsolation?.cleanup()
            fputs(
                "Failed to capture status screenshot: \(error.localizedDescription)\n",
                stderr
            )
            exit(1)
        }
    }
}

private enum StatusScreenshotError: LocalizedError {
    case statusItemUnavailable
    case pngEncodingFailed

    var errorDescription: String? {
        switch self {
        case .statusItemUnavailable:
            return "The target status item window is unavailable"
        case .pngEncodingFailed:
            return "The target status item screenshot could not be encoded"
        }
    }
}
