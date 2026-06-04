# Codex Radar Sentinel

Codex Radar Sentinel is a local macOS menu bar app for Codex usage timing. It keeps the most important signal visible without opening CodexRadar or checking the Codex usage page.

The menu bar title is intentionally compact:

```text
WK 98% · IQ75 · 低
```

When CodexRadar reports an active speed window, the title switches to:

```text
速蹬 · WK 98%
```

## What It Shows

- Weekly Codex quota remaining, read from the local Codex app-server.
- Short-window quota remaining, also from the local Codex app-server.
- CodexRadar current speed-window and reset status.
- CodexRadar 24h and 48h reset prediction.
- Codex model IQ score from the daily probe.

## Notifications

The app sends macOS notifications for events that should not require manual checking:

- Speed window opened.
- Codex limit reset confirmed.
- Weekly quota falls below 30%.
- Weekly quota falls below 15%.
- Weekly quota recovers after a low-remaining state.
- Prediction rises to high, or CodexRadar explicitly marks it as notify-worthy.
- Codex IQ falls into a red or sub-80 state.

Historical reset windows are seeded on first launch, so starting the app after a reset does not replay old reset notifications. If the first launch happens during an active speed window, it still notifies.

## Data Sources

CodexRadar Sentinel reads:

- `https://codexradar.com/current.json`
- `https://codexradar.com/prediction.json`
- `https://codexradar.com/model-iq.json`

For local quota, it starts a long-lived Codex app-server process and sends:

```json
{"method":"account/rateLimits/read"}
```

It selects the `rateLimitsByLimitId.codex` bucket when present. The 5-hour bucket is shown as `Short`; the 10,080-minute bucket is shown as `Weekly`.

## Run Locally

Build a normal macOS `.app` bundle:

```bash
./scripts/build_app.sh
open ".build/Codex Radar Sentinel.app"
```

You can also run the executable directly during development:

```bash
swift run CodexRadarSentinel
```

The bundled app is local-only. It does not need App Store publishing.

If Codex is installed somewhere other than the default app path, set:

```bash
CODEX_RADAR_CODEX_PATH=/path/to/codex
```

## Development

Run the test suite:

```bash
swift test
```

Build release artifacts:

```bash
swift build -c release
./scripts/build_app.sh
```
