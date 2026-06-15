# CodexRadar Sync

Use this skill when the user asks to keep Codex Radar Sentinel aligned with CodexRadar, mentions CodexRadar data format changes, asks why a CodexRadar-backed field is missing, or asks to prepare a release that depends on CodexRadar live data.

## Goal

Keep the macOS menu bar app mapped to the latest public CodexRadar site and endpoint behavior:

- `https://codexradar.com/`
- `https://codexradar.com/current.json` (legacy; may redirect to homepage)
- `https://codexradar.com/feed.xml` (legacy; may redirect to homepage)
- `https://codexradar.com/api/model-ratings` (community model ratings)

## Workflow

1. Fetch the homepage, `current.json`, `feed.xml`, and `api/model-ratings`. Note the retrieval date, root keys or redirect target, changed field types, new visible site sections, and any new public links or APIs.
2. Compare the live payloads with `Sources/CodexRadarCore/RadarModels.swift`, `Sources/CodexRadarCore/NotificationPolicy.swift`, `Sources/CodexRadarSentinel/DashboardMenuView.swift`, and `Sources/CodexRadarSentinel/StatusMetric.swift`.
3. Fix decoding before changing UI. JSON fields that may evolve from integer to decimal should use compatible numeric types and a display formatter.
4. Map only useful new CodexRadar capabilities into the macOS app. Prefer clear menu-bar value, compact menu detail, or low-noise notification behavior over exposing raw endpoint complexity.
5. Add or update tests. For live endpoint compatibility, update `Tests/CodexRadarCoreTests/LiveCodexRadarContractTests.swift`.
6. Update README screenshots and docs only after the app renders correctly in Chinese and English.
7. Maintain `PROMPTS.md`: append the triggering user prompt and map it to clickable commit links. Commit messages for prompt-driven work should include `Prompt-Id: N`.

## Release Gate

Before creating or pushing a release, run:

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

## Current Known Contract Notes

- As of 2026-06-15, CodexRadar says reset prediction, speed-window reminders, and historical windows are retired. `current.json` may return JSON again with official entitlement events; `feed.xml` may still redirect to homepage HTML.
- When JSON endpoints are unavailable, `CodexRadarClient` falls back to parsing the homepage Model IQ SVG `<title>` values and synthesizes a compatible `RadarCurrent` with `window_open = false`.
- Do not treat every `window_open = true` as a speed window. Current JSON can use `window_open` for official entitlement/reset-card events; only explicit speed/速蹬 wording should trigger speed-window UI and notifications.
- As of app v0.1.28, live UI should treat CodexRadar as a model-quality source first. The menu-bar `signal` metric is still the persisted key, but its user-facing label/value are Quality/质量 from Model IQ unless a legacy speed window or local limit is active.
- As of app v0.1.29, the dropdown should expose the public model-quality details CodexRadar shows on the homepage: runtime, cost, cache hit rate, and community rating. Keep these in the menu, not the default status title.
- Legacy CodexRadar schema v2 embedded Prediction and model IQ in `current.json`; keep those decoders because older fixtures and possible future JSON restoration still depend on them.
- `model_iq.latest.score` / homepage IQ values can be decimal, for example `62.5`; do not decode IQ as an integer.
