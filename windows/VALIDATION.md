# Windows validation and release gates

The Windows implementation targets the v0.1.72 release line and incorporates
`WineChord/codex-radar` main through `e5ddfd7`. These are validation builds, not a
published Windows release. macOS sources, tests, assets, and build scripts are
unchanged relative to that upstream revision.

## Behavior covered

| Area | Implementation and regression coverage |
| --- | --- |
| Current Codex quota | Managed-session reuse with a private-directory/AF_UNIX boundary, verified WebSocket framing, standalone fallback, explicit usage permission and spending-limit flags, and one bounded transient read retry. No credential file is read by the quota path. |
| Public radar | All usable published Intelligence Efficiency configurations, including schema 2 integral decimal counts and fractional cache rates; average-based Insights; current and legacy notice, community, Reset Radar, and Fast Radar formats. Public requests negotiate compressed responses within the existing timeout and carry no local credentials or cookies. Live diagnostics report feed failures instead of accepting an incomplete configuration set. |
| Local history and layout | Real weekly-quota observations, 31-day retention, reset/gap semantics, keyboard-accessible charts, section and nested-item visibility/order, and forced visibility for safety failures. |
| Reset-credit safety | Default-off explicit consent, account and complete-credit-set binding, clock checks, durable unresolved-operation reconciliation, pre-dispatch recovery, persisted revocation reasons, current-user storage, and SHA-256 fingerprints instead of raw ID fragments. |
| Windows presentation | Lightly translucent rounded dashboard, centered/wrapping labels, Chinese and English at M/L/XL, collapsed and expanded states, warning visibility, timestamp-only refresh without control-tree replacement, and an atomic swap on content changes. |
| Status surfaces | Notification-area icon or optional taskbar text left of the input/notification region; open/hide and right-click Exit. No Explorer injection. |
| Packaging | Exact platform/architecture asset names, manifest and executable checks, published checksum verification, per-user installation, upgrade, rollback after replacement, and uninstall. |

## Verification status

Local verification date: **2026-09-22**.

| Target | Evidence | Remaining limitations / release gate |
| --- | --- | --- |
| Windows 11 x64, build 26200 | Build; offline regressions; read-only live public-radar and signed-in quota checks; dashboard and Explorer taskbar checks; self-contained package verification; isolated install/start, upgrade, injected-failure rollback/restart, and uninstall. | Upstream pull-request checks require maintainer approval before they can run. |
| Windows 10 1809+ x64 | Minimum supported API target is build 17763; platform-compatibility warnings fail the build. | Native Windows 10 client/VM execution of both validation scripts is still required. Windows 11 and Windows Server results do not substitute for this. |
| Windows 11 ARM64, native hosted runner | Native build and offline tests; Chinese/English M/L/XL dashboard and Explorer taskbar checks; self-contained package and native binary verification; isolated install/start, upgrade, injected-failure rollback/restart, and uninstall. | No signed-in live Codex quota check or physical ARM64 device session was performed on this runner. |

The [Windows CI run for `dc51d38`](https://github.com/print-happy/codex-radar/actions/runs/35731014683)
passed both the x64 Windows Server 2022 job and the native Windows 11 ARM64 job.
Each job retains its verified package, checksum, package-verification JSON, and
lifecycle JSON as an architecture-specific artifact. The x64 Server result is
additional automation coverage, not a substitute for Windows 10 client testing.
The subsequent validation-note update does not change the tested Windows code,
packaging scripts, or workflow.

The current checks do not claim a multi-day soak test, every third-party taskbar
replacement, or every monitor/DPI arrangement. High-contrast mode removes window
transparency; full system-wide dark-theme matching is not claimed.

## Reproduce

Use the commands in the [Windows guide](README.md#compatibility-and-release-validation)
on the target operating system. `validate-compatibility.ps1` refuses mismatched
architectures and Windows Server. `validate-lifecycle.ps1` uses a temporary
installation and isolated data, refuses to replace an existing Start Menu
shortcut, and disables reset-credit queries and auto-use. The live quota check is
read only; no validation test consumes real reset credits.

The scripts write timestamped JSON evidence with binary/package SHA-256 values
under `artifacts/windows`. The Windows workflow retains packages and validation
evidence as build artifacts, not public releases. Do not attach real account
screenshots, identifiers, local paths, tokens, or logs to public reviews.

Online installation becomes available only after the Windows installer is on
the default branch and a stable release includes matching Windows assets and
checksums. Until then, use the documented source-launch path.
