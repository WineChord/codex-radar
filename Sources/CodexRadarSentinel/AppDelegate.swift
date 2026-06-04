import AppKit
import CodexRadarCore
import Combine
import SwiftUI
import UserNotifications

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private enum MenuMetrics {
        static let width: CGFloat = 340
        static let height: CGFloat = 430
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
        updateStatusButton(for: store.state)
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        store.$state
            .receive(on: RunLoop.main)
            .sink { [weak self] state in
                self?.updateStatusButton(for: state)
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
        hostingView.frame = NSRect(x: 0, y: 0, width: MenuMetrics.width, height: MenuMetrics.height)
        let item = NSMenuItem()
        item.view = hostingView
        menu.addItem(item)
    }

    private func updateStatusButton(for state: DashboardState) {
        guard let button = statusItem.button else {
            return
        }
        button.attributedTitle = StatusTitleFormatter.attributedTitle(for: state)
        button.toolTip = "\(AppConstants.appName) \(state.statusTitle)"
        button.setAccessibilityTitle(state.statusTitle)
    }
}
