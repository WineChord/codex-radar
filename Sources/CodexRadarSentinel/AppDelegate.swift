import AppKit
import Combine
import SwiftUI
import UserNotifications

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
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
        statusItem.button?.title = store.state.statusTitle
        statusItem.button?.font = NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .medium)
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        store.$state
            .receive(on: RunLoop.main)
            .sink { [weak self] state in
                self?.statusItem.button?.title = state.statusTitle
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
        hostingView.frame = NSRect(x: 0, y: 0, width: 380, height: 520)
        let item = NSMenuItem()
        item.view = hostingView
        menu.addItem(item)
    }
}
