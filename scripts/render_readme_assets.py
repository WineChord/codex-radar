#!/usr/bin/env python3
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont


ROOT = Path(__file__).resolve().parents[1]
ASSET_DIR = ROOT / "docs" / "assets"
ICON_SOURCE = ROOT / "Resources" / "AppIcon.png"

FONT_REGULAR = "/System/Library/Fonts/Hiragino Sans GB.ttc"
FONT_MONO = "/System/Library/Fonts/SFNSMono.ttf"


def font(size, mono=False):
    path = FONT_MONO if mono else FONT_REGULAR
    return ImageFont.truetype(path, size=size)


def rounded(draw, xy, radius, fill, outline=None, width=1):
    draw.rounded_rectangle(xy, radius=radius, fill=fill, outline=outline, width=width)


def text(draw, xy, value, size, fill, mono=False, anchor=None):
    draw.text(xy, value, font=font(size, mono=mono), fill=fill, anchor=anchor)


def shadowed_panel(width, height, radius=26):
    canvas = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    shadow = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    shadow_draw = ImageDraw.Draw(shadow)
    shadow_draw.rounded_rectangle((28, 28, width - 28, height - 28), radius=radius, fill=(0, 0, 0, 80))
    shadow = shadow.filter(ImageFilter.GaussianBlur(18))
    canvas.alpha_composite(shadow)
    draw = ImageDraw.Draw(canvas)
    rounded(draw, (24, 20, width - 24, height - 30), radius, (248, 252, 255, 245), (210, 225, 235, 255))
    return canvas, draw


def render_statusbar():
    width, height = 980, 220
    image = Image.new("RGBA", (width, height), (236, 247, 252, 255))
    draw = ImageDraw.Draw(image)

    rounded(draw, (58, 72, 922, 148), 22, (35, 142, 204, 255))
    icon = Image.open(ICON_SOURCE).convert("RGBA").resize((46, 46))
    image.alpha_composite(icon, (84, 87))
    text(draw, (150, 110), "97%", 32, (48, 245, 105, 255), mono=True, anchor="lm")
    text(draw, (222, 110), "/", 28, (210, 234, 246, 235), mono=True, anchor="lm")
    text(draw, (250, 110), "75", 32, (255, 176, 64, 255), mono=True, anchor="lm")
    text(draw, (300, 110), "/", 28, (210, 234, 246, 235), mono=True, anchor="lm")
    text(draw, (328, 110), "低", 30, (80, 220, 230, 255), anchor="lm")
    text(draw, (410, 110), "Weekly / IQ / Signal", 23, (218, 242, 250, 255), anchor="lm")

    text(draw, (690, 110), "Speed alert turns red", 21, (235, 249, 255, 255), anchor="lm")
    image.save(ASSET_DIR / "readme-statusbar.png")


def render_menu():
    width, height = 780, 1220
    image, draw = shadowed_panel(width, height)
    x0, y = 58, 54
    x1 = width - 58

    rounded(draw, (x0, y, x1, y + 86), 18, (255, 59, 48, 255))
    text(draw, (x0 + 24, y + 30), "●", 26, (255, 255, 255, 255), anchor="lm")
    text(draw, (x0 + 62, y + 28), "速蹬窗口开启", 26, (255, 255, 255, 255), anchor="lm")
    text(draw, (x0 + 62, y + 58), "Use quota now · 97% weekly left", 18, (255, 238, 236, 255), anchor="lm")
    text(draw, (x1 - 28, y + 42), "×", 34, (255, 245, 245, 235), anchor="mm")
    y += 110

    text(draw, (x0, y), "limit reset 已确认", 28, (20, 33, 45, 255))
    text(draw, (x0, y + 32), "Updated 06-04 18:03", 18, (108, 122, 138, 255))
    rounded(draw, (x1 - 168, y - 4, x1, y + 36), 20, (232, 246, 255, 255))
    text(draw, (x1 - 84, y + 16), "97%/75/低", 20, (8, 122, 195, 255), anchor="mm")
    y += 70

    labels = [("Weekly", "97%", (22, 173, 82, 255)), ("IQ", "75", (224, 128, 24, 255)), ("Signal", "低", (0, 151, 167, 255))]
    tile_w = (x1 - x0 - 16) // 3
    for index, (label, value, color) in enumerate(labels):
        tx = x0 + index * (tile_w + 8)
        rounded(draw, (tx, y, tx + tile_w, y + 78), 14, (235, 243, 248, 255))
        text(draw, (tx + 18, y + 24), label, 17, (102, 116, 132, 255), anchor="lm")
        text(draw, (tx + 18, y + 54), value, 24, color, mono=(label != "Signal"), anchor="lm")
    y += 104

    section(draw, x0, y, "Codex Quota")
    y += 34
    card(draw, x0, y, (x1 - x0 - 12) // 2, 104, "Weekly", "97%", "reset 6d 15h")
    card(draw, x0 + (x1 - x0 + 12) // 2, y, (x1 - x0 - 12) // 2, 104, "Short", "86%", "reset 1h 26m")
    y += 132

    section(draw, x0, y, "Reset Radar")
    y += 34
    text(draw, (x0, y), "Codex 可靠性事故补偿重置", 22, (20, 33, 45, 255))
    text(draw, (x0, y + 34), "Window: 无窗", 18, (72, 87, 103, 255))
    text(draw, (x0 + 280, y + 34), "Scope: 所有付费计划", 18, (72, 87, 103, 255))
    text(draw, (x0, y + 66), "Tibo 表示过去 24 小时内有三次影响 Codex 可靠性的小事故。", 17, (108, 122, 138, 255))
    y += 104

    section(draw, x0, y, "Prediction")
    y += 34
    three_cols(draw, x0, y, x1, [("Level", "low"), ("24h", "11%"), ("48h", "20%")])
    y += 76

    section(draw, x0, y, "Codex IQ")
    y += 34
    three_cols(draw, x0, y, x1, [("IQ", "75"), ("Probe", "6/12"), ("Status", "red")])
    y += 88

    section(draw, x0, y, "Settings")
    y += 36
    rounded(draw, (x0, y, x1, y + 44), 12, (230, 240, 247, 255))
    for index, value in enumerate(["M", "L", "XL"]):
        bx = x0 + 8 + index * 70
        if value == "L":
            rounded(draw, (bx, y + 7, bx + 58, y + 37), 10, (255, 255, 255, 255))
        text(draw, (bx + 29, y + 22), value, 16, (36, 49, 64, 255), anchor="mm")
    text(draw, (x0 + 250, y + 22), "Text size", 17, (80, 96, 112, 255), anchor="lm")
    y += 70

    section(draw, x0, y, "Preview")
    y += 36
    rounded(draw, (x0, y, x1, y + 52), 14, (235, 243, 248, 255))
    for index, value in enumerate(["Live", "速蹬", "Reset", "Limit"]):
        text(draw, (x0 + 70 + index * 140, y + 26), value, 18, (36, 49, 64, 255), anchor="mm")
    y += 78

    rounded(draw, (x0, y, x1, y + 58), 14, (245, 249, 252, 255), (224, 235, 242, 255))
    text(draw, (x0 + 62, y + 29), "Refresh", 18, (72, 87, 103, 255), anchor="mm")
    text(draw, (x0 + 170, y + 29), "Radar", 18, (72, 87, 103, 255), anchor="mm")
    text(draw, (x0 + 266, y + 29), "Codex", 18, (72, 87, 103, 255), anchor="mm")
    text(draw, (x1 - 44, y + 29), "Quit", 18, (72, 87, 103, 255), anchor="mm")

    image.save(ASSET_DIR / "readme-menu.png")


def section(draw, x, y, title):
    text(draw, (x, y), title, 18, (92, 110, 126, 255))


def card(draw, x, y, w, h, title, value, subtitle):
    rounded(draw, (x, y, x + w, y + h), 14, (235, 243, 248, 255))
    text(draw, (x + 18, y + 25), title, 17, (102, 116, 132, 255), anchor="lm")
    text(draw, (x + 18, y + 58), value, 30, (20, 33, 45, 255), mono=True, anchor="lm")
    text(draw, (x + 18, y + 88), subtitle, 16, (102, 116, 132, 255), anchor="lm")


def three_cols(draw, x0, y, x1, pairs):
    width = x1 - x0
    for index, (label, value) in enumerate(pairs):
        x = x0 + index * width // 3
        text(draw, (x, y), label, 17, (102, 116, 132, 255))
        text(draw, (x, y + 30), value, 19, (20, 33, 45, 255))


def main():
    ASSET_DIR.mkdir(parents=True, exist_ok=True)
    render_statusbar()
    render_menu()


if __name__ == "__main__":
    main()
