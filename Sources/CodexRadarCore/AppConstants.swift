import Foundation

public enum AppConstants {
    public static let appName = "Codex Radar Sentinel"
    public static let clientName = "codex-radar-sentinel"
    public static let bundleIdentifier = "com.codexradar.sentinel"
    public static let appVersion = "0.1.18"

    public static let codexLimitID = "codex"
    public static let weeklyWindowMinutes = 10_080.0
    public static let fiveHourWindowMinutes = 300.0
    public static let monthlyWindowMinutes = 43_200.0
    public static let windowDurationTolerance = 0.05

    public static let warningRemainingPercent = 30
    public static let criticalRemainingPercent = 15
    public static let restoredRemainingPercent = 80

    public static let defaultPollIntervalSeconds: UInt64 = 60
    public static let requestTimeoutSeconds: UInt64 = 15
    public static let speedAlertEmphasisSeconds: TimeInterval = 1_800
    public static let initialUpdateCheckDelaySeconds: UInt64 = 5
    public static let updateCheckIntervalSeconds: UInt64 = 21_600
    public static let failedInstallerRetryDelaySeconds: TimeInterval = 21_600

    public static let codexRadarBaseURL = URL(string: "https://codexradar.com")!
    public static let currentPath = "current.json"
    public static let feedPath = "feed.xml"

    public static let codexAppBinaryPath = "/Applications/Codex.app/Contents/Resources/codex"
    public static let codexPathEnvironmentKey = "CODEX_RADAR_CODEX_PATH"
    public static let debugPreviewEnvironmentKey = "CODEX_RADAR_PREVIEW"
    public static let githubRepositoryURL = URL(string: "https://github.com/WineChord/codex-radar")!
    public static let githubPromptLogURL = URL(string: "https://github.com/WineChord/codex-radar/blob/main/PROMPTS.md")!
    public static let githubReleasesURL = URL(string: "https://github.com/WineChord/codex-radar/releases")!
    public static let githubLatestReleaseURL = URL(string: "https://github.com/WineChord/codex-radar/releases/latest")!
    public static let githubLatestReleaseAPIURL = URL(string: "https://api.github.com/repos/WineChord/codex-radar/releases/latest")!

    public static let installerFailureVersionDefaultsKey = "lastInstallerFailureVersion"
    public static let installerFailureAtDefaultsKey = "lastInstallerFailureAt"
}
