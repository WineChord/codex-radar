# Codex Radar Sentinel for Windows

This is the native Windows 10/11 notification-area implementation of Codex Radar Sentinel. It uses .NET 8 WinForms and Windows APIs and is published as a self-contained application, so end users do not need to install .NET.

## Platform isolation

Windows and macOS packages intentionally use different, exact asset contracts:

- Windows x64: `CodexRadarSentinel-<version>-Windows-x64.zip` plus `CodexRadarSentinel-<version>-Windows-x64.sha256`
- Windows ARM64: `CodexRadarSentinel-<version>-Windows-arm64.zip` plus `CodexRadarSentinel-<version>-Windows-arm64.sha256`
- macOS assets contain `-macOS` and are never considered by the Windows installer.

The installer uses an anchored, architecture-specific match and requires exactly one Windows ZIP. It then verifies the release SHA256, `release-manifest.json` (`platform: windows` and the exact runtime), and the packaged executable SHA256. A missing, ambiguous, mismatched, or macOS-only release fails safely before the installed app is touched.

## Ask Codex to install it

If you are using the Codex desktop app on Windows, copy this prompt into Codex. Allow network access and PowerShell execution when asked; administrator access is not required.

```text
Install Codex Radar Sentinel for Windows only: first confirm this PC runs Windows 10 1809+ or Windows 11 and detect x64 versus ARM64. From https://github.com/WineChord/codex-radar/releases/latest select exactly CodexRadarSentinel-<version>-Windows-x64.zip or CodexRadarSentinel-<version>-Windows-arm64.zip for this PC plus the matching .sha256; never use a macOS .dmg, -macOS ZIP, or package for the other architecture. If the unique matching Windows asset and checksum are absent, stop and tell me instead of substituting another platform or architecture. Verify SHA256 and the package's Windows manifest, install for the current user in %LOCALAPPDATA%\Programs\CodexRadarSentinel, create the Start Menu shortcut, launch it, and confirm the process and notification-area icon; ask me before any required permission.
```

Codex can use the repository-managed [`windows/install.ps1`](install.ps1), which implements those checks, rollback, and process verification.

## Install directly

Download the installer script first so it can be inspected, then run it with Windows PowerShell:

```powershell
$installer = Join-Path $env:TEMP "install-codex-radar.ps1"
Invoke-WebRequest -UseBasicParsing "https://raw.githubusercontent.com/WineChord/codex-radar/main/windows/install.ps1" -OutFile $installer
powershell.exe -NoProfile -ExecutionPolicy Bypass -File $installer
if ($LASTEXITCODE -ne 0) { throw "Codex Radar Sentinel installation failed with exit code $LASTEXITCODE" }
```

Add `-StartWithWindows` to opt in to per-user startup:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File $installer -StartWithWindows
```

The default installation directory is `%LOCALAPPDATA%\Programs\CodexRadarSentinel`. The Start Menu shortcut and optional startup value are also per-user; the installer never writes to `Program Files`, HKLM, or another user's profile. During an upgrade it stops only Codex Radar processes running from that installation directory. If installation or startup verification fails, the previous files, shortcut, startup value, and running state are restored.

The way to run locally while developing is:
```powershell
Set-Location Path\to\your\codex-radar

dotnet run --project .\windows\CodexRadar.Windows\CodexRadar.Windows.csproj -c Release
```

## Uninstall

Run the installed uninstaller. It removes the per-user app, shortcut, startup value, and cached settings:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$env:LOCALAPPDATA\Programs\CodexRadarSentinel\uninstall.ps1"
```

Use `-KeepData` to retain settings and sanitized reset-card metadata.

## Features and requirements

- Native taskbar notification-area icon; left-click opens or hides the dashboard.
- Native right-click menu with Open, Refresh, Start with Windows, reset-credit checks, and Exit.
- Local weekly and 5-hour quota from `codex app-server --listen stdio://`.
- CodexRadar notice, Model IQ, model quality, community rating, Quota Radar, Reset Radar, community prompt, Prediction, and legacy speed-window compatibility.
- A 60-second refresh loop, Windows notifications, Chinese/English UI, per-monitor DPI scaling, multi-monitor placement, and a single-instance guard.
- Windows 10 version 1809 (build 17763) or newer, or Windows 11, on x64 or ARM64.
- Codex CLI installed and signed in for local quota. If it is not on `PATH`, set `CODEX_RADAR_CODEX_PATH` to `codex.exe` or `codex.cmd`.

Public CodexRadar data still works if Codex CLI is unavailable; only local quota displays an actionable connection message.

Local quota uses BOM-free UTF-8 JSON Lines with `codex app-server`; a BOM on the first RPC makes Codex reject initialization and leaves weekly/5h as `--`. The Windows self-test guards this protocol detail. The dashboard shows its cached chrome immediately and merges background data afterward, so network waits and Codex binary discovery do not block a tray click.

## Develop and test

```powershell
dotnet run --project .\windows\CodexRadar.Windows\CodexRadar.Windows.csproj

dotnet build .\windows\CodexRadar.Windows\CodexRadar.Windows.csproj -c Release
dotnet run --project .\windows\CodexRadar.Windows\CodexRadar.Windows.csproj -c Release --no-build -- --self-test
```

Launch the GUI from a normal Windows PowerShell session, Start, or Explorer. If Codex Desktop runs the development build for you, allow host-context GUI and network execution. An isolated Windows user context cannot see the interactive user's Codex sign-in; public radar remains available, but local weekly/5h quota shows an actionable connection error.

## Publish Windows release assets

Create a self-contained release archive and checksum:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\windows\build.ps1 -Runtime win-x64
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\windows\build.ps1 -Runtime win-arm64
```

The version defaults to the project version; release automation may pass `-Version 0.1.49`. Release asset versions use `major.minor.patch` with an optional prerelease suffix; `+build` metadata is deliberately rejected because it makes updater asset lookup ambiguous. Publish both files from `artifacts\windows\release` without renaming them. For example:

```text
CodexRadarSentinel-0.1.49-Windows-x64.zip
CodexRadarSentinel-0.1.49-Windows-x64.sha256
CodexRadarSentinel-0.1.49-Windows-arm64.zip
CodexRadarSentinel-0.1.49-Windows-arm64.sha256
```

`-FrameworkDependent` remains available for development output, but deliberately does not create release assets. This prevents a package that needs a separate .NET runtime from being published under the self-contained installer contract.

Each ZIP has exactly three root entries: `CodexRadarSentinel.exe`, `uninstall.ps1`, and `release-manifest.json`. Manifest schema 1 records `product`, `platform`, `runtime`, `architecture`, `version`, `executable`, `executable_sha256`, `uninstaller`, `uninstaller_sha256`, `minimum_windows_build`, `framework_dependent`, and `generated_utc`. Installers and updaters should reject missing/extra nested entries and must not search recursively for a plausible executable.

## Package trust and SmartScreen

The current community build may be unsigned. In that case Windows SmartScreen can show a first-run warning until the binary gains reputation. The installer warns for an unsigned executable, rejects any invalid Authenticode signature, and relies on the exact asset name plus both release/package SHA256 checks. That verifies the downloaded bytes against the files published by the GitHub repository, but it is not a substitute for a pinned code-signing identity if the GitHub release itself is compromised. Future official release automation should Authenticode-sign `CodexRadarSentinel.exe` before packaging; do not rename or repackage signed assets.

## Privacy

The app reads `%USERPROFILE%\.codex\auth.json` only when reset-credit checking is enabled or manually refreshed. A root-level or `tokens`-nested `access_token`/`accessToken` is sent only to the ChatGPT reset-credit endpoint and immediately discarded. Cached settings contain only card titles, statuses, local timestamps, and the last six ID characters. “Start with Windows” writes the installed executable path only to `HKCU\Software\Microsoft\Windows\CurrentVersion\Run`. The additional app alert sound is off by default; Windows controls system sounds for notification-area balloons through its notification and Focus settings.

[中文文档](README.zh-CN.md)
