import XCTest
@testable import CodexRadarCore

final class CodexBinaryLocatorTests: XCTestCase {
    func testEnvironmentOverrideWins() throws {
        let temp = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: temp) }
        let home = temp.appendingPathComponent("home", isDirectory: true)
        let override = temp.appendingPathComponent("custom/codex")
        let standalone = home.appendingPathComponent(".codex/packages/standalone/current/bin/codex")
        try makeExecutable(override)
        try makeExecutable(standalone)

        let located = CodexBinaryLocator.findBinary(
            environment: [
                AppConstants.codexPathEnvironmentKey: override.path,
                "PATH": "",
            ],
            homeDirectory: home,
            systemCandidates: []
        )

        XCTAssertEqual(located?.path, override.path)
    }

    func testFindsStandaloneCodexWhenAppBundleBinaryIsMissing() throws {
        let temp = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: temp) }
        let home = temp.appendingPathComponent("home", isDirectory: true)
        let standalone = home.appendingPathComponent(".codex/packages/standalone/current/bin/codex")
        try makeExecutable(standalone)

        let located = CodexBinaryLocator.findBinary(
            environment: ["PATH": ""],
            homeDirectory: home,
            systemCandidates: []
        )

        XCTAssertEqual(located?.path, standalone.path)
    }

    func testFindsCodexFromPathWithoutEnvExecutableFallback() throws {
        let temp = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: temp) }
        let home = temp.appendingPathComponent("home", isDirectory: true)
        let pathCodex = temp.appendingPathComponent("bin/codex")
        try makeExecutable(pathCodex)

        let located = CodexBinaryLocator.findBinary(
            environment: ["PATH": pathCodex.deletingLastPathComponent().path],
            homeDirectory: home,
            systemCandidates: []
        )

        XCTAssertEqual(located?.path, pathCodex.path)
        XCTAssertNotEqual(located?.path, "/usr/bin/env")
    }

    func testFindsBundledCLIWithBrokenLegacySymlinkAndGUIPath() throws {
        for bundleName in ["Codex", "ChatGPT"] {
            let temp = try makeTempDirectory()
            defer { try? FileManager.default.removeItem(at: temp) }
            let home = temp.appendingPathComponent("home", isDirectory: true)
            let resources = temp.appendingPathComponent(
                "Applications/\(bundleName).app/Contents/Resources"
            )
            let legacy = resources.appendingPathComponent("codex")
            let bundled = resources.appendingPathComponent(
                "codex-cli/CodexCLI.app/Contents/MacOS/codex"
            )
            try makeExecutable(bundled)
            let symlink = home.appendingPathComponent(".local/bin/codex")
            try FileManager.default.createDirectory(
                at: symlink.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try FileManager.default.createSymbolicLink(at: symlink, withDestinationURL: legacy)

            let located = CodexBinaryLocator.findBinary(
                environment: ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin"],
                homeDirectory: home,
                systemCandidates: [legacy.path, bundled.path]
            )

            XCTAssertEqual(located?.path, bundled.path)
            XCTAssertTrue(CodexBinaryLocator.candidatePaths(
                environment: ["PATH": ""], homeDirectory: home
            ).contains("/Applications/\(bundleName).app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex"))
        }
    }

    func testLegacyBundleRemainsPreferredWhenBothLayoutsExist() throws {
        let temp = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: temp) }
        let legacy = temp.appendingPathComponent("Resources/codex")
        let bundled = temp.appendingPathComponent("Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex")
        try makeExecutable(legacy)
        try makeExecutable(bundled)

        XCTAssertEqual(CodexBinaryLocator.findBinary(
            environment: ["PATH": ""],
            homeDirectory: temp.appendingPathComponent("home"),
            systemCandidates: [legacy.path, bundled.path]
        ), legacy)
    }

    func testMissingOrNonExecutableCandidatesReturnNil() throws {
        let temp = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: temp) }
        let candidate = temp.appendingPathComponent("codex")
        try Data("not executable".utf8).write(to: candidate)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: candidate.path)

        XCTAssertNil(CodexBinaryLocator.findBinary(
            environment: [AppConstants.codexPathEnvironmentKey: candidate.path, "PATH": ""],
            homeDirectory: temp.appendingPathComponent("home"),
            systemCandidates: [candidate.path, temp.appendingPathComponent("missing").path]
        ))
    }

    func testDiscoversRenamedMovedApplicationAndUnknownInternalLayout() throws {
        let temp = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: temp) }
        let application = temp.appendingPathComponent("Tools/Renamed Desktop.app")
        try makeBundle(application, identifier: "com.openai.codex")
        let executable = application.appendingPathComponent("Contents/Resources/runtime/v2/tools/codex")
        try makeExecutable(executable)
        let located = CodexBinaryLocator.findBinary(
            environment: ["PATH": ""], homeDirectory: temp.appendingPathComponent("home"),
            systemCandidates: [], applicationURLsProvider: { [application] }
        )
        XCTAssertEqual(located?.resolvingSymlinksInPath().path, executable.resolvingSymlinksInPath().path)
    }

    func testDiscoversCLIFromBundleMetadataWhenExecutableIsRenamed() throws {
        let temp = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: temp) }
        let application = temp.appendingPathComponent("Desktop.app")
        try makeBundle(application, identifier: "com.openai.codex")
        let cli = application.appendingPathComponent("Contents/Resources/new-runtime/Engine.app")
        try makeBundle(cli, identifier: "com.openai.codex.cli", executable: "codex-engine")
        let executable = cli.appendingPathComponent("Contents/MacOS/codex-engine")
        try makeExecutable(executable)
        XCTAssertEqual(CodexApplicationLocator.bundledBinary(in: application, fileManager: .default)?.resolvingSymlinksInPath().path, executable.resolvingSymlinksInPath().path)
    }

    func testDiscoveryDoesNotExecuteUnrelatedAppsOrEscapingSymlinks() throws {
        let temp = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: temp) }
        let unrelated = temp.appendingPathComponent("Unrelated.app")
        try makeBundle(unrelated, identifier: "org.example.unrelated")
        try makeExecutable(unrelated.appendingPathComponent("Contents/Resources/codex"))
        XCTAssertNil(CodexApplicationLocator.bundledBinary(in: unrelated, fileManager: .default))

        let application = temp.appendingPathComponent("Desktop.app")
        try makeBundle(application, identifier: "com.openai.codex")
        let external = temp.appendingPathComponent("outside/codex")
        try makeExecutable(external)
        let link = application.appendingPathComponent("Contents/MacOS/codex")
        try FileManager.default.createDirectory(at: link.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: external)
        XCTAssertNil(CodexApplicationLocator.bundledBinary(in: application, fileManager: .default))
    }

    func testDiscoveryIsLazyAndExplicitPathStillWins() throws {
        let temp = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: temp) }
        let executable = temp.appendingPathComponent("override/codex")
        try makeExecutable(executable)
        var discovered = false
        XCTAssertEqual(CodexBinaryLocator.findBinary(
            environment: [AppConstants.codexPathEnvironmentKey: executable.path, "PATH": ""],
            homeDirectory: temp, systemCandidates: [],
            applicationURLsProvider: { discovered = true; return [] }
        ), executable)
        XCTAssertFalse(discovered)
    }

    func testDiscoveryRechecksAfterApplicationMovesAndRespectsDepthBound() throws {
        let temp = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: temp) }
        let original = temp.appendingPathComponent("Original.app")
        try makeBundle(original, identifier: "com.openai.codex")
        let relative = "Contents/Resources/tools/codex"
        try makeExecutable(original.appendingPathComponent(relative))
        var current = original
        func locate() -> URL? {
            CodexBinaryLocator.findBinary(environment: ["PATH": ""], homeDirectory: temp,
                systemCandidates: [], applicationURLsProvider: { [current] })
        }
        XCTAssertEqual(locate()?.resolvingSymlinksInPath().path, original.appendingPathComponent(relative).resolvingSymlinksInPath().path)
        current = temp.appendingPathComponent("Moved.app")
        try FileManager.default.moveItem(at: original, to: current)
        XCTAssertEqual(locate()?.resolvingSymlinksInPath().path, current.appendingPathComponent(relative).resolvingSymlinksInPath().path)
        try FileManager.default.removeItem(at: current.appendingPathComponent(relative))
        try makeExecutable(current.appendingPathComponent("Contents/Resources/a/b/c/d/e/f/g/h/i/codex"))
        XCTAssertNil(locate())
    }

    private func makeBundle(_ url: URL, identifier: String, executable: String = "desktop") throws {
        let contents = url.appendingPathComponent("Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let data = try PropertyListSerialization.data(fromPropertyList: [
            "CFBundleIdentifier": identifier, "CFBundleExecutable": executable,
            "CFBundlePackageType": "APPL",
        ], format: .xml, options: 0)
        try data.write(to: contents.appendingPathComponent("Info.plist"))
    }

    private func makeTempDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-binary-locator-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func makeExecutable(_ url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        FileManager.default.createFile(atPath: url.path, contents: Data("#!/bin/sh\n".utf8))
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: url.path
        )
    }
}
