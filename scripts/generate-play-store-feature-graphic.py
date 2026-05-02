#!/usr/bin/env python3
"""Generate the Google Play Store Feature Graphic (1024x500, 24-bit PNG, no alpha).

Output: android/fastlane/metadata/android/ja-JP/images/featureGraphic.png
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


def load_font(size: int) -> ImageFont.FreeTypeFont:
    for path in JP_FONT_CANDIDATES:
        if os.path.exists(path):
            return ImageFont.truetype(path, size=size)
    return ImageFont.load_default()


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


def add_decorative_bars(img: Image.Image) -> None:
    overlay = Image.new("RGBA", img.size, (0, 0, 0, 0))
    draw = ImageDraw.Draw(overlay)

    bars = [
        (60, 70, 230, 22, 60),
        (40, 130, 150, 18, 50),
        (820, 90, 160, 20, 55),
        (860, 150, 120, 16, 45),
        (60, 380, 180, 18, 50),
        (780, 410, 200, 22, 55),
    ]
    for x, y, w, h, alpha in bars:
        draw.rounded_rectangle((x, y, x + w, y + h), radius=h // 2, fill=(255, 255, 255, alpha))

    stars = [(120, 220, 6), (180, 60, 5), (940, 60, 5), (900, 250, 6), (90, 320, 4), (980, 330, 5)]
    for cx, cy, r in stars:
        draw.ellipse((cx - r, cy - r, cx + r, cy + r), fill=(255, 255, 255, 180))

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


def main() -> int:
    if not ICON_PATH.exists():
        print(f"icon not found: {ICON_PATH}", file=sys.stderr)
        return 1

    bg = make_diagonal_gradient((W, H), COLOR_TOP_LEFT, COLOR_BOTTOM_RIGHT).convert("RGBA")
    add_decorative_bars(bg)

    icon = Image.open(ICON_PATH).convert("RGBA")
    icon_size = 340
    icon = icon.resize((icon_size, icon_size), Image.LANCZOS)
    icon = round_corners(icon, radius=int(icon_size * 0.22))
    icon_with_shadow = drop_shadow(icon, offset=(0, 10), blur=18, opacity=120)

    icon_x = 80 - 36
    icon_y = (H - icon_size) // 2 - 36
    bg.alpha_composite(icon_with_shadow, (icon_x, icon_y))

    draw = ImageDraw.Draw(bg)

    title = "comerune"
    title_font = load_font(108)
    tx = 440
    ty = 140
    shadow_offset = 3
    draw.text((tx + shadow_offset, ty + shadow_offset), title, font=title_font, fill=(60, 30, 90, 140))
    draw.text((tx, ty), title, font=title_font, fill=(255, 255, 255, 255))

    sub_font = load_font(36)
    subtitle_main = "ニコ生コメントを表示・読み上げ"
    sy = ty + 138
    draw.text((tx + 2, sy + 2), subtitle_main, font=sub_font, fill=(60, 30, 90, 140))
    draw.text((tx, sy), subtitle_main, font=sub_font, fill=(255, 255, 255, 255))

    tag_font = load_font(26)
    tag = "シンプル・軽量・読みやすい"
    bbox = draw.textbbox((0, 0), tag, font=tag_font)
    tw = bbox[2] - bbox[0]
    th = bbox[3] - bbox[1]
    pad_x, pad_y = 20, 10
    bx0 = tx
    by0 = sy + 64
    bx1 = bx0 + tw + pad_x * 2
    by1 = by0 + th + pad_y * 2
    pill = Image.new("RGBA", bg.size, (0, 0, 0, 0))
    pdraw = ImageDraw.Draw(pill)
    pdraw.rounded_rectangle((bx0, by0, bx1, by1), radius=(by1 - by0) // 2, fill=(255, 255, 255, 70))
    bg.alpha_composite(pill)
    draw.text((bx0 + pad_x, by0 + pad_y - bbox[1]), tag, font=tag_font, fill=(255, 255, 255, 255))

    final = bg.convert("RGB")
    OUT_PATH.parent.mkdir(parents=True, exist_ok=True)
    final.save(OUT_PATH, format="PNG", optimize=True)
    print(f"wrote {OUT_PATH} ({final.size[0]}x{final.size[1]})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
