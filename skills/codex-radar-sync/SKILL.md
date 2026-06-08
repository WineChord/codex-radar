# CodexRadar Sync

Use this skill when the user asks to keep Codex Radar Sentinel aligned with CodexRadar, mentions CodexRadar data format changes, asks why a CodexRadar-backed field is missing, or asks to prepare a release that depends on CodexRadar live data.

## Goal

Keep the macOS menu bar app mapped to the latest public CodexRadar site and endpoint behavior:

- `https://codexradar.com/`
- `https://codexradar.com/current.json`
- `https://codexradar.com/feed.xml`

## Workflow

1. Fetch the homepage, `current.json`, and `feed.xml`. Note the retrieval date, root keys, changed field types, new visible site sections, and any new public links or APIs.
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

- CodexRadar schema v2 embeds Prediction and model IQ in `current.json`; the old `prediction.json` and `model-iq.json` endpoints may return HTTP 410.
- `current.json.model_iq.latest.score` can be decimal, for example `62.5`; do not decode it as an integer.
- CodexRadar IQ is experimental, so new `baseline`, `history`, token, cost, and task detail fields may appear without needing immediate UI exposure.
- `current.json.window_open` and RSS open/close events remain the highest-priority speed-window notification signals.
