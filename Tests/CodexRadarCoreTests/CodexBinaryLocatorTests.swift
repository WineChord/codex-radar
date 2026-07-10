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
