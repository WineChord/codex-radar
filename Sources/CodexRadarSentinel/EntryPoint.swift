import AppKit

@main
enum CodexRadarSentinelMain {
    @MainActor
    static func main() {
        if DocumentationScreenshotRenderer.runIfRequested() {
            return
        }

        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) {
            app.run()
        }
    }
}
