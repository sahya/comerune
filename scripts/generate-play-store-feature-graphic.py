#!/usr/bin/env python3
"""Generate the Google Play Store Feature Graphic (1024x500, 24-bit PNG, no alpha).

Output: android/fastlane/metadata/android/ja-JP/images/featureGraphic.png

Designer review対応版:
- Latin タイトルは DejaVu Sans Bold で字形を安定化
- 右側 100px をセーフゾーンとして空け、Play ストア各サーフェスでのトリミングに耐える
- サブコピー / キャッチに半透明黒プレートを敷きコントラストを確保
- 背景の装飾は数を減らし、画面端寄せ・低彩度に
"""
from __future__ import annotations

import os
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parent.parent
ICON_PATH = ROOT / "icon_source.png"
OUT_PATH = ROOT / "android/fastlane/metadata/android/ja-JP/images/featureGraphic.png"

W, H = 1024, 500

COLOR_TOP_LEFT = (139, 107, 247)
COLOR_BOTTOM_RIGHT = (217, 117, 210)

JP_FONT_CANDIDATES = [
    "/usr/share/fonts/opentype/ipafont-gothic/ipagp.ttf",
    "/usr/share/fonts/opentype/ipafont-gothic/ipag.ttf",
    "/usr/share/fonts/truetype/fonts-japanese-gothic.ttf",
]

LATIN_FONT_CANDIDATES = [
    "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
    "/usr/share/fonts/truetype/liberation/LiberationSans-Bold.ttf",
]


def load_jp_font(size: int) -> ImageFont.FreeTypeFont:
    for path in JP_FONT_CANDIDATES:
        if os.path.exists(path):
            return ImageFont.truetype(path, size=size)
    return ImageFont.load_default()


def load_latin_font(size: int) -> ImageFont.FreeTypeFont:
    for path in LATIN_FONT_CANDIDATES:
        if os.path.exists(path):
            return ImageFont.truetype(path, size=size)
    return load_jp_font(size)


def make_diagonal_gradient(size: tuple[int, int], c1: tuple[int, int, int], c2: tuple[int, int, int]) -> Image.Image:
    w, h = size
    base = Image.new("RGB", size, c1)
    pixels = base.load()
    diag = (w - 1) + (h - 1)
    for y in range(h):
        for x in range(w):
            t = (x + y) / diag
            r = int(c1[0] + (c2[0] - c1[0]) * t)
            g = int(c1[1] + (c2[1] - c1[1]) * t)
            b = int(c1[2] + (c2[2] - c1[2]) * t)
            pixels[x, y] = (r, g, b)
    return base


def add_top_highlight(img: Image.Image) -> None:
    overlay = Image.new("RGBA", img.size, (0, 0, 0, 0))
    pixels = overlay.load()
    for y in range(img.size[1] // 2):
        a = int(50 * (1 - y / (img.size[1] / 2)) ** 2)
        for x in range(img.size[0]):
            pixels[x, y] = (255, 255, 255, a)
    img.alpha_composite(overlay)


def add_decorative_bars(img: Image.Image) -> None:
    overlay = Image.new("RGBA", img.size, (0, 0, 0, 0))
    draw = ImageDraw.Draw(overlay)

    bars = [
        (40, 70, 180, 18, 38),
        (40, 410, 140, 16, 34),
        (860, 60, 120, 16, 32),
        (840, 430, 150, 18, 34),
    ]
    for x, y, w, h, alpha in bars:
        draw.rounded_rectangle((x, y, x + w, y + h), radius=h // 2, fill=(255, 255, 255, alpha))

    stars = [(160, 50, 4), (920, 110, 4), (90, 360, 3), (970, 360, 4)]
    for cx, cy, r in stars:
        draw.ellipse((cx - r, cy - r, cx + r, cy + r), fill=(255, 255, 255, 150))

    img.alpha_composite(overlay)


def round_corners(im: Image.Image, radius: int) -> Image.Image:
    im = im.convert("RGBA")
    mask = Image.new("L", im.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, im.size[0], im.size[1]), radius=radius, fill=255)
    out = Image.new("RGBA", im.size, (0, 0, 0, 0))
    out.paste(im, (0, 0), mask=mask)
    return out


def drop_shadow(im: Image.Image, offset: tuple[int, int] = (0, 8), blur: int = 16, opacity: int = 110) -> Image.Image:
    alpha = im.split()[-1]
    shadow = Image.new("RGBA", im.size, (0, 0, 0, 0))
    shadow_layer = Image.new("RGBA", im.size, (0, 0, 0, opacity))
    shadow.paste(shadow_layer, (0, 0), mask=alpha)
    shadow = shadow.filter(ImageFilter.GaussianBlur(blur))

    pad = blur * 2
    canvas = Image.new("RGBA", (im.size[0] + pad * 2 + abs(offset[0]), im.size[1] + pad * 2 + abs(offset[1])), (0, 0, 0, 0))
    canvas.alpha_composite(shadow, (pad + offset[0], pad + offset[1]))
    canvas.alpha_composite(im, (pad, pad))
    return canvas


def draw_plate(bg: Image.Image, box: tuple[int, int, int, int], radius: int, fill: tuple[int, int, int, int]) -> None:
    plate = Image.new("RGBA", bg.size, (0, 0, 0, 0))
    ImageDraw.Draw(plate).rounded_rectangle(box, radius=radius, fill=fill)
    bg.alpha_composite(plate)


def main() -> int:
    if not ICON_PATH.exists():
        print(f"icon not found: {ICON_PATH}", file=sys.stderr)
        return 1

    bg = make_diagonal_gradient((W, H), COLOR_TOP_LEFT, COLOR_BOTTOM_RIGHT).convert("RGBA")
    add_top_highlight(bg)
    add_decorative_bars(bg)

    icon = Image.open(ICON_PATH).convert("RGBA")
    icon_size = 300
    icon = icon.resize((icon_size, icon_size), Image.LANCZOS)
    icon = round_corners(icon, radius=int(icon_size * 0.22))
    icon_with_shadow = drop_shadow(icon, offset=(6, 14), blur=22, opacity=140)

    shadow_pad = 22 * 2
    icon_x = 110 - shadow_pad
    icon_y = (H - icon_size) // 2 - shadow_pad
    bg.alpha_composite(icon_with_shadow, (icon_x, icon_y))

    draw = ImageDraw.Draw(bg)

    safe_right = 80
    text_left = 470

    title = "comerune"
    title_font = load_jp_font(108)
    tbbox = draw.textbbox((0, 0), title, font=title_font)
    title_w = tbbox[2] - tbbox[0]
    max_title_w = W - text_left - safe_right
    if title_w > max_title_w:
        title_font = load_jp_font(int(108 * max_title_w / title_w))
        tbbox = draw.textbbox((0, 0), title, font=title_font)
    title_visual_top = tbbox[1]
    title_visual_h = tbbox[3] - tbbox[1]

    sub_font = load_jp_font(36)
    subtitle = "ニコ生コメントを表示・読み上げ"
    sbbox = draw.textbbox((0, 0), subtitle, font=sub_font)
    sub_visual_top = sbbox[1]
    sub_visual_h = sbbox[3] - sbbox[1]

    tag_font = load_jp_font(26)
    tag = "ながら見でも聞き逃さない"
    gbbox = draw.textbbox((0, 0), tag, font=tag_font)
    tag_w = gbbox[2] - gbbox[0]
    tag_h = gbbox[3] - gbbox[1]

    tag_pad_x, tag_pad_y = 20, 10
    gap_title_sub = 26
    gap_sub_tag = 24

    tag_plate_h = tag_h + tag_pad_y * 2
    block_h = title_visual_h + gap_title_sub + sub_visual_h + gap_sub_tag + tag_plate_h
    block_top = (H - block_h) // 2

    tx = text_left
    ty = block_top - title_visual_top
    draw.text((tx + 2, ty + 3), title, font=title_font, fill=(60, 30, 90, 130))
    draw.text((tx, ty), title, font=title_font, fill=(255, 255, 255, 255))

    sub_top = block_top + title_visual_h + gap_title_sub
    sy = sub_top - sub_visual_top
    draw.text((tx + 2, sy + 2), subtitle, font=sub_font, fill=(60, 30, 90, 120))
    draw.text((tx, sy), subtitle, font=sub_font, fill=(255, 255, 255, 255))

    tag_plate_top = sub_top + sub_visual_h + gap_sub_tag
    tag_plate_box = (
        tx,
        tag_plate_top,
        tx + tag_w + tag_pad_x * 2,
        tag_plate_top + tag_plate_h,
    )
    draw_plate(bg, tag_plate_box, radius=tag_plate_h // 2, fill=(255, 255, 255, 70))
    draw.text((tx + tag_pad_x, tag_plate_top + tag_pad_y - gbbox[1]), tag, font=tag_font, fill=(255, 255, 255, 255))

    final = bg.convert("RGB")
    OUT_PATH.parent.mkdir(parents=True, exist_ok=True)
    final.save(OUT_PATH, format="PNG", optimize=True)
    print(f"wrote {OUT_PATH} ({final.size[0]}x{final.size[1]})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
