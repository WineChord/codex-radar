[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("win-x64", "win-arm64")]
    [string]$Runtime,

    [ValidatePattern('^\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?$')]
    [string]$Version,

    [switch]$RunSelfTest
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

function Get-PeArchitecture {
    param([Parameter(Mandatory = $true)][string]$Path)

    $stream = [IO.File]::Open(
        $Path,
        [IO.FileMode]::Open,
        [IO.FileAccess]::Read,
        [IO.FileShare]::Read
    )
    $reader = [IO.BinaryReader]::new($stream)
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
            default { throw "Packaged executable has an unsupported PE architecture." }
        }
    }
    finally {
        $reader.Dispose()
        $stream.Dispose()
    }
}

function Invoke-PackagedSelfTest {
    param([Parameter(Mandatory = $true)][string]$Path)

    $process = Start-Process `
        -FilePath $Path `
        -ArgumentList "--self-test" `
        -WindowStyle Hidden `
        -Wait `
        -PassThru
    if ($process.ExitCode -ne 0) {
        throw "Packaged self-test failed with exit code $($process.ExitCode)."
    }
}

function Remove-TemporaryDirectory {
    param([Parameter(Mandatory = $true)][string]$Path)

    for ($attempt = 1; $attempt -le 10; $attempt++) {
        try {
            if (Test-Path -LiteralPath $Path) {
                Remove-Item -LiteralPath $Path -Recurse -Force
            }
            return
        }
        catch {
            if ($attempt -ge 10) {
                throw
            }
            Start-Sleep -Milliseconds 100
        }
    }
}

if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) {
    throw "Windows release verification must run on Windows."
}

$RepositoryRoot = Split-Path $PSScriptRoot -Parent
$Project = Join-Path $PSScriptRoot "CodexRadar.Windows\CodexRadar.Windows.csproj"
$ArtifactsRoot = Join-Path $RepositoryRoot "artifacts\windows"
$ReleaseRoot = Join-Path $ArtifactsRoot "release"
$Architecture = if ($Runtime -eq "win-arm64") { "arm64" } else { "x64" }

if (-not $Version) {
    [xml]$projectXml = [IO.File]::ReadAllText($Project)
    $Version = [string](
        $projectXml.Project.PropertyGroup.Version |
            Select-Object -First 1
    )
}

$AssetBaseName = "CodexRadarSentinel-$Version-Windows-$Architecture"
$ArchivePath = Join-Path $ReleaseRoot "$AssetBaseName.zip"
$ChecksumPath = Join-Path $ReleaseRoot "$AssetBaseName.sha256"
foreach ($path in @($ArchivePath, $ChecksumPath)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Expected release asset is missing: $path"
    }
}

$checksumLines = @(
    [IO.File]::ReadAllLines($ChecksumPath) |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
)
if ($checksumLines.Count -ne 1 -or
    $checksumLines[0].Trim().TrimStart([char]0xFEFF) -notmatch
        '^([0-9a-fA-F]{64})\s+\*?(.+)$') {
    throw "Checksum must contain exactly one SHA256 entry."
}
$ExpectedArchiveHash = $Matches[1].ToLowerInvariant()
$ListedArchiveName = [IO.Path]::GetFileName(
    $Matches[2].Trim().Replace('/', '\')
)
if (-not $ListedArchiveName.Equals(
        [IO.Path]::GetFileName($ArchivePath),
        [StringComparison]::Ordinal)) {
    throw "Checksum names a different archive: $ListedArchiveName"
}
$ActualArchiveHash = (
    Get-FileHash -LiteralPath $ArchivePath -Algorithm SHA256
).Hash.ToLowerInvariant()
if ($ActualArchiveHash -ne $ExpectedArchiveHash) {
    throw "Release archive SHA256 does not match its checksum."
}

$TemporaryRoot = Join-Path (
    [IO.Path]::GetTempPath()
) ("codex-radar-release-validation-" + [Guid]::NewGuid().ToString("N"))
Assert-ChildPath -Parent ([IO.Path]::GetTempPath()) -Child $TemporaryRoot
New-Item -ItemType Directory -Path $TemporaryRoot -Force | Out-Null

try {
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip = [IO.Compression.ZipFile]::OpenRead($ArchivePath)
    try {
        $expectedEntries = @(
            "CodexRadarSentinel.exe",
            "uninstall.ps1",
            "release-manifest.json"
        )
        $actualEntries = @($zip.Entries | ForEach-Object { $_.FullName })
        if ($actualEntries.Count -ne $expectedEntries.Count -or
            @($actualEntries | Where-Object { $_ -notin $expectedEntries }).Count -gt 0 -or
            @($expectedEntries | Where-Object { $_ -notin $actualEntries }).Count -gt 0) {
            throw "Release archive entries do not match the Windows contract."
        }
    }
    finally {
        $zip.Dispose()
    }

    Expand-Archive -LiteralPath $ArchivePath -DestinationPath $TemporaryRoot
    $ManifestPath = Join-Path $TemporaryRoot "release-manifest.json"
    $ExecutablePath = Join-Path $TemporaryRoot "CodexRadarSentinel.exe"
    $UninstallerPath = Join-Path $TemporaryRoot "uninstall.ps1"
    $Manifest = [IO.File]::ReadAllText($ManifestPath) | ConvertFrom-Json

    if ([int]$Manifest.schema_version -ne 1 -or
        -not ([string]$Manifest.product).Equals(
            "CodexRadarSentinel", [StringComparison]::Ordinal) -or
        -not ([string]$Manifest.platform).Equals(
            "windows", [StringComparison]::OrdinalIgnoreCase) -or
        -not ([string]$Manifest.runtime).Equals(
            $Runtime, [StringComparison]::OrdinalIgnoreCase) -or
        -not ([string]$Manifest.architecture).Equals(
            $Architecture, [StringComparison]::OrdinalIgnoreCase) -or
        -not ([string]$Manifest.version).Equals(
            $Version, [StringComparison]::OrdinalIgnoreCase) -or
        [bool]$Manifest.framework_dependent -or
        [int]$Manifest.minimum_windows_build -ne 17763) {
        throw "Release manifest does not match the expected Windows contract."
    }

    $ExecutableHash = (
        Get-FileHash -LiteralPath $ExecutablePath -Algorithm SHA256
    ).Hash.ToLowerInvariant()
    $UninstallerHash = (
        Get-FileHash -LiteralPath $UninstallerPath -Algorithm SHA256
    ).Hash.ToLowerInvariant()
    if ($ExecutableHash -ne ([string]$Manifest.executable_sha256).ToLowerInvariant() -or
        $UninstallerHash -ne ([string]$Manifest.uninstaller_sha256).ToLowerInvariant()) {
        throw "Packaged file SHA256 does not match release-manifest.json."
    }
    if ((Get-PeArchitecture -Path $ExecutablePath) -ne $Architecture) {
        throw "Packaged executable architecture does not match $Architecture."
    }

    $SelfTestPassed = $false
    if ($RunSelfTest) {
        $HostArchitecture = (
            [Runtime.InteropServices.RuntimeInformation]::OSArchitecture
        ).ToString().ToLowerInvariant()
        if ($HostArchitecture -ne $Architecture) {
            throw "Native self-test requires a $Architecture host; detected $HostArchitecture."
        }
        Invoke-PackagedSelfTest -Path $ExecutablePath
        $SelfTestPassed = $true
    }

    $EvidencePath = Join-Path $ArtifactsRoot "validation-$Architecture.json"
    $Evidence = [ordered]@{
        schema_version = 1
        platform = "windows"
        runtime = $Runtime
        architecture = $Architecture
        host_os = [Runtime.InteropServices.RuntimeInformation]::OSDescription
        host_architecture = (
            [Runtime.InteropServices.RuntimeInformation]::OSArchitecture
        ).ToString().ToLowerInvariant()
        host_build = [Environment]::OSVersion.Version.Build
        version = $Version
        archive_sha256 = $ActualArchiveHash
        executable_sha256 = $ExecutableHash
        native_self_test = $SelfTestPassed
        verified_utc = [DateTimeOffset]::UtcNow.ToString("O")
    }
    [IO.File]::WriteAllText(
        $EvidencePath,
        ($Evidence | ConvertTo-Json -Depth 4),
        [Text.UTF8Encoding]::new($false)
    )
    Write-Host "Verified Windows release: $ArchivePath"
    Write-Host "Validation evidence: $EvidencePath"
}
finally {
    if (Test-Path -LiteralPath $TemporaryRoot) {
        Assert-ChildPath -Parent ([IO.Path]::GetTempPath()) -Child $TemporaryRoot
        Remove-TemporaryDirectory -Path $TemporaryRoot
    }
}
