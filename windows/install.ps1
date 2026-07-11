[CmdletBinding()]
param(
    [ValidateSet("auto", "win-x64", "win-arm64")]
    [string]$Runtime = "auto",
    [string]$InstallDir,
    [switch]$StartWithWindows
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"
$Repository = "WineChord/codex-radar"
$ProductName = "Codex Radar Sentinel"
$RunValueName = "Codex Radar Sentinel"
$RunKeyPath = "Software\Microsoft\Windows\CurrentVersion\Run"
$MinimumWindowsBuild = 17763
$DetectedWindowsBuild = 0

function Get-WindowsBuildNumber {
    $key = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey("SOFTWARE\Microsoft\Windows NT\CurrentVersion", $false)
    if ($null -ne $key) {
        try {
            $raw = [string]$key.GetValue("CurrentBuildNumber", "")
            $build = 0
            if ([int]::TryParse($raw, [ref]$build) -and $build -gt 0) {
                return $build
            }
        }
        finally {
            $key.Dispose()
        }
    }
    return [Environment]::OSVersion.Version.Build
}

function Assert-WindowsPlatform {
    if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) {
        throw "This installer is Windows-only. It will not download or install a macOS asset."
    }

    $script:DetectedWindowsBuild = Get-WindowsBuildNumber
    if ($DetectedWindowsBuild -lt $MinimumWindowsBuild) {
        throw "Windows 10 version 1809 (build $MinimumWindowsBuild) or newer is required. Detected build $DetectedWindowsBuild."
    }
}

function Get-NativeRuntime {
    $architecture = [Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString().ToLowerInvariant()
    switch ($architecture) {
        "x64" { return "win-x64" }
        "arm64" { return "win-arm64" }
        default { throw "Unsupported Windows architecture '$architecture'. Only x64 and ARM64 packages are published." }
    }
}

function Get-SafeDirectoryPath {
    param([Parameter(Mandatory = $true)][string]$Path)

    $resolved = [IO.Path]::GetFullPath($Path).TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
    $root = [IO.Path]::GetPathRoot($resolved).TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
    if ([string]::IsNullOrWhiteSpace($resolved) -or $resolved.Equals($root, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to use a filesystem root as the installation directory: $Path"
    }
    return $resolved
}

function Test-PathInsideDirectory {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Directory
    )

    $parent = [IO.Path]::GetFullPath($Directory).TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
    return [IO.Path]::GetFullPath($Path).StartsWith($parent, [StringComparison]::OrdinalIgnoreCase)
}

function Invoke-Download {
    param(
        [Parameter(Mandatory = $true)][string]$Uri,
        [Parameter(Mandatory = $true)][string]$OutFile,
        [Parameter(Mandatory = $true)][hashtable]$Headers
    )

    Invoke-WebRequest -Uri $Uri -Headers $Headers -OutFile $OutFile -UseBasicParsing -TimeoutSec 600
    if (-not (Test-Path -LiteralPath $OutFile -PathType Leaf)) {
        throw "Download completed without creating $OutFile"
    }
}

function Get-VerifiedGitHubAssetUri {
    param([Parameter(Mandatory = $true)][string]$Value)

    $uri = $null
    if (-not [Uri]::TryCreate($Value, [UriKind]::Absolute, [ref]$uri) -or
        -not $uri.Scheme.Equals("https", [StringComparison]::OrdinalIgnoreCase) -or
        -not $uri.Host.Equals("github.com", [StringComparison]::OrdinalIgnoreCase) -or
        -not $uri.AbsolutePath.StartsWith("/WineChord/codex-radar/releases/download/", [StringComparison]::OrdinalIgnoreCase)) {
        throw "Release metadata contains an unexpected asset download URL."
    }
    return $uri
}

function Get-HashFromChecksumFile {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$ArchiveName
    )

    $matchingHashes = @()
    foreach ($rawLine in [IO.File]::ReadAllLines($Path)) {
        $line = $rawLine.Trim().TrimStart([char]0xFEFF)
        if ($line -match '^([0-9A-Fa-f]{64})$') {
            $matchingHashes += $Matches[1].ToLowerInvariant()
            continue
        }
        if ($line -match '^([0-9A-Fa-f]{64})\s+\*?(.+?)\s*$') {
            $listedName = [IO.Path]::GetFileName($Matches[2].Replace('/', '\'))
            if ($listedName.Equals($ArchiveName, [StringComparison]::Ordinal)) {
                $matchingHashes += $Matches[1].ToLowerInvariant()
            }
        }
    }

    if ($matchingHashes.Count -ne 1) {
        throw "The checksum asset does not contain exactly one SHA256 entry for $ArchiveName."
    }
    return $matchingHashes[0]
}

function Expand-VerifiedWindowsPackage {
    param(
        [Parameter(Mandatory = $true)][string]$Archive,
        [Parameter(Mandatory = $true)][string]$Destination
    )

    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $allowedEntries = @("CodexRadarSentinel.exe", "uninstall.ps1", "release-manifest.json")
    $seenEntries = @{}
    $destinationRoot = [IO.Path]::GetFullPath($Destination).TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
    $zip = [IO.Compression.ZipFile]::OpenRead($Archive)
    try {
        foreach ($entry in $zip.Entries) {
            $entryName = $entry.FullName.Replace('\', '/')
            $target = [IO.Path]::GetFullPath((Join-Path $Destination $entryName))
            if (-not $target.StartsWith($destinationRoot, [StringComparison]::OrdinalIgnoreCase)) {
                throw "Windows package contains an unsafe path: $entryName"
            }
            $isAllowed = $false
            foreach ($allowed in $allowedEntries) {
                if ($entryName.Equals($allowed, [StringComparison]::Ordinal)) {
                    $isAllowed = $true
                    break
                }
            }
            if (-not $isAllowed) {
                throw "Windows package contains an unexpected or non-Windows entry: $entryName"
            }
            if ($seenEntries.ContainsKey($entryName)) {
                throw "Windows package contains a duplicate entry: $entryName"
            }
            $seenEntries[$entryName] = $true
        }
    }
    finally {
        $zip.Dispose()
    }
    if ($seenEntries.Count -ne $allowedEntries.Count) {
        throw "Windows package does not contain exactly the required release files."
    }
    Expand-Archive -LiteralPath $Archive -DestinationPath $Destination -Force
}

function Get-PeArchitecture {
    param([Parameter(Mandatory = $true)][string]$Path)

    $stream = [IO.File]::Open($Path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
    $reader = New-Object IO.BinaryReader($stream)
    try {
        if ($stream.Length -lt 70 -or $reader.ReadUInt16() -ne 0x5A4D) {
            throw "Packaged executable is not a valid Windows PE file."
        }
        $stream.Position = 0x3C
        $peOffset = $reader.ReadInt32()
        if ($peOffset -lt 64 -or $peOffset -gt ($stream.Length - 6)) {
            throw "Packaged executable has an invalid PE header offset."
        }
        $stream.Position = $peOffset
        if ($reader.ReadUInt32() -ne 0x00004550) {
            throw "Packaged executable has an invalid PE signature."
        }
        switch ($reader.ReadUInt16()) {
            0x8664 { return "x64" }
            0xAA64 { return "arm64" }
            default { throw "Packaged executable uses an unsupported PE architecture."
            }
        }
    }
    finally {
        $reader.Dispose()
        $stream.Dispose()
    }
}

function Get-InstalledProcesses {
    param([Parameter(Mandatory = $true)][string]$Directory)

    $result = @()
    foreach ($name in @("CodexRadarSentinel", "CodexRadar.Windows")) {
        foreach ($process in @(Get-Process -Name $name -ErrorAction SilentlyContinue)) {
            try {
                if ($process.Path -and (Test-PathInsideDirectory -Path $process.Path -Directory $Directory)) {
                    $result += $process
                }
            }
            catch {
                # A process owned by another user cannot be this HKCU installation.
            }
        }
    }
    return $result
}

function Test-ExistingInstallation {
    param([Parameter(Mandatory = $true)][string]$Directory)

    if (-not (Test-Path -LiteralPath $Directory)) {
        return $true
    }
    if (-not (Test-Path -LiteralPath $Directory -PathType Container)) {
        return $false
    }

    $newExecutable = Join-Path $Directory "CodexRadarSentinel.exe"
    $legacyExecutable = Join-Path $Directory "CodexRadar.Windows.exe"
    $hasExecutable = (Test-Path -LiteralPath $newExecutable -PathType Leaf) -or
        (Test-Path -LiteralPath $legacyExecutable -PathType Leaf)
    if (-not $hasExecutable) {
        return $false
    }

    $manifestPath = Join-Path $Directory "release-manifest.json"
    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
        $defaultDirectory = [IO.Path]::GetFullPath((Join-Path $env:LOCALAPPDATA "Programs\CodexRadarSentinel")).TrimEnd([IO.Path]::DirectorySeparatorChar)
        if (-not $Directory.Equals($defaultDirectory, [StringComparison]::OrdinalIgnoreCase)) {
            return $false
        }
        $legacyAllowed = @("CodexRadarSentinel.exe", "CodexRadar.Windows.exe", "uninstall.ps1")
        $legacyEntries = @(Get-ChildItem -LiteralPath $Directory -Force)
        if ($legacyEntries.Count -eq 0 -or @($legacyEntries | Where-Object { $_.PSIsContainer -or $_.Name -notin $legacyAllowed }).Count -gt 0) {
            return $false
        }
        return $true
    }
    try {
        $manifest = [IO.File]::ReadAllText($manifestPath) | ConvertFrom-Json
        $allowed = @("CodexRadarSentinel.exe", "uninstall.ps1", "release-manifest.json")
        $entries = @(Get-ChildItem -LiteralPath $Directory -Force)
        return ([string]$manifest.product).Equals("CodexRadarSentinel", [StringComparison]::Ordinal) -and
            ([string]$manifest.platform).Equals("windows", [StringComparison]::OrdinalIgnoreCase) -and
            $entries.Count -eq $allowed.Count -and
            @($entries | Where-Object { $_.PSIsContainer -or $_.Name -notin $allowed }).Count -eq 0
    }
    catch {
        return $false
    }
}

function Get-StartupSnapshot {
    $snapshot = [ordered]@{ Exists = $false; Value = $null; Kind = [Microsoft.Win32.RegistryValueKind]::String }
    $key = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey($RunKeyPath, $false)
    if ($null -eq $key) {
        return $snapshot
    }
    try {
        if ($key.GetValueNames() -contains $RunValueName) {
            $snapshot.Exists = $true
            $snapshot.Value = $key.GetValue($RunValueName, $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
            $snapshot.Kind = $key.GetValueKind($RunValueName)
        }
    }
    finally {
        $key.Dispose()
    }
    return $snapshot
}

function Set-StartupValue {
    param([Parameter(Mandatory = $true)][string]$Executable)

    $key = [Microsoft.Win32.Registry]::CurrentUser.CreateSubKey($RunKeyPath)
    try {
        $key.SetValue($RunValueName, ('"{0}" --startup' -f $Executable), [Microsoft.Win32.RegistryValueKind]::String)
    }
    finally {
        $key.Dispose()
    }
}

function Restore-StartupSnapshot {
    param([Parameter(Mandatory = $true)]$Snapshot)

    $key = [Microsoft.Win32.Registry]::CurrentUser.CreateSubKey($RunKeyPath)
    try {
        if ($Snapshot.Exists) {
            $key.SetValue($RunValueName, $Snapshot.Value, $Snapshot.Kind)
        }
        else {
            $key.DeleteValue($RunValueName, $false)
        }
    }
    finally {
        $key.Dispose()
    }
}

function Get-RunCommandExecutable {
    param([string]$Command)

    if ([string]::IsNullOrWhiteSpace($Command)) {
        return $null
    }
    $trimmed = $Command.Trim()
    if ($trimmed.StartsWith('"')) {
        $closingQuote = $trimmed.IndexOf('"', 1)
        if ($closingQuote -gt 1) {
            return $trimmed.Substring(1, $closingQuote - 1)
        }
        return $null
    }
    $match = [Regex]::Match($trimmed, '^(?<path>\S+\.exe)(?:\s|$)', [Text.RegularExpressions.RegexOptions]::IgnoreCase)
    if ($match.Success) {
        return $match.Groups['path'].Value
    }
    return $null
}

function Test-RunCommandForDirectory {
    param(
        [string]$Command,
        [Parameter(Mandatory = $true)][string]$Directory
    )

    $executable = Get-RunCommandExecutable -Command $Command
    if (-not $executable) {
        return $false
    }
    try {
        $leafName = [IO.Path]::GetFileName($executable)
        if ($leafName -notin @("CodexRadarSentinel.exe", "CodexRadar.Windows.exe")) {
            return $false
        }
        return Test-PathInsideDirectory -Path $executable -Directory $Directory
    }
    catch {
        return $false
    }
}

function New-StartMenuShortcut {
    param(
        [Parameter(Mandatory = $true)][string]$ShortcutPath,
        [Parameter(Mandatory = $true)][string]$Executable
    )

    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($ShortcutPath)
    $shortcut.TargetPath = $Executable
    $shortcut.WorkingDirectory = [IO.Path]::GetDirectoryName($Executable)
    $shortcut.IconLocation = "$Executable,0"
    $shortcut.Description = "Codex Radar Sentinel for Windows"
    $shortcut.Save()
    [Runtime.InteropServices.Marshal]::FinalReleaseComObject($shortcut) | Out-Null
    [Runtime.InteropServices.Marshal]::FinalReleaseComObject($shell) | Out-Null
}

$TempRoot = $null
$BackupPath = $null
$InstallWasReplaced = $false
$ShortcutWasChanged = $false
$StartupWasChanged = $false
$PriorWasRunning = $false
$NewProcess = $null
$Committed = $false
$StartupSnapshot = $null
$ShortcutPath = $null
$ShortcutBackup = $null
$ShortcutExisted = $false

try {
    Assert-WindowsPlatform

    if ([string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) {
        throw "LOCALAPPDATA is unavailable; cannot determine a non-administrator installation path."
    }
    if ([string]::IsNullOrWhiteSpace($InstallDir)) {
        $InstallDir = Join-Path $env:LOCALAPPDATA "Programs\CodexRadarSentinel"
    }
    $InstallDir = Get-SafeDirectoryPath -Path $InstallDir

    $NativeRuntime = Get-NativeRuntime
    if ($Runtime -eq "auto") {
        $Runtime = $NativeRuntime
    }
    elseif ($Runtime -ne $NativeRuntime) {
        throw "Requested runtime '$Runtime' does not match this computer ($NativeRuntime). Refusing the wrong architecture package."
    }
    $Architecture = if ($Runtime -eq "win-arm64") { "arm64" } else { "x64" }

    if (-not (Test-ExistingInstallation -Directory $InstallDir)) {
        throw "Refusing to replace '$InstallDir' because it is not a verified Codex Radar Sentinel installation."
    }

    $TempRoot = Join-Path ([IO.Path]::GetTempPath()) ("CodexRadar-install-{0}" -f [Guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Path $TempRoot | Out-Null
    $ArchivePath = Join-Path $TempRoot "package.zip"
    $ChecksumPath = Join-Path $TempRoot "package.sha256"
    $ExtractPath = Join-Path $TempRoot "extracted"
    New-Item -ItemType Directory -Path $ExtractPath | Out-Null

    if ([Net.ServicePointManager]::SecurityProtocol -band [Net.SecurityProtocolType]::Tls12 -eq 0) {
        [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    }
    $ApiHeaders = @{
        Accept = "application/vnd.github+json"
        "User-Agent" = "CodexRadarSentinel-Windows-Installer"
        "X-GitHub-Api-Version" = "2022-11-28"
    }
    if (-not [string]::IsNullOrWhiteSpace($env:GITHUB_TOKEN)) {
        $ApiHeaders.Authorization = "Bearer $env:GITHUB_TOKEN"
    }
    $DownloadHeaders = @{
        Accept = "application/octet-stream"
        "User-Agent" = "CodexRadarSentinel-Windows-Installer"
    }

    Write-Host "Reading the latest $Repository release..."
    $Release = Invoke-RestMethod -Uri "https://api.github.com/repos/$Repository/releases/latest" -Headers $ApiHeaders -TimeoutSec 30
    if ([bool]$Release.draft -or [bool]$Release.prerelease) {
        throw "The latest GitHub response is not a stable published release."
    }
    $VersionPattern = '\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?'
    $ArchivePattern = '^CodexRadarSentinel-(?<version>' + $VersionPattern + ')-Windows-' + [Regex]::Escape($Architecture) + '\.zip$'
    $ArchiveAssets = @($Release.assets | Where-Object { ([string]$_.name) -match $ArchivePattern })
    if ($ArchiveAssets.Count -ne 1) {
        throw "Latest release '$($Release.tag_name)' must contain exactly one '$Architecture' Windows asset named CodexRadarSentinel-{version}-Windows-$Architecture.zip. Found $($ArchiveAssets.Count)."
    }
    $ArchiveAsset = $ArchiveAssets[0]
    if (-not ([string]$ArchiveAsset.name -match $ArchivePattern)) {
        throw "Internal asset-selection error."
    }
    $PackageVersion = $Matches.version
    $NormalizedTag = ([string]$Release.tag_name) -replace '^v', ''
    if (-not $NormalizedTag.Equals($PackageVersion, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Windows asset version '$PackageVersion' does not match release tag '$($Release.tag_name)'."
    }
    $AssetBaseName = "CodexRadarSentinel-$PackageVersion-Windows-$Architecture"
    $ExpectedArchiveName = "$AssetBaseName.zip"
    $ExpectedChecksumName = "$AssetBaseName.sha256"
    if (-not ([string]$ArchiveAsset.name).Equals($ExpectedArchiveName, [StringComparison]::Ordinal)) {
        throw "Refusing non-canonical Windows asset '$($ArchiveAsset.name)'."
    }

    $ChecksumAssets = @($Release.assets | Where-Object { ([string]$_.name).Equals($ExpectedChecksumName, [StringComparison]::Ordinal) })
    if ($ChecksumAssets.Count -ne 1) {
        throw "Release must contain exactly one checksum asset named $ExpectedChecksumName. Found $($ChecksumAssets.Count)."
    }

    Write-Host "Downloading $ExpectedArchiveName..."
    $ArchiveUri = Get-VerifiedGitHubAssetUri -Value ([string]$ArchiveAsset.browser_download_url)
    Invoke-Download -Uri $ArchiveUri.AbsoluteUri -OutFile $ArchivePath -Headers $DownloadHeaders
    if ([long]$ArchiveAsset.size -gt 0 -and (Get-Item -LiteralPath $ArchivePath).Length -ne [long]$ArchiveAsset.size) {
        throw "Downloaded archive size does not match the GitHub release metadata."
    }

    $ExpectedHash = $null
    if ($ArchiveAsset.PSObject.Properties.Name -contains "digest" -and
        ([string]$ArchiveAsset.digest) -match '^sha256:([0-9A-Fa-f]{64})$') {
        $ExpectedHash = $Matches[1].ToLowerInvariant()
    }
    Write-Host "Downloading $ExpectedChecksumName..."
    $ChecksumUri = Get-VerifiedGitHubAssetUri -Value ([string]$ChecksumAssets[0].browser_download_url)
    Invoke-Download -Uri $ChecksumUri.AbsoluteUri -OutFile $ChecksumPath -Headers $DownloadHeaders
    $ChecksumHash = Get-HashFromChecksumFile -Path $ChecksumPath -ArchiveName $ExpectedArchiveName
    if ($ExpectedHash -and -not $ExpectedHash.Equals($ChecksumHash, [StringComparison]::OrdinalIgnoreCase)) {
        throw "GitHub's asset digest conflicts with the published checksum file."
    }
    $ExpectedHash = $ChecksumHash
    $ActualHash = (Get-FileHash -LiteralPath $ArchivePath -Algorithm SHA256).Hash.ToLowerInvariant()
    if (-not $ActualHash.Equals($ExpectedHash, [StringComparison]::OrdinalIgnoreCase)) {
        throw "SHA256 verification failed for $ExpectedArchiveName."
    }
    Write-Host "SHA256 verified: $ActualHash"

    Expand-VerifiedWindowsPackage -Archive $ArchivePath -Destination $ExtractPath
    $ManifestPath = Join-Path $ExtractPath "release-manifest.json"
    if (-not (Test-Path -LiteralPath $ManifestPath -PathType Leaf)) {
        throw "Package is missing the Windows release-manifest.json at its root."
    }
    $Manifest = [IO.File]::ReadAllText($ManifestPath) | ConvertFrom-Json
    if ([int]$Manifest.schema_version -ne 1 -or
        -not ([string]$Manifest.product).Equals("CodexRadarSentinel", [StringComparison]::Ordinal) -or
        -not ([string]$Manifest.platform).Equals("windows", [StringComparison]::OrdinalIgnoreCase) -or
        -not ([string]$Manifest.runtime).Equals($Runtime, [StringComparison]::OrdinalIgnoreCase) -or
        -not ([string]$Manifest.architecture).Equals($Architecture, [StringComparison]::OrdinalIgnoreCase) -or
        -not ([string]$Manifest.version).Equals($PackageVersion, [StringComparison]::OrdinalIgnoreCase) -or
        -not ([string]$Manifest.executable).Equals("CodexRadarSentinel.exe", [StringComparison]::Ordinal) -or
        -not ([string]$Manifest.uninstaller).Equals("uninstall.ps1", [StringComparison]::Ordinal) -or
        [bool]$Manifest.framework_dependent) {
        throw "Package manifest is not the expected self-contained Codex Radar Sentinel Windows/$Architecture release."
    }
    if ([int]$Manifest.minimum_windows_build -lt $MinimumWindowsBuild) {
        throw "Package manifest contains an invalid minimum Windows build."
    }
    if ($DetectedWindowsBuild -lt [int]$Manifest.minimum_windows_build) {
        throw "This package requires Windows build $($Manifest.minimum_windows_build) or newer."
    }

    $ExtractedExecutable = Join-Path $ExtractPath "CodexRadarSentinel.exe"
    $ExtractedUninstaller = Join-Path $ExtractPath "uninstall.ps1"
    if (-not (Test-Path -LiteralPath $ExtractedExecutable -PathType Leaf) -or
        -not (Test-Path -LiteralPath $ExtractedUninstaller -PathType Leaf)) {
        throw "Windows package is missing CodexRadarSentinel.exe or uninstall.ps1 at its root."
    }
    $ExecutableHash = (Get-FileHash -LiteralPath $ExtractedExecutable -Algorithm SHA256).Hash
    $UninstallerHash = (Get-FileHash -LiteralPath $ExtractedUninstaller -Algorithm SHA256).Hash
    if (-not $ExecutableHash.Equals([string]$Manifest.executable_sha256, [StringComparison]::OrdinalIgnoreCase) -or
        -not $UninstallerHash.Equals([string]$Manifest.uninstaller_sha256, [StringComparison]::OrdinalIgnoreCase)) {
        throw "A packaged file does not match the SHA256 recorded in the Windows manifest."
    }
    $PeArchitecture = Get-PeArchitecture -Path $ExtractedExecutable
    if (-not $PeArchitecture.Equals($Architecture, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Packaged executable architecture '$PeArchitecture' does not match this computer ($Architecture)."
    }
    $Signature = Get-AuthenticodeSignature -LiteralPath $ExtractedExecutable
    if ($Signature.Status -eq [System.Management.Automation.SignatureStatus]::Valid) {
        Write-Host "Authenticode signature valid: $($Signature.SignerCertificate.Subject)"
    }
    elseif ($Signature.Status -eq [System.Management.Automation.SignatureStatus]::NotSigned) {
        Write-Warning "This release is not Authenticode-signed. Trust is based on the exact GitHub release asset and its verified SHA256; Windows SmartScreen may ask for confirmation."
    }
    else {
        throw "The executable has a non-valid Authenticode signature: $($Signature.Status)."
    }
    $ProgramsDirectory = [Environment]::GetFolderPath([Environment+SpecialFolder]::Programs)
    if ([string]::IsNullOrWhiteSpace($ProgramsDirectory)) {
        throw "The current user's Start Menu Programs directory is unavailable."
    }
    $ShortcutPath = Join-Path $ProgramsDirectory "$ProductName.lnk"
    $ShortcutBackup = Join-Path $TempRoot "previous-shortcut.lnk"
    $ShortcutExisted = Test-Path -LiteralPath $ShortcutPath -PathType Leaf
    if ($ShortcutExisted) {
        Copy-Item -LiteralPath $ShortcutPath -Destination $ShortcutBackup
    }
    $StartupSnapshot = Get-StartupSnapshot
    $PreserveExistingStartup = $StartupSnapshot.Exists -and
        (Test-RunCommandForDirectory -Command ([string]$StartupSnapshot.Value) -Directory $InstallDir)

    $PriorProcesses = @(Get-InstalledProcesses -Directory $InstallDir)
    $PriorWasRunning = $PriorProcesses.Count -gt 0
    foreach ($process in $PriorProcesses) {
        Stop-Process -Id $process.Id -Force -ErrorAction Stop
        $process.WaitForExit(5000) | Out-Null
    }

    $InstallParent = Split-Path $InstallDir -Parent
    New-Item -ItemType Directory -Path $InstallParent -Force | Out-Null
    $BackupPath = Join-Path $InstallParent ("CodexRadarSentinel.rollback-{0}" -f [Guid]::NewGuid().ToString("N"))
    if (-not (Test-PathInsideDirectory -Path $BackupPath -Directory $InstallParent)) {
        throw "Computed rollback directory escaped the installation parent."
    }
    if (Test-Path -LiteralPath $InstallDir) {
        Move-Item -LiteralPath $InstallDir -Destination $BackupPath
    }
    New-Item -ItemType Directory -Path $InstallDir | Out-Null
    $InstallWasReplaced = $true

    Copy-Item -LiteralPath $ExtractedExecutable -Destination (Join-Path $InstallDir "CodexRadarSentinel.exe")
    Copy-Item -LiteralPath $ExtractedUninstaller -Destination (Join-Path $InstallDir "uninstall.ps1")
    Copy-Item -LiteralPath $ManifestPath -Destination (Join-Path $InstallDir "release-manifest.json")
    $InstalledExecutable = Join-Path $InstallDir "CodexRadarSentinel.exe"

    $ShortcutWasChanged = $true
    New-StartMenuShortcut -ShortcutPath $ShortcutPath -Executable $InstalledExecutable
    if ($StartWithWindows -or $PreserveExistingStartup) {
        $StartupWasChanged = $true
        Set-StartupValue -Executable $InstalledExecutable
    }

    Write-Host "Starting $ProductName..."
    $NewProcess = Start-Process -FilePath $InstalledExecutable -PassThru
    Start-Sleep -Milliseconds 2000
    $NewProcess.Refresh()
    if ($NewProcess.HasExited) {
        throw "$ProductName exited during its startup check (exit code $($NewProcess.ExitCode))."
    }
    $VerifiedProcess = Get-Process -Id $NewProcess.Id -ErrorAction Stop
    if (-not $VerifiedProcess.Path.Equals($InstalledExecutable, [StringComparison]::OrdinalIgnoreCase)) {
        throw "The startup check found a process at an unexpected path."
    }

    $Committed = $true
    if ($BackupPath -and (Test-Path -LiteralPath $BackupPath)) {
        try {
            # BackupPath is a verified sibling generated above.
            Remove-Item -LiteralPath $BackupPath -Recurse -Force
        }
        catch {
            Write-Warning "Installation succeeded, but the rollback directory could not be removed: $BackupPath"
        }
    }

    Write-Host "$ProductName $PackageVersion is installed for the current user."
    Write-Host "Install directory: $InstallDir"
    Write-Host "Start Menu shortcut: $ShortcutPath"
    if ($StartWithWindows -or $PreserveExistingStartup) {
        Write-Host "Start with Windows: enabled"
    }
    else {
        Write-Host "Start with Windows: unchanged (enable it from the tray menu or rerun with -StartWithWindows)"
    }
    Write-Host "The process is running (PID $($NewProcess.Id)); confirm the radar icon in the notification area."
}
catch {
    $Failure = $_
    if (-not $Committed) {
        $RollbackErrors = @()
        try {
            if ($NewProcess -and -not $NewProcess.HasExited) {
                Stop-Process -Id $NewProcess.Id -Force -ErrorAction SilentlyContinue
                $NewProcess.WaitForExit(5000) | Out-Null
            }
        }
        catch {
            $RollbackErrors += "stop new process: $($_.Exception.Message)"
        }
        try {
            if ($InstallWasReplaced -and (Test-Path -LiteralPath $InstallDir)) {
                # InstallDir was resolved and explicitly selected before this transaction.
                Remove-Item -LiteralPath $InstallDir -Recurse -Force
            }
        }
        catch {
            $RollbackErrors += "remove partial installation: $($_.Exception.Message)"
        }
        try {
            if ($BackupPath -and (Test-Path -LiteralPath $BackupPath)) {
                Move-Item -LiteralPath $BackupPath -Destination $InstallDir
            }
        }
        catch {
            $RollbackErrors += "restore previous files: $($_.Exception.Message)"
        }
        try {
            if ($ShortcutWasChanged) {
                if (Test-Path -LiteralPath $ShortcutPath) {
                    Remove-Item -LiteralPath $ShortcutPath -Force
                }
                if ($ShortcutExisted -and (Test-Path -LiteralPath $ShortcutBackup)) {
                    Copy-Item -LiteralPath $ShortcutBackup -Destination $ShortcutPath
                }
            }
        }
        catch {
            $RollbackErrors += "restore Start Menu shortcut: $($_.Exception.Message)"
        }
        try {
            if ($StartupWasChanged -and $StartupSnapshot) {
                Restore-StartupSnapshot -Snapshot $StartupSnapshot
            }
        }
        catch {
            $RollbackErrors += "restore startup value: $($_.Exception.Message)"
        }
        try {
            if ($PriorWasRunning -and (Test-Path -LiteralPath $InstallDir)) {
                $RestoredExecutable = @(
                    (Join-Path $InstallDir "CodexRadarSentinel.exe"),
                    (Join-Path $InstallDir "CodexRadar.Windows.exe")
                ) | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1
                if ($RestoredExecutable) {
                    Start-Process -FilePath $RestoredExecutable | Out-Null
                }
            }
        }
        catch {
            $RollbackErrors += "restart previous version: $($_.Exception.Message)"
        }
        foreach ($rollbackError in $RollbackErrors) {
            Write-Warning "Rollback issue: $rollbackError"
        }
    }
    Write-Error ("Installation failed: {0}" -f $Failure.Exception.Message) -ErrorAction Continue
    exit 1
}
finally {
    if ($TempRoot -and (Test-Path -LiteralPath $TempRoot)) {
        try {
            Remove-Item -LiteralPath $TempRoot -Recurse -Force
        }
        catch {
            Write-Warning "Could not remove temporary installer files: $TempRoot"
        }
    }
}

exit 0
