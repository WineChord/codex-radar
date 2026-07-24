#!/usr/bin/env python3
import hashlib
import os
import subprocess
import tempfile
from pathlib import Path

from PIL import Image, ImageDraw, ImageStat


ROOT = Path(__file__).resolve().parents[1]
ASSET_ROOT = ROOT / "docs" / "assets"
APP_BUNDLE = Path(os.environ.get("CODEX_RADAR_APP", "/Applications/Codex Radar Sentinel.app"))
APP_EXECUTABLE = APP_BUNDLE / "Contents" / "MacOS" / "Codex Radar Sentinel"
SCREENSHOT_MODE_ENV = "CODEX_RADAR_SCREENSHOT_MODE"
SCREENSHOT_LANGUAGE_ENV = "CODEX_RADAR_SCREENSHOT_LANGUAGE"
SCREENSHOT_METRICS_ENV = "CODEX_RADAR_SCREENSHOT_METRICS"
SCREENSHOT_OUTPUT_ENV = "CODEX_RADAR_STATUS_SCREENSHOT_OUTPUT"


CASES = [
    ("zh", "zhHans", "normal", "qualityNormal", ["weeklyQuota", "codexIQ", "signal"]),
    ("zh", "zhHans", "quality-low", "qualityLow", ["weeklyQuota", "codexIQ", "signal"]),
    ("zh", "zhHans", "speed", "speedWindow", ["weeklyQuota", "codexIQ", "signal"]),
    ("zh", "zhHans", "limit", "blocked", ["weeklyQuota", "codexIQ", "signal"]),
    ("zh", "zhHans", "custom", "qualityNormal", ["weeklyQuota", "signal"]),
    ("en", "en", "normal", "qualityNormal", ["weeklyQuota", "codexIQ", "signal"]),
    ("en", "en", "quality-low", "qualityLow", ["weeklyQuota", "codexIQ", "signal"]),
    ("en", "en", "speed", "speedWindow", ["weeklyQuota", "codexIQ", "signal"]),
    ("en", "en", "limit", "blocked", ["weeklyQuota", "codexIQ", "signal"]),
    ("en", "en", "custom", "qualityNormal", ["weeklyQuota", "signal"]),
]

NEWS_CROPS = {
    "zh": [(0, 1560, 1560, 2820), (0, 8622, 1560, 9992)],
    "en": [(0, 1550, 1560, 2820), (0, 9022, 1560, 10492)],
}


def run(command, **kwargs):
    return subprocess.run(command, check=True, text=True, **kwargs)


def ensure_app_exists():
    if APP_EXECUTABLE.exists():
        return
    run([str(ROOT / "scripts" / "build_app.sh")], stdout=subprocess.DEVNULL)


def render_status(preview, language, metrics, destination):
    if preview == "live":
        raise ValueError("status screenshot renderer refuses live preview")

    env = os.environ.copy()
    env.pop("CODEX_RADAR_RENDER_DOC_SCREENSHOTS", None)
    env[SCREENSHOT_MODE_ENV] = "1"
    env["CODEX_RADAR_PREVIEW"] = preview
    env[SCREENSHOT_LANGUAGE_ENV] = language
    env[SCREENSHOT_METRICS_ENV] = ",".join(metrics)
    env[SCREENSHOT_OUTPUT_ENV] = str(destination)
    result = subprocess.run(
        [str(APP_EXECUTABLE)],
        env=env,
        capture_output=True,
        check=True,
        text=True,
        timeout=30,
    )
    title_marker = "CODEX_RADAR_STATUS_TITLE="
    style_marker = "CODEX_RADAR_STATUS_STYLE="
    titles = [
        line[len(title_marker):]
        for line in result.stdout.splitlines()
        if line.startswith(title_marker)
    ]
    if len(titles) != 1:
        detail = result.stdout.strip() or result.stderr.strip()
        raise RuntimeError(
            "status renderer did not report exactly one target title: "
            f"{detail}"
        )
    styles = [
        line[len(style_marker):]
        for line in result.stdout.splitlines()
        if line.startswith(style_marker)
    ]
    if len(styles) != 1:
        raise RuntimeError(
            "status renderer did not report exactly one target style"
        )
    style = [float(value) for value in styles[0].split(",")]
    if len(style) != 6:
        raise RuntimeError(
            f"status renderer reported an invalid target style: {styles[0]}"
        )
    return titles[0], style


def has_status_content(path):
    image = Image.open(path).convert("RGB")
    stat = ImageStat.Stat(image)
    return sum(stat.stddev) > 20


def flatten_status_background(path, style):
    image = Image.open(path).convert("RGBA")
    red, green, blue, alpha, corner_radius, logical_height = style
    if alpha > 0:
        scale = image.height / max(1, logical_height)
        alert = Image.new("RGBA", image.size)
        draw = ImageDraw.Draw(alert)
        draw.rounded_rectangle(
            (0, 0, image.width - 1, image.height - 1),
            radius=round(corner_radius * scale),
            fill=(
                round(red * 255),
                round(green * 255),
                round(blue * 255),
                round(alpha * 255),
            ),
        )
        alert.alpha_composite(image)
        image = alert
    top = (88, 115, 165, 255)
    bottom = (76, 98, 136, 255)
    background = Image.new("RGBA", image.size)
    denominator = max(1, image.height - 1)
    for y in range(image.height):
        ratio = y / denominator
        color = tuple(
            round(start + (end - start) * ratio)
            for start, end in zip(top, bottom)
        )
        background.paste(color, (0, y, image.width, y + 1))
    background.alpha_composite(image)
    background.convert("RGB").save(path)


def capture_case(language_dir, language, name, preview, metrics):
    destination_dir = ASSET_ROOT / language_dir
    destination_dir.mkdir(parents=True, exist_ok=True)
    destination = destination_dir / f"status-{name}.png"
    file_descriptor, temporary_name = tempfile.mkstemp(
        prefix=f"status-{name}.capture-",
        suffix=".png",
        dir=destination_dir,
    )
    os.close(file_descriptor)
    temporary_destination = Path(temporary_name)
    temporary_destination.unlink()

    try:
        title, style = render_status(
            preview,
            language,
            metrics,
            temporary_destination,
        )
        if title.count("/") != len(metrics) - 1 or "?" in title:
            raise RuntimeError(f"unexpected status title for {name}: {title}")
        emphasized = style[3] > 0
        if emphasized != (name == "speed"):
            raise RuntimeError(
                f"unexpected alert background state for {name}: {style}"
            )
        flatten_status_background(temporary_destination, style)
        if not temporary_destination.exists() or not has_status_content(
            temporary_destination
        ):
            raise RuntimeError(
                f"status renderer produced no visible content for {name}"
            )
        os.replace(temporary_destination, destination)
        print(f"{destination.relative_to(ROOT)}: {title}")
        return {
            "language": language_dir,
            "name": name,
            "metrics": metrics,
            "title": title,
            "style": style,
            "path": destination,
        }
    finally:
        temporary_destination.unlink(missing_ok=True)


def validate_status_screenshots(results):
    by_key = {
        (result["language"], result["name"]): result
        for result in results
    }
    for language in ("zh", "en"):
        titles = [
            by_key[(language, name)]["title"]
            for name in ("normal", "quality-low", "speed", "limit")
        ]
        if len(set(titles)) != len(titles):
            raise RuntimeError(
                f"{language} status scenarios did not render distinct titles"
            )
        normal = by_key[(language, "normal")]
        custom = by_key[(language, "custom")]
        if custom["title"].count("/") != 1:
            raise RuntimeError(
                f"{language} custom status did not render exactly two metrics"
            )
        normal_width = Image.open(normal["path"]).width
        custom_width = Image.open(custom["path"]).width
        if custom_width >= normal_width:
            raise RuntimeError(
                f"{language} custom status is not narrower than the three-metric status"
            )

    for name in ("normal", "quality-low", "speed", "limit", "custom"):
        zh = by_key[("zh", name)]
        en = by_key[("en", name)]
        if zh["title"] == en["title"]:
            raise RuntimeError(
                f"{name} status did not honor the requested language"
            )

    digests = {
        key: hashlib.sha256(result["path"].read_bytes()).hexdigest()
        for key, result in by_key.items()
    }
    if len(set(digests.values())) != len(digests):
        raise RuntimeError(
            "status screenshots contain duplicate images across distinct scenarios"
        )


def render_menu_screenshots():
    env = os.environ.copy()
    env["CODEX_RADAR_RENDER_DOC_SCREENSHOTS"] = str(ASSET_ROOT)
    run(["swift", "run", "CodexRadarSentinel"], cwd=ROOT, env=env)


def render_news_screenshots():
    for language, boxes in NEWS_CROPS.items():
        source = ASSET_ROOT / language / "menu-full.png"
        destination = ASSET_ROOT / language / "news-pacing.png"
        image = Image.open(source).convert("RGB")
        parts = [image.crop(box) for box in boxes]
        gap = 28
        output = Image.new(
            "RGB",
            (image.width, sum(part.height for part in parts) + gap * (len(parts) - 1)),
            "white",
        )
        y = 0
        for index, part in enumerate(parts):
            output.paste(part, (0, y))
            y += part.height
            if index < len(parts) - 1:
                y += gap
        output.save(destination)
        print(f"{destination.relative_to(ROOT)}")


def main():
    ensure_app_exists()
    results = [capture_case(*case) for case in CASES]
    validate_status_screenshots(results)
    render_menu_screenshots()
    render_news_screenshots()


if __name__ == "__main__":
    main()
