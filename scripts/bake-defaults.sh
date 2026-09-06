#!/usr/bin/env bash
# Bakes src/Core/Shipped.lua out of an install's saved variables, so that the
# screen you play on is the screen the addon ships with and the one `/wk
# defaults yes` puts back.
#
#   in game     set it up, drag it where you want it, /reload
#   in a shell  ./scripts/bake-defaults.sh [anniversary|classic_era|path]
#
# An addon cannot write files and saved variables live in WTF, which is per
# install and does not travel, so the layout goes out through saved variables
# and comes back in here as a file a git clone carries with it. bake-ui.sh does
# the same trick for Blizzard's own Edit Mode layout; this one is the addon's
# own settings.
#
# Two files are read. The account's holds the screen: where the windows sit and
# every switch and number that is not somebody's character. The character's
# holds the handful that live on one, and only the scalars among them come
# across, because every table under a character names spells that character has.
# Which character is the one that played most recently, or CHARACTER=<name>.
#
# Only settings are carried. The gold ledger, the drop counts, the groups and
# every other record the reset keeps are stepped over in bake-defaults.lua,
# which asks the addon which is which rather than keeping a list of its own.
set -uo pipefail
cd "$(dirname "$0")/.."

WOW_ROOT="${WOW_ROOT:-$HOME/Games/battlenet/drive_c/Program Files (x86)/World of Warcraft}"

# A flavour name, a path, or nothing. Nothing means the anniversary client,
# which is the one the addon is developed against; the file that was read is
# printed either way, because two installs both hold a plausible capture and
# baking the wrong one is a silent mistake.
want="${1:-anniversary}"
if [ -f "$want" ]; then
	saved="$want"
else
	found=()
	while IFS= read -r f; do
		found+=("$f")
	done < <(find "$WOW_ROOT/_${want}_/WTF/Account" -maxdepth 3 \
		-path '*/SavedVariables/WarriorKit.lua' 2>/dev/null | sort)

	if [ "${#found[@]}" -eq 0 ]; then
		echo "no WarriorKit saved variables under $WOW_ROOT/_${want}_." >&2
		echo "Log in once and /reload, or pass the file." >&2
		exit 1
	fi
	if [ "${#found[@]}" -gt 1 ]; then
		echo "more than one account has played there, name the file you want:" >&2
		printf '  %s\n' "${found[@]}" >&2
		exit 1
	fi
	saved="${found[0]}"
fi

[ -r "$saved" ] || { echo "cannot read $saved" >&2; exit 1; }

# The character whose file was written last, which is the one you were playing
# when you set the screen up. Named outright with CHARACTER=<name> where that
# guess is wrong, and skipped entirely where the install has never seen one.
account="${saved%/SavedVariables/WarriorKit.lua}"
character=""
if [ -n "${CHARACTER:-}" ]; then
	character=$(find "$account" -maxdepth 4 -path "*/$CHARACTER/SavedVariables/WarriorKit.lua" \
		2>/dev/null | head -1)
	[ -n "$character" ] || { echo "no saved variables for $CHARACTER under $account" >&2; exit 1; }
else
	character=$(find "$account" -mindepth 3 -maxdepth 4 \
		-path '*/SavedVariables/WarriorKit.lua' -printf '%T@ %p\n' 2>/dev/null |
		sort -rn | head -1 | cut -d' ' -f2-)
fi

echo "reading $saved"
if [ -n "$character" ]; then
	echo "        $character"
fi
lua5.1 scripts/bake-defaults.lua src "$saved" "$character" || exit 1

# Shipped.lua is a Lua file in a TOC, so a bad bake is a broken addon.
lua5.1 -e "assert(loadfile('src/Core/Shipped.lua'))" || {
	echo "the baked file does not parse" >&2
	exit 1
}
