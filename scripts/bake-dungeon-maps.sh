#!/usr/bin/env bash
# Bakes Dungeons/Sheets.lua out of Blizzard's own map tables.
#
#   ./scripts/bake-dungeon-maps.sh [path/to/a/folder/of/exports]
#
# Neither of the two clients this addon ships for will say what a dungeon's map
# looks like. The 1.15 one has no dungeon maps in its map tree; the 2.5 one has
# a hundred and four and files art for none of them. Both ship the tiles under
# Interface\WorldMap all the same, so the picture is drawn by path and the path
# is what this bakes.
#
# Six exports, and every one of them is Blizzard's own table:
#
#   uimap.csv         the 2.5 client's map list. Which dungeon maps that client
#                     has, what it calls them and what id each is.
#   groupmembers.csv  which floor of which place a map is, and what the floor is
#                     called. The 2.5 client does not ship this table, so it is
#                     read out of a build that still does.
#   xmapart.csv       which art belongs to which map.
#   arts.csv          which style that art is cut in.
#   styles.csv        what that style's size and tile size are.
#   tiles.csv         the tiles themselves, as file ids.
#   files.json        which path each file id is filed under, so nothing is
#                     baked that cannot be checked.
#
# They come from wago.tools, which serves Blizzard's tables per build. This is
# not a dependency of the addon and is not needed to run it. It is needed to run
# this, once, when the dungeon list changes.
set -uo pipefail
cd "$(dirname "$0")/.."

# The build the dungeon maps are read from, and the build they are read for.
# LATER is a build that still ships the tables the classic one dropped; CLIENT
# is the 2.5 client, which is the one that decides which dungeon maps exist.
LATER="wow"
CLIENT="wow_anniversary"

EXPORTS="${1:-}"
if [ -z "$EXPORTS" ]; then
	EXPORTS="${TMPDIR:-/tmp}/warriorkit-map-exports"
	mkdir -p "$EXPORTS" || exit 1

	fetch() {
		local into="$EXPORTS/$1"
		local from="$2"
		[ -s "$into" ] && return 0
		echo "fetching $1"
		curl -fsS --max-time 180 "$from" -o "$into" || {
			echo "could not fetch $from" >&2
			rm -f "$into"
			return 1
		}
	}

	fetch uimap.csv "https://wago.tools/db2/UiMap/csv?branch=$CLIENT" || exit 1
	fetch groupmembers.csv "https://wago.tools/db2/UiMapGroupMember/csv?branch=$LATER" || exit 1
	fetch xmapart.csv "https://wago.tools/db2/UiMapXMapArt/csv?branch=$LATER" || exit 1
	fetch arts.csv "https://wago.tools/db2/UiMapArt/csv?branch=$LATER" || exit 1
	fetch styles.csv "https://wago.tools/db2/UiMapArtStyleLayer/csv?branch=$LATER" || exit 1
	fetch tiles.csv "https://wago.tools/db2/UiMapArtTile/csv?branch=$LATER" || exit 1
	fetch files.json "https://wago.tools/api/files?search=interface%2Fworldmap%2F" || exit 1
fi

for name in uimap.csv groupmembers.csv xmapart.csv arts.csv styles.csv tiles.csv files.json; do
	[ -s "$EXPORTS/$name" ] || {
		echo "no $name in $EXPORTS" >&2
		exit 1
	}
done

echo "reading $EXPORTS"
lua5.1 scripts/bake-dungeon-maps.lua "$EXPORTS" || exit 1
lua5.1 -e "assert(loadfile('src/Dungeons/Sheets.lua'))" || {
	echo "the baked file does not parse" >&2
	exit 1
}
