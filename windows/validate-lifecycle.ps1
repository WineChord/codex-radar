[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("win-x64", "win-arm64")]
    [string]$Runtime,

    [Parameter(Mandatory = $true)]
    [string]$Archive,

    [Parameter(Mandatory = $true)]
    [string]$Checksum,

    [string]$EvidencePath,

    [switch]$RunLiveRadarRead,

    [switch]$RunLiveQuotaRead
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

function Assert-ChildPath {
    param(
        [Parameter(Mandatory = $true)][string]$Parent,
        [Parameter(Mandatory = $true)][string]$Child
    )

    $parentPath = [IO.Path]::GetFullPath($Parent).TrimEnd(
        [IO.Path]::DirectorySeparatorChar,
        [IO.Path]::AltDirectorySeparatorChar
    ) + [IO.Path]::DirectorySeparatorChar
    $childPath = [IO.Path]::GetFullPath($Child)
    if (-not $childPath.StartsWith(
            $parentPath,
            [StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to modify a path outside $parentPath"
    }
}

function Get-WindowsProductName {
    $key = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey(
        "SOFTWARE\Microsoft\Windows NT\CurrentVersion",
        $false
    )
    if ($null -eq $key) {
        return ""
    }
    try {
        return [string]$key.GetValue("ProductName", "")
    }
    finally {
        $key.Dispose()
    }
}

function Get-InstallProcesses {
    param([Parameter(Mandatory = $true)][string]$Directory)

    $directoryRoot = [IO.Path]::GetFullPath($Directory).TrimEnd(
        [IO.Path]::DirectorySeparatorChar
    ) + [IO.Path]::DirectorySeparatorChar
    $result = @()
    foreach ($name in @("CodexRadarSentinel", "CodexRadar.Windows")) {
        foreach ($process in @(Get-Process -Name $name -ErrorAction SilentlyContinue)) {
            try {
                if ($process.Path -and
                    ([IO.Path]::GetFullPath($process.Path)).StartsWith(
                        $directoryRoot,
                        [StringComparison]::OrdinalIgnoreCase)) {
                    $result += $process
                }
            }
            catch {
                # A process that cannot expose its path is outside this
                # current-user validation installation.
            }
        }
    }
    return $result
}

function Wait-ForInstallProcess {
    param([Parameter(Mandatory = $true)][string]$Directory)

    $deadline = [DateTimeOffset]::UtcNow.AddSeconds(10)
    do {
        $processes = @(Get-InstallProcesses -Directory $Directory)
        if ($processes.Count -eq 1) {
            return $processes[0]
        }
        if ($processes.Count -gt 1) {
            throw "Lifecycle validation found more than one installed process."
        }
        Start-Sleep -Milliseconds 200
    } while ([DateTimeOffset]::UtcNow -lt $deadline)
    throw "The installed process did not remain running."
}

function Invoke-Diagnostic {
    param(
        [Parameter(Mandatory = $true)][string]$Executable,
        [Parameter(Mandatory = $true)][string]$Argument,
        [ValidateRange(1, 3)][int]$Attempts = 1,
        [switch]$Visible
    )

    for ($attempt = 1; $attempt -le $Attempts; $attempt++) {
        $diagnosticId = [Guid]::NewGuid().ToString("N")
        $stdoutPath = Join-Path $TemporaryRoot ".diagnostic-$diagnosticId.stdout.log"
        $stderrPath = Join-Path $TemporaryRoot ".diagnostic-$diagnosticId.stderr.log"
        $parameters = @{
            FilePath = $Executable
            ArgumentList = $Argument
            Wait = $true
            PassThru = $true
            RedirectStandardOutput = $stdoutPath
            RedirectStandardError = $stderrPath
        }
        if (-not $Visible) {
            $parameters.WindowStyle = "Hidden"
        }
        $process = Start-Process @parameters
        $exitCode = $process.ExitCode
        $process.Dispose()
        $diagnosticParts = @()
        if (Test-Path -LiteralPath $stdoutPath) {
            $diagnosticParts += [IO.File]::ReadAllText($stdoutPath).Trim()
        }
        if (Test-Path -LiteralPath $stderrPath) {
            $diagnosticParts += [IO.File]::ReadAllText($stderrPath).Trim()
        }
        $diagnosticOutput = [string]::Join(
            [Environment]::NewLine,
            @($diagnosticParts | Where-Object {
                -not [string]::IsNullOrWhiteSpace($_)
            })
        )
        Remove-Item -LiteralPath $stdoutPath, $stderrPath -Force -ErrorAction SilentlyContinue
        if ($exitCode -eq 0) {
            return
        }
        if ($attempt -lt $Attempts) {
            Start-Sleep -Seconds 2
        }
    }
    $details = if ([string]::IsNullOrWhiteSpace($diagnosticOutput)) {
        "No diagnostic output was captured."
    }
    else {
        $diagnosticOutput
    }
    throw "Installed diagnostic '$Argument' failed after $Attempts attempt(s): $details"
}

function Invoke-Installer {
    param(
        [Parameter(Mandatory = $true)][string]$PackageArchive,
        [Parameter(Mandatory = $true)][string]$PackageChecksum,
        [switch]$FailAfterReplace
    )

    $arguments = @(
        "-NoProfile",
        "-ExecutionPolicy", "Bypass",
        "-File", $Installer,
        "-Runtime", $Runtime,
        "-InstallDir", $InstallDirectory,
        "-PackageArchive", $PackageArchive,
        "-PackageChecksum", $PackageChecksum
    )
    if ($FailAfterReplace) {
        $arguments += "-FailAfterReplaceForValidation"
    }
    $previousTemp = $env:TEMP
    $previousTmp = $env:TMP
    $exitCode = 1
    try {
        # Keep the installer's extraction and rollback workspace inside this
        # validation root so its NTFS compression and final cleanup apply.
        $env:TEMP = $TemporaryRoot
        $env:TMP = $TemporaryRoot
        & powershell.exe @arguments |
            ForEach-Object { Write-Host $_ }
        $exitCode = $LASTEXITCODE
    }
    finally {
        $env:TEMP = $previousTemp
        $env:TMP = $previousTmp
    }
    return [int]$exitCode
}

function Assert-SearchShortcut {
    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $null
    try {
        if (-not (Test-Path -LiteralPath $ShortcutPath -PathType Leaf)) {
            throw "The searchable Start Menu shortcut is missing."
        }
        $shortcut = $shell.CreateShortcut($ShortcutPath)
        if (-not $shortcut.TargetPath.Equals($InstalledExecutable, [StringComparison]::OrdinalIgnoreCase) -or
            $shortcut.Arguments -ne "--show-dashboard") {
            throw "The Search shortcut must open the installed dashboard."
        }
    }
    finally {
        if ($shortcut) { [Runtime.InteropServices.Marshal]::FinalReleaseComObject($shortcut) | Out-Null }
        [Runtime.InteropServices.Marshal]::FinalReleaseComObject($shell) | Out-Null
    }
}

function Start-ActivationClient {
    param([string]$Argument)

    # Own the process handle from creation. Windows PowerShell's Start-Process
    # can lose the exit status of a very short-lived activation process.
    $info = New-Object Diagnostics.ProcessStartInfo
    $info.FileName = $InstalledExecutable
    $info.Arguments = $Argument
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    $info.WindowStyle = [Diagnostics.ProcessWindowStyle]::Hidden
    $info.RedirectStandardError = $true
    return [Diagnostics.Process]::Start($info)
}

function Assert-DashboardVisibility {
    param([Parameter(Mandatory = $true)][bool]$Visible)

    # A tray window has an invisible owner and is not Process.MainWindowHandle.
    # Ask its UI thread without changing visibility or reading account data.
    $probe = Start-ActivationClient -Argument "--dashboard-visible-self-test"
    try {
        if (-not $probe.WaitForExit(15000)) {
            Stop-Process -Id $probe.Id -Force
            throw "Dashboard visibility probe timed out."
        }
        $expectedExit = if ($Visible) { 0 } else { 1 }
        if ($probe.ExitCode -ne $expectedExit) {
            throw "Dashboard visibility did not match the expected startup behavior (exit $($probe.ExitCode)): $($probe.StandardError.ReadToEnd())"
        }
    }
    finally { $probe.Dispose() }
}

function Assert-ExistingInstanceActivation {
    param([Parameter(Mandatory = $true)]$Process)

    $launcher = Start-ActivationClient -Argument "--show-dashboard"
    try {
        if (-not $launcher.WaitForExit(15000)) {
            Stop-Process -Id $launcher.Id -Force
            $launcher.WaitForExit()
            $detail = $launcher.StandardError.ReadToEnd().Trim()
            throw "The second Search launch did not exit within its activation deadline. $detail"
        }
        if ($launcher.ExitCode -ne 0) { throw "The second Search launch failed (exit $($launcher.ExitCode)): $($launcher.StandardError.ReadToEnd())" }
        Assert-DashboardVisibility -Visible $true
        $running = @(Get-InstallProcesses -Directory $InstallDirectory)
        if ($running.Count -ne 1 -or $running[0].Id -ne $Process.Id) {
            throw "Search must reuse the existing process without creating another instance."
        }
    }
    finally { $launcher.Dispose() }
}

if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) {
    throw "Lifecycle validation must run on Windows."
}

$Archive = [IO.Path]::GetFullPath($Archive)
$Checksum = [IO.Path]::GetFullPath($Checksum)
foreach ($path in @($Archive, $Checksum)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Lifecycle input does not exist: $path"
    }
}

$HostArchitecture = (
    [Runtime.InteropServices.RuntimeInformation]::OSArchitecture
).ToString().ToLowerInvariant()
$HostBuild = [Environment]::OSVersion.Version.Build
$HostProductName = Get-WindowsProductName
$HostWindowsVersion = if ($HostProductName.IndexOf(
        "Server", [StringComparison]::OrdinalIgnoreCase) -ge 0) {
    "server-$HostBuild"
}
elseif ($HostBuild -ge 22000) { "11" }
else { "10" }
$ExpectedArchitecture = if ($Runtime -eq "win-arm64") { "arm64" } else { "x64" }
if ($HostArchitecture -ne $ExpectedArchitecture) {
    throw "$Runtime lifecycle validation requires a native $ExpectedArchitecture host; detected $HostArchitecture."
}

$RepositoryRoot = Split-Path $PSScriptRoot -Parent
$Installer = Join-Path $PSScriptRoot "install.ps1"
$ArtifactsRoot = Join-Path $RepositoryRoot "artifacts\windows"
if (-not $EvidencePath) {
    $EvidencePath = Join-Path $ArtifactsRoot "lifecycle-$ExpectedArchitecture.json"
}
$EvidencePath = [IO.Path]::GetFullPath($EvidencePath)
$evidenceDirectory = Split-Path $EvidencePath -Parent
New-Item -ItemType Directory -Path $evidenceDirectory -Force | Out-Null

$TemporaryRoot = Join-Path (
    [IO.Path]::GetTempPath()
) ("codex-radar-lifecycle-" + [Guid]::NewGuid().ToString("N"))
Assert-ChildPath -Parent ([IO.Path]::GetTempPath()) -Child $TemporaryRoot
New-Item -ItemType Directory -Path $TemporaryRoot -Force | Out-Null
# Release EXEs are intentionally self-contained. Marking this isolated root as
# NTFS-compressed keeps the two-copy upgrade/rollback window usable on
# space-constrained validation hosts without changing the package under test.
& compact.exe /C /Q $TemporaryRoot | Out-Null
if ($LASTEXITCODE -ne 0) {
    Write-Warning "Could not enable NTFS compression for the lifecycle workspace."
}
$InstallDirectory = Join-Path $TemporaryRoot "installed"
$ValidationDataRoot = Join-Path $TemporaryRoot "data"
New-Item -ItemType Directory -Path $ValidationDataRoot -Force | Out-Null

$ProgramsDirectory = [Environment]::GetFolderPath(
    [Environment+SpecialFolder]::Programs
)
$ShortcutPath = Join-Path $ProgramsDirectory "CodexRadarSentinel.lnk"
$LegacyShortcutPath = Join-Path $ProgramsDirectory "Codex Radar Sentinel.lnk"
if ((Test-Path -LiteralPath $ShortcutPath) -or (Test-Path -LiteralPath $LegacyShortcutPath)) {
    throw "Lifecycle validation refuses to replace an existing Codex Radar Sentinel Start Menu shortcut."
}

$PreviousValidationDataRoot = $env:CODEX_RADAR_VALIDATION_DATA_ROOT
$PreviousLifecycleValidation = $env:CODEX_RADAR_LIFECYCLE_VALIDATION
$PreviousBundleExtractBaseDirectory = $env:DOTNET_BUNDLE_EXTRACT_BASE_DIR
$env:CODEX_RADAR_VALIDATION_DATA_ROOT = $ValidationDataRoot
$env:CODEX_RADAR_LIFECYCLE_VALIDATION = "1"
$env:DOTNET_BUNDLE_EXTRACT_BASE_DIR = Join-Path $TemporaryRoot "bundle-cache"
$SettingsDirectory = Join-Path $ValidationDataRoot "CodexRadarSentinel"
New-Item -ItemType Directory -Path $SettingsDirectory -Force | Out-Null
[IO.File]::WriteAllText(
    (Join-Path $SettingsDirectory "settings.json"),
    '{"AutomaticUpdates":false,"AutoResetCreditCheck":false,"ResetCreditProtectionEnabled":false}',
    [Text.UTF8Encoding]::new($false)
)

$Installed = $false
try {
    if ((Invoke-Installer -PackageArchive $Archive -PackageChecksum $Checksum) -ne 0) {
        throw "Initial local-package installation failed."
    }
    $Installed = $true
    $InstalledExecutable = Join-Path $InstallDirectory "CodexRadarSentinel.exe"
    $InitialProcess = Wait-ForInstallProcess -Directory $InstallDirectory
    Assert-SearchShortcut
    Assert-DashboardVisibility -Visible $false
    Write-Host "Background startup stays hidden."
    Assert-ExistingInstanceActivation -Process $InitialProcess
    Write-Host "First Search launch opened the running dashboard."
    Assert-ExistingInstanceActivation -Process $InitialProcess
    Write-Host "Repeated Search launches reuse and show the existing dashboard."
    Stop-Process -Id $InitialProcess.Id -Force
    $InitialProcess.WaitForExit(5000) | Out-Null
    $SearchProcess = Start-Process -FilePath $InstalledExecutable -ArgumentList "--show-dashboard" -WindowStyle Hidden -PassThru
    $SearchProcess = Wait-ForInstallProcess -Directory $InstallDirectory
    Assert-DashboardVisibility -Visible $true
    Write-Host "Cold Search launch shows the dashboard."
    $InitialExecutableHash = (
        Get-FileHash -LiteralPath $InstalledExecutable -Algorithm SHA256
    ).Hash.ToLowerInvariant()
    $SourceManifestPath = Join-Path $InstallDirectory "release-manifest.json"
    $SourceManifest = [IO.File]::ReadAllText(
        $SourceManifestPath
    ) | ConvertFrom-Json
    $BaseVersion = [string]$SourceManifest.version
    if ($BaseVersion -notmatch '^\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?$') {
        throw "Lifecycle source package has an invalid version."
    }

    Invoke-Diagnostic -Executable $InstalledExecutable -Argument "--self-test"
    Invoke-Diagnostic -Executable $InstalledExecutable -Argument "--ui-self-test" -Visible
    Invoke-Diagnostic -Executable $InstalledExecutable -Argument "--taskbar-ui-self-test" -Visible
    if ($RunLiveRadarRead) {
        Invoke-Diagnostic `
            -Executable $InstalledExecutable `
            -Argument "--live-radar-self-test" `
            -Attempts 3
    }
    if ($RunLiveQuotaRead) {
        Invoke-Diagnostic `
            -Executable $InstalledExecutable `
            -Argument "--live-quota-self-test" `
            -Attempts 3
    }

    # Simulate a previous installer, then verify migration rolls back atomically.
    Move-Item -LiteralPath $ShortcutPath -Destination $LegacyShortcutPath
    $shell = New-Object -ComObject WScript.Shell
    try {
        $legacy = $shell.CreateShortcut($LegacyShortcutPath)
        $legacy.Arguments = ""
        $legacy.Save()
        [Runtime.InteropServices.Marshal]::FinalReleaseComObject($legacy) | Out-Null
    }
    finally { [Runtime.InteropServices.Marshal]::FinalReleaseComObject($shell) | Out-Null }
    $LegacyShortcutHash = (Get-FileHash -LiteralPath $LegacyShortcutPath -Algorithm SHA256).Hash
    if ((Invoke-Installer -PackageArchive $Archive -PackageChecksum $Checksum -FailAfterReplace) -eq 0) {
        throw "The intentionally failing shortcut migration unexpectedly succeeded."
    }
    if ((Test-Path -LiteralPath $ShortcutPath) -or
        -not (Test-Path -LiteralPath $LegacyShortcutPath) -or
        (Get-FileHash -LiteralPath $LegacyShortcutPath -Algorithm SHA256).Hash -ne $LegacyShortcutHash) {
        throw "Failed migration did not restore the exact legacy shortcut."
    }

    $PreUpgradeVersion = "$BaseVersion-validation.base"
    $SourceManifest.version = $PreUpgradeVersion
    [IO.File]::WriteAllText(
        $SourceManifestPath,
        ($SourceManifest | ConvertTo-Json -Depth 5),
        [Text.UTF8Encoding]::new($false)
    )
    if ((Invoke-Installer `
            -PackageArchive $Archive `
            -PackageChecksum $Checksum) -ne 0) {
        throw "Isolated package upgrade failed."
    }
    $UpgradeProcess = Wait-ForInstallProcess -Directory $InstallDirectory
    Assert-SearchShortcut
    if (Test-Path -LiteralPath $LegacyShortcutPath) {
        throw "Upgrade left a duplicate legacy Search entry."
    }
    $ShortcutHash = (Get-FileHash -LiteralPath $ShortcutPath -Algorithm SHA256).Hash
    $UpgradeManifest = [IO.File]::ReadAllText(
        (Join-Path $InstallDirectory "release-manifest.json")
    ) | ConvertFrom-Json
    if (-not ([string]$UpgradeManifest.version).Equals(
            $BaseVersion,
            [StringComparison]::Ordinal)) {
        throw "The upgraded installation did not commit the expected manifest."
    }
    $UpgradeExecutableHash = (
        Get-FileHash -LiteralPath $InstalledExecutable -Algorithm SHA256
    ).Hash.ToLowerInvariant()

    if ((Invoke-Installer `
            -PackageArchive $Archive `
            -PackageChecksum $Checksum `
            -FailAfterReplace) -eq 0) {
        throw "The intentionally failing upgrade unexpectedly succeeded."
    }
    $RollbackProcess = Wait-ForInstallProcess -Directory $InstallDirectory
    Assert-SearchShortcut
    if ((Get-FileHash -LiteralPath $ShortcutPath -Algorithm SHA256).Hash -ne $ShortcutHash) {
        throw "Rollback did not preserve the existing Search shortcut."
    }
    Assert-ExistingInstanceActivation -Process $RollbackProcess
    $RollbackManifest = [IO.File]::ReadAllText(
        (Join-Path $InstallDirectory "release-manifest.json")
    ) | ConvertFrom-Json
    $RollbackExecutableHash = (
        Get-FileHash -LiteralPath $InstalledExecutable -Algorithm SHA256
    ).Hash.ToLowerInvariant()
    if (-not ([string]$RollbackManifest.version).Equals(
            $BaseVersion,
            [StringComparison]::Ordinal) -or
        -not $RollbackExecutableHash.Equals(
            $UpgradeExecutableHash,
            [StringComparison]::OrdinalIgnoreCase)) {
        throw "Failed upgrade did not restore the previously verified installation."
    }

    $InstalledUninstaller = Join-Path $InstallDirectory "uninstall.ps1"
    & powershell.exe `
        -NoProfile `
        -ExecutionPolicy Bypass `
        -File $InstalledUninstaller `
        -InstallDir $InstallDirectory `
        -KeepData
    if ($LASTEXITCODE -ne 0) {
        throw "Installed uninstaller failed with exit code $LASTEXITCODE."
    }
    $Installed = $false
    if (Test-Path -LiteralPath $InstallDirectory) {
        throw "Uninstall left the isolated installation directory behind."
    }
    if ((Test-Path -LiteralPath $ShortcutPath) -or (Test-Path -LiteralPath $LegacyShortcutPath)) {
        throw "Uninstall left the validation Start Menu shortcut behind."
    }

    $Evidence = [ordered]@{
        schema_version = 1
        target = "windows-$HostWindowsVersion-$ExpectedArchitecture"
        product_name = $HostProductName
        os_description = [Runtime.InteropServices.RuntimeInformation]::OSDescription
        build = $HostBuild
        architecture = $HostArchitecture
        version = $BaseVersion
        upgrade_from_version = $PreUpgradeVersion
        upgrade_to_version = $BaseVersion
        source_archive_sha256 = (
            Get-FileHash -LiteralPath $Archive -Algorithm SHA256
        ).Hash.ToLowerInvariant()
        installed = $true
        launched = $InitialProcess.Id -gt 0
        search_shortcut = $true
        search_opens_dashboard = $SearchProcess.Id -gt 0
        search_reuses_existing_instance = $true
        background_start_is_quiet = $true
        legacy_shortcut_migration_and_rollback = $true
        offline_refresh_contract = $true
        live_public_radar_read = [bool]$RunLiveRadarRead
        live_quota_read = [bool]$RunLiveQuotaRead
        winforms_visual_smoke = $true
        taskbar_status_smoke = $true
        upgraded = $UpgradeProcess.Id -gt 0
        rollback_restored_previous = $RollbackProcess.Id -gt 0
        uninstalled = $true
        initial_executable_sha256 = $InitialExecutableHash
        restored_executable_sha256 = $RollbackExecutableHash
        verified_utc = [DateTimeOffset]::UtcNow.ToString("O")
    }
    [IO.File]::WriteAllText(
        $EvidencePath,
        ($Evidence | ConvertTo-Json -Depth 5),
        [Text.UTF8Encoding]::new($false)
    )
    Write-Host "Windows lifecycle validation passed."
    Write-Host "Evidence: $EvidencePath"
}
finally {
    if (Test-Path -LiteralPath (Join-Path $InstallDirectory "uninstall.ps1") -PathType Leaf) {
        & powershell.exe `
            -NoProfile `
            -ExecutionPolicy Bypass `
            -File (Join-Path $InstallDirectory "uninstall.ps1") `
            -InstallDir $InstallDirectory `
            -KeepData | Out-Null
    }
    foreach ($process in @(Get-InstallProcesses -Directory $InstallDirectory)) {
        Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
    }
    $env:CODEX_RADAR_VALIDATION_DATA_ROOT = $PreviousValidationDataRoot
    $env:CODEX_RADAR_LIFECYCLE_VALIDATION = $PreviousLifecycleValidation
    $env:DOTNET_BUNDLE_EXTRACT_BASE_DIR = $PreviousBundleExtractBaseDirectory
    if (Test-Path -LiteralPath $TemporaryRoot) {
        Assert-ChildPath -Parent ([IO.Path]::GetTempPath()) -Child $TemporaryRoot
        Remove-Item -LiteralPath $TemporaryRoot -Recurse -Force
    }
}
