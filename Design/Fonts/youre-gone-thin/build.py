#!/usr/bin/env python3
"""Builds You're Gone Thin from the original You're Gone (source/YoureGone-Regular.otf, and
source/YoureGone-Italic.otf for the italic).

    python3 -I build.py [--stroke -26] [--out file.otf]   (default: AppHost/Supporting/YoureGoneThin-Regular.otf)
    python3 -I build.py --style Italic                    (default: AppHost/Supporting/YoureGoneThin-Italic.otf)

Needs fontTools and skia-pathops (pip install -r requirements.txt). See README.md for what it
changes and why.
"""
import argparse
import os
import sys

import pathops
from fontTools.pens.t2CharStringPen import T2CharStringPen
from fontTools.pens.recordingPen import RecordingPen
from fontTools.ttLib import TTFont

HERE = os.path.dirname(os.path.abspath(__file__))
APP_FONTS = os.path.normpath(os.path.join(HERE, "..", "..", "..", "AppHost", "Supporting"))  # the copies the app bundles
SOURCES = {style: os.path.join(HERE, "source", f"YoureGone-{style}.otf") for style in ("Regular", "Italic")}
SOURCE = SOURCES["Regular"]

# The original's stems are about 205 units (of 1000); -26 takes about 13% off them.
STROKE = -26
FAMILY = "You're Gone Thin"
POSTSCRIPT = "YoureGoneThin-Regular"


def postscript_name(style):
    return f"YoureGoneThin-{style}"


def full_name(family, style):
    return family if style == "Regular" else f"{family} {style}"
WEIGHT = 300


def eroded(glyphset, name, d):
    """The glyph's outline with everything within d/2 of its edge taken away.

    Its own edge stroked with a round pen d wide (half of that band lies inside the outline),
    subtracted from it: what drawing the same skeleton with a pen d thinner would give. Round
    ends stay round; inside corners round off by d/2; counters open up by d.
    """
    outline = pathops.Path()
    glyphset[name].draw(outline.getPen(glyphSet=glyphset))
    outline.simplify(fix_winding=True)
    edge = pathops.Path(outline)
    edge.stroke(d, pathops.LineCap.ROUND_CAP, pathops.LineJoin.ROUND_JOIN, 4)
    edge.convertConicsToQuads()  # round joins come out as conics, which fonts can't hold
    edge.simplify(fix_winding=True)
    return pathops.op(outline, edge, pathops.PathOp.DIFFERENCE, fix_winding=True)


def thin(font, stroke):
    """Every glyph drawn with a pen `-stroke` units thinner (stroke is negative).

    Each outline is eroded by half the stroke on every side (see `eroded`), so every stem, bar
    and curve loses the same amount on the same skeleton. Then the zone between baseline
    and cap height is stretched back to its full height (horizontal bars thicken back by ~3.6%,
    unnoticeably) and what lies above or below it (accents, descenders) is moved out by half the
    stroke, so baseline, cap height and the line's extremes are the original's; and each glyph is moved left by
    half the stroke with its advance narrowed by the stroke, so it keeps the original's side
    bearings: the designer's spacing and kerning (GPOS, untouched) still fit. Zero-width marks
    keep their width and place.
    """
    d = -stroke
    if d <= 0:
        raise SystemExit("--stroke must be negative (thinner)")
    cap = font["OS/2"].sCapHeight or 739
    k = cap / (cap - d)

    def vertical(y):
        # Between the eroded baseline and cap height: stretched back to 0..cap. Above and below
        # (accents, descenders): only moved, so nothing grows past the original's line.
        if y < d / 2:
            return y - d / 2
        if y > cap - d / 2:
            return y + d / 2
        return (y - d / 2) * k
    glyphset = font.getGlyphSet()
    cff = font["CFF "].cff
    charstrings = cff.topDictIndex[0].CharStrings
    hmtx = font["hmtx"].metrics
    new = {}
    for name in font.getGlyphOrder():
        width = hmtx[name][0]
        moved = 0 if width == 0 else -d / 2
        new[name] = (eroded(glyphset, name, d), moved, width if width == 0 else width - d)
    privates = {}
    for name, (path, moved, advance) in new.items():
        private = charstrings[name].private
        privates[id(private)] = private
        width = None if advance == private.defaultWidthX else advance - private.nominalWidthX
        pen = T2CharStringPen(width, None)
        recording = RecordingPen()
        path.draw(recording)
        for op, points in recording.value:
            getattr(pen, op)(*[(x + moved, vertical(y)) for x, y in points])
        charstring = pen.getCharString(private=private, globalSubrs=cff.GlobalSubrs)
        charstrings[name] = charstring
        bounds = charstring.calcBounds(charstrings)
        hmtx[name] = (advance, round(bounds[0]) if bounds else 0)
    # The hints described the original's stems: drop them rather than keep wrong ones.
    for private in privates.values():
        for key in ("StdHW", "StdVW", "StemSnapH", "StemSnapV"):
            private.rawDict.pop(key, None)
            if key in private.__dict__:
                delattr(private, key)
    font["post"].underlineThickness = max(1, font["post"].underlineThickness - d // 2)


def rename(font, family, postscript, stroke, style="Regular"):
    """The font's own names, so it installs beside the original and never replaces it (the
    italic as the Italic of the same family, so the two link as upright and italic)."""
    name = font["name"]
    original = {r.nameID: r.toUnicode() for r in name.names if r.platformID == 3}
    version = original.get(5, "Version 5.002").split(";")[0]
    entries = {
        0: original.get(0, "Released in 2024 under CC0 license. No rights reserved."),
        1: family,
        2: style,
        3: f"{version.replace('Version ', '')};{postscript};stroke{stroke}",
        4: full_name(family, style),
        5: f"{version}; You're Gone{' Italic' if style != 'Regular' else ''} by Ray Larabie, every stroke {-stroke} units thinner",
        6: postscript,
        8: "Typodermic (original design)",
        9: "Ray Larabie (original design); thinned by The RetroPlay Authors",
        10: "A slightly lighter derivative of You're Gone by Ray Larabie (CC0). "
            "Made with Design/Fonts/youre-gone-thin/build.py in RetroPlay's source.",
        13: original.get(13, "Released under CC0 1.0. No rights reserved."),
        14: original.get(14, "https://creativecommons.org/publicdomain/zero/1.0/"),
    }
    name.names = []
    for name_id, text in entries.items():
        name.setName(text, name_id, 3, 1, 0x409)
        if all(ord(c) < 128 for c in text):
            name.setName(text, name_id, 1, 0, 0)
    cff = font["CFF "].cff
    cff.fontNames = [postscript]
    top = cff.topDictIndex[0]
    top.FullName = full_name(family, style)
    top.FamilyName = family
    top.Weight = "Light"  # the italic keeps its own ItalicAngle, fsSelection and macStyle
    top.Notice = entries[0]
    font["OS/2"].usWeightClass = WEIGHT
    font["OS/2"].fsType = 0
    if "DSIG" in font:
        del font["DSIG"]  # the original's signature no longer matches


def build(stroke, out, family=FAMILY, style="Regular"):
    # The original's timestamps kept, so the same source always builds the same bytes.
    font = TTFont(SOURCES[style], recalcTimestamp=False)
    thin(font, stroke)
    rename(font, family, postscript_name(style), stroke, style)
    font.save(out)
    return out


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--stroke", type=int, default=STROKE)
    parser.add_argument("--style", choices=sorted(SOURCES), default="Regular")
    parser.add_argument("--out")
    args = parser.parse_args()
    print(build(args.stroke, args.out or os.path.join(APP_FONTS, f"{postscript_name(args.style)}.otf"), style=args.style))


if __name__ == "__main__":
    sys.exit(main())
