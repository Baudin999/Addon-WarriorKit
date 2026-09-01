#!/usr/bin/env bash
# Bakes src/Dungeons/Art.lua out of Blizzard's own instance tables.
#
#   ./scripts/bake-dungeon-art.sh [path/to/a/folder/of/exports]
#
# The shelf is a page of cards, one per dungeon, and a card wants a picture of
# the place. Retail draws that out of the Encounter Journal's art, which the 2.5
# client does not ship: there is no interface/encounterjournal folder in its
# manifest at all. It does ship every instance's loading screen, which is a
# painting of the same place by the same artists, so that is what a card wears.
#
# Three exports, and every one of them is Blizzard's own table:
#
#   map.csv       the 2.5 client's instance list, which says which maps are five
#                 mans and which loading screen each carries.
#   screens.csv   LoadingScreens, which turns that id into a file id.
#   files.csv     ManifestInterfaceData, filtered to the loading screen folder,
#                 which turns a file id into the path it is drawn by.
#
# They come from wago.tools, which serves Blizzard's tables per build. This is
# not a dependency of the addon and is not needed to run it. It is needed to run
# this, once, when the dungeon list changes.
set -uo pipefail
cd "$(dirname "$0")/.."

# The 2.5 client, which is the one that decides which instances exist and what
# art shipped with them. Unlike the map bake beside this one there is no second
# build to read: nothing here was dropped from the tables the client carries.
CLIENT="wow_anniversary"

EXPORTS="${1:-}"
if [ -z "$EXPORTS" ]; then
	EXPORTS="${TMPDIR:-/tmp}/warriorkit-art-exports"
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

	fetch map.csv "https://wago.tools/db2/Map/csv?branch=$CLIENT" || exit 1
	fetch screens.csv "https://wago.tools/db2/LoadingScreens/csv?branch=$CLIENT" || exit 1
	# Filtered rather than whole. The manifest is every interface file the client
	# knows, it is served as one unbroken response, and fetching all of it drops
	# the connection often enough that an unfiltered bake is a bake that usually
	# fails. The filter is the folder every loading screen is in.
	fetch files.csv "https://wago.tools/db2/ManifestInterfaceData/csv?branch=$CLIENT&filter%5BFilePath%5D=LOADINGSCREENS" || exit 1
fi

for name in map.csv screens.csv files.csv; do
	[ -s "$EXPORTS/$name" ] || {
		echo "no $name in $EXPORTS" >&2
		exit 1
	}
done

echo "reading $EXPORTS"
lua5.1 scripts/bake-dungeon-art.lua "$EXPORTS" || exit 1
lua5.1 -e "assert(loadfile('src/Dungeons/Art.lua'))" || {
	echo "the baked file does not parse" >&2
	exit 1
}
