#!/usr/bin/env python3
import os
import re
import subprocess
import time
from pathlib import Path

from PIL import Image, ImageStat


ROOT = Path(__file__).resolve().parents[1]
ASSET_ROOT = ROOT / "docs" / "assets"
APP_BUNDLE = Path(os.environ.get("CODEX_RADAR_APP", "/Applications/Codex Radar Sentinel.app"))
APP_EXECUTABLE = APP_BUNDLE / "Contents" / "MacOS" / "Codex Radar Sentinel"
BUNDLE_ID = "com.codexradar.sentinel"
PROCESS_NAME = "Codex Radar Sentinel"


CASES = [
    ("zh", "zhHans", "normal", "live", ["weeklyQuota", "codexIQ", "signal"]),
    ("zh", "zhHans", "speed", "speedWindow", ["weeklyQuota", "codexIQ", "signal"]),
    ("zh", "zhHans", "limit", "blocked", ["weeklyQuota", "codexIQ", "signal"]),
    ("zh", "zhHans", "custom", "live", ["weeklyQuota", "signal"]),
    ("en", "en", "normal", "live", ["weeklyQuota", "codexIQ", "signal"]),
    ("en", "en", "speed", "speedWindow", ["weeklyQuota", "codexIQ", "signal"]),
    ("en", "en", "limit", "blocked", ["weeklyQuota", "codexIQ", "signal"]),
    ("en", "en", "custom", "live", ["weeklyQuota", "signal"]),
]


def run(command, **kwargs):
    return subprocess.run(command, check=True, text=True, **kwargs)


def output(command, **kwargs):
    return subprocess.check_output(command, text=True, **kwargs).strip()


def ensure_app_exists():
    if APP_EXECUTABLE.exists():
        return
    run([str(ROOT / "scripts" / "build_app.sh")], stdout=subprocess.DEVNULL)


def kill_app():
    subprocess.run(["pkill", "-x", PROCESS_NAME], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    time.sleep(0.4)


def write_defaults(language, metrics):
    run(["defaults", "write", BUNDLE_ID, "appLanguage", "-string", language])
    run(["defaults", "write", BUNDLE_ID, "menuTextSize", "-string", "large"])
    run(["defaults", "write", BUNDLE_ID, "statusBarPreciseIQEnabled", "-bool", "false"])
    run(["defaults", "write", BUNDLE_ID, "selectedStatusMetrics", "-array", *metrics])


def launch(preview):
    if preview == "live":
        run(["open", str(APP_BUNDLE)])
        return

    env = os.environ.copy()
    env["CODEX_RADAR_PREVIEW"] = preview
    subprocess.Popen(
        [str(APP_EXECUTABLE)],
        env=env,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
    )


def menu_bar_item():
    script = f'''
tell application "System Events"
  tell process "{PROCESS_NAME}"
    set itemPosition to position of menu bar item 1 of menu bar 1
    set itemSize to size of menu bar item 1 of menu bar 1
    set itemTitle to title of menu bar item 1 of menu bar 1
    return (item 1 of itemPosition as text) & "," & (item 2 of itemPosition as text) & "," & (item 1 of itemSize as text) & "," & (item 2 of itemSize as text) & "," & itemTitle
  end tell
end tell
'''
    raw = output(["osascript", "-e", script], stderr=subprocess.DEVNULL)
    match = re.match(r"(-?\d+),(-?\d+),(\d+),(\d+),(.*)", raw)
    if not match:
        raise RuntimeError(f"Could not parse menu bar item output: {raw}")
    x, y, width, height, title = match.groups()
    return int(x), int(y), int(width), int(height), title


def wait_for_title(preview, metrics):
    deadline = time.time() + 25
    last_error = None
    expected_parts = len(metrics)
    while time.time() < deadline:
        try:
            x, y, width, height, title = menu_bar_item()
            if title and title.count("/") == expected_parts - 1:
                if preview == "live" and "%" not in title:
                    time.sleep(0.5)
                    continue
                if preview != "live" or "?" not in title:
                    time.sleep(0.35)
                    stable_item = menu_bar_item()
                    if stable_item[2] == width and stable_item[4] == title:
                        return stable_item
        except Exception as exc:
            last_error = exc
        time.sleep(0.5)
    if last_error:
        raise last_error
    return menu_bar_item()


def capture(destination, item):
    x, y, width, height, _ = item
    regions = [
        (x - 30, y - 3, width + 120, height + 6),
        (x - 15, y - 3, width + 90, height + 6),
        (x - 5, y - 3, width + 70, height + 6),
    ]
    last_error = None
    for region in regions:
        region_arg = ",".join(str(value) for value in region)
        try:
            run(
                ["screencapture", "-x", f"-R{region_arg}", str(destination)],
                stderr=subprocess.DEVNULL,
            )
            if not has_status_content(destination):
                raise RuntimeError("captured menu bar background without status text")
            trim_to_status_item(destination)
            return
        except subprocess.CalledProcessError as exc:
            last_error = exc
        except RuntimeError as exc:
            last_error = exc
    if last_error:
        raise last_error


def has_status_content(path):
    image = Image.open(path).convert("RGB")
    stat = ImageStat.Stat(image)
    return sum(stat.stddev) > 20


def trim_to_status_item(path):
    image = Image.open(path).convert("RGBA")
    if image.width < 20 or image.height < 10:
        return

    background = background_color(image)
    changed_columns = []
    pixels = image.load()
    for x in range(image.width):
        changed_count = 0
        for y in range(image.height):
            r, g, b, a = pixels[x, y]
            if a > 0 and is_status_pixel((r, g, b), background):
                changed_count += 1
        if changed_count >= 2:
            changed_columns.append(x)

    if not changed_columns:
        return

    max_gap = 16
    groups = []
    start = changed_columns[0]
    previous = changed_columns[0]
    for x in changed_columns[1:]:
        if x - previous > max_gap:
            groups.append((start, previous))
            start = x
        previous = x
    groups.append((start, previous))

    start, end = max(groups, key=lambda group: group[1] - group[0])
    left = max(0, start - 10)
    right = min(image.width, end + 11)
    if right - left >= 20:
        image.crop((left, 0, right, image.height)).save(path)


def background_color(image):
    sample_points = [
        (0, 0),
        (image.width - 1, 0),
        (0, image.height - 1),
        (image.width - 1, image.height - 1),
    ]
    channels = list(zip(*(image.getpixel(point)[:3] for point in sample_points)))
    return tuple(sorted(channel)[len(channel) // 2] for channel in channels)


def color_distance(lhs, rhs):
    return sum((left - right) ** 2 for left, right in zip(lhs, rhs)) ** 0.5


def is_status_pixel(rgb, background):
    if color_distance(rgb, background) <= 35:
        return False
    saturation = max(rgb) - min(rgb)
    brightness = sum(rgb) / len(rgb)
    return saturation >= 45 or brightness < 180


def capture_case(language_dir, language, name, preview, metrics):
    write_defaults(language, metrics)
    kill_app()
    launch(preview)
    destination_dir = ASSET_ROOT / language_dir
    destination_dir.mkdir(parents=True, exist_ok=True)
    destination = destination_dir / f"status-{name}.png"
    last_error = None
    for _ in range(8):
        item = wait_for_title(preview, metrics)
        try:
            capture(destination, item)
            print(f"{destination.relative_to(ROOT)}: {item[4]}")
            return
        except (subprocess.CalledProcessError, RuntimeError) as exc:
            last_error = exc
            time.sleep(0.75)
    if last_error:
        raise last_error


def restore_app():
    write_defaults("zhHans", ["weeklyQuota", "codexIQ", "signal"])
    kill_app()
    launch("live")


def render_menu_screenshots():
    env = os.environ.copy()
    env["CODEX_RADAR_RENDER_DOC_SCREENSHOTS"] = str(ASSET_ROOT)
    run(["swift", "run", "CodexRadarSentinel"], cwd=ROOT, env=env)


def main():
    ensure_app_exists()
    for case in CASES:
        capture_case(*case)
    render_menu_screenshots()
    restore_app()


if __name__ == "__main__":
    main()
