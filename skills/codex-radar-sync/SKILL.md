# CodexRadar Sync

Use this skill when the user asks to keep Codex Radar Sentinel aligned with CodexRadar, mentions CodexRadar data format changes, asks why a CodexRadar-backed field is missing, or asks to prepare a release that depends on CodexRadar live data.

## Goal

Keep both the macOS menu-bar app and Windows notification-area app mapped to the latest public CodexRadar site and endpoint behavior:

- `https://codexradar.com/`
- `https://codexradar.com/current.json` (legacy; may redirect to homepage)
- `https://codexradar.com/feed.xml` (legacy; may redirect to homepage)
- `https://codexradar.com/api/model-ratings` (community model ratings)

## Workflow

1. Fetch the homepage, `current.json`, `feed.xml`, and `api/model-ratings`. Note the retrieval date, root keys or redirect target, changed field types, new visible site sections, and any new public links or APIs.
2. Compare the live payloads with both platform implementations:
   - macOS: `Sources/CodexRadarCore/RadarModels.swift`, `Sources/CodexRadarCore/NotificationPolicy.swift`, `Sources/CodexRadarSentinel/DashboardMenuView.swift`, and `Sources/CodexRadarSentinel/StatusMetric.swift`.
   - Windows: `windows/CodexRadar.Windows/RadarService.cs`, `windows/CodexRadar.Windows/CodexRadarHtmlParser.cs`, `windows/CodexRadar.Windows/NotificationPolicy.cs`, `windows/CodexRadar.Windows/DashboardForm.cs`, and `windows/CodexRadar.Windows/AppOptions.cs`.
3. Fix decoding before changing UI. JSON fields that may evolve from integer to decimal should use compatible numeric types and a display formatter.
4. Map useful capabilities on both platforms. Prefer a clear status value, compact dashboard detail, or low-noise notification behavior over exposing raw endpoint complexity. Platform-native styling may differ, but data, thresholds, event classification, and user-facing capability must stay aligned.
5. Add or update tests. For live endpoint compatibility, update `Tests/CodexRadarCoreTests/LiveCodexRadarContractTests.swift`; add the same payload shape to the Windows `--self-test` fixtures in `windows/CodexRadar.Windows/Program.cs`.
6. Update README screenshots and docs only after both apps render correctly in Chinese and English. If Windows UI screenshots are unavailable, the Windows build and `--self-test` are still mandatory.
7. Maintain `PROMPTS.md`: append the triggering user prompt and map it to clickable commit links. Commit messages for prompt-driven work should include `Prompt-Id: N`.

## Release Gate

Before creating or pushing a release, run:

```bash
./scripts/check_release_readiness.sh VERSION
```

This checks live CodexRadar endpoints, runs Swift tests with live contract checks enabled, rebuilds the macOS app, refreshes real status/menu screenshots, packages the release, and verifies checksum plus DMG integrity.

On a Windows 10 1809+/Windows 11 x64 or ARM64 runner, also run:

```powershell
dotnet build .\windows\CodexRadar.Windows\CodexRadar.Windows.csproj -c Release
dotnet run --project .\windows\CodexRadar.Windows\CodexRadar.Windows.csproj -c Release --no-build -- --self-test
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\windows\build.ps1 -Runtime win-x64
```

Build the ARM64 asset with `-Runtime win-arm64` before a release that publishes ARM64. Verify that each Windows ZIP contains exactly the three documented root entries and that its external SHA256, manifest file hashes, platform, runtime, architecture, and packaged `--self-test` all pass. Never substitute a macOS asset for a missing Windows asset or vice versa.

Also inspect the generated screenshots in:

- `docs/assets/zh/status-normal.png`
- `docs/assets/zh/menu-full.png`
- `docs/assets/en/status-normal.png`
- `docs/assets/en/menu-full.png`

If any menu-bar segment shows `--` while CodexRadar has a visible value on the website, treat it as a release blocker.

## Current Known Contract Notes

- As of 2026-06-15, CodexRadar says reset prediction, speed-window reminders, and historical windows are retired. `current.json` may return JSON again with official entitlement events; `feed.xml` may still redirect to homepage HTML.
- When JSON endpoints are unavailable, `CodexRadarClient` falls back to parsing the homepage Model IQ SVG `<title>` values and synthesizes a compatible `RadarCurrent` with `window_open = false`.
- Do not treat every `window_open = true` as a speed window. Current JSON can use `window_open` for official entitlement/reset-card events; only explicit speed/速蹬 wording should trigger speed-window UI and notifications.
- As of app v0.1.28, live UI should treat CodexRadar as a model-quality source first. The menu-bar `signal` metric is still the persisted key, but its user-facing label/value are Quality/质量 from Model IQ unless a legacy speed window or local limit is active.
- As of app v0.1.29, the dropdown should expose the public model-quality details CodexRadar shows on the homepage: runtime, cost, cache hit rate, and community rating. Keep these in the menu, not the default status title.
- As of app v0.1.30, CodexRadar HTTP requests must use `AppConstants.requestTimeoutSeconds`; otherwise one stuck endpoint can block future polling cycles and leave the status bar stale during an active window.
- Legacy CodexRadar schema v2 embedded Prediction and model IQ in `current.json`; keep those decoders because older fixtures and possible future JSON restoration still depend on them.
- `model_iq.latest.score` / homepage IQ values can be decimal, for example `62.5`; do not decode IQ as an integer.
- `rateLimitsByLimitId` can be JSON `null`; Windows and macOS must fall back to the root `rateLimits` object without failing local quota refresh.
- Schema v2 may provide only a root `window` payload. Normalize `open=true,status=none` to `open`, and a payload with `closed_at` to `closed`, consistently on both platforms.
