# Codex Radar Sentinel for Windows

This is the native Windows 10 version 1809+/11 status implementation of Codex Radar Sentinel. It uses .NET 8 WinForms and Windows APIs and is published as a self-contained application, so end users do not need to install .NET. Its data semantics, section order, published Intelligence Efficiency configurations, Insights, reset-credit protection, and degradation behavior track the macOS app, while its window and taskbar interactions follow Windows conventions.

## Platform isolation

Windows and macOS packages intentionally use different, exact asset contracts:

- Windows x64: `CodexRadarSentinel-<version>-Windows-x64.zip` plus `CodexRadarSentinel-<version>-Windows-x64.sha256`
- Windows ARM64: `CodexRadarSentinel-<version>-Windows-arm64.zip` plus `CodexRadarSentinel-<version>-Windows-arm64.sha256`
- macOS assets contain `-macOS` and are never considered by the Windows installer.

The installer uses an anchored, architecture-specific match and requires exactly one Windows ZIP. It then verifies the release SHA256, `release-manifest.json` (`platform: windows` and the exact runtime), and the packaged executable SHA256. A missing, ambiguous, mismatched, or macOS-only release fails safely before the installed app is touched.

## Ask Codex to install it

If you are using the Codex desktop app on Windows, copy this prompt into Codex. Allow network access and PowerShell execution when asked; administrator access is not required.

```text
Install Codex Radar Sentinel for Windows only: first confirm this PC runs Windows 10 1809+ or Windows 11 and detect x64 versus ARM64. Download and inspect https://raw.githubusercontent.com/WineChord/codex-radar/main/windows/install.ps1; allow it to select only the unique CodexRadarSentinel-<version>-Windows-x64.zip or CodexRadarSentinel-<version>-Windows-arm64.zip for this PC plus the matching .sha256 from https://github.com/WineChord/codex-radar/releases/latest. Never use a macOS .dmg, -macOS ZIP, or package for the other architecture. If the unique matching Windows asset and checksum are absent, stop and tell me instead of substituting another platform or architecture. Verify the release SHA256, the package's platform=windows/runtime manifest, and the executable SHA256; install for the current user in %LOCALAPPDATA%\Programs\CodexRadarSentinel, create the Start Menu shortcut, launch it, and confirm the process plus either its notification-area icon or taskbar text. Ask me before any required permission.
```

Codex can use the repository-managed [`windows/install.ps1`](install.ps1), which implements those checks, rollback, and process verification.

## Install directly

Download the installer script first so it can be inspected, then run it with Windows PowerShell:

```powershell
$ErrorActionPreference = "Stop"
$installer = Join-Path $env:TEMP "install-codex-radar.ps1"
Invoke-WebRequest -UseBasicParsing "https://raw.githubusercontent.com/WineChord/codex-radar/main/windows/install.ps1" -OutFile $installer -ErrorAction Stop
powershell.exe -NoProfile -ExecutionPolicy Bypass -File $installer
if ($LASTEXITCODE -ne 0) { throw "Codex Radar Sentinel installation failed with exit code $LASTEXITCODE" }
```

The `raw.githubusercontent.com/.../main/windows/install.ps1` URL exists only after this file has been merged into the repository's default branch; it returns 404 for an unmerged development branch. If this repository is already cloned, run the checked-out script directly:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\windows\install.ps1
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

- Switch between the existing notification-area icon and taskbar text placed immediately left of the input/notification area; the icon remains the default.
- Taskbar text keeps the same configurable macOS-style summary segments visible in a safe rounded no-activate window; it does not inject into or modify Explorer.
- Both locations support left-click to open or hide the dashboard and a complete right-click menu with Exit.
- When Codex exposes a managed control socket protected by a current-user ACL, the app first reuses that signed-in session through `codex app-server proxy --sock`. Handshake, authentication, or transport failures safely fall back to `codex app-server --listen stdio://` for local weekly and 5-hour quota.
- Real local weekly-quota observations in `Codex Quota`, with 24-hour, 7-day, and 30-day curves. Hover, drag, or use the arrow keys to inspect points; observed resets and data gaps remain explicit. History is shown but collapsed by default, and hiding it does not stop background sampling.
- The bottom `Layout` command opens a compact editor inside the current radar window. Drag or use arrows to reorder sections, then independently choose visibility and default-open state for sections and nested items. Current results, urgent alerts, and connection errors stay present; reset-credit attention or failed updates temporarily move first and cannot be hidden.
- CodexRadar notice, distributed Model IQ, per-task cost/runtime/pass count/rating, all published Intelligence Efficiency configurations, Quota Radar, Reset Radar, Fast Radar, community prompts, scenario recommendations, degradation alerts, and legacy contract compatibility.
- Insights accepts only a known schema and valid timestamps. Network failures, empty data, malformed payloads, or timestamp regression keep the last valid result instead of replacing the UI with damaged data.
- Reset-credit auto-use is strictly off by default. A request is sent only after explicit consent while the account and full credit set still match, the clock is continuous, the target is unique, and it is approximately 30 minutes from expiry. Unresolved requests reconcile read-only first; account, card-set, clock, or storage changes revoke consent and fail closed.
- A 60-second refresh loop, Windows notifications, Chinese/English UI, per-monitor DPI scaling, multi-monitor placement, and a single-instance guard. Dashboard cards are swapped atomically, and unchanged data updates only the timestamp instead of clearing the panel during a background refresh.
- A lightly transparent, taskbar-toned dashboard with rounded cards and centered, wrapping action labels. High-contrast mode disables window transparency. Chinese and English are checked at all three supported text sizes.
- Windows 10 version 1809 (build 17763) or newer, or Windows 11, on x64 or ARM64.
- Codex CLI installed and signed in for local quota. If it is not on `PATH`, set `CODEX_RADAR_CODEX_PATH` to `codex.exe` or `codex.cmd`.

Public CodexRadar data still works if Codex CLI is unavailable; only local quota displays an actionable connection message.

Explicit usage permissions and spending limits take precedence over remaining percentages; unknown permission cannot trigger a quota-recovery notification. A transient quota read retries once. Reset-credit auto-use preserves the same consent after a session ends before dispatch, then fully verifies again before retrying; account, credit-set, clock, or storage failures still revoke consent and preserve a local reason and timestamp. No reset credit is used by the diagnostic tests.

Switch locations from `Open Settings` in the dashboard's `Display & alerts` section, then choose `Status bar`; or right-click the current status surface and use `Status location`. Windows controls whether a notification-area icon moves into the `^` overflow. Taskbar text needs no overflow click: it follows the current taskbar immediately left of the input/notification area and hides while a full-screen app is active.

The managed channel validates the RFC 6455 handshake, masks every client frame, and handles fragmented messages plus Ping/Pong; the independent channel uses BOM-free UTF-8 JSON Lines. Both talk only to Codex app-server and never read, copy, or cache sign-in credentials. Managed fallback is allowed only before a safe read completes; a reset-credit write bound to a session cannot continue after that process ends. Windows self-tests cover the handshake proof, framing, masking, fallback classification, and BOM constraint. The dashboard shows its cached chrome immediately and merges background data afterward, so network waits and Codex binary discovery do not block a status-surface click. If a minute refresh changes only the fetch time, only the header timestamp is updated. When content changes, a hidden candidate control tree is fully built and laid out before one atomic swap; a render failure keeps the previous complete UI for the next retry instead of clearing it to white.

## Develop and test

```powershell
dotnet run --project .\windows\CodexRadar.Windows\CodexRadar.Windows.csproj

dotnet build .\windows\CodexRadar.Windows\CodexRadar.Windows.csproj -c Release
dotnet run --project .\windows\CodexRadar.Windows\CodexRadar.Windows.csproj -c Release --no-build -- --self-test
dotnet run --project .\windows\CodexRadar.Windows\CodexRadar.Windows.csproj -c Release --no-build -- --live-radar-self-test
dotnet run --project .\windows\CodexRadar.Windows\CodexRadar.Windows.csproj -c Release --no-build -- --live-quota-self-test
dotnet run --project .\windows\CodexRadar.Windows\CodexRadar.Windows.csproj -c Release --no-build -- --ui-self-test
dotnet run --project .\windows\CodexRadar.Windows\CodexRadar.Windows.csproj -c Release --no-build -- --taskbar-ui-self-test
```

Launch the GUI from a normal Windows PowerShell session, Start, or Explorer. If Codex Desktop runs the development build for you, allow host-context GUI and network execution. An isolated Windows user context cannot see the interactive user's Codex sign-in; public radar remains available, but local weekly/5h quota shows an actionable connection error.

## Publish Windows release assets

Create a self-contained release archive and checksum:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\windows\build.ps1 -Runtime win-x64
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\windows\build.ps1 -Runtime win-arm64
```

The version defaults to the project version; release automation may pass `-Version 0.1.72`. Release asset versions use `major.minor.patch` with an optional prerelease suffix; `+build` metadata is deliberately rejected because it makes updater asset lookup ambiguous. Publish both files from `artifacts\windows\release` without renaming them. For example:

```text
CodexRadarSentinel-0.1.72-Windows-x64.zip
CodexRadarSentinel-0.1.72-Windows-x64.sha256
CodexRadarSentinel-0.1.72-Windows-arm64.zip
CodexRadarSentinel-0.1.72-Windows-arm64.sha256
```

`-FrameworkDependent` remains available for development output, but deliberately does not create release assets. This prevents a package that needs a separate .NET runtime from being published under the self-contained installer contract.

Each ZIP has exactly three root entries: `CodexRadarSentinel.exe`, `uninstall.ps1`, and `release-manifest.json`. Manifest schema 1 records `product`, `platform`, `runtime`, `architecture`, `version`, `executable`, `executable_sha256`, `uninstaller`, `uninstaller_sha256`, `minimum_windows_build`, `framework_dependent`, and `generated_utc`. Installers and updaters should reject missing/extra nested entries and must not search recursively for a plausible executable.

## Compatibility and release validation

See [verification status and remaining release gates](VALIDATION.md) for the current evidence boundary.

The project targets `net8.0-windows10.0.17763.0` and treats platform-compatibility warnings as build errors. `.github/workflows/windows.yml` builds on Windows x64 and a native Windows 11 ARM64 runner, then runs the offline protocol/privacy suite, a WinForms visual smoke test, self-contained packaging, and native packaged-binary verification.

Each release candidate should also produce reproducible evidence on its target:

| Target | Execution |
| --- | --- |
| Windows 10 1809+ x64 | Physical machine or VM with `validate-compatibility.ps1 -Target windows-10-x64` |
| Windows 11 x64 | x64 runner, physical machine, or VM with `-Target windows-11-x64` |
| Windows 11 ARM64 | Native ARM64 runner or device with `-Target windows-11-arm64` |

```powershell
.\windows\verify-release.ps1 -Runtime win-x64 -RunSelfTest
.\windows\validate-lifecycle.ps1 `
  -Runtime win-x64 `
  -Archive .\artifacts\windows\release\CodexRadarSentinel-0.1.72-Windows-x64.zip `
  -Checksum .\artifacts\windows\release\CodexRadarSentinel-0.1.72-Windows-x64.sha256 `
  -RunLiveRadarRead `
  -RunLiveQuotaRead
.\windows\validate-compatibility.ps1 `
  -Target windows-11-x64 `
  -Executable .\artifacts\windows\win-x64\CodexRadar.Windows.exe `
  -RunLiveRadarRead `
  -RunLiveQuotaRead
```

The scripts verify OS build, process architecture, core tests, Chinese/English M/L/XL dashboard rendering, placement beside the real Explorer notification area plus the right-click Exit entry, exact ZIP entries, manifest contents, both SHA256 layers, and PE architecture, then write JSON evidence under `artifacts\windows`. Lifecycle validation passes the local archive and checksum explicitly to `install.ps1`, uses an isolated data root with destructive reset-credit behavior disabled, starts the installed app, exercises refresh diagnostics and UI, performs a verified upgrade, forces a post-replacement transaction failure to prove rollback, and runs the packaged uninstaller. The installer's default behavior remains the public latest GitHub Release path; `-PackageArchive` and `-PackageChecksum` must be provided together and receive the same package, hash, manifest, architecture, and signature checks. `-RunLiveRadarRead` validates the current public radar contract through cookie-free HTTPS requests and sends no credentials. `-RunLiveQuotaRead` performs a read-only check of the current user's real Codex sign-in and quota; neither diagnostic queries nor consumes reset credits. Desktop compatibility validation rejects Windows Server, and lifecycle evidence labels Server hosts explicitly. Real Windows 10 desktop behavior still requires running the matrix script on a Windows 10 machine or VM; compiling or testing on a newer client or Server host is not a substitute.

## Package trust and SmartScreen

The current community build may be unsigned. In that case Windows SmartScreen can show a first-run warning until the binary gains reputation. The installer warns for an unsigned executable, rejects any invalid Authenticode signature, and relies on the exact asset name plus both release/package SHA256 checks. That verifies the downloaded bytes against the files published by the GitHub repository, but it is not a substitute for a pinned code-signing identity if the GitHub release itself is compromised. Future official release automation should Authenticode-sign `CodexRadarSentinel.exe` before packaging; do not rename or repackage signed assets.

## Privacy

The app reads `%USERPROFILE%\.codex\auth.json` only when reset-credit checking is enabled or manually refreshed. A root-level or `tokens`-nested `access_token`/`accessToken` is sent only to the ChatGPT reset-credit endpoint, then discarded; it is never written to settings, logs, or protection state.

The credit cache stores only titles, status, local timestamps, type, and a full SHA-256 fingerprint of the original ID. The UI shows at most the first eight fingerprint characters. The fingerprint is irreversible; neither the raw ID nor its suffix is persisted. Auto-use consent, ledger, reconciliation, and revocation files contain only account/credit fingerprints, timestamps, random UUIDs/idempotency keys, and state—never access tokens, email addresses, or raw credit IDs. Loading legacy settings that contain `IdSuffix` immediately migrates and overwrites that field.

Quota history is stored separately at `%LOCALAPPDATA%\CodexRadarSentinel\weekly-quota-history-v1.json`. It contains only sample timestamps, weekly remaining percentages, and server reset times and retains at most 31 days. The directory, archive, and lock are restricted to the current Windows user; writes use an exclusive lock, a same-directory temporary file, write-through flushing, and atomic replacement. A corrupt archive produces a safe warning and is never overwritten or uploaded.

“Start with Windows” writes the installed executable path only to `HKCU\Software\Microsoft\Windows\CurrentVersion\Run`. The additional app alert sound is off by default; Windows controls system sounds for notification-area balloons through its notification and Focus settings.

[中文文档](README.zh-CN.md)
