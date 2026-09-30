import AppKit
import Foundation

public enum CodexApplicationLocator {
    static let bundleIdentifiers = ["com.openai.codex", "com.openai.chat"]

    public static func applicationURLs() -> [URL] {
        let workspace = NSWorkspace.shared
        let applications = bundleIdentifiers.flatMap { identifier -> [URL] in
            let running = workspace.runningApplications.compactMap { application -> URL? in
                guard application.bundleIdentifier == identifier else { return nil }
                return application.bundleURL
            }
            let registered = workspace.urlForApplication(withBundleIdentifier: identifier)
            return running + [registered].compactMap { $0 }
        }
        var seen = Set<URL>()
        return applications.filter {
            seen.insert($0.resolvingSymlinksInPath()).inserted
        }
    }

    static func bundledBinary(in application: URL, fileManager: FileManager) -> URL? {
        guard let bundle = Bundle(url: application),
              let identifier = bundle.bundleIdentifier,
              bundleIdentifiers.contains(identifier) else { return nil }
        let root = application.resolvingSymlinksInPath()
        let contents = root.appendingPathComponent("Contents", isDirectory: true)
        let knownPaths = [
            "Resources/codex",
            "Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex",
            "MacOS/codex",
        ]
        func isBinary(_ url: URL) -> Bool {
            let resolved = url.resolvingSymlinksInPath()
            return resolved.path.hasPrefix(contents.path + "/")
                && (try? resolved.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true
                && fileManager.isExecutableFile(atPath: resolved.path)
        }
        for path in knownPaths {
            let url = contents.appendingPathComponent(path)
            if isBinary(url) { return url }
        }
        // Only inspect the identified application, with bounded depth and work.
        guard let enumerator = fileManager.enumerator(
            at: contents,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }
        var visited = 0
        for case let url as URL in enumerator {
            visited += 1
            guard visited <= 2_048 else { break }
            if enumerator.level > 8 {
                enumerator.skipDescendants()
                continue
            }
            if url.pathExtension == "app",
               let cli = Bundle(url: url), cli.bundleIdentifier == "com.openai.codex.cli",
               let executable = cli.executableURL, isBinary(executable) {
                return executable
            }
            if url.lastPathComponent == "codex", isBinary(url) { return url }
        }
        return nil
    }
}
