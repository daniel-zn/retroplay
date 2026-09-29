#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""RetroPlay Liquid Glass PSP icon — MindPlay recipe, no banding."""
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

SIZE = 1024
SCALE = 2
C = SIZE * SCALE

MIDNIGHT = (6, 8, 20)
LIFT = (24, 36, 78)
MINT = (110, 231, 197)
LILAC = (184, 166, 255)
CORAL = (255, 139, 122)
AMBER = (245, 185, 66)
HI = (232, 242, 255)


def xy(v):
    return int(v * SCALE)


def mix(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))


def radial(base, cx, cy, radius, color, strength):
    ov = Image.new("RGBA", base.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(ov)
    r, g, b = color
    for i in range(10, 0, -1):
        t = i / 10
        rr = int(radius * t)
        a = int(strength * (1 - t) ** 1.35)
        d.ellipse((cx - rr, cy - rr, cx + rr, cy + rr), fill=(r, g, b, a))
    ov = ov.filter(ImageFilter.GaussianBlur(max(1, int(radius * 0.2))))
    return Image.alpha_composite(base, ov)


def vgrad(size, top, bottom):
    w, h = size
    img = Image.new("RGB", (w, h))
    px = img.load()
    for y in range(h):
        c = mix(top, bottom, y / max(1, h - 1))
        for x in range(w):
            px[x, y] = c
    return img.convert("RGBA")


def slab(base, box, radius, body, opacity, sheen=True):
    x0, y0, x1, y1 = [xy(v) for v in box]
    w, h = x1 - x0, y1 - y0
    layer = vgrad((w, h), mix(HI, body, 0.18), mix(body, (8, 12, 24), 0.22))
    mask = Image.new("L", (w, h), 0)
    md = ImageDraw.Draw(mask)
    md.rounded_rectangle((0, 0, w - 1, h - 1), radius=xy(radius), fill=int(255 * opacity))
    layer.putalpha(mask)
    if sheen:
        sd = ImageDraw.Draw(layer)
        sd.ellipse((int(w * 0.08), int(h * 0.06), int(w * 0.58), int(h * 0.48)), fill=(*HI, 70))
        sd.rounded_rectangle((0, 0, w - 1, h - 1), radius=xy(radius), outline=(*HI, 90), width=max(2, xy(2)))
    base.paste(layer, (x0, y0), layer)
    return base


def circle(base, cx, cy, r, fill, outline=None, width=3):
    d = ImageDraw.Draw(base)
    box = (xy(cx - r), xy(cy - r), xy(cx + r), xy(cy + r))
    d.ellipse(box, fill=fill)
    if outline:
        d.ellipse(box, outline=outline, width=xy(width))


def make_icon():
    img = Image.new("RGBA", (C, C), (*MIDNIGHT, 255))
    img = radial(img, xy(340), xy(260), xy(540), LIFT, 220)
    img = radial(img, xy(790), xy(210), xy(320), MINT, 72)
    img = radial(img, xy(210), xy(840), xy(340), LILAC, 66)
    img = radial(img, xy(560), xy(910), xy(280), AMBER, 50)

    orbit = Image.new("RGBA", (C, C), (0, 0, 0, 0))
    od = ImageDraw.Draw(orbit)
    od.ellipse((xy(168), xy(318), xy(856), xy(742)), outline=(*MINT, 150), width=xy(30))
    od.ellipse((xy(196), xy(346), xy(828), xy(714)), outline=(*LILAC, 80), width=xy(8))
    orbit = orbit.rotate(-22, resample=Image.Resampling.BICUBIC, center=(xy(512), xy(512)))
    orbit = orbit.filter(ImageFilter.GaussianBlur(xy(1.2)))
    img = Image.alpha_composite(img, orbit)

    # Connected PSP: back plate, face plate, screen well.
    img = slab(img, (150, 348, 874, 692), 120, CORAL, 0.55, sheen=False)
    img = slab(img, (168, 338, 856, 668), 108, AMBER, 0.48, sheen=False)
    img = slab(img, (178, 352, 846, 656), 96, MINT, 0.86)
    img = slab(img, (292, 408, 732, 604), 34, (16, 28, 46), 0.92)

    d = ImageDraw.Draw(img, "RGBA")
    d.ellipse((xy(318), xy(428), xy(500), xy(498)), fill=(*HI, 36))

    # Shoulders as part of the body, not extra chrome.
    img = slab(img, (198, 314, 348, 366), 20, MINT, 0.7)
    img = slab(img, (676, 314, 826, 366), 20, LILAC, 0.7)

    # D-pad: one plus, large.
    d.rectangle((xy(216), xy(484), xy(276), xy(532)), fill=(*HI, 155))
    d.rectangle((xy(232), xy(468), xy(260), xy(548)), fill=(*HI, 155))

    # Face pips
    for cx, cy, col in ((776, 452, CORAL), (812, 492, AMBER), (740, 492, LILAC), (776, 532, MINT)):
        circle(img, cx, cy, 17, (*col, 210), (*HI, 80), 2)

    # Analog orb
    d.ellipse((xy(236), xy(572), xy(328), xy(668)), fill=(0, 0, 0, 70))
    circle(img, 274, 608, 42, (*MINT, 220), (*AMBER, 150), 3)
    d.ellipse((xy(258), xy(584), xy(292), xy(612)), fill=(255, 255, 255, 150))
    d.ellipse((xy(278), xy(612), xy(314), xy(644)), fill=(*CORAL, 70))

    rgb = Image.new("RGB", img.size, MIDNIGHT)
    rgb.paste(img, mask=img.split()[-1])
    rgb = rgb.filter(ImageFilter.GaussianBlur(0.45 * SCALE))
    return rgb.resize((SIZE, SIZE), Image.Resampling.LANCZOS)


def main():
    out = Path(__file__).resolve().parent / "out"
    out.mkdir(exist_ok=True)
    icon = make_icon()
    icon.save(out / "RetroPlayAppIcon.png")
    icon.resize((180, 180), Image.Resampling.LANCZOS).save(out / "RetroPlayAppIcon-60@3x.png")
    print("ok")


if __name__ == "__main__":
    main()
