#!/usr/bin/env bash
# Bakes Dungeons/Baked.lua out of Questie's own databases.
#
#   ./scripts/bake-dungeons.sh [path/to/Questie]
#
# Which dungeons there are and what order their bosses are fought in is written
# out by hand in scripts/bake-dungeons.lua. Every number in the baked file is
# read out of Questie: creature ids, levels, item ids and item names, all of
# which Questie generates from the client rather than typing. A boss name in the
# hand-written list that Questie cannot place stops the bake and writes nothing,
# so the two halves check each other every time this runs.
#
# Questie is not a dependency of the addon and is not needed to run it. It is
# needed to run this, once, when the dungeon list changes.
set -uo pipefail
cd "$(dirname "$0")/.."

QUESTIE="${1:-}"
if [ -z "$QUESTIE" ]; then
	# The usual places: an install's own copy, then an unpacked download.
	WOW_ROOT="${WOW_ROOT:-$HOME/Games/battlenet/drive_c/Program Files (x86)/World of Warcraft}"
	for guess in "$WOW_ROOT"/_*_/Interface/AddOns/Questie "$HOME"/Downloads/Questie*/Questie; do
		[ -f "$guess/Database/Classic/classicNpcDB.lua" ] && { QUESTIE="$guess"; break; }
	done
fi

if [ -z "$QUESTIE" ] || [ ! -f "$QUESTIE/Database/Classic/classicNpcDB.lua" ]; then
	echo "no Questie found. Pass the path to a Questie folder." >&2
	exit 1
fi

echo "reading $QUESTIE"
lua5.1 scripts/bake-dungeons.lua "$QUESTIE" || exit 1
lua5.1 -e "assert(loadfile('src/Dungeons/Baked.lua'))" || {
	echo "the baked file does not parse" >&2
	exit 1
}
