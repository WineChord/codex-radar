# Codex Radar Sentinel

[中文](README.md) | English

Full credit to [CodexRadar](https://codexradar.com/): this project is built on CodexRadar's public signals. CodexRadar previously published Codex speed windows, resets, reset prediction, RSS events, and model IQ; it now focuses on model quality. Codex Radar Sentinel is a local macOS menu bar app that brings the currently public CodexRadar Model IQ together with the user's local Codex quota state, while keeping compatibility if the old reset/speed endpoints return.

![Codex Radar Sentinel English menu bar status](docs/assets/en/status-normal.png)

## News

<details>
<summary><strong>v0.1.27: CodexRadar homepage fallback</strong> - After the old JSON/RSS endpoints were retired, Model IQ is read from the homepage.</summary>

<img src="docs/assets/en/menu-full.png" width="390" alt="Codex Radar Sentinel CodexRadar homepage fallback screenshot">

- CodexRadar has retired reset prediction, speed-window alerts, and historical windows. The old `/current.json` and `/feed.xml` endpoints now return the homepage.
- The app detects homepage HTML, extracts the latest public Model IQ, and synthesizes a compatible “no speed window” state.
- Local Codex quota, IQ, and the main menu continue to work without surfacing a JSON decoding error.

</details>

<details>
<summary><strong>v0.1.23: Collapsed rows are easier to open</strong> - Click the title, icon, or trailing status to expand; no precise chevron click required.</summary>

<img src="docs/assets/en/news-pacing.png" width="390" alt="Codex Radar Sentinel pace strategy screenshot">

- `Pace rule` and `Menu bar advanced` headers are now full-row buttons.
- The chevron is only a visual hint; the title, icon, and trailing status are clickable too.
- This makes frequent menu-bar checks less fiddly on high-resolution displays.

</details>

<details>
<summary><strong>v0.1.22: Strategy cards switch directly</strong> - No unreliable menu picker inside the menu bar panel.</summary>

- `Pace` compares target remaining with actual weekly quota remaining, then tells you whether there is room to spend more or slow down.
- After expanding `Pace rule`, click any strategy explanation card to switch.
- The active strategy is highlighted and marked `Current`, so the selected rule is always visible.

</details>

<details>
<summary><strong>v0.1.21: Multiple pacing strategies</strong> - Plan weekly quota around different working styles.</summary>

<img src="docs/assets/en/news-pacing.png" width="390" alt="Codex Radar Sentinel usage pace screenshot">

- Added `Time`, `Daily`, `Reserve`, `Workdays`, and `Front-load`.
- Each rule explains its formula, refresh granularity, and best-use case.
- The optional `Pace` menu-bar segment can show target remaining directly, such as `R80%`.

</details>

<details>
<summary><strong>v0.1.19: Pace became target remaining</strong> - “How much should be left now” is easier than “how much should be used”.</summary>

- The pace section now explains `Target left`, `Actual left`, and `Can spend`.
- If target remaining is 80% and actual remaining is 90%, the app says there is room to spend more.
- This better matches how people manage a weekly quota without mental reverse math.

</details>

<details>
<summary><strong>v0.1.17: Advanced menu-bar compaction</strong> - Save status-bar space without losing readability.</summary>

<p>
  <img src="docs/assets/en/status-normal.png" height="30" alt="Normal status">
  <img src="docs/assets/en/status-custom.png" height="30" alt="Custom status">
</p>

- Tune separator, side padding, and font scale.
- Show IQ as raw, `/10` integer, or `/10` decimal.
- Hide `%` or keep only the segments that matter to you.

</details>

<details>
<summary><strong>v0.1.11: Optional 5h short-window segment</strong> - Weekly quota is not the only limit worth watching.</summary>

- `5h` is off by default and can be enabled manually.
- When enabled, the title can look like `96%/99%/62/low`; the second percentage is the short window.
- Useful when weekly quota is fine but the short window is the real blocker.

</details>

<details>
<summary><strong>v0.1.7: Prompt Log is open source</strong> - The product prompts, feedback, screenshot notes, and release asks are part of the repo.</summary>

- Added [Prompt Log](PROMPTS.md) for the user's direct product requests, design feedback, and verification asks.
- Timestamps, local paths, screenshot cache paths, and security-sensitive details are removed.
- Later prompts are mapped to the real commits that implemented them, with clickable commit links.

</details>

<details>
<summary><strong>v0.1.4: Automatic updates</strong> - Download, verify, replace, and reopen from GitHub Releases.</summary>

- Auto update is on by default: first check after launch, then every 6 hours.
- Release ZIPs are verified by SHA256 before replacing the app bundle.
- Failed updates keep the current app running and pause short-term automatic retries for that same version.

</details>

<details>
<summary><strong>v0.1.0: First menu-bar dashboard</strong> - CodexRadar public signals plus local Codex quota in one macOS status item.</summary>

<p>
  <img src="docs/assets/en/status-normal.png" height="30" alt="Normal status">
  <img src="docs/assets/en/status-speed.png" height="30" alt="Speed status">
  <img src="docs/assets/en/status-limit.png" height="30" alt="Limit status">
</p>

- Always-on weekly quota, Codex IQ, and CodexRadar signal.
- Red menu-bar emphasis and macOS notification when a speed window opens.
- Reset events, prediction, IQ, and local quota status in one dropdown.

</details>

## Install With Codex

If you use the Codex desktop app, you can copy this prompt into Codex. Grant Codex network access, shell execution, and permission to write to `/Applications`; if macOS asks for notification permission, allow it.

```text
Directly install Codex Radar Sentinel: download latest macOS package from https://github.com/WineChord/codex-radar/releases/latest, install to /Applications, launch, confirm menu bar; ask for permissions if needed.
```

## Menu Bar Meaning

The menu bar title is intentionally compact:

```text
96%/62/low
```

The three values are:

- `96%`: weekly Codex quota remaining.
- `62`: Codex IQ score. The menu bar truncates it to a whole number by default to save space; the Codex IQ section in the dropdown shows the precise value, such as `62.5`.
- `low`: CodexRadar signal. CodexRadar has currently retired reset prediction and speed-window alerts, so live mode normally shows low risk; if the legacy endpoints return, the app will keep recognizing window and reset states.

The `Menu bar segments` setting can also enable:

- `5h`: adds the 5-hour short-window quota to the menu bar. It is off by default; when enabled, the title looks like `96%/99%/62/low`.
- `Pace`: adds the weekly quota that should remain at the current point in the reset window. It is off by default; English shows it as `R80%`.

`Pace rule` is collapsed by default. Click the whole header row to expand or collapse it; after expanding, click any rule card to switch. The app explains each rule's formula, refresh granularity, and best use case.

`Menu bar advanced` is collapsed by default. Click the whole header row to expand or collapse it. When expanded, it can tune the separator, side padding, font scale, IQ `/10` display, and whether `%` is kept in the menu bar. These settings only affect the menu bar title; dropdown values stay complete.

When compatible signals from [CodexRadar](https://codexradar.com/) report an active speed window, the menu bar item turns red with white text. The red emphasis can be dismissed manually; it also clears when the window closes or after the 30-minute emphasis window expires. CodexRadar's current homepage says speed-window alerts have been retired, so live mode will not invent a speed-window alert.

## Status States

These screenshots are real macOS menu bar captures. The script launches the real app, switches preview states, and crops only this app's menu bar item. They are not hand-drawn mocks and do not include other menu bar icons.

| Normal | Speed window | Limit reached | Custom |
| --- | --- | --- | --- |
| ![Normal status](docs/assets/en/status-normal.png) | ![Speed window status](docs/assets/en/status-speed.png) | ![Limit reached status](docs/assets/en/status-limit.png) | ![Custom status](docs/assets/en/status-custom.png) |

You can choose which values appear in the menu bar. For example, if you do not care about IQ, show only `96%/low`.
If you care about the 5-hour short window, enable `5h`; it appears as an extra percentage between weekly quota and IQ.
If you want to pace weekly quota evenly across the reset window, enable `Pace`.
Turn on `Decimal IQ in menu bar` if you want the menu bar itself to show the precise IQ value.

## Full Menu

This image is captured by the app itself from the real SwiftUI menu window on a high-resolution screen, and it is maintained together with the menu bar screenshots and News crop by `./scripts/update_readme_screenshots.sh`. The README displays it at 390px wide so it stays readable without taking over the page; open the source image for the full-resolution view.

<img src="docs/assets/en/menu-full.png" width="390" alt="Codex Radar Sentinel full English menu">

## What It Shows

- Weekly Codex quota remaining, read from the local Codex app-server.
- Short-window quota remaining, also from the local Codex app-server.
- Usage pace: the suggested remaining percentage based on the selected strategy, compared with actual weekly quota remaining. For example, if target remaining is 80% and actual remaining is 90%, it tells you there is room to spend more.
  Strategies include: `Time` for smooth even spending; `Daily` for day-level budgeting; `Reserve` to keep a 20% buffer early; `Workdays` for heavier weekday usage and lighter weekends; `Front-load` to spend earlier and avoid unused quota near reset.
- The currently public Model IQ from [CodexRadar](https://codexradar.com/).
- Compatibility state for CodexRadar's legacy reset/speed/prediction endpoints. Those features are currently retired on CodexRadar, so the app shows no window / low risk and will keep recognizing them if the endpoints return later.
- Codex IQ from the daily probe, currently read from the CodexRadar homepage first.

The app defaults to Chinese. English can be selected in the dropdown. Technical terms such as Codex, IQ, Reset, Prediction, and Radar are kept in English where they are clearer.

## Notifications

The app sends macOS notifications for:

- Compatible signal reports a speed window opened.
- Compatible CodexRadar signal records a reset; the header says `Last reset was ...`, while local quota stays in `Codex Quota`.
- Weekly quota falls below 30%.
- Weekly quota falls below 15%.
- Weekly quota recovers after a low-remaining state.
- Prediction rises to high, or CodexRadar explicitly marks it as should_notify. When CodexRadar's reset prediction is retired, live mode does not trigger prediction notifications.
- Codex IQ enters red or falls below 80.

Notification sound is off by default and can be enabled in the dropdown. Historical reset windows are seeded on first launch, so starting the app after a reset does not replay old reset notifications. If the first launch happens during an active speed window, it still notifies.

## Updates

Automatic updates are on by default. The app checks once 5 seconds after launch, then every 6 hours checks the latest GitHub Release, downloads the ZIP, verifies the release SHA256, replaces the installed app bundle, and reopens itself.

If download, verification, or installation fails, the app keeps the current version running and shows the failure in the menu. The installer also backs up the old app first; if replacement fails, it restores and reopens the old app. Automatic updates pause short-term retries for the same failed version, while manual `Check` can retry immediately.

The bottom toolbar always includes `Refresh`, `Radar`, `Codex`, `GitHub`, and `Quit`, so common jumps do not require scrolling.

The update section also includes:

- `Check`: manually checks and installs a newer release.
- `Changelog`: opens the latest release notes.
- `Prompts`: opens the open-source prompt log.
- `GitHub`: opens the repository page.

Turn off `Auto update` in the dropdown if you prefer manual updates only.

## Codex Skill

This repository includes a repo-managed skill: [CodexRadar Sync](skills/codex-radar-sync/SKILL.md). When the CodexRadar page or JSON payload shape changes, ask Codex to run this skill. It checks the latest CodexRadar homepage and public endpoints, compares field changes, updates Swift decoding and macOS menu mappings, and runs the full UI/data release check before shipping.

## Preview Mode

Use the `Preview` segmented control in the dropdown to inspect local UI states:

- `Live`: real data.
- `Speed`: urgent speed-window UI, including the red menu bar item and red banner.
- `Reset`: CodexRadar-recorded reset UI.
- `Limit`: local quota-limit UI.

Preview mode only changes what the app displays. Notifications and persisted event memory still use live data.

For scripted UI checks, launch with:

```bash
CODEX_RADAR_PREVIEW=speedWindow swift run CodexRadarSentinel
```

Accepted values are `live`, `speedWindow`, `resetConfirmed`, and `blocked`.

## Data Sources

Codex Radar Sentinel reads these public endpoints:

- [CodexRadar homepage](https://codexradar.com/)
- [current.json](https://codexradar.com/current.json) and [feed.xml](https://codexradar.com/feed.xml): legacy reset/speed endpoints. CodexRadar currently redirects them back to the homepage, so the app falls back to homepage Model IQ parsing.

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

Run live data and UI checks before a release:

```bash
./scripts/check_release_readiness.sh 0.1.27
```

Build release packages:

```bash
swift build -c release
./scripts/build_app.sh
./scripts/package_release.sh 0.1.27
```

Update README menu bar and menu screenshots:

```bash
./scripts/update_readme_screenshots.sh
```

This script launches the real app and crops the macOS menu bar item. It also asks the app to render the full menu from its real SwiftUI view, then crops the compact News image. The Mac must allow System Events accessibility access and screen capture.

Regenerate the macOS icon:

```bash
./scripts/generate_app_icon.sh
```

## Credits

Codex Radar Sentinel exists because [CodexRadar](https://codexradar.com/) publishes clear public Codex signals. CodexRadar previously published speed windows, resets, reset prediction, RSS events, and model IQ; it now focuses on model quality. This app wraps those public signals together with the user's local Codex quota state in a macOS menu bar tool.

Codex Radar Sentinel is not affiliated with CodexRadar or OpenAI.
