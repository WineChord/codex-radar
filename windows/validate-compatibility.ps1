[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("windows-10-x64", "windows-11-x64", "windows-11-arm64")]
    [string]$Target,

    [Parameter(Mandatory = $true)]
    [string]$Executable,

    [string]$EvidencePath,

    [switch]$RunLiveRadarRead,

    [switch]$RunLiveQuotaRead
)

$ErrorActionPreference = "Stop"

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

function Invoke-ValidationExecutable {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Argument,
        [switch]$Visible
    )

    $parameters = @{
        FilePath = $Path
        ArgumentList = $Argument
        Wait = $true
        PassThru = $true
    }
    if (-not $Visible) {
        $parameters.WindowStyle = "Hidden"
    }
    $process = Start-Process @parameters
    return $process.ExitCode
}

if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) {
    throw "Compatibility validation must run on Windows."
}

$Executable = [IO.Path]::GetFullPath($Executable)
if (-not (Test-Path -LiteralPath $Executable -PathType Leaf)) {
    throw "Validation executable does not exist: $Executable"
}

$Build = [Environment]::OSVersion.Version.Build
$ProductName = Get-WindowsProductName
if ($ProductName.IndexOf(
        "Server", [StringComparison]::OrdinalIgnoreCase) -ge 0) {
    throw "$Target requires Windows client; detected '$ProductName'."
}
$HostArchitecture = (
    [Runtime.InteropServices.RuntimeInformation]::OSArchitecture
).ToString().ToLowerInvariant()
$ExpectedArchitecture = if ($Target.EndsWith(
        "-arm64", [StringComparison]::Ordinal)) {
    "arm64"
}
else {
    "x64"
}

if ($HostArchitecture -ne $ExpectedArchitecture) {
    throw "$Target requires a native $ExpectedArchitecture host; detected $HostArchitecture."
}
switch -Wildcard ($Target) {
    "windows-10-*" {
        if ($Build -lt 17763 -or $Build -ge 22000) {
            throw "Windows 10 validation requires build 17763 through 21999; detected $Build."
        }
    }
    "windows-11-*" {
        if ($Build -lt 22000) {
            throw "Windows 11 validation requires build 22000 or newer; detected $Build."
        }
    }
}

$CoreTestExitCode = Invoke-ValidationExecutable `
    -Path $Executable `
    -Argument "--self-test"
if ($CoreTestExitCode -ne 0) {
    throw "Offline regression suite failed with exit code $CoreTestExitCode."
}
$LiveRadarReadPassed = $false
if ($RunLiveRadarRead) {
    $LiveRadarExitCode = Invoke-ValidationExecutable `
        -Path $Executable `
        -Argument "--live-radar-self-test"
    if ($LiveRadarExitCode -ne 0) {
        throw "Read-only live public-radar validation failed with exit code $LiveRadarExitCode."
    }
    $LiveRadarReadPassed = $true
}
$LiveQuotaReadPassed = $false
if ($RunLiveQuotaRead) {
    $LiveQuotaExitCode = Invoke-ValidationExecutable `
        -Path $Executable `
        -Argument "--live-quota-self-test"
    if ($LiveQuotaExitCode -ne 0) {
        throw "Read-only live quota validation failed with exit code $LiveQuotaExitCode."
    }
    $LiveQuotaReadPassed = $true
}
$VisualTestExitCode = Invoke-ValidationExecutable `
    -Path $Executable `
    -Argument "--ui-self-test" `
    -Visible
if ($VisualTestExitCode -ne 0) {
    throw "WinForms visual smoke test failed with exit code $VisualTestExitCode."
}
$TaskbarTestExitCode = Invoke-ValidationExecutable `
    -Path $Executable `
    -Argument "--taskbar-ui-self-test" `
    -Visible
if ($TaskbarTestExitCode -ne 0) {
    throw "Taskbar status smoke test failed with exit code $TaskbarTestExitCode."
}

if (-not $EvidencePath) {
    $RepositoryRoot = Split-Path $PSScriptRoot -Parent
    $EvidencePath = Join-Path (
        Join-Path $RepositoryRoot "artifacts\windows"
    ) "compatibility-$Target.json"
}
$EvidencePath = [IO.Path]::GetFullPath($EvidencePath)
$EvidenceDirectory = Split-Path $EvidencePath -Parent
New-Item -ItemType Directory -Path $EvidenceDirectory -Force | Out-Null
$ExecutableHash = (
    Get-FileHash -LiteralPath $Executable -Algorithm SHA256
).Hash.ToLowerInvariant()
$Evidence = [ordered]@{
    schema_version = 1
    target = $Target
    product_name = $ProductName
    os_description = [Runtime.InteropServices.RuntimeInformation]::OSDescription
    build = $Build
    architecture = $HostArchitecture
    executable_sha256 = $ExecutableHash
    offline_self_test = $true
    live_public_radar_read = $LiveRadarReadPassed
    live_quota_read = $LiveQuotaReadPassed
    winforms_visual_smoke = $true
    taskbar_status_smoke = $true
    verified_utc = [DateTimeOffset]::UtcNow.ToString("O")
}
[IO.File]::WriteAllText(
    $EvidencePath,
    ($Evidence | ConvertTo-Json -Depth 4),
    [Text.UTF8Encoding]::new($false)
)
Write-Host "Compatibility validation passed for $Target."
Write-Host "Evidence: $EvidencePath"
