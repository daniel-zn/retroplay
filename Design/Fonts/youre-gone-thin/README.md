# You're Gone Thin

A slightly lighter **You're Gone** (Ray Larabie, Typodermic, CC0): the same letters drawn with a
pen 26 units (of 1000) thinner, so its stems go from about 205 to about 179 units, some 13%
lighter. Upright and italic, from the original's upright and italic. It's RetroPlay's typeface
(the italic for its titles).

The font files the app bundles live in `AppHost/Supporting/` (`YoureGoneThin-Regular.otf`,
`YoureGoneThin-Italic.otf`, with `YoureGoneThin-SOURCE.md` and `YoureGoneThin-LICENSE.txt`);
this folder holds what makes them again.

| File | What it is |
| --- | --- |
| `source/YoureGone-Regular.otf` | The original, unchanged (`Youre Gone.otf` from you-re-gone.zip, 1001fonts.com; SHA-256 `1e1a01c9…070f7066d`). |
| `source/YoureGone-Italic.otf` | The original italic, unchanged (`Youre Gone It.otf` from the same archive; SHA-256 `dbba476d…70dcf5060`). |
| `build.py` | Makes the thin font from the original (by default into `AppHost/Supporting/`). Family "You're Gone Thin", PostScript `YoureGoneThin-Regular` / `YoureGoneThin-Italic`, weight 300; the italic is the same family's style "Italic", with the original italic's slant. |
| `validate.py` | Checks a build against the original (below). |
| `build.sh` | Builds both styles into `AppHost/Supporting/`, validates them and draws the previews. |
| `preview.py` | Draws the previews into `preview/` (not committed): `specimen.png`, original vs thin; `overlay.png` / `overlay-italic.png`, each thin glyph over its original. |
| `requirements.txt` | The Python packages the scripts use. |
| `LICENSE` | CC0, with the original's license record and Ray Larabie's credit (the same text as `AppHost/Supporting/YoureGoneThin-LICENSE.txt`). |

## What changed, and how

- **Every outline eroded by 13 units on every side** (`build.py`, `eroded`): the glyph's own
  edge is stroked with a round pen 26 units wide and that band is subtracted from the outline
  (skia-pathops, whose boolean operations are robust on these curves; FontForge's
  `changeWeight` and its `exclude` both left self-crossing outlines here). This is what
  drawing the same skeleton with a thinner pen gives, so stems, bars and curves all lose the
  same amount: round ends stay round, counters open up by 26 units and nothing else moves.
- **Vertical zones kept**: between the baseline and the cap height (739) each glyph is stretched
  back to full height (horizontal bars come back by ~3.6%, too little to see). Accents above the caps
  and descenders below the baseline are only moved out by 13 units, so nothing reaches past the
  original's line (the original fills its win ascent/descent exactly) and capitals sit on the
  same baseline and cap height.
- **Spacing kept**: each glyph moves left by 13 units and its advance shrinks by 26, so it keeps
  the original's side bearings; the kerning (GPOS) and every other layout table are untouched.
  Zero-width combining marks keep their width and place.
- **Its own names**: "You're Gone Thin" / `YoureGoneThin-Regular` (and its Italic,
  `YoureGoneThin-Italic`, linked to it as the family's italic, slant and style bits as the
  original italic's), weight class 300, so it installs beside the original. The CC0 notice (name IDs 0, 13, 14) is kept; the description
  credits Ray Larabie. fsType 0 (installable). The CFF stem hints (the original's stem widths)
  are dropped; the original's DSIG is removed (it no longer matched).
- The build keeps the original's timestamps, so the same source always builds the same bytes;
  the check rebuilds and compares.

### Picking the weight

Three strokes were tried: −18 (~9%), −26 (~13%) and −34
(~17%). −26 was picked: it reads as the same font, slightly lighter, and its smallest counters
(B, 8, @, %) are clearly more open at body sizes. −18 is hard to tell from the original; −34
starts to look like a different weight.

## Checks (`validate.py`)

A build fails unless fontTools opens it and decompiles every table; it maps exactly the
original's characters to the same glyphs and has exactly its glyphs (269); its names are its
own (family, full and PostScript name all differ from the original's) with the CC0 notice kept;
vertical metrics are unchanged; and every glyph is clean: the same number of contours as the
original (no counter closed or split), no open, self-crossing or reversed outline (FontForge's
validation), within the line and on the original's baseline and cap height, narrower than the
original (marks keep zero width) and lighter.

## Rebuilding

On a Linux or macOS machine with Python 3, fontTools, skia-pathops, Pillow and FontForge's Python
module (Debian: `python3-fonttools python3-fontforge python3-pil`, then `pip install skia-pathops`
in a venv made with `--system-site-packages`; elsewhere `pip install -r requirements.txt` plus
FontForge):

    ./build.sh                              # both styles into AppHost/Supporting, validated, previews
    git status ../../../AppHost/Supporting  # no change: the build makes the same bytes
    python3 -I build.py --stroke -30 --out /tmp/try.otf   # another weight
    python3 -I build.py --style Italic                    # just the italic

`PY=/path/to/python3 ./build.sh` picks the Python with the tools. When the fonts change, update
their SHA-256s in `AppHost/Supporting/YoureGoneThin-SOURCE.md` and `docs/licensing/inventory.json`
(and the files `App/Vendor/generate-license-bundle.py` makes from it:
`AppHost/Supporting/Licenses/components.json`, `THIRD_PARTY_NOTICES.md`).

Run the scripts with `python3 -I` from outside a folder holding a file named after a standard
module (an `inspect.py` scratch script broke fontTools' imports once). skia-pathops' round
strokes come out as conics, which its boolean ops reject: `convertConicsToQuads()` first.
