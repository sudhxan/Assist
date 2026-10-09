#!/usr/bin/env python3
"""Builds the Product Hunt gallery for Assist.

    python3 marketing/product-hunt/source/build.py            # everything
    python3 marketing/product-hunt/source/build.py 01 04      # only slides whose name starts with 01 or 04

1. Cleans the app screenshots in docs/images (drops the white-background shadow,
   makes "floating" variants with all four corners rounded).
2. Renders every slides/*.html at 1270x760 @2x with headless Chrome.
3. Writes the 240x240 thumbnail from the app icon.
"""
import subprocess
import sys
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
SHOTS = ROOT / "docs" / "images"
ASSETS = HERE / "assets"
SLIDES = HERE / "slides"
OUT = HERE.parent
CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"

PANELS = ["answer", "welcome", "context", "on-device", "privacy"]
# Content in these ends well above the panel's bottom edge; trim the empty black middle.
COMPACT = {"on-device", "privacy"}


def clean(name):
    """Panel only, no drop shadow: keep opaque pixels, crop to the panel."""
    im = Image.open(SHOTS / f"{name}.png").convert("RGBA")
    alpha = im.getchannel("A").point(lambda a: 0 if a <= 55 else a)
    im.putalpha(alpha)
    return im.crop(alpha.point(lambda a: 255 if a >= 250 else 0).getbbox())


def content_bottom(im, start=40):
    """Last row (above the rounded bottom) with anything but plain black."""
    w, h = im.size
    rgb = im.convert("RGB")
    last = start
    for y in range(start, h - 70):
        row = rgb.crop((40, y, w - 40, y + 1))
        if max(c for band in row.getextrema() for c in band[1:2]) > 10:
            last = y
    return last


def compact(im):
    cut_from = content_bottom(im) + 44
    cut_to = im.height - 64
    if cut_to - cut_from < 20:
        return im
    out = Image.new("RGBA", (im.width, im.height - (cut_to - cut_from)))
    out.paste(im.crop((0, 0, im.width, cut_from)), (0, 0))
    out.paste(im.crop((0, cut_to, im.width, im.height)), (0, cut_from))
    return out


def floating(im, pad_top=22, radius=44):
    """Drop the notch 'ears', add a little headroom, round all four corners, add a hairline."""
    body = im.crop((10, 0, im.width - 10, im.height))
    w, h = body.width, body.height + pad_top
    out = Image.new("RGBA", (w, h), (0, 0, 0, 255))
    out.paste(body, (0, pad_top), body)
    s = 4  # supersampled mask for smooth corners
    mask = Image.new("L", (w * s, h * s), 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, w * s - 1, h * s - 1), radius * s, fill=255)
    out.putalpha(ImageChops.multiply(out.getchannel("A"), mask.resize((w, h), Image.LANCZOS)))
    ring = Image.new("L", (w * s, h * s), 0)
    ImageDraw.Draw(ring).rounded_rectangle((0, 0, w * s - 1, h * s - 1), radius * s, outline=255, width=2 * s)
    hairline = Image.new("RGBA", (w, h), (255, 255, 255, 0))
    hairline.putalpha(ring.resize((w, h), Image.LANCZOS).point(lambda a: a * 30 // 255))
    return Image.alpha_composite(out, hairline)


def prepare():
    ASSETS.mkdir(exist_ok=True)
    for name in PANELS:
        im = clean(name)
        if name in COMPACT:
            im = compact(im)
        im.save(ASSETS / f"notch-{name}.png", optimize=True)
        floating(im).save(ASSETS / f"card-{name}.png", optimize=True)
    Image.open(SHOTS / "icon.png").save(ASSETS / "icon.png")


def render(only):
    for html in sorted(SLIDES.glob("*.html")):
        if only and not any(html.stem.startswith(p) for p in only):
            continue
        size = "240,240" if html.stem == "thumbnail" else "1270,760"
        png = OUT / f"{html.stem}.png"
        subprocess.run(
            [CHROME, "--headless=new", "--disable-gpu", "--hide-scrollbars", "--force-device-scale-factor=2",
             f"--window-size={size}", "--virtual-time-budget=1500", f"--screenshot={png}", html.as_uri()],
            check=True, capture_output=True,
        )
        if html.stem == "thumbnail":
            Image.open(png).resize((240, 240), Image.LANCZOS).save(png, optimize=True)
        print(f"{png.relative_to(ROOT)}  {Image.open(png).size}")


if __name__ == "__main__":
    prepare()
    render(sys.argv[1:])
