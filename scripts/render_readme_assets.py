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


def checkmark(draw, center, fill=(255, 255, 255, 255), width=3):
    x, y = center
    draw.line([(x - 6, y), (x - 2, y + 5), (x + 7, y - 7)], fill=fill, width=width, joint="curve")


def statusline_icons(draw, start_x, y):
    fill = (229, 248, 255, 235)
    stroke = (229, 248, 255, 235)
    x = start_x

    draw.polygon([(x, y - 13), (x + 13, y), (x, y + 13), (x - 13, y)], outline=stroke)
    x += 56
    draw.ellipse((x - 13, y - 13, x + 13, y + 13), outline=stroke, width=3)
    draw.line((x - 12, y, x + 12, y), fill=stroke, width=3)
    x += 56
    draw.rounded_rectangle((x - 13, y - 13, x + 13, y + 13), radius=6, outline=stroke, width=3)
    x += 56
    text(draw, (x, y), "G", 24, fill, anchor="mm")
    x += 56
    draw.ellipse((x - 14, y - 14, x + 14, y + 14), outline=stroke, width=3)
    text(draw, (x, y + 1), "P", 16, fill, anchor="mm")
    x += 56
    draw.polygon([(x - 14, y - 10), (x + 14, y - 10), (x + 8, y + 12), (x - 8, y + 12)], outline=stroke)


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


def icon(size):
    return Image.open(ICON_SOURCE).convert("RGBA").resize((size, size))


def render_statusline(filename, segments, emphasized=False):
    width, height = 760, 86
    image = Image.new("RGBA", (width, height), (62, 157, 204, 255))
    draw = ImageDraw.Draw(image)
    draw.rectangle((0, 0, width, height), fill=(61, 158, 207, 255))

    x = 44
    y = 42
    title_font_size = 24
    text_width = 0
    for index, (value, _, use_mono) in enumerate(segments):
        if index > 0:
            text_width += int(draw.textlength("/", font=font(title_font_size, mono=True))) + 7
        text_width += int(draw.textlength(value, font=font(title_font_size, mono=use_mono))) + 5

    if emphasized:
        rounded(draw, (x - 13, 15, x + text_width + 12, 67), 18, (255, 59, 48, 255))

    for index, (value, color, use_mono) in enumerate(segments):
        if index > 0:
            slash_color = (255, 255, 255, 205) if emphasized else (220, 244, 252, 210)
            text(draw, (x, y), "/", title_font_size, slash_color, mono=True, anchor="lm")
            x += int(draw.textlength("/", font=font(title_font_size, mono=True))) + 7
        text(draw, (x, y), value, title_font_size, color, mono=use_mono, anchor="lm")
        x += int(draw.textlength(value, font=font(title_font_size, mono=use_mono))) + 5

    statusline_icons(draw, x + 22, y)
    image.save(ASSET_DIR / filename)


def render_status_examples():
    render_statusline(
        "readme-statusline-normal.png",
        [("97%", (48, 245, 105, 255), True), ("75", (255, 176, 64, 255), True), ("低", (80, 220, 230, 255), False)],
    )
    render_statusline(
        "readme-statusline-speed.png",
        [("97%", (255, 255, 255, 255), True), ("75", (255, 255, 255, 255), True), ("速蹬", (255, 255, 255, 255), False)],
        emphasized=True,
    )
    render_statusline(
        "readme-statusline-limit.png",
        [("0%", (255, 82, 82, 255), True), ("75", (255, 176, 64, 255), True), ("限额", (255, 196, 86, 255), False)],
    )
    render_statusline(
        "readme-statusline-custom.png",
        [("97%", (48, 245, 105, 255), True), ("低", (80, 220, 230, 255), False)],
    )


def render_menu():
    width, height = 860, 1580
    image, draw = shadowed_panel(width, height)
    x0, y = 58, 54
    x1 = width - 58

    rounded(draw, (x0, y, x1, y + 86), 18, (255, 59, 48, 255))
    text(draw, (x0 + 24, y + 30), "●", 26, (255, 255, 255, 255), anchor="lm")
    text(draw, (x0 + 62, y + 28), "速蹬窗口开启", 26, (255, 255, 255, 255), anchor="lm")
    text(draw, (x0 + 62, y + 58), "建议尽快使用 · 周额度剩余 97%", 18, (255, 238, 236, 255), anchor="lm")
    text(draw, (x1 - 28, y + 42), "×", 34, (255, 245, 245, 235), anchor="mm")
    y += 110

    text(draw, (x0, y), "limit reset 已确认", 28, (20, 33, 45, 255))
    text(draw, (x0, y + 32), "更新 06-04 18:03", 18, (108, 122, 138, 255))
    rounded(draw, (x1 - 168, y - 4, x1, y + 36), 20, (232, 246, 255, 255))
    text(draw, (x1 - 84, y + 16), "97%/75/低", 20, (8, 122, 195, 255), anchor="mm")
    y += 70

    section(draw, x0, y, "状态栏含义")
    text(draw, (x0 + 112, y), "菜单栏按“周额度 / IQ / 信号”拼接", 16, (108, 122, 138, 255))
    y += 34
    labels = [("周额度", "97%", (22, 173, 82, 255)), ("IQ", "75", (224, 128, 24, 255)), ("信号", "低", (0, 151, 167, 255))]
    tile_w = (x1 - x0 - 16) // 3
    for index, (label, value, color) in enumerate(labels):
        tx = x0 + index * (tile_w + 8)
        rounded(draw, (tx, y, tx + tile_w, y + 78), 14, (235, 243, 248, 255))
        text(draw, (tx + 18, y + 24), label, 17, (102, 116, 132, 255), anchor="lm")
        text(draw, (tx + 18, y + 54), value, 24, color, mono=(label != "信号"), anchor="lm")
    y += 104

    section(draw, x0, y, "Codex 额度")
    y += 34
    card(draw, x0, y, (x1 - x0 - 12) // 2, 104, "周额度", "97%", "重置 6d 15h")
    card(draw, x0 + (x1 - x0 + 12) // 2, y, (x1 - x0 - 12) // 2, 104, "短窗", "86%", "重置 1h 26m")
    y += 132

    section(draw, x0, y, "Reset Radar")
    y += 34
    text(draw, (x0, y), "Codex 可靠性事故补偿重置", 22, (20, 33, 45, 255))
    text(draw, (x0, y + 34), "窗口：无窗", 18, (72, 87, 103, 255))
    text(draw, (x0 + 300, y + 34), "范围：所有付费计划", 18, (72, 87, 103, 255))
    text(draw, (x0, y + 66), "Tibo 表示过去 24 小时内有三次影响 Codex 可靠性的小事故。", 17, (108, 122, 138, 255))
    y += 104

    section(draw, x0, y, "Prediction 预测")
    y += 34
    three_cols(draw, x0, y, x1, [("等级", "低"), ("24h", "11%"), ("48h", "20%")])
    y += 76

    section(draw, x0, y, "Codex IQ")
    y += 34
    three_cols(draw, x0, y, x1, [("IQ", "75"), ("探针", "6/12"), ("状态", "red")])
    y += 88

    section(draw, x0, y, "显示与提醒")
    y += 34
    segmented(draw, x0, y, x1, ["中文", "English"], selected=0, label="语言", label_width=132)
    y += 54
    segmented(draw, x0, y, x1, ["M", "L", "XL"], selected=1, label="字号", label_width=132)
    y += 58
    text(draw, (x0, y + 18), "状态栏显示", 17, (102, 116, 132, 255), anchor="lm")
    equal_chips(draw, x0 + 132, y, x1, ["周额度", "IQ", "信号"])
    y += 56
    checkbox_grid(draw, x0, y, x1, [
        ("Prediction 提醒", True),
        ("IQ 提醒", True),
        ("通知声音", False),
        ("登录时启动", False),
    ])
    y += 88

    section(draw, x0, y, "版本更新")
    y += 36
    checkbox(draw, x0, y, "自动更新", True)
    text(draw, (x1, y + 11), "v0.1.4", 17, (102, 116, 132, 255), anchor="rm")
    y += 34
    text(draw, (x0, y), "默认检查 GitHub Release；发现新版会校验并安装。", 16, (108, 122, 138, 255))
    y += 28
    compact_buttons(draw, x0, y, x1, ["检查更新", "Changelog", "GitHub ★"])
    y += 70

    section(draw, x0, y, "调试预览")
    y += 36
    segmented(draw, x0, y, x1, ["Live", "速蹬", "Reset", "限额"], selected=0)
    y += 74

    toolbar(draw, x0, y, x1)
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


def segmented(draw, x0, y, x1, values, selected=0, label=None, label_width=120):
    width = x1 - x0
    control_x0 = x0 + label_width if label else x0
    if label:
        text(draw, (x0, y + 22), label, 17, (102, 116, 132, 255), anchor="lm")
    rounded(draw, (control_x0, y, x1, y + 44), 12, (230, 240, 247, 255))
    item_w = (x1 - control_x0 - 16) / len(values)
    for index, value in enumerate(values):
        bx = int(control_x0 + 8 + index * item_w)
        if index == selected:
            rounded(draw, (bx, y + 7, int(bx + item_w - 8), y + 37), 10, (255, 255, 255, 255))
        text(draw, (int(bx + item_w / 2 - 4), y + 22), value, 16, (36, 49, 64, 255), anchor="mm")


def chips(draw, x, y, values):
    cursor = x
    for value in values:
        w = 78 if value != "周额度" else 94
        rounded(draw, (cursor, y, cursor + w, y + 36), 10, (232, 246, 255, 255))
        text(draw, (cursor + w / 2, y + 18), value, 16, (8, 122, 195, 255), anchor="mm")
        cursor += w + 8


def equal_chips(draw, x0, y, x1, values):
    item_w = (x1 - x0 - 16) / len(values)
    for index, value in enumerate(values):
        x = int(x0 + index * (item_w + 8))
        rounded(draw, (x, y, int(x + item_w), y + 36), 10, (232, 246, 255, 255))
        center_x = x + item_w / 2 - 32
        draw.ellipse((center_x - 8, y + 10, center_x + 8, y + 26), fill=(8, 122, 195, 255))
        checkmark(draw, (center_x, y + 18), width=2)
        text(draw, (center_x + 16, y + 18), value, 15, (8, 122, 195, 255), anchor="lm")


def checkbox(draw, x, y, label, checked):
    fill = (8, 122, 195, 255) if checked else (214, 224, 232, 255)
    rounded(draw, (x, y, x + 22, y + 22), 6, fill)
    if checked:
        checkmark(draw, (x + 11, y + 11), width=2)
    text(draw, (x + 30, y + 11), label, 17, (36, 49, 64, 255), anchor="lm")


def checkbox_grid(draw, x0, y, x1, items):
    col_w = (x1 - x0 - 12) / 2
    row_h = 38
    for index, (label, checked) in enumerate(items):
        col = index % 2
        row = index // 2
        x = int(x0 + col * (col_w + 12))
        checkbox(draw, x, y + row * row_h, label, checked)


def compact_buttons(draw, x0, y, x1, labels):
    item_w = (x1 - x0 - 16) / len(labels)
    for index, label in enumerate(labels):
        x = int(x0 + index * (item_w + 8))
        rounded(draw, (x, y, int(x + item_w), y + 42), 11, (235, 243, 248, 255))
        text(draw, (x + item_w / 2, y + 21), label, 16, (36, 49, 64, 255), anchor="mm")


def toolbar(draw, x0, y, x1):
    labels = ["刷新", "Radar", "Codex", "退出"]
    item_w = (x1 - x0 - 24) / 4
    for index, label in enumerate(labels):
        x = int(x0 + index * (item_w + 8))
        rounded(draw, (x, y, int(x + item_w), y + 58), 12, (235, 243, 248, 255))
        text(draw, (x + item_w / 2, y + 20), "●", 14, (72, 87, 103, 255), anchor="mm")
        text(draw, (x + item_w / 2, y + 40), label, 16, (36, 49, 64, 255), anchor="mm")


def main():
    ASSET_DIR.mkdir(parents=True, exist_ok=True)
    render_status_examples()
    render_menu()


if __name__ == "__main__":
    main()
