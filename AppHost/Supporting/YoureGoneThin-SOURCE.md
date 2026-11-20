# You're Gone Thin

RetroPlay sets its text in You're Gone Thin, a slightly lighter derivative of You're Gone by
Ray Larabie (Typodermic), version 5.002: every stroke 26 units (of 1000) thinner, about 13%
lighter, with the original's spacing, kerning, metrics and characters. Body text uses the
upright (`YoureGoneThin-Regular.otf`, PostScript `YoureGoneThin-Regular`); titles use the
italic (`YoureGoneThin-Italic.otf`, PostScript `YoureGoneThin-Italic`), made the same way from
the original italic.

- Built by `Design/Fonts/youre-gone-thin/build.py` in this repository, which also holds the
  original files, the validation and the rebuild instructions (`README.md` there). Its
  `build.sh` writes these files in place, and the same sources always build the same bytes.
- Sources: `Youre Gone.otf` (SHA-256 `1e1a01c9760372d50ba233822df234fe982552feb861aff585edcfb070f7066d`)
  and `Youre Gone It.otf` (SHA-256 `dbba476d8173dc8e975a53810d29d80884c6dd36e210bc2d293f39170dcf5060`)
  from `you-re-gone.zip` (SHA-256 `9acd7561cca69258b7d1bdd6ea908b5bf94abd7cfcfa51f1f85d52db73c3c092`),
  downloaded from 1001fonts.com.
- Bundled: `YoureGoneThin-Regular.otf` (SHA-256 `6ef6bce5a2823ef9888927809d6de0b3dbb2752a50f4136e583dfce5e16e4049`),
  `YoureGoneThin-Italic.otf` (SHA-256 `12afc43368d58264b4c8b282acf172b92f404a3e78c29b1a7d141b0a054e0d49`).
- License: CC0 1.0 (public domain dedication, https://creativecommons.org/publicdomain/zero/1.0/),
  as the original, and the derivative is dedicated the same way. The original's license record
  and Ray Larabie's credit are in `YoureGoneThin-LICENSE.txt`.
- Embedding: OS/2 fsType 0 (installable).
- A capitals face: its lowercase keys draw the capitals, so the app shows text as written.

The app bundles these files as resources and performs no runtime font download.
