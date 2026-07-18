[CmdletBinding()]
param(
    [string]$InstallDir,
    [switch]$KeepData
)

$ErrorActionPreference = "Stop"
$ProductName = "Codex Radar Sentinel"
$RunValueName = "Codex Radar Sentinel"
$RunKeyPath = "Software\Microsoft\Windows\CurrentVersion\Run"

function Assert-WindowsPlatform {
    if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) {
        throw "This uninstaller is Windows-only. No files were changed."
    }
}

function Get-SafeDirectoryPath {
    param([Parameter(Mandatory = $true)][string]$Path)

    $resolved = [IO.Path]::GetFullPath($Path).TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
    $root = [IO.Path]::GetPathRoot($resolved).TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
    if ([string]::IsNullOrWhiteSpace($resolved) -or $resolved.Equals($root, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to use a filesystem root as an uninstall directory: $Path"
    }
    return $resolved
}

function Test-PathInsideDirectory {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Directory
    )

    $parent = $Directory.TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
    return [IO.Path]::GetFullPath($Path).StartsWith($parent, [StringComparison]::OrdinalIgnoreCase)
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
                # Processes owned by another user are outside this per-user installation.
            }
        }
    }
    return $result
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

function Test-ProductExecutableForDirectory {
    param(
        [string]$Executable,
        [Parameter(Mandatory = $true)][string]$Directory
    )

    if ([string]::IsNullOrWhiteSpace($Executable)) {
        return $false
    }
    try {
        $leafName = [IO.Path]::GetFileName($Executable)
        if ($leafName -notin @("CodexRadarSentinel.exe", "CodexRadar.Windows.exe")) {
            return $false
        }
        return Test-PathInsideDirectory -Path $Executable -Directory $Directory
    }
    catch {
        return $false
    }
}

function Remove-StartupValue {
    param([Parameter(Mandatory = $true)][string]$Directory)

    $key = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey($RunKeyPath, $true)
    if ($null -eq $key) {
        return
    }
    try {
        $current = $key.GetValue($RunValueName, $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
        $currentExecutable = Get-RunCommandExecutable -Command ([string]$current)
        if (Test-ProductExecutableForDirectory -Executable $currentExecutable -Directory $Directory) {
            $key.DeleteValue($RunValueName, $false)
        }
    }
    finally {
        $key.Dispose()
    }
}

try {
    Assert-WindowsPlatform

    if ([string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) {
        throw "LOCALAPPDATA is unavailable; cannot determine the per-user installation path."
    }
    if ([string]::IsNullOrWhiteSpace($InstallDir)) {
        $InstallDir = Join-Path $env:LOCALAPPDATA "Programs\CodexRadarSentinel"
    }
    $InstallDir = Get-SafeDirectoryPath -Path $InstallDir

    if (Test-Path -LiteralPath $InstallDir) {
        $manifestPath = Join-Path $InstallDir "release-manifest.json"
        $newExecutable = Join-Path $InstallDir "CodexRadarSentinel.exe"
        $legacyExecutable = Join-Path $InstallDir "CodexRadar.Windows.exe"
        $looksLikeProduct = (Test-Path -LiteralPath $newExecutable -PathType Leaf) -or
            (Test-Path -LiteralPath $legacyExecutable -PathType Leaf)

        if (Test-Path -LiteralPath $manifestPath -PathType Leaf) {
            $manifest = [IO.File]::ReadAllText($manifestPath) | ConvertFrom-Json
            $looksLikeProduct = $looksLikeProduct -and
                ([string]$manifest.product).Equals("CodexRadarSentinel", [StringComparison]::Ordinal) -and
                ([string]$manifest.platform).Equals("windows", [StringComparison]::OrdinalIgnoreCase)
            $allowedEntries = @("CodexRadarSentinel.exe", "uninstall.ps1", "release-manifest.json")
            $entries = @(Get-ChildItem -LiteralPath $InstallDir -Force)
            $looksLikeProduct = $looksLikeProduct -and $entries.Count -eq $allowedEntries.Count -and
                @($entries | Where-Object { $_.PSIsContainer -or $_.Name -notin $allowedEntries }).Count -eq 0
        }
        else {
            $defaultDirectory = [IO.Path]::GetFullPath((Join-Path $env:LOCALAPPDATA "Programs\CodexRadarSentinel")).TrimEnd([IO.Path]::DirectorySeparatorChar)
            $legacyAllowed = @("CodexRadarSentinel.exe", "CodexRadar.Windows.exe", "uninstall.ps1")
            $legacyEntries = @(Get-ChildItem -LiteralPath $InstallDir -Force)
            $looksLikeProduct = $looksLikeProduct -and
                $InstallDir.Equals($defaultDirectory, [StringComparison]::OrdinalIgnoreCase) -and
                $legacyEntries.Count -gt 0 -and
                @($legacyEntries | Where-Object { $_.PSIsContainer -or $_.Name -notin $legacyAllowed }).Count -eq 0
        }
        if (-not $looksLikeProduct) {
            throw "Refusing to remove '$InstallDir': it is not a verified Codex Radar Sentinel Windows installation."
        }
    }

    foreach ($process in @(Get-InstalledProcesses -Directory $InstallDir)) {
        Stop-Process -Id $process.Id -Force -ErrorAction Stop
        $process.WaitForExit(5000) | Out-Null
    }

    Remove-StartupValue -Directory $InstallDir

    $ProgramsDirectory = [Environment]::GetFolderPath([Environment+SpecialFolder]::Programs)
    $ShortcutPath = Join-Path $ProgramsDirectory "$ProductName.lnk"
    if (Test-Path -LiteralPath $ShortcutPath -PathType Leaf) {
        $shell = New-Object -ComObject WScript.Shell
        try {
            $shortcut = $shell.CreateShortcut($ShortcutPath)
            $shortcutTarget = $shortcut.TargetPath
            [Runtime.InteropServices.Marshal]::FinalReleaseComObject($shortcut) | Out-Null
            if (Test-ProductExecutableForDirectory -Executable $shortcutTarget -Directory $InstallDir) {
                Remove-Item -LiteralPath $ShortcutPath -Force
            }
        }
        finally {
            [Runtime.InteropServices.Marshal]::FinalReleaseComObject($shell) | Out-Null
        }
    }

    if (Test-Path -LiteralPath $InstallDir) {
        # The current directory may legitimately be a drive root; unlike an uninstall
        # target, it is only compared and must not go through the root-rejecting guard.
        $currentDirectory = [IO.Path]::GetFullPath((Get-Location).Path)
        if ($currentDirectory.Equals($InstallDir, [StringComparison]::OrdinalIgnoreCase) -or
            (Test-PathInsideDirectory -Path $currentDirectory -Directory $InstallDir)) {
            Set-Location ([IO.Path]::GetTempPath())
        }
        # InstallDir has been resolved and verified as this product above.
        Remove-Item -LiteralPath $InstallDir -Recurse -Force
    }

    # The automatic updater keeps one verified rollback copy beside the install.
    # Remove it only when it is unmistakably this product; never delete an arbitrary sibling.
    $BackupDirectory = Get-SafeDirectoryPath -Path ($InstallDir + ".previous")
    if (Test-Path -LiteralPath $BackupDirectory -PathType Container) {
        $backupManifestPath = Join-Path $BackupDirectory "release-manifest.json"
        $backupExecutablePath = Join-Path $BackupDirectory "CodexRadarSentinel.exe"
        $verifiedBackup = $false
        if ((Test-Path -LiteralPath $backupManifestPath -PathType Leaf) -and
            (Test-Path -LiteralPath $backupExecutablePath -PathType Leaf)) {
            try {
                $backupManifest = [IO.File]::ReadAllText($backupManifestPath) | ConvertFrom-Json
                $verifiedBackup = ([string]$backupManifest.product).Equals("CodexRadarSentinel", [StringComparison]::Ordinal) -and
                    ([string]$backupManifest.platform).Equals("windows", [StringComparison]::OrdinalIgnoreCase)
                $backupAllowedEntries = @("CodexRadarSentinel.exe", "uninstall.ps1", "release-manifest.json")
                $backupEntries = @(Get-ChildItem -LiteralPath $BackupDirectory -Force)
                $verifiedBackup = $verifiedBackup -and $backupEntries.Count -eq $backupAllowedEntries.Count -and
                    @($backupEntries | Where-Object { $_.PSIsContainer -or $_.Name -notin $backupAllowedEntries }).Count -eq 0
            }
            catch {
                $verifiedBackup = $false
            }
        }
        if ($verifiedBackup) {
            Remove-Item -LiteralPath $BackupDirectory -Recurse -Force
        }
    }

    if (-not $KeepData) {
        $DataDirectory = Get-SafeDirectoryPath -Path (Join-Path $env:LOCALAPPDATA "CodexRadarSentinel")
        $LocalAppDataRoot = Get-SafeDirectoryPath -Path $env:LOCALAPPDATA
        if (-not (Test-PathInsideDirectory -Path $DataDirectory -Directory $LocalAppDataRoot)) {
            throw "Refusing to remove an application-data path outside LOCALAPPDATA."
        }
        if (Test-Path -LiteralPath $DataDirectory) {
            Remove-Item -LiteralPath $DataDirectory -Recurse -Force
        }
    }

    Write-Host "$ProductName was removed from this Windows user account."
    if ($KeepData) {
        Write-Host "Settings and cached reset-card metadata were kept."
    }
    exit 0
}
catch {
    Write-Error ("Uninstall failed: {0}" -f $_.Exception.Message) -ErrorAction Continue
    exit 1
}
