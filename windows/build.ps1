[CmdletBinding()]
param(
    [ValidateSet("win-x64", "win-arm64")]
    [string]$Runtime = "win-x64",

    [ValidatePattern('^\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?$')]
    [string]$Version,

    [switch]$FrameworkDependent
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

function Assert-WindowsPlatform {
    if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) {
        throw "The Windows package must be built on Windows. Refusing to create a Windows-labelled asset on another platform."
    }
}

function Assert-ChildPath {
    param(
        [Parameter(Mandatory = $true)][string]$Parent,
        [Parameter(Mandatory = $true)][string]$Child
    )

    $resolvedParent = [IO.Path]::GetFullPath($Parent).TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
    $resolvedChild = [IO.Path]::GetFullPath($Child)
    if (-not $resolvedChild.StartsWith($resolvedParent, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to modify a path outside $resolvedParent"
    }
}

function Add-FileToZipArchive {
    param(
        [Parameter(Mandatory = $true)]$Archive,
        [Parameter(Mandatory = $true)][string]$SourcePath,
        [Parameter(Mandatory = $true)][string]$EntryName
    )

    $entry = $Archive.CreateEntry($EntryName, [IO.Compression.CompressionLevel]::Optimal)
    $entry.LastWriteTime = [DateTimeOffset](Get-Item -LiteralPath $SourcePath).LastWriteTime
    $sourceStream = $null
    $entryStream = $null
    try {
        $sourceStream = [IO.File]::OpenRead($SourcePath)
        $entryStream = $entry.Open()
        $sourceStream.CopyTo($entryStream, 1MB)
    }
    finally {
        if ($entryStream) { $entryStream.Dispose() }
        if ($sourceStream) { $sourceStream.Dispose() }
    }
}

function Add-BytesToZipArchive {
    param(
        [Parameter(Mandatory = $true)]$Archive,
        [Parameter(Mandatory = $true)][byte[]]$Bytes,
        [Parameter(Mandatory = $true)][string]$EntryName
    )

    $entry = $Archive.CreateEntry($EntryName, [IO.Compression.CompressionLevel]::Optimal)
    $entryStream = $null
    try {
        $entryStream = $entry.Open()
        $entryStream.Write($Bytes, 0, $Bytes.Length)
    }
    finally {
        if ($entryStream) { $entryStream.Dispose() }
    }
}

Assert-WindowsPlatform

$Project = Join-Path $PSScriptRoot "CodexRadar.Windows\CodexRadar.Windows.csproj"
$RepositoryRoot = Split-Path $PSScriptRoot -Parent
$ArtifactsRoot = Join-Path $RepositoryRoot "artifacts\windows"
$Output = Join-Path $ArtifactsRoot $Runtime
$ReleaseOutput = Join-Path $ArtifactsRoot "release"
$SelfContained = if ($FrameworkDependent) { "false" } else { "true" }
$Architecture = if ($Runtime -eq "win-arm64") { "arm64" } else { "x64" }

if (-not $Version) {
    [xml]$projectXml = [IO.File]::ReadAllText($Project)
    $Version = [string]($projectXml.Project.PropertyGroup.Version | Select-Object -First 1)
}
if ($Version -notmatch '^\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?$') {
    throw "Project version '$Version' is not a release-safe semantic version."
}

Assert-ChildPath -Parent $RepositoryRoot -Child $ArtifactsRoot
Assert-ChildPath -Parent $ArtifactsRoot -Child $Output
Assert-ChildPath -Parent $ArtifactsRoot -Child $ReleaseOutput

if (Test-Path -LiteralPath $Output) {
    Remove-Item -LiteralPath $Output -Recurse -Force
}
New-Item -ItemType Directory -Path $Output -Force | Out-Null

& dotnet publish $Project `
    --configuration Release `
    --runtime $Runtime `
    --self-contained $SelfContained `
    --output $Output `
    -p:Version=$Version `
    -p:PublishSingleFile=true `
    -p:IncludeNativeLibrariesForSelfExtract=true `
    -p:DebugType=None `
    -p:DebugSymbols=false

if ($LASTEXITCODE -ne 0) {
    throw "dotnet publish failed with exit code $LASTEXITCODE"
}

$PublishedExecutable = Join-Path $Output "CodexRadar.Windows.exe"
if (-not (Test-Path -LiteralPath $PublishedExecutable -PathType Leaf)) {
    throw "Publish completed without the expected Windows executable: $PublishedExecutable"
}

Write-Host "Windows publish output: $Output"

if ($FrameworkDependent) {
    Write-Host "Framework-dependent development output created. Release assets are intentionally not produced."
    exit 0
}

# The self-contained publish output is complete at this point. Remove only the
# runtime-specific MSBuild copy under this project so packaging does not require
# two full copies of the runtime on space-constrained Windows machines.
$ProjectDirectory = Split-Path $Project -Parent
$RuntimeIntermediate = Join-Path $ProjectDirectory "bin\Release\net8.0-windows\$Runtime"
Assert-ChildPath -Parent $ProjectDirectory -Child $RuntimeIntermediate
if (Test-Path -LiteralPath $RuntimeIntermediate) {
    Remove-Item -LiteralPath $RuntimeIntermediate -Recurse -Force
}

New-Item -ItemType Directory -Path $ReleaseOutput -Force | Out-Null
$AssetBaseName = "CodexRadarSentinel-$Version-Windows-$Architecture"
$ArchivePath = Join-Path $ReleaseOutput "$AssetBaseName.zip"
$ChecksumPath = Join-Path $ReleaseOutput "$AssetBaseName.sha256"
$TemporaryArchivePath = Join-Path $ArtifactsRoot (".asset-{0}.zip" -f [Guid]::NewGuid().ToString("N"))
$TemporaryChecksumPath = Join-Path $ArtifactsRoot (".asset-{0}.sha256" -f [Guid]::NewGuid().ToString("N"))
Assert-ChildPath -Parent $ArtifactsRoot -Child $TemporaryArchivePath
Assert-ChildPath -Parent $ArtifactsRoot -Child $TemporaryChecksumPath

try {
    $UninstallerPath = Join-Path $PSScriptRoot "uninstall.ps1"
    if (-not (Test-Path -LiteralPath $UninstallerPath -PathType Leaf)) {
        throw "Windows uninstaller is missing: $UninstallerPath"
    }

    $ExecutableHash = (Get-FileHash -LiteralPath $PublishedExecutable -Algorithm SHA256).Hash.ToLowerInvariant()
    $UninstallerHash = (Get-FileHash -LiteralPath $UninstallerPath -Algorithm SHA256).Hash.ToLowerInvariant()
    $ReleaseManifest = [ordered]@{
        schema_version = 1
        product = "CodexRadarSentinel"
        platform = "windows"
        runtime = $Runtime
        architecture = $Architecture
        version = $Version
        executable = "CodexRadarSentinel.exe"
        executable_sha256 = $ExecutableHash
        uninstaller = "uninstall.ps1"
        uninstaller_sha256 = $UninstallerHash
        minimum_windows_build = 17763
        framework_dependent = $false
        generated_utc = [DateTime]::UtcNow.ToString("o")
    }
    $Utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    $ManifestBytes = $Utf8NoBom.GetBytes(($ReleaseManifest | ConvertTo-Json -Depth 4))

    Add-Type -AssemblyName System.IO.Compression
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $archiveStream = $null
    $zipArchive = $null
    try {
        $archiveStream = [IO.File]::Open(
            $TemporaryArchivePath,
            [IO.FileMode]::CreateNew,
            [IO.FileAccess]::ReadWrite,
            [IO.FileShare]::None
        )
        $zipArchive = [IO.Compression.ZipArchive]::new(
            $archiveStream,
            [IO.Compression.ZipArchiveMode]::Create,
            $false
        )
        # Stream directly from publish output. Do not create a second 162 MB EXE copy.
        Add-FileToZipArchive -Archive $zipArchive -SourcePath $PublishedExecutable -EntryName "CodexRadarSentinel.exe"
        Add-FileToZipArchive -Archive $zipArchive -SourcePath $UninstallerPath -EntryName "uninstall.ps1"
        Add-BytesToZipArchive -Archive $zipArchive -Bytes $ManifestBytes -EntryName "release-manifest.json"
    }
    finally {
        if ($zipArchive) { $zipArchive.Dispose() }
        if ($archiveStream) { $archiveStream.Dispose() }
    }

    $ArchiveHash = (Get-FileHash -LiteralPath $TemporaryArchivePath -Algorithm SHA256).Hash.ToLowerInvariant()
    [IO.File]::WriteAllText(
        $TemporaryChecksumPath,
        "$ArchiveHash *$([IO.Path]::GetFileName($ArchivePath))`r`n",
        $Utf8NoBom
    )

    if (Test-Path -LiteralPath $ArchivePath) {
        Remove-Item -LiteralPath $ArchivePath -Force
    }
    if (Test-Path -LiteralPath $ChecksumPath) {
        Remove-Item -LiteralPath $ChecksumPath -Force
    }
    Move-Item -LiteralPath $TemporaryArchivePath -Destination $ArchivePath
    Move-Item -LiteralPath $TemporaryChecksumPath -Destination $ChecksumPath

    Write-Host "Windows release archive: $ArchivePath"
    Write-Host "Windows release checksum: $ChecksumPath"
    Write-Host "GitHub asset contract: $AssetBaseName.zip + $AssetBaseName.sha256"
}
finally {
    if (Test-Path -LiteralPath $TemporaryArchivePath) {
        Remove-Item -LiteralPath $TemporaryArchivePath -Force
    }
    if (Test-Path -LiteralPath $TemporaryChecksumPath) {
        Remove-Item -LiteralPath $TemporaryChecksumPath -Force
    }
}
