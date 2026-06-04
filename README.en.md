# Codex Radar Sentinel

[中文](README.md) | English

Full credit to [CodexRadar](https://codexradar.com/): this project depends on CodexRadar's public signals for Codex speed windows, resets, reset prediction, RSS events, and model IQ. Codex Radar Sentinel is a local macOS menu bar app that brings those public CodexRadar signals together with the user's local Codex quota state.

![Codex Radar Sentinel English menu bar status](docs/assets/en/status-normal.png)

## Install With Codex

If you use the Codex desktop app, you can copy this prompt into Codex. Grant Codex network access, shell execution, and permission to write to `/Applications`; if macOS asks for notification permission, allow it.

```text
Please install Codex Radar Sentinel on this Mac.

Requirements:
1. Open https://github.com/WineChord/codex-radar/releases/latest
2. Download the latest CodexRadarSentinel-*-macOS.dmg
3. Mount the DMG
4. Copy "Codex Radar Sentinel.app" into /Applications
5. Launch the app
6. If macOS asks for notification permission, tell me to allow it
7. After launch, read the menu bar status and confirm it shows something like 96%/75/low, 97%/75/low, or 96%/low

Please perform the installation and verification directly instead of only giving me instructions.
```

## Menu Bar Meaning

The menu bar title is intentionally compact:

```text
96%/75/low
```

The three values are:

- `96%`: weekly Codex quota remaining.
- `75`: Codex IQ score.
- `low`: reset / speed-window signal from CodexRadar.

When [CodexRadar](https://codexradar.com/) reports an active speed window, the menu bar item turns red with white text. The red emphasis can be dismissed manually; it also clears when the window closes or after the 30-minute emphasis window expires.

## Status States

These screenshots are real macOS menu bar captures. The script launches the real app, switches preview states, and crops only this app's menu bar item. They are not hand-drawn mocks and do not include other menu bar icons.

| Normal | Speed window | Limit reached | Custom |
| --- | --- | --- | --- |
| ![Normal status](docs/assets/en/status-normal.png) | ![Speed window status](docs/assets/en/status-speed.png) | ![Limit reached status](docs/assets/en/status-limit.png) | ![Custom status](docs/assets/en/status-custom.png) |

You can choose which values appear in the menu bar. For example, if you do not care about IQ, show only `96%/low`.

## Full Menu

This image is captured by the app itself from the real SwiftUI menu window on a high-resolution screen, and it is maintained together with the menu bar screenshots by `./scripts/update_readme_screenshots.sh`. The README displays it at 390px wide so it stays readable without taking over the page; open the source image for the full-resolution view.

<img src="docs/assets/en/menu-full.png" width="390" alt="Codex Radar Sentinel full English menu">

## What It Shows

- Weekly Codex quota remaining, read from the local Codex app-server.
- Short-window quota remaining, also from the local Codex app-server.
- [CodexRadar](https://codexradar.com/) current speed-window and reset status.
- [CodexRadar](https://codexradar.com/) 24h and 48h reset prediction.
- Codex IQ from the daily probe.

The app defaults to Chinese. English can be selected in the dropdown. Technical terms such as Codex, IQ, Reset, Prediction, and Radar are kept in English where they are clearer.

## Notifications

The app sends macOS notifications for:

- Speed window opened.
- Codex limit reset confirmed.
- Weekly quota falls below 30%.
- Weekly quota falls below 15%.
- Weekly quota recovers after a low-remaining state.
- Prediction rises to high, or CodexRadar explicitly marks it as should_notify.
- Codex IQ enters red or falls below 80.

Notification sound is off by default and can be enabled in the dropdown. Historical reset windows are seeded on first launch, so starting the app after a reset does not replay old reset notifications. If the first launch happens during an active speed window, it still notifies.

## Updates

Automatic updates are on by default. The app checks once 5 seconds after launch, then every 6 hours checks the latest GitHub Release, downloads the ZIP, verifies the release SHA256, replaces the installed app bundle, and reopens itself.

The dropdown also includes:

- `Check`: manually checks and installs a newer release.
- `Changelog`: opens the latest release notes.
- `GitHub ★`: opens the repository page.

Turn off `Auto update` in the dropdown if you prefer manual updates only.

## Preview Mode

Use the `Preview` segmented control in the dropdown to inspect local UI states:

- `Live`: real data.
- `Speed`: urgent speed-window UI, including the red menu bar item and red banner.
- `Reset`: confirmed reset UI.
- `Limit`: local quota-limit UI.

Preview mode only changes what the app displays. Notifications and persisted event memory still use live data.

For scripted UI checks, launch with:

```bash
CODEX_RADAR_PREVIEW=speedWindow swift run CodexRadarSentinel
```

Accepted values are `live`, `speedWindow`, `resetConfirmed`, and `blocked`.

## Data Sources

Codex Radar Sentinel reads these public CodexRadar endpoints:

- [CodexRadar homepage](https://codexradar.com/)
- [current.json](https://codexradar.com/current.json)
- [prediction.json](https://codexradar.com/prediction.json)
- [model-iq.json](https://codexradar.com/model-iq.json)
- [feed.xml](https://codexradar.com/feed.xml)

For local quota, it reads the Codex app-server:

```json
{"method":"account/rateLimits/read"}
```

It selects the `rateLimitsByLimitId.codex` bucket when present. The 5-hour bucket is shown as `Short`; the 10,080-minute bucket is shown as `Weekly`.

## Manual Install

Download the latest `.dmg` from GitHub Releases, open it, and drag `Codex Radar Sentinel.app` into `Applications`.

The `.zip` asset contains the same app bundle for users who prefer to copy it manually.

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

If Codex is installed somewhere other than the default app path, set:

```bash
CODEX_RADAR_CODEX_PATH=/path/to/codex
```

## Development

Run the test suite:

```bash
swift test
```

Build release packages:

```bash
swift build -c release
./scripts/build_app.sh
./scripts/package_release.sh 0.1.6
```

Update README menu bar and menu screenshots:

```bash
./scripts/update_readme_screenshots.sh
```

This script launches the real app and crops the macOS menu bar item. It also asks the app to render the full menu from its real SwiftUI view. The Mac must allow System Events accessibility access and screen capture.

Regenerate the macOS icon:

```bash
./scripts/generate_app_icon.sh
```

## Credits

Codex Radar Sentinel exists because [CodexRadar](https://codexradar.com/) publishes clear public signals for Codex speed windows, resets, reset prediction, RSS events, and model IQ. This app wraps those public signals together with the user's local Codex quota state in a macOS menu bar tool.

Codex Radar Sentinel is not affiliated with CodexRadar or OpenAI.
