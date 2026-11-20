#!/usr/bin/env python3
"""Checks a built You're Gone Thin against the original (build.sh runs it).

    python3 -I validate.py [YoureGoneThin-Regular.otf]   (default: the app's copy in AppHost/Supporting)
    python3 -I validate.py YoureGoneThin-Italic.otf   (checked against source/YoureGone-Italic.otf)

Fails (exit 1) unless: fontTools opens it and every table decompiles; it maps exactly the
characters the original maps and has exactly its glyphs; its names are its own ("You're Gone
Thin", PostScript YoureGoneThin-Regular, both unlike the original's) and keep the CC0 notice;
and every glyph is clean: the same number of contours as the original (no counter closed up or
split), no open, self-crossing or reversed outline, each within the line and on the original's baseline and cap height, each
narrower (zero-width marks stay zero) and lighter than the original's.
"""
import os
import sys

from fontTools.pens.areaPen import AreaPen
from fontTools.pens.boundsPen import BoundsPen
from fontTools.pens.recordingPen import DecomposingRecordingPen
from fontTools.ttLib import TTFont

HERE = os.path.dirname(os.path.abspath(__file__))
FAMILY = "You're Gone Thin"
POSTSCRIPT = "YoureGoneThin-Regular"
CAP_ZONE = set("ABCDEFGHJKLMNOPQRSTUVWXYZ") | {"zero", "one", "two", "four", "seven", "eight"}

problems = []


def fail(message):
    problems.append(message)


def contours(glyphset, name):
    pen = DecomposingRecordingPen(glyphset)
    glyphset[name].draw(pen)
    return sum(1 for op, _ in pen.value if op in ("closePath", "endPath"))


def bounds(glyphset, name):
    pen = BoundsPen(glyphset)
    glyphset[name].draw(pen)
    return pen.bounds


def area(glyphset, name):
    pen = AreaPen(glyphset)
    glyphset[name].draw(pen)
    return abs(pen.value)


def names(font):
    return {r.nameID: r.toUnicode() for r in font["name"].names if r.platformID == 3}


def main(path):
    # The style from the file's name: YoureGoneThin-<Style>.otf, against YoureGone-<Style>.otf.
    style = os.path.splitext(os.path.basename(path))[0].rsplit("-", 1)[-1]
    postscript = f"YoureGoneThin-{style}"
    full = FAMILY if style == "Regular" else f"{FAMILY} {style}"
    source = TTFont(os.path.join(HERE, "source", f"YoureGone-{style}.otf"))
    try:
        thin = TTFont(path)
        for tag in thin.keys():
            thin[tag]  # decompile every table
    except Exception as error:  # noqa: BLE001
        print(f"FAIL: fontTools can't open {path}: {error}")
        return 1

    # Coverage: the same characters, the same glyphs.
    a, b = source.getBestCmap(), thin.getBestCmap()
    if set(a) != set(b):
        fail(f"cmap differs: missing {sorted(set(a) - set(b))[:20]}, extra {sorted(set(b) - set(a))[:20]}")
    if set(source.getGlyphOrder()) != set(thin.getGlyphOrder()):
        fail(f"glyph set differs: {sorted(set(source.getGlyphOrder()) ^ set(thin.getGlyphOrder()))[:20]}")
    for code in set(a) & set(b):
        if a[code] != b[code]:
            fail(f"U+{code:04X} maps to {b[code]}, the original to {a[code]}")

    # Names: its own, unlike the original's, with the CC0 notice kept.
    n, o = names(thin), names(source)
    if n.get(1) != FAMILY or n.get(2) != style or n.get(4) != full:
        fail(f"family/style/full name {n.get(1)!r}/{n.get(2)!r}/{n.get(4)!r}, want {FAMILY!r}/{style!r}/{full!r}")
    if n.get(6) != postscript or thin["CFF "].cff.fontNames != [postscript]:
        fail(f"PostScript name {n.get(6)!r} {thin['CFF '].cff.fontNames}, want {postscript!r}")
    # The italic stays italic (slant and style bits as the original's).
    if (thin["post"].italicAngle, thin["OS/2"].fsSelection, thin["head"].macStyle) != \
            (source["post"].italicAngle, source["OS/2"].fsSelection, source["head"].macStyle):
        fail("italic angle / fsSelection / macStyle differ from the original's")
    for nid in (1, 3, 4, 6):
        if n.get(nid) == o.get(nid):
            fail(f"name {nid} {n.get(nid)!r} is the original's")
    if "CC0" not in (n.get(13, "") + n.get(0, "")):
        fail("the CC0 notice (name 0/13) is gone")
    if thin["OS/2"].fsType != 0:
        fail(f"fsType {thin['OS/2'].fsType}, want 0 (installable)")

    # Metrics: vertical ones unchanged.
    for table, field in (("hhea", "ascent"), ("hhea", "descent"), ("OS/2", "sTypoAscender"),
                         ("OS/2", "sTypoDescender"), ("OS/2", "usWinAscent"), ("OS/2", "usWinDescent"),
                         ("head", "unitsPerEm")):
        if getattr(source[table], field) != getattr(thin[table], field):
            fail(f"{table}.{field} changed")

    # Every glyph.
    sg, tg = source.getGlyphSet(), thin.getGlyphSet()
    smtx, tmtx = source["hmtx"].metrics, thin["hmtx"].metrics
    lighter = 0
    for name in source.getGlyphOrder():
        if name not in tg:
            continue
        sc, tc = contours(sg, name), contours(tg, name)
        if sc != tc:
            fail(f"{name}: {tc} contours, the original has {sc}")
        sb, tb = bounds(sg, name), bounds(tg, name)
        if (sb is None) != (tb is None):
            fail(f"{name}: outline appeared or vanished")
            continue
        if sb is None:
            continue
        # Within the line (nothing clipped) and close to the original's height: the build's
        # vertical stretch moves marks above the caps and below the baseline a few units.
        if tb[3] > thin["OS/2"].usWinAscent or tb[1] < -thin["OS/2"].usWinDescent:
            fail(f"{name}: {tb[1]}..{tb[3]} outside the line ({-thin['OS/2'].usWinDescent}..{thin['OS/2'].usWinAscent})")
        # Inside the original's extent; each edge in by at most the stroke (marks above the
        # caps and below the baseline thin from their inner side).
        if not (sb[1] - 2 <= tb[1] <= sb[1] + 40 and sb[3] - 40 <= tb[3] <= sb[3] + 2):
            fail(f"{name}: vertical extent {tb[1]}..{tb[3]}, the original's {sb[1]}..{sb[3]}")
        # Capitals and figures sit exactly on the original's baseline and cap height.
        if name in CAP_ZONE and (abs(tb[1] - sb[1]) > 2 or abs(tb[3] - sb[3]) > 2):
            fail(f"{name}: {tb[1]}..{tb[3]} off the original's baseline/cap height {sb[1]}..{sb[3]}")
        sw, tw = smtx[name][0], tmtx[name][0]
        if sw and not (0 < sw - tw <= 40) or not sw and tw:
            fail(f"{name}: advance {tw}, the original {sw}")
        sa, ta = area(sg, name), area(tg, name)
        if sa > 0:
            if not (0.3 < ta / sa < 0.99):
                fail(f"{name}: ink {ta / sa:.2f} of the original's")
            else:
                lighter += 1

    # Outlines: closed, not self-crossing (FontForge's checks), if FontForge is here.
    try:
        import fontforge  # noqa: PLC0415
    except ImportError:
        print("note: no FontForge module; outline validity not checked")
    else:
        font = fontforge.open(path)
        for glyph in font.glyphs():
            if not glyph.foreground:
                continue
            state = glyph.validate(True)
            # 0x2 open contour, 0x4 self-intersection, 0x8 wrong direction.
            bad = state & (0x2 | 0x4 | 0x8)
            if bad:
                fail(f"{glyph.glyphname}: outline invalid (FontForge flags {bad:#x})")
        font.close()

    if problems:
        print(f"FAIL {path}: {len(problems)} problem(s)")
        for p in problems[:60]:
            print("  -", p)
        return 1
    print(f"OK {path}: {len(b)} characters, {len(thin.getGlyphOrder())} glyphs as the original; "
          f"{lighter} glyphs lighter, all clean; names {n.get(1)!r} / {n.get(6)!r}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1] if len(sys.argv) > 1 else os.path.join(HERE, "..", "..", "..", "AppHost", "Supporting", f"{POSTSCRIPT}.otf")))
