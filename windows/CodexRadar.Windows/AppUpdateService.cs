using System.Diagnostics;
using System.Globalization;
using System.IO.Compression;
using System.Reflection;
using System.Reflection.PortableExecutable;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text.Json;
using System.Text.RegularExpressions;

namespace CodexRadar.Windows;

internal enum AppUpdatePhase { Idle, Checking, UpToDate, Available, Downloading, Installing, Failed }
internal sealed record AppUpdateStatus(AppUpdatePhase Phase, string? Version = null, string? Message = null, Uri? ReleaseUrl = null);
internal sealed record AppUpdateInfo(string Version, Uri ReleaseUrl, string? Changelog, ReleaseAsset Zip, ReleaseAsset Checksum, string Runtime);
internal sealed record ReleaseAsset(string Name, Uri DownloadUrl);

internal sealed class AppUpdateService : IDisposable
{
    public const string RepositoryUrl = "https://github.com/WineChord/codex-radar";
    public const string ReleasesUrl = RepositoryUrl + "/releases";
    public const string PromptsUrl = RepositoryUrl + "/blob/main/PROMPTS.md";
    private const string LatestApiUrl = "https://api.github.com/repos/WineChord/codex-radar/releases/latest";
    private const string LatestReleaseUrl = RepositoryUrl + "/releases/latest";
    private readonly HttpClient _http = new(new HttpClientHandler { AllowAutoRedirect = true }) { Timeout = TimeSpan.FromSeconds(30) };

    public AppUpdateService()
    {
        _http.DefaultRequestHeaders.UserAgent.ParseAdd($"CodexRadarSentinel-Windows/{CurrentVersion}");
        CleanupStaleWorkDirectories();
    }
    public static string CurrentVersion
    {
        get
        {
            var informational = Assembly.GetExecutingAssembly()
                .GetCustomAttribute<AssemblyInformationalVersionAttribute>()?.InformationalVersion.Split('+')[0];
            if (informational is not null && Regex.IsMatch(informational, @"^\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?$"))
                return informational;
            return Assembly.GetExecutingAssembly().GetName().Version is { } version
                ? $"{version.Major}.{version.Minor}.{version.Build}" : "0.1.48";
        }
    }
    public static string Runtime => RuntimeInformation.OSArchitecture switch
    {
        Architecture.X64 => "win-x64", Architecture.Arm64 => "win-arm64",
        _ => throw new PlatformNotSupportedException("Only Windows x64 and arm64 packages are supported.")
    };
    public static string ArchitectureLabel => Runtime[4..];

    public async Task<AppUpdateInfo?> FindUpdateAsync(CancellationToken cancellationToken)
    {
        var current = SemanticVersion.Parse(CurrentVersion);
        try
        {
            using var response = await _http.GetAsync(LatestApiUrl, cancellationToken);
            response.EnsureSuccessStatusCode();
            using var release = JsonDocument.Parse(await response.Content.ReadAsStringAsync(cancellationToken));
            var root = release.RootElement;
            if (root.Bool("draft") == true || root.Bool("prerelease") == true) return null;
            var tag = root.String("tag_name") ?? throw new InvalidDataException("GitHub release tag is missing.");
            var latest = SemanticVersion.Parse(tag);
            if (latest <= current) return null;
            var expectedBase = $"CodexRadarSentinel-{latest}-Windows-{ArchitectureLabel}";
            var zipName = expectedBase + ".zip";
            var checksumName = expectedBase + ".sha256";
            var assets = root.Array("assets") ?? throw new InvalidDataException("GitHub release assets are missing.");
            var parsed = assets.EnumerateArray().Select(asset => new ReleaseAsset(asset.String("name") ?? "",
                new Uri(asset.String("browser_download_url") ?? "about:blank"))).ToArray();
            var zip = parsed.SingleOrDefault(asset => asset.Name.Equals(zipName, StringComparison.OrdinalIgnoreCase));
            var checksum = parsed.SingleOrDefault(asset => asset.Name.Equals(checksumName, StringComparison.OrdinalIgnoreCase));
            if (zip is null || checksum is null) throw new InvalidDataException(
                $"Release {latest} does not contain the exact {ArchitectureLabel} Windows package and checksum.");
            EnsureWindowsAsset(zip.Name); EnsureWindowsAsset(checksum.Name);
            EnsureGitHubAssetUri(zip.DownloadUrl); EnsureGitHubAssetUri(checksum.DownloadUrl);
            return new AppUpdateInfo(latest.ToString(), new Uri(root.String("html_url") ?? LatestReleaseUrl),
                root.String("body"), zip, checksum, Runtime);
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
        {
            throw;
        }
        catch
        {
            return await FindUpdateFromRedirectAsync(current, cancellationToken);
        }
    }

    private async Task<AppUpdateInfo?> FindUpdateFromRedirectAsync(SemanticVersion current, CancellationToken cancellationToken)
    {
        using var response = await _http.GetAsync(LatestReleaseUrl, HttpCompletionOption.ResponseHeadersRead, cancellationToken);
        response.EnsureSuccessStatusCode();
        var final = response.RequestMessage?.RequestUri ?? throw new InvalidDataException("Latest release redirect is missing.");
        var tag = final.Segments.LastOrDefault()?.Trim('/') ?? throw new InvalidDataException("Latest release tag is missing.");
        var latest = SemanticVersion.Parse(tag);
        if (latest <= current) return null;
        var baseName = $"CodexRadarSentinel-{latest}-Windows-{ArchitectureLabel}";
        var download = new Uri($"{RepositoryUrl}/releases/download/{tag}/");
        var zip = new ReleaseAsset(baseName + ".zip", new Uri(download, baseName + ".zip"));
        var checksum = new ReleaseAsset(baseName + ".sha256", new Uri(download, baseName + ".sha256"));
        EnsureWindowsAsset(zip.Name); EnsureWindowsAsset(checksum.Name);
        EnsureGitHubAssetUri(zip.DownloadUrl); EnsureGitHubAssetUri(checksum.DownloadUrl);
        return new AppUpdateInfo(latest.ToString(), final, null, zip, checksum, Runtime);
    }

    public async Task LaunchInstallAsync(AppUpdateInfo update, CancellationToken cancellationToken)
    {
        EnsureWindowsAsset(update.Zip.Name); EnsureWindowsAsset(update.Checksum.Name);
        var currentExe = Environment.ProcessPath ?? throw new InvalidOperationException("Current executable path is unavailable.");
        var installRoot = Path.GetFullPath(Path.GetDirectoryName(currentExe)
                                           ?? throw new InvalidOperationException("Current installation directory is unavailable."));
        await ValidateInstalledCopyAsync(installRoot, currentExe, cancellationToken);

        var work = Path.Combine(Path.GetTempPath(), "codex-radar-update-" + Guid.NewGuid().ToString("N"));
        var extract = Path.Combine(work, "extract");
        Directory.CreateDirectory(extract);
        var zipPath = Path.Combine(work, update.Zip.Name);
        var checksumPath = Path.Combine(work, update.Checksum.Name);
        await DownloadAsync(update.Zip.DownloadUrl, zipPath, cancellationToken);
        await DownloadAsync(update.Checksum.DownloadUrl, checksumPath, cancellationToken);
        var expected = ExpectedChecksum(await File.ReadAllTextAsync(checksumPath, cancellationToken), update.Zip.Name);
        var actual = await Sha256Async(zipPath, cancellationToken);
        if (!actual.Equals(expected, StringComparison.OrdinalIgnoreCase)) throw new InvalidDataException("Windows update SHA256 mismatch.");
        ExtractSafely(zipPath, extract);
        var manifestPath = Path.Combine(extract, "release-manifest.json");
        if (!File.Exists(manifestPath)) throw new InvalidDataException("Windows release manifest is missing from the package root.");
        using var manifest = JsonDocument.Parse(await File.ReadAllTextAsync(manifestPath, cancellationToken));
        ValidateManifest(manifest.RootElement, update);
        var executableName = manifest.RootElement.String("executable")!;
        var sourceExe = Path.Combine(extract, executableName);
        if (!File.Exists(sourceExe)) throw new InvalidDataException("Windows executable is missing from the package root.");
        var manifestExeHash = manifest.RootElement.String("executable_sha256")!;
        var exeHash = await Sha256Async(sourceExe, cancellationToken);
        if (!exeHash.Equals(manifestExeHash, StringComparison.OrdinalIgnoreCase))
            throw new InvalidDataException("Windows executable checksum does not match release-manifest.json.");
        ValidatePeArchitecture(sourceExe);
        var uninstaller = Path.Combine(extract, manifest.RootElement.String("uninstaller")!);
        if (!File.Exists(uninstaller) || !string.Equals(await Sha256Async(uninstaller, cancellationToken),
                manifest.RootElement.String("uninstaller_sha256"), StringComparison.OrdinalIgnoreCase))
            throw new InvalidDataException("Windows uninstaller checksum does not match release-manifest.json.");
        var fileVersion = FileVersionInfo.GetVersionInfo(sourceExe).ProductVersion?.Split('+')[0];
        if (string.IsNullOrWhiteSpace(fileVersion))
            throw new InvalidDataException("Package executable version is missing.");
        if (SemanticVersion.Parse(fileVersion).ToString() != SemanticVersion.Parse(update.Version).ToString())
            throw new InvalidDataException($"Package executable version {fileVersion} does not match release {update.Version}.");
        var script = WriteHelperScript(work);
        var expectedTarget = Path.Combine(installRoot, executableName);
        if (!Path.GetFullPath(currentExe).Equals(Path.GetFullPath(expectedTarget), StringComparison.OrdinalIgnoreCase))
            throw new InvalidOperationException($"Installed executable must be named {executableName}.");
        var backup = installRoot + ".previous";
        var log = Path.Combine(work, "install.log");
        var powerShell = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Windows),
            "System32", "WindowsPowerShell", "v1.0", "powershell.exe");
        if (!File.Exists(powerShell)) throw new FileNotFoundException("The system Windows PowerShell executable is missing.", powerShell);
        var process = new ProcessStartInfo
        {
            FileName = powerShell, UseShellExecute = false, CreateNoWindow = true, WindowStyle = ProcessWindowStyle.Hidden
        };
        process.WorkingDirectory = Path.GetTempPath();
        foreach (var argument in new[] { "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-File", script,
                     Process.GetCurrentProcess().Id.ToString(CultureInfo.InvariantCulture), extract, installRoot, backup,
                     executableName, log, work, exeHash, AppSettings.InstallerFailureMarkerPath, update.Version })
            process.ArgumentList.Add(argument);
        _ = Process.Start(process) ?? throw new InvalidOperationException("Could not launch the Windows update helper.");
    }

    private async Task DownloadAsync(Uri url, string destination, CancellationToken cancellationToken)
    {
        using var response = await _http.GetAsync(url, HttpCompletionOption.ResponseHeadersRead, cancellationToken);
        response.EnsureSuccessStatusCode();
        await using var source = await response.Content.ReadAsStreamAsync(cancellationToken);
        await using var target = File.Create(destination);
        await source.CopyToAsync(target, cancellationToken);
    }

    private static void ValidateManifest(JsonElement manifest, AppUpdateInfo update)
    {
        if (manifest.Int32("schema_version") != 1 || !string.Equals(manifest.String("product"), "CodexRadarSentinel", StringComparison.Ordinal))
            throw new InvalidDataException("Unsupported Windows release manifest schema or product.");
        if (!string.Equals(manifest.String("platform"), "windows", StringComparison.OrdinalIgnoreCase))
            throw new InvalidDataException("Release manifest is not a Windows package.");
        if (!string.Equals(manifest.String("runtime", "rid"), update.Runtime, StringComparison.OrdinalIgnoreCase))
            throw new InvalidDataException($"Release manifest runtime does not match {update.Runtime}.");
        if (!string.Equals(manifest.String("architecture"), ArchitectureLabel, StringComparison.OrdinalIgnoreCase))
            throw new InvalidDataException($"Release manifest architecture does not match {ArchitectureLabel}.");
        var version = manifest.String("version");
        if (string.IsNullOrWhiteSpace(version) || SemanticVersion.Parse(version).ToString() != SemanticVersion.Parse(update.Version).ToString())
            throw new InvalidDataException("Release manifest version mismatch.");
        if (manifest.Bool("framework_dependent") is not false)
            throw new InvalidDataException("Windows updates must be self-contained.");
        if (manifest.Int32("minimum_windows_build") is not { } minimumBuild || minimumBuild < 17763 || Environment.OSVersion.Version.Build < minimumBuild)
            throw new PlatformNotSupportedException("This update does not support the current Windows build.");
        if (!string.Equals(manifest.String("executable"), "CodexRadarSentinel.exe", StringComparison.Ordinal))
            throw new InvalidDataException("Release manifest has an unexpected Windows executable name.");
        if (!string.Equals(manifest.String("uninstaller"), "uninstall.ps1", StringComparison.Ordinal))
            throw new InvalidDataException("Release manifest has an unexpected Windows uninstaller name.");
        foreach (var field in new[] { "executable_sha256", "uninstaller_sha256" })
            if (manifest.String(field) is not { } hash || !Regex.IsMatch(hash, "^[a-fA-F0-9]{64}$"))
                throw new InvalidDataException($"Release manifest field {field} is missing or invalid.");
    }

    private static async Task ValidateInstalledCopyAsync(string installRoot, string currentExe, CancellationToken cancellationToken)
    {
        if (installRoot.TrimEnd(Path.DirectorySeparatorChar)
            .Equals(Path.GetPathRoot(installRoot)?.TrimEnd(Path.DirectorySeparatorChar), StringComparison.OrdinalIgnoreCase))
            throw new InvalidOperationException("Refusing to update an installation at a filesystem root.");
        if (!string.Equals(Path.GetFileName(currentExe), "CodexRadarSentinel.exe", StringComparison.Ordinal))
            throw new InvalidOperationException("Automatic updates require an installed CodexRadarSentinel.exe package.");
        var allowed = new HashSet<string>(StringComparer.Ordinal)
            { "CodexRadarSentinel.exe", "uninstall.ps1", "release-manifest.json" };
        var entries = Directory.EnumerateFileSystemEntries(installRoot, "*", SearchOption.TopDirectoryOnly).ToArray();
        if (entries.Length != allowed.Count || entries.Any(entry => !File.Exists(entry) || !allowed.Contains(Path.GetFileName(entry))))
            throw new InvalidDataException("The installed directory contains unexpected files and cannot be replaced safely.");
        var manifestPath = Path.Combine(installRoot, "release-manifest.json");
        if (!File.Exists(manifestPath))
            throw new InvalidOperationException("Automatic updates require the installed Windows release manifest. Use windows/install.ps1 first.");
        using var document = JsonDocument.Parse(await File.ReadAllTextAsync(manifestPath, cancellationToken));
        var manifest = document.RootElement;
        if (manifest.Int32("schema_version") != 1
            || !string.Equals(manifest.String("product"), "CodexRadarSentinel", StringComparison.Ordinal)
            || !string.Equals(manifest.String("platform"), "windows", StringComparison.OrdinalIgnoreCase)
            || !string.Equals(manifest.String("runtime"), Runtime, StringComparison.OrdinalIgnoreCase)
            || !string.Equals(manifest.String("architecture"), ArchitectureLabel, StringComparison.OrdinalIgnoreCase)
            || !string.Equals(manifest.String("executable"), "CodexRadarSentinel.exe", StringComparison.Ordinal))
            throw new InvalidDataException("The installed release manifest is not a matching Windows package.");
        var expectedHash = manifest.String("executable_sha256");
        if (expectedHash is null || !Regex.IsMatch(expectedHash, "^[a-fA-F0-9]{64}$")
            || !string.Equals(await Sha256Async(currentExe, cancellationToken), expectedHash, StringComparison.OrdinalIgnoreCase))
            throw new InvalidDataException("The installed executable no longer matches its release manifest.");
        var uninstaller = Path.Combine(installRoot, "uninstall.ps1");
        var expectedUninstallerHash = manifest.String("uninstaller_sha256");
        if (!File.Exists(uninstaller) || expectedUninstallerHash is null
            || !Regex.IsMatch(expectedUninstallerHash, "^[a-fA-F0-9]{64}$")
            || !string.Equals(await Sha256Async(uninstaller, cancellationToken), expectedUninstallerHash, StringComparison.OrdinalIgnoreCase))
            throw new InvalidDataException("The installed uninstaller no longer matches its release manifest.");
    }

    private static void ExtractSafely(string archive, string destination)
    {
        var root = Path.GetFullPath(destination) + Path.DirectorySeparatorChar;
        var allowed = new HashSet<string>(StringComparer.Ordinal)
            { "CodexRadarSentinel.exe", "uninstall.ps1", "release-manifest.json" };
        var seen = new HashSet<string>(StringComparer.Ordinal);
        using var zip = ZipFile.OpenRead(archive);
        foreach (var entry in zip.Entries)
        {
            var entryName = entry.FullName.Replace('\\', '/');
            if (!allowed.Contains(entryName) || !seen.Add(entryName))
                throw new InvalidDataException($"Unexpected, nested, or duplicate file in Windows update archive: {entryName}");
            var target = Path.GetFullPath(Path.Combine(destination, entry.FullName));
            if (!target.StartsWith(root, StringComparison.OrdinalIgnoreCase)) throw new InvalidDataException("Unsafe path in Windows update archive.");
        }
        if (seen.Count != allowed.Count) throw new InvalidDataException("Windows update archive does not contain exactly the required release files.");
        ZipFile.ExtractToDirectory(archive, destination, true);
    }

    private static string WriteHelperScript(string directory)
    {
        var path = Path.Combine(directory, "install-update.ps1");
        File.WriteAllText(path, """
param([int]$ParentPid,[string]$SourceRoot,[string]$TargetRoot,[string]$BackupRoot,[string]$ExecutableName,[string]$Log,[string]$WorkRoot,[string]$ExpectedExeHash,[string]$FailureMarker,[string]$UpdateVersion)
$ErrorActionPreference = 'Stop'
$TranscriptStarted = $false
$TargetWasMoved = $false
try {
  Start-Transcript -Path $Log -Force | Out-Null
  $TranscriptStarted = $true
  for ($i = 0; $i -lt 100; $i++) {
    if (-not (Get-Process -Id $ParentPid -ErrorAction SilentlyContinue)) { break }
    Start-Sleep -Milliseconds 200
  }
  if (Get-Process -Id $ParentPid -ErrorAction SilentlyContinue) { throw 'Application did not exit in time.' }
  if (Test-Path -LiteralPath $BackupRoot) { Remove-Item -LiteralPath $BackupRoot -Recurse -Force }
  if (Test-Path -LiteralPath $TargetRoot) {
    Move-Item -LiteralPath $TargetRoot -Destination $BackupRoot -Force
    $TargetWasMoved = $true
  }
  Copy-Item -LiteralPath $SourceRoot -Destination $TargetRoot -Recurse -Force
  $TargetExe = Join-Path $TargetRoot $ExecutableName
  if (-not (Test-Path -LiteralPath $TargetExe)) { throw 'Updated executable is missing.' }
  $InstalledHash = (Get-FileHash -LiteralPath $TargetExe -Algorithm SHA256).Hash.ToLowerInvariant()
  if ($InstalledHash -ne $ExpectedExeHash.ToLowerInvariant()) { throw 'Updated executable checksum verification failed.' }
  Start-Process -FilePath $TargetExe -ArgumentList '--updated' -WindowStyle Hidden
  try { if (Test-Path -LiteralPath $SourceRoot) { Remove-Item -LiteralPath $SourceRoot -Recurse -Force } } catch {}
  try {
    Get-ChildItem -LiteralPath $WorkRoot -File | Where-Object { $_.Extension -in @('.zip', '.sha256') } | Remove-Item -Force
  } catch {}
  if ($TranscriptStarted) { Stop-Transcript | Out-Null }
  exit 0
} catch {
  try { $_ | Out-String | Add-Content -LiteralPath $Log } catch {}
  try {
    $MarkerDirectory = Split-Path -Parent $FailureMarker
    New-Item -ItemType Directory -Path $MarkerDirectory -Force | Out-Null
    $MarkerTemp = "$FailureMarker.$PID.tmp"
    @{ version = $UpdateVersion; occurred_at = [DateTimeOffset]::UtcNow.ToString('O') } | ConvertTo-Json -Compress | Set-Content -LiteralPath $MarkerTemp -Encoding UTF8
    Move-Item -LiteralPath $MarkerTemp -Destination $FailureMarker -Force
  } catch {}
  if ($TargetWasMoved) {
    try { if (Test-Path -LiteralPath $TargetRoot) { Remove-Item -LiteralPath $TargetRoot -Recurse -Force } } catch {}
    try { if (Test-Path -LiteralPath $BackupRoot) { Move-Item -LiteralPath $BackupRoot -Destination $TargetRoot -Force } } catch {}
  }
  if ($TranscriptStarted) { try { Stop-Transcript | Out-Null } catch {} }
  $RecoveredExe = Join-Path $TargetRoot $ExecutableName
  if (-not (Get-Process -Id $ParentPid -ErrorAction SilentlyContinue) -and (Test-Path -LiteralPath $RecoveredExe)) {
    try { Start-Process -FilePath $RecoveredExe -ArgumentList '--update-recovered' -WindowStyle Hidden } catch {}
  }
  exit 1
}
""", new System.Text.UTF8Encoding(false));
        return path;
    }

    private static string ExpectedChecksum(string text, string asset)
    {
        foreach (var line in text.Split(new[] { '\r', '\n' }, StringSplitOptions.RemoveEmptyEntries))
        {
            var columns = Regex.Split(line.Trim(), @"\s+");
            if (columns.Length >= 2 && Path.GetFileName(columns[1].TrimStart('*')) == asset && Regex.IsMatch(columns[0], "^[a-fA-F0-9]{64}$"))
                return columns[0];
        }
        throw new InvalidDataException($"Checksum for {asset} is missing.");
    }
    private static async Task<string> Sha256Async(string path, CancellationToken cancellationToken)
    {
        await using var stream = File.OpenRead(path);
        var hash = await SHA256.HashDataAsync(stream, cancellationToken);
        return Convert.ToHexString(hash).ToLowerInvariant();
    }
    private static void ValidatePeArchitecture(string path)
    {
        using var stream = File.OpenRead(path);
        using var reader = new PEReader(stream);
        var expected = RuntimeInformation.OSArchitecture == Architecture.Arm64
            ? System.Reflection.PortableExecutable.Machine.Arm64
            : System.Reflection.PortableExecutable.Machine.Amd64;
        if (reader.PEHeaders.CoffHeader.Machine != expected)
            throw new InvalidDataException($"Package executable PE architecture does not match {ArchitectureLabel}.");
    }
    internal static void EnsureWindowsAsset(string name)
    {
        var expected = $@"^CodexRadarSentinel-\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?-Windows-{Regex.Escape(ArchitectureLabel)}\.(?:zip|sha256)$";
        if (!Regex.IsMatch(name, expected, RegexOptions.IgnoreCase) || name.Contains("macOS", StringComparison.OrdinalIgnoreCase))
            throw new InvalidDataException($"Refusing non-Windows or wrong-architecture release asset: {name}");
    }
    internal static void EnsureGitHubAssetUri(Uri uri)
    {
        if (uri.Scheme != Uri.UriSchemeHttps || !uri.Host.Equals("github.com", StringComparison.OrdinalIgnoreCase)
            || !uri.AbsolutePath.StartsWith("/WineChord/codex-radar/releases/download/", StringComparison.OrdinalIgnoreCase))
            throw new InvalidDataException($"Refusing unexpected update download URL: {uri}");
    }
    private static void CleanupStaleWorkDirectories()
    {
        try
        {
            var temporaryRoot = Path.GetFullPath(Path.GetTempPath()).TrimEnd(Path.DirectorySeparatorChar) + Path.DirectorySeparatorChar;
            foreach (var directory in Directory.EnumerateDirectories(temporaryRoot, "codex-radar-update-*", SearchOption.TopDirectoryOnly))
            {
                var fullPath = Path.GetFullPath(directory);
                if (!fullPath.StartsWith(temporaryRoot, StringComparison.OrdinalIgnoreCase)
                    || !Path.GetFileName(fullPath).StartsWith("codex-radar-update-", StringComparison.Ordinal)
                    || DateTime.UtcNow - Directory.GetLastWriteTimeUtc(fullPath) < TimeSpan.FromDays(2)) continue;
                try { Directory.Delete(fullPath, true); } catch { }
            }
        }
        catch { }
    }
    public void Dispose() => _http.Dispose();
}

internal readonly record struct SemanticVersion(int Major, int Minor, int Patch, string? Prerelease = null) : IComparable<SemanticVersion>
{
    public static SemanticVersion Parse(string raw)
    {
        var value = raw.Trim().TrimStart('v', 'V');
        if (value.Contains('+')) throw new FormatException($"Build metadata is not allowed in release versions: {raw}");
        var match = Regex.Match(value, @"^(\d+)\.(\d+)\.(\d+)(?:-([0-9A-Za-z.-]+))?$");
        if (!match.Success) throw new FormatException($"Invalid semantic version: {raw}");
        return new SemanticVersion(int.Parse(match.Groups[1].Value), int.Parse(match.Groups[2].Value),
            int.Parse(match.Groups[3].Value), match.Groups[4].Success ? match.Groups[4].Value : null);
    }
    public int CompareTo(SemanticVersion other)
    {
        var core = Major.CompareTo(other.Major); if (core != 0) return core;
        core = Minor.CompareTo(other.Minor); if (core != 0) return core;
        core = Patch.CompareTo(other.Patch); if (core != 0) return core;
        if (Prerelease is null && other.Prerelease is not null) return 1;
        if (Prerelease is not null && other.Prerelease is null) return -1;
        return string.CompareOrdinal(Prerelease, other.Prerelease);
    }
    public static bool operator >(SemanticVersion left, SemanticVersion right) => left.CompareTo(right) > 0;
    public static bool operator <(SemanticVersion left, SemanticVersion right) => left.CompareTo(right) < 0;
    public static bool operator <=(SemanticVersion left, SemanticVersion right) => left.CompareTo(right) <= 0;
    public static bool operator >=(SemanticVersion left, SemanticVersion right) => left.CompareTo(right) >= 0;
    public override string ToString() => $"{Major}.{Minor}.{Patch}{(Prerelease is null ? "" : $"-{Prerelease}")}";
}
