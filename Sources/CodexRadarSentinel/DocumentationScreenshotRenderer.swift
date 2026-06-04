import AppKit
import Foundation
import SwiftUI

@MainActor
enum DocumentationScreenshotRenderer {
    private static let renderEnvironmentKey = "CODEX_RADAR_RENDER_DOC_SCREENSHOTS"
    private static let defaultsSuitePrefix = "com.codexradar.sentinel.docs"
    private static let layoutProbeHeight: CGFloat = 10
    private static let captureSettleSeconds: TimeInterval = 0.2
    private static let captureWindowMargin: CGFloat = 40

    static func runIfRequested() -> Bool {
        guard let outputPath = ProcessInfo.processInfo.environment[renderEnvironmentKey],
              !outputPath.isEmpty else {
            return false
        }

        NSApplication.shared.setActivationPolicy(.accessory)
        let outputDirectory = URL(fileURLWithPath: outputPath, isDirectory: true)
        do {
            try FileManager.default.createDirectory(
                at: outputDirectory,
                withIntermediateDirectories: true
            )
            try render(language: .zhHans, directoryName: "zh", outputDirectory: outputDirectory)
            try render(language: .en, directoryName: "en", outputDirectory: outputDirectory)
        } catch {
            fputs("Failed to render documentation screenshots: \(error.localizedDescription)\n", stderr)
            exit(1)
        }

        return true
    }

    private static func render(
        language: AppLanguage,
        directoryName: String,
        outputDirectory: URL
    ) throws {
        let languageDirectory = outputDirectory.appendingPathComponent(directoryName, isDirectory: true)
        try FileManager.default.createDirectory(
            at: languageDirectory,
            withIntermediateDirectories: true
        )

        let suiteName = "\(defaultsSuitePrefix).\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            throw DocumentationScreenshotError.defaultsCreationFailed
        }
        defaults.removePersistentDomain(forName: suiteName)

        let store = SentinelStore(defaults: defaults)
        store.configureForDocumentation(language: language)

        let view = DashboardMenuView(store: store, scrolling: false)
            .environment(\.colorScheme, .light)
        let image = try renderImage(view: view, width: store.menuTextSize.metrics.width)
        let destination = languageDirectory.appendingPathComponent("menu-full.png")
        try writePNG(image, to: destination)

        defaults.removePersistentDomain(forName: suiteName)
        print("\(destination.path)")
    }

    private static func renderImage<Content: View>(
        view: Content,
        width: CGFloat
    ) throws -> NSImage {
        let hostingView = NSHostingView(rootView: view)
        hostingView.frame = NSRect(x: 0, y: 0, width: width, height: layoutProbeHeight)
        hostingView.layoutSubtreeIfNeeded()

        let fittingSize = hostingView.fittingSize
        let renderSize = NSSize(
            width: ceil(max(width, fittingSize.width)),
            height: ceil(fittingSize.height)
        )
        hostingView.frame = NSRect(origin: .zero, size: renderSize)
        hostingView.layoutSubtreeIfNeeded()

        return try captureWindowImage(hostingView: hostingView, size: renderSize)
    }

    private static func captureWindowImage(
        hostingView: NSHostingView<some View>,
        size: NSSize
    ) throws -> NSImage {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false,
            screen: screenshotScreen
        )
        window.isReleasedWhenClosed = false
        window.isOpaque = true
        window.backgroundColor = .windowBackgroundColor
        window.contentView = hostingView
        window.setFrameOrigin(windowOrigin(for: size))
        window.orderFrontRegardless()
        window.displayIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(captureSettleSeconds))

        guard let cgImage = CGWindowListCreateImage(
            .null,
            .optionIncludingWindow,
            CGWindowID(window.windowNumber),
            [.bestResolution, .boundsIgnoreFraming]
        ) else {
            window.close()
            throw DocumentationScreenshotError.windowCaptureFailed
        }
        window.close()

        let bitmap = NSBitmapImageRep(cgImage: cgImage)
        let image = NSImage(size: NSSize(width: cgImage.width, height: cgImage.height))
        image.addRepresentation(bitmap)
        return image
    }

    private static var screenshotScreen: NSScreen? {
        NSScreen.screens.max { lhs, rhs in
            let left = (lhs.backingScaleFactor, lhs.frame.height)
            let right = (rhs.backingScaleFactor, rhs.frame.height)
            return left < right
        }
    }

    private static func windowOrigin(for size: NSSize) -> NSPoint {
        guard let screen = screenshotScreen else {
            return .zero
        }
        let frame = screen.visibleFrame
        return NSPoint(
            x: frame.minX + captureWindowMargin,
            y: max(frame.minY + captureWindowMargin, frame.maxY - size.height - captureWindowMargin)
        )
    }

    private static func writePNG(_ image: NSImage, to destination: URL) throws {
        let flattened = NSImage(size: image.size)
        flattened.lockFocus()
        NSColor.windowBackgroundColor.setFill()
        NSRect(origin: .zero, size: image.size).fill()
        image.draw(
            in: NSRect(origin: .zero, size: image.size),
            from: .zero,
            operation: .sourceOver,
            fraction: 1
        )
        flattened.unlockFocus()

        guard let tiffData = flattened.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:]) else {
            throw DocumentationScreenshotError.pngEncodingFailed
        }
        try pngData.write(to: destination)
    }
}

private enum DocumentationScreenshotError: LocalizedError {
    case defaultsCreationFailed
    case windowCaptureFailed
    case pngEncodingFailed

    var errorDescription: String? {
        switch self {
        case .defaultsCreationFailed:
            return "Could not create documentation screenshot defaults"
        case .windowCaptureFailed:
            return "Could not capture the menu screenshot window"
        case .pngEncodingFailed:
            return "Could not encode the menu view as PNG"
        }
    }
}
