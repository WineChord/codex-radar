import AppKit
import CodexRadarCore
import CryptoKit
import Foundation

struct AppUpdateInfo: Equatable {
    let version: String
    let releaseURL: URL
    let changelog: String?
    let zipAsset: ReleaseAsset
    let checksumAsset: ReleaseAsset
}

struct ReleaseAsset: Decodable, Equatable {
    let name: String
    let browserDownloadURL: URL

    enum CodingKeys: String, CodingKey {
        case name
        case browserDownloadURL = "browser_download_url"
    }
}

enum AppUpdatePhase: Equatable {
    case idle
    case checking
    case upToDate(Date)
    case available(String)
    case downloading(String)
    case installing(String)
    case failed(String)

    var isActive: Bool {
        switch self {
        case .checking, .downloading, .installing:
            return true
        case .idle, .upToDate, .available, .failed:
            return false
        }
    }

    func label(language: AppLanguage) -> String {
        switch self {
        case .idle:
            return language.text("未检查", "Not checked")
        case .checking:
            return language.text("正在检查更新", "Checking for updates")
        case .upToDate:
            return language.text("已是最新版本", "Up to date")
        case .available(let version):
            return language.text("发现 \(version)", "Found \(version)")
        case .downloading(let version):
            return language.text("正在下载 \(version)", "Downloading \(version)")
        case .installing(let version):
            return language.text("正在安装 \(version)，应用会自动重开", "Installing \(version); the app will reopen")
        case .failed(let message):
            return language.text("更新失败：\(message)", "Update failed: \(message)")
        }
    }
}

final class AppUpdater {
    private let session: URLSession
    private let fileManager: FileManager

    init(
        session: URLSession = .shared,
        fileManager: FileManager = .default
    ) {
        self.session = session
        self.fileManager = fileManager
    }

    func latestUpdate(currentVersion: String) async throws -> AppUpdateInfo? {
        guard let current = SemanticVersion(currentVersion) else {
            throw AppUpdaterError.invalidCurrentVersion(currentVersion)
        }

        do {
            return try await latestUpdateFromAPI(current: current)
        } catch {
            return try await latestUpdateFromRedirect(current: current)
        }
    }

    private func latestUpdateFromAPI(current: SemanticVersion) async throws -> AppUpdateInfo? {
        let release: GitHubRelease = try await requestJSON(AppConstants.githubLatestReleaseAPIURL)
        guard !release.draft, !release.prerelease else {
            return nil
        }
        guard let latest = SemanticVersion(release.tagName), latest > current else {
            return nil
        }
        guard let zipAsset = release.assets.first(where: { asset in
            asset.name.hasSuffix(".zip") && asset.name.contains("macOS")
        }) else {
            throw AppUpdaterError.missingZipAsset
        }
        guard let checksumAsset = release.assets.first(where: { $0.name.hasSuffix(".sha256") }) else {
            throw AppUpdaterError.missingChecksumAsset
        }

        return AppUpdateInfo(
            version: latest.description,
            releaseURL: release.htmlURL,
            changelog: release.body,
            zipAsset: zipAsset,
            checksumAsset: checksumAsset
        )
    }

    private func latestUpdateFromRedirect(current: SemanticVersion) async throws -> AppUpdateInfo? {
        let releaseURL = try await latestReleaseRedirectURL()
        let tag = try releaseTag(from: releaseURL)
        guard let latest = SemanticVersion(tag), latest > current else {
            return nil
        }

        let archiveName = "CodexRadarSentinel-\(latest.description)-macOS"
        let downloadBaseURL = AppConstants.githubRepositoryURL
            .appendingPathComponent("releases")
            .appendingPathComponent("download")
            .appendingPathComponent(tag)

        return AppUpdateInfo(
            version: latest.description,
            releaseURL: releaseURL,
            changelog: nil,
            zipAsset: ReleaseAsset(
                name: "\(archiveName).zip",
                browserDownloadURL: downloadBaseURL.appendingPathComponent("\(archiveName).zip")
            ),
            checksumAsset: ReleaseAsset(
                name: "\(archiveName).sha256",
                browserDownloadURL: downloadBaseURL.appendingPathComponent("\(archiveName).sha256")
            )
        )
    }

    func install(_ update: AppUpdateInfo) async throws {
        let workingDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("codex-radar-update-\(UUID().uuidString)", isDirectory: true)
        let extractDirectory = workingDirectory.appendingPathComponent("extract", isDirectory: true)
        try fileManager.createDirectory(at: extractDirectory, withIntermediateDirectories: true)

        let zipURL = try await download(update.zipAsset.browserDownloadURL, to: workingDirectory)
        let checksumText = try await requestString(update.checksumAsset.browserDownloadURL)
        try verifyChecksum(for: zipURL, assetName: update.zipAsset.name, checksumText: checksumText)
        try runProcess("/usr/bin/ditto", arguments: ["-x", "-k", zipURL.path, extractDirectory.path])

        guard let appBundle = findAppBundle(in: extractDirectory) else {
            throw AppUpdaterError.missingAppBundle
        }
        try validateAppBundle(appBundle, expectedVersion: update.version)
        let targetBundle = Bundle.main.bundleURL
        guard targetBundle.pathExtension == "app" else {
            throw AppUpdaterError.unsupportedInstallLocation
        }

        try launchInstaller(
            sourceBundle: appBundle,
            targetBundle: targetBundle,
            workingDirectory: workingDirectory,
            updateVersion: update.version
        )
    }

    private func requestJSON<T: Decodable>(_ url: URL) async throws -> T {
        let data = try await requestData(url)
        return try JSONDecoder().decode(T.self, from: data)
    }

    private func requestString(_ url: URL) async throws -> String {
        let data = try await requestData(url)
        guard let value = String(data: data, encoding: .utf8) else {
            throw AppUpdaterError.invalidChecksumFile
        }
        return value
    }

    private func requestData(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("\(AppConstants.clientName)/\(AppConstants.appVersion)", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)
        try validate(response)
        return data
    }

    private func latestReleaseRedirectURL() async throws -> URL {
        var request = URLRequest(url: AppConstants.githubLatestReleaseURL)
        request.setValue("text/html", forHTTPHeaderField: "Accept")
        request.setValue("\(AppConstants.clientName)/\(AppConstants.appVersion)", forHTTPHeaderField: "User-Agent")

        let (_, response) = try await session.data(for: request)
        try validate(response)
        guard let finalURL = response.url else {
            throw AppUpdaterError.missingLatestReleaseRedirect
        }
        return finalURL
    }

    private func releaseTag(from url: URL) throws -> String {
        let components = url.pathComponents
        guard let tagIndex = components.lastIndex(of: "tag"),
              components.indices.contains(tagIndex + 1) else {
            throw AppUpdaterError.invalidLatestReleaseRedirect(url)
        }
        return components[tagIndex + 1]
    }

    private func download(_ url: URL, to directory: URL) async throws -> URL {
        var request = URLRequest(url: url)
        request.setValue("\(AppConstants.clientName)/\(AppConstants.appVersion)", forHTTPHeaderField: "User-Agent")

        let (temporaryURL, response) = try await session.download(for: request)
        try validate(response)
        let destination = directory.appendingPathComponent(url.lastPathComponent)
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        try fileManager.moveItem(at: temporaryURL, to: destination)
        return destination
    }

    private func validate(_ response: URLResponse) throws {
        guard let response = response as? HTTPURLResponse else {
            return
        }
        guard 200..<300 ~= response.statusCode else {
            throw AppUpdaterError.httpStatus(response.statusCode)
        }
    }

    private func verifyChecksum(for fileURL: URL, assetName: String, checksumText: String) throws {
        let expected = try expectedChecksum(for: assetName, checksumText: checksumText)
        let data = try Data(contentsOf: fileURL)
        let digest = SHA256.hash(data: data)
        let actual = digest.map { String(format: "%02x", $0) }.joined()
        guard actual.caseInsensitiveCompare(expected) == .orderedSame else {
            throw AppUpdaterError.checksumMismatch
        }
    }

    private func expectedChecksum(for assetName: String, checksumText: String) throws -> String {
        for line in checksumText.split(whereSeparator: \.isNewline) {
            let columns = line.split(whereSeparator: \.isWhitespace)
            guard columns.count >= 2 else {
                continue
            }
            let checksum = String(columns[0])
            let filename = String(columns[1]).split(separator: "/").last.map(String.init) ?? ""
            if filename == assetName {
                return checksum
            }
        }
        throw AppUpdaterError.checksumNotFound(assetName)
    }

    private func findAppBundle(in directory: URL) -> URL? {
        guard let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }

        for case let url as URL in enumerator {
            guard url.pathExtension == "app",
                  url.lastPathComponent == "\(AppConstants.appName).app" else {
                continue
            }
            return url
        }
        return nil
    }

    private func validateAppBundle(_ appBundle: URL, expectedVersion: String) throws {
        let actualVersion = try bundleVersion(in: appBundle)
        guard actualVersion == expectedVersion else {
            throw AppUpdaterError.unexpectedBundleVersion(expected: expectedVersion, actual: actualVersion)
        }
        try runProcess(
            "/usr/bin/codesign",
            arguments: ["--verify", "--deep", "--strict", appBundle.path]
        )
    }

    private func bundleVersion(in appBundle: URL) throws -> String {
        let infoPlistURL = appBundle
            .appendingPathComponent("Contents", isDirectory: true)
            .appendingPathComponent("Info.plist")
        let data = try Data(contentsOf: infoPlistURL)
        let plist = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        guard let dictionary = plist as? [String: Any],
              let version = dictionary["CFBundleShortVersionString"] as? String,
              !version.isEmpty else {
            throw AppUpdaterError.missingBundleVersion
        }
        return version
    }

    private func launchInstaller(
        sourceBundle: URL,
        targetBundle: URL,
        workingDirectory: URL,
        updateVersion: String
    ) throws {
        let scriptURL = workingDirectory.appendingPathComponent("install.sh")
        let logURL = workingDirectory.appendingPathComponent("install.log")
        let script = """
        #!/bin/bash
        set -euo pipefail

        pid="$1"
        source_bundle="$2"
        target_bundle="$3"
        log_file="$4"
        update_version="$5"
        defaults_domain="$6"
        failure_version_key="$7"
        failure_at_key="$8"

        exec >> "$log_file" 2>&1

        working_directory="$(/usr/bin/dirname "$log_file")"
        staged_bundle="$working_directory/staged.app"
        backup_bundle="$working_directory/backup.app"

        record_failure() {
          /usr/bin/defaults write "$defaults_domain" "$failure_version_key" "$update_version" >/dev/null 2>&1 || true
          /usr/bin/defaults write "$defaults_domain" "$failure_at_key" "$(/bin/date +%s)" >/dev/null 2>&1 || true
        }

        restore_and_open() {
          if [ ! -d "$target_bundle" ] && [ -d "$backup_bundle" ]; then
            /usr/bin/ditto "$backup_bundle" "$target_bundle" || true
          fi
          if [ -d "$target_bundle" ]; then
            /usr/bin/open "$target_bundle" || true
          fi
        }

        on_failure() {
          status="$?"
          if [ "$status" -ne 0 ]; then
            echo "install failed with status $status"
            record_failure
            restore_and_open
          fi
          exit "$status"
        }

        trap on_failure EXIT

        for _ in {1..80}; do
          if ! /bin/kill -0 "$pid" >/dev/null 2>&1; then
            break
          fi
          /bin/sleep 0.25
        done
        if /bin/kill -0 "$pid" >/dev/null 2>&1; then
          echo "app process $pid did not exit in time"
          exit 1
        fi

        /bin/rm -rf "$staged_bundle" "$backup_bundle"
        /usr/bin/ditto "$source_bundle" "$staged_bundle"
        /usr/bin/codesign --verify --deep --strict "$staged_bundle"

        if [ -d "$target_bundle" ]; then
          /usr/bin/ditto "$target_bundle" "$backup_bundle"
        fi
        /bin/rm -rf "$target_bundle"
        /bin/mv "$staged_bundle" "$target_bundle"
        /usr/bin/codesign --verify --deep --strict "$target_bundle"
        /usr/bin/defaults delete "$defaults_domain" "$failure_version_key" >/dev/null 2>&1 || true
        /usr/bin/defaults delete "$defaults_domain" "$failure_at_key" >/dev/null 2>&1 || true
        /usr/bin/open "$target_bundle"
        trap - EXIT
        """
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)
        try runProcess("/bin/bash", arguments: ["-n", scriptURL.path])

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [
            scriptURL.path,
            String(ProcessInfo.processInfo.processIdentifier),
            sourceBundle.path,
            targetBundle.path,
            logURL.path,
            updateVersion,
            AppConstants.bundleIdentifier,
            AppConstants.installerFailureVersionDefaultsKey,
            AppConstants.installerFailureAtDefaultsKey,
        ]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
    }

    private func runProcess(_ executable: String, arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw AppUpdaterError.processFailed(executable, process.terminationStatus)
        }
    }
}

private struct GitHubRelease: Decodable {
    let tagName: String
    let htmlURL: URL
    let body: String?
    let draft: Bool
    let prerelease: Bool
    let assets: [ReleaseAsset]

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlURL = "html_url"
        case body
        case draft
        case prerelease
        case assets
    }
}

private enum AppUpdaterError: LocalizedError {
    case invalidCurrentVersion(String)
    case httpStatus(Int)
    case missingZipAsset
    case missingChecksumAsset
    case missingLatestReleaseRedirect
    case invalidLatestReleaseRedirect(URL)
    case invalidChecksumFile
    case checksumNotFound(String)
    case checksumMismatch
    case missingAppBundle
    case missingBundleVersion
    case unexpectedBundleVersion(expected: String, actual: String)
    case unsupportedInstallLocation
    case processFailed(String, Int32)

    var errorDescription: String? {
        switch self {
        case .invalidCurrentVersion(let version):
            return "Invalid current version \(version)"
        case .httpStatus(let status):
            if status == 403 {
                return "HTTP 403 (GitHub API rate limit or access denied)"
            }
            return "HTTP \(status)"
        case .missingZipAsset:
            return "Release zip asset not found"
        case .missingChecksumAsset:
            return "Release checksum asset not found"
        case .missingLatestReleaseRedirect:
            return "Latest release redirect not found"
        case .invalidLatestReleaseRedirect(let url):
            return "Latest release redirect is not a tag URL: \(url.absoluteString)"
        case .invalidChecksumFile:
            return "Checksum file is not UTF-8"
        case .checksumNotFound(let assetName):
            return "Checksum for \(assetName) not found"
        case .checksumMismatch:
            return "Checksum mismatch"
        case .missingAppBundle:
            return "App bundle not found in update archive"
        case .missingBundleVersion:
            return "Update app bundle version not found"
        case .unexpectedBundleVersion(let expected, let actual):
            return "Update app bundle version \(actual) does not match release \(expected)"
        case .unsupportedInstallLocation:
            return "Current app is not running from an app bundle"
        case .processFailed(let executable, let status):
            return "\(executable) exited with \(status)"
        }
    }
}
