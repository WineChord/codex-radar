import AppKit
import Foundation
import SwiftUI

@MainActor
enum DocumentationScreenshotRenderer {
    private static let renderEnvironmentKey = "CODEX_RADAR_RENDER_DOC_SCREENSHOTS"
    private static let defaultsSuitePrefix = "com.codexradar.sentinel.docs"

    static func runIfRequested() -> Bool {
        guard let outputPath = ProcessInfo.processInfo.environment[renderEnvironmentKey],
              !outputPath.isEmpty else {
            return false
        }

        NSApplication.shared.setActivationPolicy(.prohibited)
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
        hostingView.frame = NSRect(x: 0, y: 0, width: width, height: 10)
        hostingView.layoutSubtreeIfNeeded()

        let fittingSize = hostingView.fittingSize
        let renderSize = NSSize(
            width: ceil(max(width, fittingSize.width)),
            height: ceil(fittingSize.height)
        )
        hostingView.frame = NSRect(origin: .zero, size: renderSize)
        hostingView.layoutSubtreeIfNeeded()

        guard let bitmap = hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds) else {
            throw DocumentationScreenshotError.bitmapCreationFailed
        }
        bitmap.size = renderSize
        hostingView.cacheDisplay(in: hostingView.bounds, to: bitmap)

        let image = NSImage(size: renderSize)
        image.addRepresentation(bitmap)
        return image
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
    case bitmapCreationFailed
    case pngEncodingFailed

    var errorDescription: String? {
        switch self {
        case .defaultsCreationFailed:
            return "Could not create documentation screenshot defaults"
        case .bitmapCreationFailed:
            return "Could not create a bitmap for the menu view"
        case .pngEncodingFailed:
            return "Could not encode the menu view as PNG"
        }
    }
}
