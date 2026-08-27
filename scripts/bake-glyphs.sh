#!/usr/bin/env bash
# Bakes src/Media/Glyphs.ttf out of the Font Awesome Free solid face.
#
# A glyph here is a mark this addon draws at the size of a letter: a chevron, a
# cross, a plus. An icon is the game's own art for a spell, which UI/Draw.lua
# crops and UI.Icon hands out. Two different things, two words, and this is the
# first.
#
# Five glyphs, and they are drawn on the letters the panel was already using:
# the chevrons on `v` and `>`, the close cross on `x`, and the stepper's own
# `+` and `-`. Nothing in the Lua carries a codepoint escape and nothing has to
# know it is looking at an icon. A string given the icon font draws the icon; the
# same string given the text font draws the letter, which is what the panel drew
# before this file existed and is what it draws again on a client that will not
# take the font.
#
# The source is the system copy rather than a download, because a build step
# that reaches the network is a build step that breaks when you are on a train.
#
#   pacman -S woff2-font-awesome python-fonttools    (or the same two elsewhere)
#   ./bake-icons.sh
#
# The output is about 1.8 KB and is committed, because the addon ships to people
# who have neither of those packages.
set -uo pipefail
cd "$(dirname "$0")/.."

SRC="${FA_SOLID:-/usr/share/fonts/WOFF2/fa-solid-900.woff2}"
LICENSE="${FA_LICENSE:-/usr/share/licenses/woff2-font-awesome/LICENSE.txt}"
OUT="src/Media/Glyphs.ttf"
NOTICE="src/Media/Glyphs-LICENSE.txt"

for f in "$SRC" "$LICENSE"; do
	[ -f "$f" ] || { echo "missing $f. Install woff2-font-awesome, or set FA_SOLID and FA_LICENSE." >&2; exit 1; }
done
command -v woff2_decompress >/dev/null || { echo "no woff2_decompress: install woff2" >&2; exit 1; }
python3 -c 'import fontTools' 2>/dev/null || { echo "no fonttools: install python-fonttools" >&2; exit 1; }

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
cp "$SRC" "$work/fa.woff2"
woff2_decompress "$work/fa.woff2" || exit 1

python3 - "$work/fa.ttf" "$OUT" <<'PY' || exit 1
import sys
from fontTools.ttLib import TTFont
from fontTools.subset import Options, Subsetter

src, out = sys.argv[1], sys.argv[2]

# Font Awesome 4's own codepoints, which 7 still carries, to the letter each one
# replaces. The comment beside each is the name it goes by upstream.
PICK = {
    0xF078: "v",  # chevron-down, a group folded open
    0xF054: ">",  # chevron-right, a group folded shut
    0xF00D: "x",  # xmark, the close button
    0xF067: "+",  # plus, a stepper and the loadout list
    0xF068: "-",  # minus, a stepper
}

font = TTFont(src)
options = Options()
options.notdef_outline = True
options.recalc_bounds = True
options.drop_tables += ["DSIG"]
subsetter = Subsetter(options=options)
subsetter.populate(unicodes=list(PICK))
subsetter.subset(font)

glyphs = font.getBestCmap()
missing = [hex(cp) for cp in PICK if cp not in glyphs]
if missing:
    sys.exit("this Font Awesome has no glyph at " + ", ".join(missing))

remap = {ord(letter): glyphs[cp] for cp, letter in PICK.items()}
for table in font["cmap"].tables:
    table.cmap = dict(remap)

# The OFL reserves the name "Font Awesome", and a subset with its cmap rewritten
# is a modified version, so it may not go out under that name. Everything else
# in the name table is left as it was found, including whose copyright it is.
NAMES = {
    1: "WarriorKit Glyphs",
    2: "Regular",
    3: "WarriorKit Glyphs: five glyphs of Font Awesome Free Solid",
    4: "WarriorKit Glyphs",
    6: "WarriorKitGlyphs-Regular",
    13: "SIL Open Font License 1.1. See Media/Glyphs-LICENSE.txt.",
    14: "http://scripts.sil.org/OFL",
}
for name_id, value in NAMES.items():
    font["name"].setName(value, name_id, 3, 1, 0x409)
    font["name"].setName(value, name_id, 1, 0, 0)

font.save(out)
print("%s, %d glyphs on %s" % (out, len(remap), " ".join(sorted(PICK.values()))))
PY

cp "$LICENSE" "$NOTICE"
ls -l "$OUT" "$NOTICE" | sed 's/^/  /'
