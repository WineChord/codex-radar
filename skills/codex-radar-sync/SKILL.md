# CodexRadar Sync

Use this skill when the user asks to keep Codex Radar Sentinel aligned with CodexRadar, mentions CodexRadar data format changes, asks why a CodexRadar-backed field is missing, or asks to prepare a release that depends on CodexRadar live data.

## Goal

Keep the macOS menu bar app and native Windows status app mapped to the same latest public CodexRadar site and endpoint behavior:

- `https://codexradar.com/`
- `https://codexradar.com/current.json` (legacy; may redirect to homepage)
- `https://codexradar.com/feed.xml` (legacy; may redirect to homepage)
- `https://codexradar.com/api/model-ratings` (community model ratings)
- `https://codexradar.com/data/intelligence-efficiency.json` (distributed IQ, cost, and runtime points)
- `https://api.codexradar.com/api/v1/radar-insights` (scenario recommendations and degradation alerts)

## Workflow

1. Fetch the homepage, `current.json`, `feed.xml`, `api/model-ratings`, `data/intelligence-efficiency.json`, and `api.codexradar.com/api/v1/radar-insights`. Note the retrieval date, root keys or redirect target, changed field types, new visible site sections, and any new public links or APIs.
2. Compare the live payloads with both platform implementations:
   - macOS: `Sources/CodexRadarCore/RadarModels.swift`, `Sources/CodexRadarCore/NotificationPolicy.swift`, `Sources/CodexRadarSentinel/DashboardMenuView.swift`, and `Sources/CodexRadarSentinel/StatusMetric.swift`.
   - Windows: `windows/CodexRadar.Windows/RadarService.cs`, `RadarInsights.cs`, `IntelligenceEfficiency.cs`, `CodexRadarHtmlParser.cs`, `DashboardSnapshot.cs`, `DashboardForm.cs`, `QuotaHistory.cs`, and `DashboardLayout.cs`.
3. Fix decoding before changing UI. JSON fields that may evolve from integer to decimal should use compatible numeric types and a display formatter.
4. Map only useful new CodexRadar capabilities into both apps. Keep their data meaning, fallback order, cache validity, ordering, safety state, and user-visible detail aligned. Platform-native presentation can differ: prefer a clear menu-bar/taskbar value, compact detail, progressive disclosure, and low-noise notification behavior over exposing raw endpoint complexity.
5. Add or update tests. For live endpoint compatibility, update `Tests/CodexRadarCoreTests/LiveCodexRadarContractTests.swift`; add the equivalent Windows fixture/contract regression to the `--self-test` suite. Windows public endpoint fetches must remain cookie-free and must never attach local Codex credentials.
6. Update README screenshots and docs only after the app renders correctly in Chinese and English.
7. Maintain `PROMPTS.md`: append the triggering user prompt and map it to clickable commit links. Commit messages for prompt-driven work should include `Prompt-Id: N`.

## Release Gate

Before creating or pushing a macOS release, run:

```bash
./scripts/check_release_readiness.sh VERSION
```

This checks live CodexRadar endpoints, runs Swift tests with live contract checks enabled, rebuilds the app, refreshes real status/menu screenshots, packages the release, and verifies checksum plus DMG integrity.

Also inspect the generated screenshots in:

- `docs/assets/zh/status-normal.png`
- `docs/assets/zh/menu-full.png`
- `docs/assets/en/status-normal.png`
- `docs/assets/en/menu-full.png`

If any menu-bar segment shows `--` while CodexRadar has a visible value on the website, treat it as a release blocker.

Before creating or pushing a Windows release, run the offline suite, visual smoke test, packaging verifier, and the matching native compatibility target:

```powershell
dotnet build .\windows\CodexRadar.Windows\CodexRadar.Windows.csproj -c Release
dotnet run --project .\windows\CodexRadar.Windows\CodexRadar.Windows.csproj -c Release --no-build -- --self-test
dotnet run --project .\windows\CodexRadar.Windows\CodexRadar.Windows.csproj -c Release --no-build -- --ui-self-test
dotnet run --project .\windows\CodexRadar.Windows\CodexRadar.Windows.csproj -c Release --no-build -- --taskbar-ui-self-test
.\windows\build.ps1 -Runtime win-x64
.\windows\verify-release.ps1 -Runtime win-x64 -RunSelfTest
.\windows\validate-compatibility.ps1 -Target windows-11-x64 -Executable .\artifacts\windows\win-x64\CodexRadar.Windows.exe
```

Use `win-arm64` plus `windows-11-arm64` on a native ARM64 runner/device. Verify Windows 10 claims with `windows-10-x64` on a Windows 10 1809+ machine or VM. Treat a blank refresh, missing 19-point efficiency data, dropped valid Insights cache, fabricated quota-history sample, corrupt history overwrite, hidden critical state, raw reset-credit identifier on disk, wrong-platform package match, or any visible macOS/Windows data-semantic divergence as a release blocker.

## Current Known Contract Notes

- As of 2026-06-15, CodexRadar says reset prediction, speed-window reminders, and historical windows are retired. `current.json` may return JSON again with official entitlement events; `feed.xml` may still redirect to homepage HTML.
- When JSON endpoints are unavailable, `CodexRadarClient` falls back to parsing the homepage Model IQ SVG `<title>` values and synthesizes a compatible `RadarCurrent` with `window_open = false`.
- Do not treat every `window_open = true` as a speed window. Current JSON can use `window_open` for official entitlement/reset-card events; only explicit speed/速蹬 wording should trigger speed-window UI and notifications.
- As of app v0.1.28, live UI should treat CodexRadar as a model-quality source first. The menu-bar `signal` metric is still the persisted key, but its user-facing label/value are Quality/质量 from Model IQ unless a legacy speed window or local limit is active.
- As of app v0.1.29, the dropdown should expose the public model-quality details CodexRadar shows on the homepage: runtime, cost, cache hit rate, and community rating. Keep these in the menu, not the default status title.
- As of app v0.1.30, CodexRadar HTTP requests must use `AppConstants.requestTimeoutSeconds`; otherwise one stuck endpoint can block future polling cycles and leave the status bar stale during an active window.
- Legacy CodexRadar schema v2 embedded Prediction and model IQ in `current.json`; keep those decoders because older fixtures and possible future JSON restoration still depend on them.
- `model_iq.latest.score` / homepage IQ values can be decimal, for example `62.5`; do not decode IQ as an integer.
- As of 2026-07-14, CodexRadar describes the 5h limit as temporarily inactive and renders only the active 7d Quota Radar column. `current.json` may still carry derived `five_h` row values while `basis_window_label` is `7d`; follow the basis label for UI visibility instead of exposing values the site intentionally hides.
- The local Codex app-server may return only a 10,080-minute weekly window while 5h is paused. Never infer 5h from the shortest available window; show local 5h UI only for an explicitly returned window near 300 minutes so it can disappear and return dynamically.
- As of 2026-07-17, Model IQ uses distributed community runs across roughly 80-110 tasks per model configuration. `cost_usd` and `wall_seconds` are totals for all selected tasks; user-facing cost and time must prefer `average_cost_usd`, `average_task_seconds`, and `average_task_time_human`.
- The distributed homepage chart publishes fallback values in IQ-view circle `aria-label` attributes rather than the old SVG `<title>` format. Keep both parsers, restrict the new parser to `data-model-iq-chart-view="iq"`, and ignore duplicate value/cost/time chart circles.
- `model_iq.data_source.url` points to the public distributed radar. Surface it as an optional menu link, while keeping the default status title compact.
- As of 2026-07-22, the homepage renders its 19-point Intelligence Efficiency matrix from `data/intelligence-efficiency.json`; raw homepage HTML no longer contains the generated model cards. Merge this lightweight same-origin payload into `current.json`, preserve richer matching fields such as cache hit rate, and use it as the Model IQ fallback when the static homepage chart is absent.
- As of 2026-07-26, the homepage loads scenario recommendations and degradation alerts from `https://api.codexradar.com/api/v1/radar-insights`. Treat every declared `schema` as a strict `1` compatibility gate, accept empty recommendation/alert lists, ignore unknown optional fields, and keep the last valid result on endpoint, decoding, or timestamp-regression failure. Fetch independently at most once per 10-minute monotonic cache window, never attach local Codex credentials, and keep these insights out of the default status title and notification stream.
- As of app v0.1.62, both platforms retain up to 31 days of real local weekly-quota observations and expose 24-hour, 7-day, and 30-day views. Record only a newly successful local weekly bucket, preserve double precision, reset jumps, and continuity gaps, and continue sampling when the quota section or history disclosure is hidden. Layout visibility changes presentation only; current results, urgent alerts, connection errors, reset-credit attention, and failed updates retain their forced visibility rules.
