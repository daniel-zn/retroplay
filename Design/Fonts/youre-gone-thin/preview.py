#!/usr/bin/env python3
"""Renders the original beside one or more thin builds, one band each, to a PNG.

    python3 -I preview.py out.png "Label=font.otf" ["Label=font.otf" ...]
    python3 -I preview.py --overlay out.png original.otf thin.otf
"""
import sys

from PIL import Image, ImageDraw, ImageFont

LINES = [("RETROPLAY", 150), ("LIBRARY  RECENTLY PLAYED  SETTINGS", 64),
         ("ABCDEFGHIJKLMNOPQRSTUVWXYZ 0123456789", 52),
         ("SUPER BOMBERMAN 2 · CONTINUE 1× — SAVES 12/48 …", 38),
         ("BODY TEXT AT 15 PT: IMPORT ROMS FROM FILES OR A SHARE", 22)]


def main(out, specs):
    width, band = 2000, 470
    image = Image.new("RGB", (width, band * len(specs)), "white")
    draw = ImageDraw.Draw(image)
    label_font = ImageFont.load_default(size=26)
    for i, spec in enumerate(specs):
        label, path = spec.split("=", 1)
        top = i * band
        if i % 2:
            draw.rectangle((0, top, width, top + band), fill=(244, 244, 246))
        draw.text((30, top + 14), label, font=label_font, fill=(200, 40, 90))
        y = top + 52
        for text, size in LINES:
            font = ImageFont.truetype(path, size)
            draw.text((30, y), text, font=font, fill="black")
            y += int(size * 1.18) + 8
    image.save(out)


def overlay(out, original, thin, text="RAGE&Q@%5", shift=13):
    """Each thin glyph drawn over its original, large, moved right by half the stroke (`shift`
    units of 1000) so the two share a skeleton: the pink rim is what was taken off."""
    size = 300
    a, b = ImageFont.truetype(original, size), ImageFont.truetype(thin, size)
    image = Image.new("RGB", (2000, 420), "white")
    draw = ImageDraw.Draw(image)
    x = 30
    for c in text:
        draw.text((x, 50), c, font=a, fill=(255, 150, 180))
        draw.text((x + shift * size / 1000, 50), c, font=b, fill="black")
        x += a.getlength(c) + 20
    draw.text((30, 8), "pink: the original; black: the thin build on the same skeleton",
              font=ImageFont.load_default(size=24), fill=(200, 40, 90))
    image.save(out)


if __name__ == "__main__":
    if sys.argv[1] == "--overlay":
        overlay(*sys.argv[2:5])
    else:
        main(sys.argv[1], sys.argv[2:])
