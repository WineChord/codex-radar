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

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let store = SentinelStore()
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        configureStatusItem()
        NotificationService.shared.requestAuthorization()
        store.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
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
        let title = StatusTitleFormatter.plainTitle(
            for: state,
            metrics: store.selectedStatusMetrics,
            language: store.appLanguage
        )
        button.attributedTitle = StatusTitleFormatter.attributedTitle(
            for: state,
            emphasized: emphasized,
            metrics: store.selectedStatusMetrics,
            language: store.appLanguage
        )
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
}
