#!/usr/bin/env bash
# Quality gate for WarriorKit. Exits non-zero on any syntax error or lint
# warning, so it can be wired to a hook or run before a /reload.
set -uo pipefail
# The addon is src/, this script is scripts/. Everything below is relative to
# the addon root, so land there and the paths stay as they were.
cd "$(dirname "$0")/../src"

status=0

# find rather than a glob, because the addon is split across feature folders
# and a glob would silently stop covering the files that moved.
while IFS= read -r f; do
	if ! lua5.1 -e "assert(loadfile('$f'))"; then
		echo "syntax FAIL $f"
		status=1
	fi
done < <(find . -name '*.lua' -type f | sort)

# Every file in a TOC must exist, and every Lua file must be in every TOC.
# A file that is not loaded is not gated by anything below, and a file left
# behind by a refactor still looks like live code.
#
# There is one TOC per client flavour. They have to agree: a file added to one
# and not the other loads on one client and silently does not on the other,
# which is the worst kind of difference to debug. So the lists are compared as
# well as checked.
reference=""
reference_name=""

while IFS= read -r toc; do
	toc="${toc#./}"

	grep -qE '^## Interface: [0-9]+' "$toc" || { echo "$toc declares no interface version"; status=1; }

	toc_files=$(grep -E '^[A-Za-z].*\.lua' "$toc" | tr -d '\r' | tr '\\' '/' | sort)

	while IFS= read -r listed; do
		[ -f "$listed" ] || { echo "$toc lists a missing file: $listed"; status=1; }
	done <<< "$toc_files"

	while IFS= read -r f; do
		f="${f#./}"
		# Exact line match, not a substring: Core.lua must not satisfy Core/Core.lua.
		if ! grep -qxF "$f" <<< "$toc_files"; then
			echo "not loaded by $toc: $f"
			status=1
		fi
	done < <(find . -name '*.lua' -type f | sort)

	if [ -z "$reference_name" ]; then
		reference="$toc_files"
		reference_name="$toc"
	elif [ "$toc_files" != "$reference" ]; then
		echo "$toc and $reference_name do not load the same files:"
		diff <(printf '%s\n' "$reference") <(printf '%s\n' "$toc_files") | sed 's/^/  /'
		status=1
	fi
done < <(find . -maxdepth 1 -name 'WarriorKit*.toc' -type f | sort)

# Every TOC agrees with every other TOC on what the addon is, and all of them
# agree with ns.version. These drifted once already: the TOCs said 1.1 while
# Core said 1.2, and nothing anywhere could tell. Interface is deliberately not
# compared, because differing is the whole point of having two files.
core_version=$(sed -n 's/^ns\.version = "\(.*\)"$/\1/p' Core/Core.lua)
[ -n "$core_version" ] || { echo "Core/Core.lua declares no ns.version"; status=1; }

for field in Version Title Notes IconTexture; do
	first_value=""
	first_toc=""
	while IFS= read -r toc; do
		toc="${toc#./}"
		value=$(sed -n "s/^## $field: //p" "$toc")
		if [ -z "$first_toc" ]; then
			first_value="$value"
			first_toc="$toc"
		elif [ "$value" != "$first_value" ]; then
			echo "$toc and $first_toc disagree on ## $field: '$value' vs '$first_value'"
			status=1
		fi
	done < <(find . -maxdepth 1 -name 'WarriorKit*.toc' -type f | sort)

	if [ "$field" = "Version" ] && [ "$first_value" != "$core_version" ]; then
		echo "$first_toc says ## Version: $first_value, Core/Core.lua says ns.version = $core_version"
		status=1
	fi
done

# Every saved variable table a TOC declares must be one the code actually
# writes, and every one the code writes must be declared. An undeclared table
# is not saved at all, and the symptom is settings that vanish on logout.
for table_name in $(grep -hE '^## SavedVariables(PerCharacter)?:' WarriorKit*.toc | sed 's/^[^:]*: *//' | tr ',' ' ' | sort -u); do
	grep -qrE "\b$table_name\b" --include='*.lua' . || {
		echo "TOC declares $table_name, no Lua file touches it"
		status=1
	}
done

# Every texture a TOC names must be in the addon, and every file in Media/ must
# be named by something.
#
# A path that does not resolve draws as a green question mark and writes nothing
# to the log, so the only symptom is art that is quietly wrong. An asset nothing
# names is weight in every download and nobody notices it either. Both are
# invisible in review for the same reason: the file list and the code that reads
# it are never open at the same time.
#
# The client's paths are Interface\AddOns\WarriorKit\..., which is this
# directory with the slashes turned round and a prefix on the front, so the
# prefix comes off before the file can be looked for.
while IFS= read -r declared; do
	[ -n "$declared" ] || continue
	path=$(printf '%s' "$declared" | tr -d '\r' | tr '\\' '/')
	case "$path" in
		Interface/AddOns/WarriorKit/*) path="${path#Interface/AddOns/WarriorKit/}" ;;
		*) echo "a TOC names a texture outside the addon: $declared"; status=1; continue ;;
	esac
	[ -f "$path" ] || { echo "a TOC names a missing texture: $declared"; status=1; }
done < <(grep -hE '^## IconTexture:' WarriorKit*.toc | sed 's/^[^:]*: *//' | sort -u)

# And the same the other way round, for the paths that are in the code rather
# than in a TOC. A font, a texture or a sound is named as a string at the point
# it is used, the client says nothing at all when one does not resolve, and the
# symptom is a missing glyph or a silence that reads as a setting.
#
# Matched on the folder rather than on the whole path, because UI/Text.lua
# builds its own out of ADDON and a rule that only saw a literal would stop
# covering the file it was written for.
# One name is exempt, and the exemption is a rule of its own rather than a hole.
#
# Media/BestAround.mp3 is somebody else's recording. This repository is public,
# so the file is not in it: a clone gets the line in Comfort/Fanfare.lua that
# names it and nothing at the end of that line. That is the shipped state and
# not a fault. The part asks the client, the call comes back refused, and `/wk`
# says the file is not there.
#
# So the file being absent is allowed and the file being tracked is not, which
# is the half worth gating: a wide `git add` on the machine that has the mp3
# puts it back in a public repository and nothing says so. Everything else this
# rule catches is still a path that stopped resolving in a refactor.
UNSHIPPED="BestAround.mp3"
if git ls-files --error-unmatch "Media/$UNSHIPPED" >/dev/null 2>&1; then
	echo "Media/$UNSHIPPED is tracked, and it is not ours to publish"
	status=1
fi

while IFS= read -r named; do
	[ -n "$named" ] || continue
	[ "$named" = "$UNSHIPPED" ] && continue
	[ -f "Media/$named" ] \
		|| { echo "a Lua file names Media\\$named and it is not there"; status=1; }
done < <(grep -rhoE 'Media\\\\[A-Za-z0-9_.-]+' --include='*.lua' . | sed 's/.*\\//' | sort -u)

# Four kinds of file live in Media/ and each has its own rule.
#
# A texture is BLP or TGA, because the client reads nothing else, and both its
# sides are powers of two, because a texture that is not is not drawn. Neither
# failure says anything out loud, which is why this is a gate.
#
# A font is TTF. It is not measured, because a glyph has no power of two to keep,
# and it carries one more rule instead: somebody else's licence has to travel
# with it. Media/Glyphs.ttf is a subset of Font Awesome Free under the SIL OFL,
# and a font in this folder with no <name>-LICENSE.txt beside it is a licence
# that got left behind in a refactor.
#
# A sound is OGG or MP3, because PlaySoundFile reads nothing else, and it
# carries the font's licence rule for a harder reason. An audio file is the one
# kind of asset here that can be somebody else's whole work rather than a glyph
# out of a set. A sound with no <name>-LICENSE.txt beside it is a file nobody
# can tell the provenance of by looking, which is exactly the state you do not
# want to find a repository in.
#
# This half of the rule now only ever runs on somebody's own disk. The one
# sound the addon names is not in the repository, for the reason the exemption
# above gives, so a clone reaches this loop with no sound in Media/ at all.
# The rule stays because the next sound might be ours.
#
# A licence is that file, and it is allowed here only because a font or a sound
# it belongs to is here too.
#
# Everything is named by something in the addon, licences apart, because an
# asset nothing names is weight in every download and nobody notices it.
while IFS= read -r asset; do
	asset="${asset#./}"
	named=1
	case "$asset" in
		*.tga|*.blp) kind=texture ;;
		*.ttf) kind=font ;;
		*.ogg|*.mp3) kind=sound ;;
		*-LICENSE.txt)
			kind=licence
			named=0
			stem="${asset%-LICENSE.txt}"
			[ -f "$stem.ttf" ] || [ -f "$stem.ogg" ] || [ -f "$stem.mp3" ] \
				|| { echo "$asset is a licence for nothing that is here"; status=1; }
			;;
		*) echo "$asset is not a format the client reads"; status=1; continue ;;
	esac

	if [ "$named" -eq 1 ]; then
		grep -qrF "$(basename "$asset")" --include='*.lua' --include='*.toc' --include='*.xml' . \
			|| { echo "nothing in the addon names $asset"; status=1; }
	fi

	if [ "$kind" = "font" ] || [ "$kind" = "sound" ]; then
		[ -f "${asset%.*}-LICENSE.txt" ] \
			|| { echo "$asset ships with no ${asset%.*}-LICENSE.txt beside it"; status=1; }
	fi

	[ "$kind" = "texture" ] || continue

	if [ -x "$(command -v identify || true)" ]; then
		read -r w h < <(identify -format '%w %h' "$asset" 2>/dev/null || echo "0 0")
		for side in "$w" "$h"; do
			if [ "$side" -lt 1 ] || [ $(( side & (side - 1) )) -ne 0 ]; then
				echo "$asset is ${w}x${h}, and both sides have to be powers of two"
				status=1
				break
			fi
		done
	else
		echo "identify missing, so no texture in Media/ was measured: install imagemagick"
		status=1
		break
	fi
done < <(find Media -type f 2>/dev/null | sort)

# The glyph face and the addon agree on which letters carry a mark.
#
# Media/Glyphs.ttf is a subset of Font Awesome with its cmap rewritten to a
# handful of letters, so a glyph string given any other letter draws nothing at
# all: no error, no fallback, an empty rectangle. Both halves of that can drift
# on their own. A letter added to the Lua without rebaking the font draws
# nothing, and a letter dropped from the bake script's PICK draws nothing on
# whatever was already using it. Neither says a word at load, at lint, or in the
# harness, because the font is not read by any of them.
#
# So the two lists are compared as text: UI.GLYPHS in UI/Text.lua against the
# letters PICK maps to in scripts/bake-glyphs.sh. What this cannot check is that
# every letter the addon actually draws is in the alphabet, because the letter
# reaches SetText as a string on a font object chosen elsewhere and no grep can
# follow that. The harness is where that half is asserted.
baked=$(sed -n 's/^[[:space:]]*0x[0-9A-Fa-f]*: "\(.\)",.*/\1/p' ../scripts/bake-glyphs.sh \
	| LC_ALL=C sort | tr -d '\n')
declared=$(sed -n 's/^UI\.GLYPHS = "\(.*\)"$/\1/p' UI/Text.lua)
if [ -z "$baked" ] || [ -z "$declared" ]; then
	echo "the glyph alphabet is not declared in both UI/Text.lua and scripts/bake-glyphs.sh"
	status=1
elif [ "$baked" != "$declared" ]; then
	echo "UI.GLYPHS says '$declared' and scripts/bake-glyphs.sh bakes '$baked'"
	status=1
fi

# Every write on a ticker path is guarded against the value already on the
# frame.
#
# This is the defect that made the addon feel sluggish, and it is invisible in
# review because each instance looks harmless. A SetText or a SetColorTexture
# costs a measure and a relayout whether or not the value changed. A guard
# costs one comparison. At four tickers, fifteen nameplates and five ticks a
# second, the difference was about two thousand pointless widget writes every
# second.
#
# HOT lists the functions reachable from an OnUpdate. A banned write inside one
# of them fails unless an if, elseif or else stands between it and the top of
# the function. A for loop is not a guard: it repeats the write, it does not
# decide it.
#
# The same scan bans allocation on those paths, for the same reason one step
# further out. A table constructor or an anonymous function inside a ticker is
# garbage the collector has to walk later, and the collector runs in the middle
# of a frame. The list collector on the enemy bars was building a table for the
# list, one per mob in it and two closures every fifth of a second, about eighty
# objects a second to answer a question whose answer almost never changed. An
# allocation behind an if is a cache being filled once and is fine; an
# allocation the tick reaches every time is not.
#
# A string is the fourth shape and it was missed for a long time. `:format(`,
# `string.format(` and the `..` operator each hand back a fresh string, and Lua
# interns none of them, so a label built every tick is garbage on the same
# terms a table is. It is worse than a table in one way: the string usually
# goes straight into a SetText, and a SetText of a string that compares equal
# to the one already there still costs the measure. That was item 34.
# ThreatState built its percentage into a string and its caller compared the
# string against what the bar was drawing, so the guard read as a guard and let
# every tick through. The rule is: compare the numbers, format after.
#
# Reading `..` off a line takes a small lexer rather than a match, because the
# scan skips a whole-line comment and nothing else. A trailing `-- two dots ..`
# on a line of code, and a `..` inside a string literal, are both text and
# neither is a concatenation. So `code_of` walks the line, drops anything from
# an unquoted `--` or `[[` to the end of it, and blanks what is inside quotes.
# Varargs are the other false hit: `...` is three dots and is not an operator,
# so it comes out before the two-dot test.
#
# To exempt one line, put `-- unguarded: <reason>` or `-- allocates: <reason>`
# on it. A reason is required, because an exemption without one is the same
# invisible debt as a warning. A whole function that a tick reaches but does not
# run every tick says so with `-- cold: <reason>` above its definition, which
# stops scripts/hot.lua's walk there.
#
# The list is derived rather than typed. scripts/hot.lua walks out from every
# ticker and every OnUpdate and prints one `File.lua:Function` per line, and its
# own header says how it resolves a call and what it deliberately cannot follow.
#
# It used to be two hundred lines here, written by hand. A hand-written
# transitive closure has one failure mode and it is silent: a hot function grows
# a new callee, nobody adds it, and the scan below comes off that code with
# nothing to report. The derived closure is 335 functions against those 200, and
# the 135 it found include a per-tick SetShown in UnitFrames/Block.lua that
# nothing had ever scanned.
HOT=$(lua5.1 ../scripts/hot.lua .) || {
	echo "scripts/hot.lua could not derive the tick paths"
	status=1
}

# The four exemptions this scan honours, each one allow-listed by name.
#
# Two of them are the markers above a definition, `-- hot:` and `-- cold:`, and
# two are the per-line `-- unguarded:` and `-- allocates:`. All four are the same
# thing: a place the walk or the scan was told something it could not work out.
# All four are the shape an allow-list has, and none of them was one.
#
# The markers were a pair of counts, HOT_MARKERS and COLD_MARKERS, held exactly
# equal to what src/ carried. That is a ceiling and scripts/ratchet.lua refuses
# to see it raised, so a ninth `cold:` had no legal path in any number of
# commits: raising the number fails the ratchet, lowering it first fails the
# equality, and deleting a marker to buy room fails the equality too. A gate
# with no legal door is not strict, it is a gate people go round.
#
# And the door they go round it by was standing open. The two line exemptions
# were not counted at all. Fifteen of them, uncapped, honoured by the same awk
# below, growing without anyone deciding. The gate blocked the measured door and
# left the unmeasured one wide, which is exactly the pressure that puts the next
# exemption on a line instead of a function.
#
# So all four are lists now, in the path-keyed shape the harness budgets below
# already use and scripts/ratchet.lua already reads:
#
#   path:how many that file carries:what is exempt and why
#
# A file that did not appear before is a new key, and a new key is legal: this
# refuses a raise, not an addition. Raising a file that is already on the list
# still fails, which is the move that reads as progress and is not. The count is
# exact in both directions, so an exemption retired comes off the list in the
# same commit rather than leaving room the next one spends unremarked.
#
# The marker lists name the function too, and the marker sets are read out of
# scripts/hot.lua rather than grepped for a second time here. One reader of that
# syntax means the list and the code cannot drift into disagreeing about what a
# marker says or which definition it sits above: a marker renamed, moved to
# another function or deleted fails here by name.
#
# `cold:` is the largest of the four and it is a work list, not a settled shape.
# Seven of the fifteen are a builder or a layout pass, which is one repeated
# idea: a function whose writes belong to a widget appearing rather than to the
# tick that found it. If UI/ ever grows a construction seam those seven go
# through, this list is eight entries. Four of the rest are a part talking to
# you rather than drawing: the three in the mouse tracer and ns.Print under it.

# path:cold markers in that file:function, and why the walk stops there
COLD_ALLOWED="
Bags/Window.lua:1:Booked is the redraw a frame after a bag moved, booked by an event and not by a tick
Buffs/Nag.lua:1:Place is layout, run on a settings change and a rescale
Buttons/Trace.lua:3:Trace.Cursor reads what the cursor is holding, on the pass the frame under it changed
Buttons/Trace.lua:3:Trace.Name names the frame under the cursor, on the pass that frame changed
Buttons/Trace.lua:3:Trace.Say prints one trace line, and only while the trace switch is on
Charge/Icon.lua:1:MacroText runs behind SyncMacro comparing target, weapon and spell
CombatText/Anchors.lua:2:Anchors.Apply places three anchors, on a settings change and on the first number of a session
CombatText/Anchors.lua:2:Build makes one anchor, on the first pass after the part is switched on
CombatText/Numbers.lua:1:Build makes one number's frame, on the spawn a busier second than any before it needs another
Cooldowns/Row.lua:1:Place is layout rather than tick
Standing/Row.lua:1:Place is layout, run when the plan is rebuilt or a setting moves
Perf/Hud.lua:3:FillCost writes the five rows under the strip, on the second the ranking moved
Perf/Hud.lua:3:FillDips writes the log, on the tick a dip arrived or an age rolled over a second
Perf/Hud.lua:3:FillNow turns the second's numbers into words, on the tick one of them moved
Perf/Trace.lua:1:Record writes one dip down, on the frames that already went wrong
Core/Core.lua:1:ns.Print writes one line into the chat frame, which is the addon telling you something
UI/Ability.lua:1:Ability.Size is a settings change and a rescale, never a tick
UI/Aura.lua:1:Aura.Size is a settings change and a rescale, never a tick
UI/Feed.lua:1:Feed:Enter fills a tooltip, which is a hover, and the one reopen that is not is throttled to a fifth of a second
UI/Fresh.lua:1:Redraw builds the box again, on the tick a stamp moved and not on the ticks it did not
UI/Tip.lua:1:Land opens the box once, on the frame the wait ran out, and hides the tick with it
UnitFrames/Auras.lua:1:Grow builds the squares an aura row has not needed yet, on the pass a unit first carries that many
UnitFrames/EnemyBars.lua:2:CreateWidget builds one nameplate widget, on the tick a plate first appears
UnitFrames/EnemyBars.lua:2:LayoutWidget places every region of one widget, on a rescale or a settings change
UnitFrames/Plates.lua:1:ApplyOverlap writes the plate overlap CVar, on a settings change and on the login that finds the size call did not take
"

# path:hot markers in that file:function, and why the walk cannot reach it
HOT_ALLOWED="
Breakdown/Breakdown.lua:1:Breakdown.OnLog is a combat log reader, called back out of ns.CombatLog's list
Buffs/Upkeep.lua:1:Upkeep.Scan runs on every UNIT_AURA on the player, off an OnEvent closure
Buttons/Reaction.lua:1:OnLog is a combat log reader, called back out of ns.CombatLog's list
Character/Paperdoll.lua:1:Landed is a tween's onDone, called back through the field when a gear row has finished sliding in
Chat/Feed.lua:1:Feed.Handle runs on every chat line, off this file's OnEvent closure
Ck/Float.lua:2:Expire is a tween's onDone, called back through the field when a message's time on screen runs out
Ck/Float.lua:2:Leave is a tween's onDone, called back through the field when a message has finished fading
CombatText/Numbers.lua:2:Numbers.OnLog is a combat log reader, called back out of ns.CombatLog's list
CombatText/Numbers.lua:2:Release is handed to a style as onGone and called back through the field when a number has finished falling
Comfort/Thanks.lua:1:OnLog is a combat log reader, called back out of ns.CombatLog's list
Cooldowns/Cooldowns.lua:1:Cooldowns.Scan runs on every UNIT_AURA on the player, off an OnEvent closure
Feeds/Combat.lua:1:CombatFeed.OnLog is a combat log reader, called back out of ns.CombatLog's list
Feeds/Purse.lua:1:Purse.Line is handed to a stream as onStatus and called back through the field
Meter/Meter.lua:1:OnLog is a combat log reader, called back out of ns.CombatLog's list
Perf/Census.lua:1:Census.Count runs on every event the client sends, off this file's OnEvent closure
Perf/Feature.lua:1:Paint is assigned to ns.Perf.OnSample and called back through the field
Swing/Swing.lua:2:OnLog is a combat log reader, called back out of ns.CombatLog's list
Swing/Swing.lua:2:Swing.Retime runs on UNIT_AURA and UNIT_ATTACK_SPEED, off an OnEvent closure
UnitFrames/EnemyBars.lua:2:Attach runs on NAME_PLATE_UNIT_ADDED, off an OnEvent closure
UnitFrames/EnemyBars.lua:2:Release runs on NAME_PLATE_UNIT_REMOVED, off an OnEvent closure
"

# path:unguarded writes in that file:why the tick may write there every time
UNGUARDED_ALLOWED="
Charge/Marker.lua:1:the two returns above leave only a marker that is already up
Core/Core.lua:1:a one-shot ticker handing its own handler back
UI/Draw.lua:1:the return above compares all four channels
UI/Feed.lua:1:the return above compares the marker against what the row is drawing
UI/Pixel.lua:1:UI.Rezoom compares the zoom a frame already carries before it calls Rescale
UnitFrames/Cast.lua:1:the moving edge of a cast bar
UnitFrames/EnemyBars.lua:6:a nameplate appearing and a nameplate going, which is once per plate and not once per tick
UnitFrames/PlayerCast.lua:2:the moving edge of the player's cast and of the channel it replaces
"

# path:allocations in that file:why the tick does not reach them every time
ALLOCATES_ALLOWED="
Ck/Stream.lua:1:the pool was empty, which happens as many times as the busiest second of a session ever needs at once
Breakdown/Breakdown.lua:1:one record per spell id ever recorded, behind the two returns above it
Charge/Charge.lua:1:a fallback path the live client's GetNamePlateForUnit never reaches
Chat/Feed.lua:1:one string per chat line, which is the line the window draws
Core/Core.lua:1:one join per denomination in one money reading, and every caller compares the copper figure first
Feeds/Combat.lua:1:one preposition per feed row, which is a thing that happened to you rather than a tick
Feeds/Purse.lua:1:the words for a rate, built where Purse.Line found the figure in whole gold moved
Meter/Window.lua:1:the words for a number, built where the row found the number moved
UI/Ticker.lua:1:one object per tick a part arms, built where the tick is created
Unit/Color.lua:3:one tint and one fill per class, filled once behind a lookup the scan cannot see
Unit/Level.lua:2:one table per classification and one string per level, both behind a lookup
Unit/Unit.lua:1:one token per unit ever seen, behind a lookup the scan cannot see
UnitFrames/EnemyBars.lua:1:the threat wording, built where PaintThreat found one of the three values it compares moved
"

markers=$(lua5.1 ../scripts/hot.lua --markers .) || {
	echo "scripts/hot.lua could not read the markers"
	status=1
}

# One entry, split into its path, its count and the rest. The reason is whatever
# follows the count, and an entry with none is the invisible debt the list
# exists to stop.
entry_path="" entry_count="" entry_why=""
marker_entry() {
	local list="$1" entry="$2" rest
	entry_path=${entry%%:*}
	rest=${entry#*:}
	entry_count=${rest%%:*}
	entry_why=${rest#*:}

	case "$entry_count" in
		*[!0-9]* | "")
			echo "$list carries an entry with no count: $entry"
			status=1
			return 1
			;;
	esac
	[ -f "$entry_path" ] || {
		echo "$list names $entry_path, which is not a file in src/"
		status=1
		return 1
	}
	return 0
}

# One marker kind against one allow-list, both directions. The derived side is
# hot.lua's, so a marker this does not recognise is a marker that moved.
marker_list() {
	local kind="$1" list="$2" allowed="$3"
	local derived listed counted entry fn reason held

	derived=$(printf '%s\n' "$markers" | awk -v k="$kind" '$1 == k { print $2 " " $3 }' | sort)
	listed=""
	# A file with three markers has three entries and one count. Reported once.
	counted=""

	while IFS= read -r entry; do
		[ -n "$entry" ] || continue
		marker_entry "$list" "$entry" || continue

		fn=${entry_why%% *}
		reason=${entry_why#"$fn"}
		[ -n "${reason# }" ] || {
			echo "$list allow-lists $entry_path:$fn with no reason given"
			status=1
		}

		if ! grep -qxF "$entry_path $fn" <<< "$derived"; then
			echo "$list names $entry_path:$fn and there is no $kind: marker on it: a marker renamed or moved comes off the list in the same commit"
			status=1
			continue
		fi

		held=$(awk -v p="$entry_path" '$1 == p' <<< "$derived" | wc -l)
		if [ "$held" -ne "$entry_count" ] && ! grep -qxF "$entry_path" <<< "$counted"; then
			counted="$counted$entry_path"$'\n'
			echo "$list says $entry_path carries $entry_count $kind: markers and it carries $held: one added needs the count raised and defending, one retired needs it lowered in the same commit"
			status=1
		fi

		listed="$listed$entry_path $fn"$'\n'
	done <<< "$allowed"

	while IFS= read -r entry; do
		[ -n "$entry" ] || continue
		grep -qxF "$entry" <<< "$listed" || {
			echo "src/${entry% *} carries a $kind: marker on ${entry#* } that $list does not hold: add an entry with its reason"
			status=1
		}
	done <<< "$derived"
}

# One line exemption against one allow-list, both directions. Per file rather
# than per line, because the reason a line is exempt is already written on the
# line and hot_scan below refuses it without one. What was missing was the
# ceiling: how many a file is allowed, and why it has any.
exemption_list() {
	local tag="$1" list="$2" allowed="$3"
	local derived listed entry held

	derived=$(grep -rl -e "-- $tag:" --include='*.lua' . | sed 's|^\./||' | sort)
	listed=""

	while IFS= read -r entry; do
		[ -n "$entry" ] || continue
		marker_entry "$list" "$entry" || continue

		[ -n "${entry_why# }" ] || {
			echo "$list allow-lists $entry_path with no reason given"
			status=1
		}

		held=$(grep -c -e "-- $tag:" "$entry_path")
		if [ "$held" -ne "$entry_count" ]; then
			echo "$list says $entry_path carries $entry_count lines marked $tag: and it carries $held: one added needs the count raised and defending, one retired needs it lowered in the same commit"
			status=1
		fi

		listed="$listed$entry_path"$'\n'
	done <<< "$allowed"

	while IFS= read -r entry; do
		[ -n "$entry" ] || continue
		grep -qxF "$entry" <<< "$listed" || {
			echo "src/$entry carries a line marked $tag: that $list does not hold: add an entry with its count and its reason"
			status=1
		}
	done <<< "$derived"
}

marker_list cold COLD_ALLOWED "$COLD_ALLOWED"
marker_list hot HOT_ALLOWED "$HOT_ALLOWED"
exemption_list unguarded UNGUARDED_ALLOWED "$UNGUARDED_ALLOWED"
exemption_list allocates ALLOCATES_ALLOWED "$ALLOCATES_ALLOWED"

hot_scan='
BEGIN { inside = 0; QUOTE = sprintf("%c", 39) }

# The line with its comments and its string literals taken out, so that a `..`
# which is prose or is part of a message does not read as an operator. Anything
# from an unquoted `--` or an opening `[[` to the end of the line goes, and the
# body of a quoted string goes while its quotes stay.
function code_of(s,   out, i, n, c, q) {
	out = ""
	i = 1
	n = length(s)
	q = ""
	while (i <= n) {
		c = substr(s, i, 1)
		if (q != "") {
			if (c == "\\") { i += 2; continue }
			if (c == q) { out = out c; q = "" }
			i++
			continue
		}
		if (c == "\"" || c == QUOTE) { q = c; out = out c; i++; continue }
		if (c == "-" && substr(s, i + 1, 1) == "-") break
		if (c == "[" && substr(s, i + 1, 1) == "[") break
		out = out c
		i++
	}
	return out
}

{
	line = $0
	if (!inside) {
		if (line ~ ("^(local[ ]+)?function[ ]+" target "[ ]*\\(")) {
			inside = 1
			for (k in opener) delete opener[k]
		}
		next
	}
	if (line ~ /^end/) { inside = 0; next }

	indent = 0
	while (substr(line, indent + 1, 1) == "\t") indent++
	body = substr(line, indent + 1)

	for (k in opener) if (k + 0 > indent + 1) delete opener[k]
	if (body ~ /^--/ || body == "") next

	if (body ~ /^if[ (]/ || body ~ /^elseif[ (]/ || body == "else") opener[indent + 1] = "if"
	else if (body ~ /^for[ (]/ || body ~ /^while[ (]/ || body == "do" || body == "repeat") opener[indent + 1] = "loop"
	else if (body ~ /function[ ]*\(/) opener[indent + 1] = "loop"
	else if (body ~ / then$/) opener[indent + 1] = "if"
	else if (body ~ / do$/) opener[indent + 1] = "loop"

	code = code_of(body)
	joins = code
	gsub(/\.\.\./, " ", joins)

	writes = (body ~ /:Set[A-Z][A-Za-z]*\(/)
	allocates = (body ~ /\{/ || body ~ /function[ ]*\(/ \
		|| code ~ /:format\(/ || code ~ /string\.format\(/ \
		|| joins ~ /\.\./)
	if (!writes && !allocates) next

	kind = writes ? "writes" : "allocates"
	tag = writes ? "unguarded" : "allocates"
	if (body ~ ("-- " tag ":[ ]*[^ ]")) next
	if (body ~ ("-- " tag ":")) {
		printf "%s:%d: %s exempts a %s with no reason: %s\n", FILENAME, NR, target, kind, body
		next
	}

	guarded = 0
	for (k = 2; k <= indent; k++) if (opener[k] == "if") guarded = 1
	if (!guarded) printf "%s:%d: %s %s without a guard: %s\n", FILENAME, NR, target, kind, body
}
'

# Nothing checks that the list names a file that exists or a function that is
# there, the way it did while a person typed it. hot.lua only ever prints a
# definition it found, so both of those are answered by where the list comes
# from rather than by a check after the fact.
while IFS=: read -r file fn; do
	[ -n "$file" ] || continue
	found=$(awk -v target="$(printf '%s' "$fn" | sed 's/\./[.]/g')" "$hot_scan" "$file")
	if [ -n "$found" ]; then
		echo "$found"
		status=1
	fi
done <<HOTEOF
$HOT
HOTEOF

# One file talks to Blizzard's tooltip, and it is UI/Scan.lua.
#
# The addon draws its own tooltip: a flat box, the theme's palette, the addon's
# own sans, one physical pixel of edge. GameTooltip is a tiled parchment with a
# gold border drawn off a corner sheet. Every file that named GameTooltip put
# one of those on the screen beside the other, and there were six of them: the
# action squares, the aura squares, the chat log's links, the minimap clock, the
# meter header and the charge icon. Nothing was wrong at any one site, which is
# exactly why it went on for six files.
#
# The stats, the rank, the cost and the enchant line are computed inside the
# game and no API hands them over, so reading them off a hidden GameTooltip is
# the only supported way to get at them. UI/Scan.lua does that and hands the
# text back as data. Every other file asks for a subject and gets the addon's
# own box.
#
# Comments are read too, on purpose. A file explaining what it does to
# GameTooltip is a file that thinks it still owns one.
while IFS= read -r bad; do
	echo "only UI/Scan.lua may name GameTooltip, and this is a tooltip drawn in two designs: $bad"
	status=1
done < <(grep -rn 'GameTooltip' --include='*.lua' . \
	| grep -v '^\./UI/Scan\.lua:' || true)

# One file talks to Questie, and it is Core/Core.lua.
#
# Questie is another addon. Every question this one asks it starts at
# QuestieLoader:ImportModule, which hands back a fresh empty table for a name it
# has never heard of rather than nil, so the module coming back proves nothing
# and the caller has to check for the call it means to make. That is six lines
# and a paragraph explaining them, and five files wrote both out: Quests/Where,
# Quests/Tracker, Quests/Party, Map/Pins and Comfort/Clutter. Four of the five
# were character for character the same, and Where.lua handed its copy back out
# as Where.Module so Quests/Drops could borrow it, which is the shape a probe
# takes on the way to being everywhere.
#
# ns.Questie in Core/Core.lua is that probe, asked for by the name of the module
# and the names of the calls the reader is about to make. It is the rule item 21
# wrote with a name on it: outside Core, a file does not probe for a call it
# means to make.
#
# Comments are read too, for the reason the GameTooltip rule reads them. A file
# explaining what ImportModule does is a file about to do it.
while IFS= read -r bad; do
	echo "only Core/Core.lua may name QuestieLoader, and ns.Questie is the probe: $bad"
	status=1
done < <(grep -rnE 'QuestieLoader|ImportModule' --include='*.lua' . \
	| grep -v '^\./Core/Core\.lua:' || true)

# And the client half of the same rule, which item 21 asked for and could not
# size. Outside Core/, a file does not probe the client for a call it means to
# make.
#
# The reason the rule sat as a comment for a week is that it looks unmeasurable.
# `_G` is read 365 times outside Core/ and most of those are a frame fetched by
# name, `_G["MultiBarBottomLeftButtonName"..i]`, which is the client's own
# naming scheme and is not a probe at all. A gate on `_G` would have been 365
# violations, which is a warning wearing a gate's clothes.
#
# So the rule names the shape it refuses rather than the symbol: `type(_G.Foo)`
# or `type(_G[name])`, which is the question "does this client have this call"
# and nothing else. That shape is 78 sites in 39 files, small enough to hold
# exactly, and every one of them is a file deciding for itself which flavour it
# is running on. Core/ is exempt because deciding that is what Core is for:
# ns.Questie, ns.RegisterUnitEvent and the thirty shims beside them exist so a
# feature file can call one name and not know the answer.
#
# The list below is a migration state and it is counted, so it drains. A file
# whose probe moves into Core comes off in the same commit, a raise fails the
# ratchet, and a probe in a file that is not on the list fails outright.
#
# path:probes in that file:what it asks the client and why the answer is not Core's yet
PROBED_ALLOWED="
Bags/Blizzard.lua:2:the numbered ContainerFrame globals, hooked only on the flavour that defines them
Bags/Grid.lua:1:ContainerFrame_UpdateCooldown, which the vanilla flavour does not carry
Bags/Session.lua:1:GetZoneText, absent early in login on one flavour
Buttons/Layout.lua:1:an action button global fetched by name and checked before it is hooked
Buttons/Ranks.lua:1:an action button global fetched by name and checked before it is hooked
Buttons/Slot.lua:1:an action button global fetched by name and checked before it is hooked
Character/Blizzard.lua:3:ToggleCharacter and the binding pair, which item 26 retires into ns.TakeKey
Character/Reputation.lua:2:GetNumFactions, which the two flavours spell differently
Character/Worn.lua:1:PickupInventoryItem, guarded because the drag path runs under the stub too
Chat/Blizzard.lua:1:hooksecurefunc, the one call that has to exist before anything else can be said
Chat/Compose.lua:2:ChatEdit_SendText and SendChatMessage, the client's send path or ours
Chat/Feed.lua:3:the message filter pair and GetPlayerInfoByGUID, none of them on vanilla
Chat/Field.lua:2:ChatEdit_ActivateChat and ChatEdit_ChooseBoxForSend, the client's edit box handover
Chat/Rooms.lua:7:seven ways to count a group, and which of them exists is the flavour
Chat/Window.lua:1:PlaySound, whose signature changed between the two
Comfort/Camera.lua:1:GetCVarDefault, so a reset can put back what the client shipped
Comfort/Clutter.lua:2:the quest log pair, read the same way Quests/Client.lua reads it
Comfort/Destroy.lua:2:ClearCursor, guarded because the destroy path runs under the stub
Comfort/Fanfare.lua:1:PlaySoundFile, and the file it names is not in a public clone
Comfort/Leftovers.lua:1:ClearCursor, the same guard as Destroy.lua for the same reason
Comfort/Loot.lua:1:GetLootMethod, absent when the player is in no group
Comfort/Thanks.lua:2:SendChatMessage, once per channel it will speak on
Feeds/Auction.lua:2:two other addons' price calls, which is ns.Questie's rule and wants ns.Questie's shape
Hover/Hover.lua:2:GetSpellBookItemName and SecureCmdOptionParse, both flavour-split
Mail/Send.lua:1:SetSendMailMoney, absent on the flavour with no attachments
Mail/Who.lua:2:the friend list pair, which changed name between the two
Mail/Window.lua:1:CloseMail, guarded because the window closes under the stub as well
Map/Blizzard.lua:1:ToggleWorldMap, the call the cage gives its key back to
Perf/Cause.lua:2:GetScriptCPUUsage, which is off unless the player turned it on
Quests/Blizzard.lua:1:ToggleQuestLog, the call the cage gives its key back to
Quests/Client.lua:4:four quest log calls, and Progress/Progress.lua argues on disk why each part reads its own returns
Spellbook/Blizzard.lua:3:ToggleSpellBook and the binding pair, which item 26 retires into ns.TakeKey
Spellbook/Read.lua:1:SPELL_PASSIVE, a client string constant rather than a call
Talents/Blizzard.lua:2:ToggleTalentFrame and GetBindingKey, which item 26 retires into ns.TakeKey
Talents/Read.lua:10:the whole dual-spec API, which one flavour has and the other does not
Talents/Window.lua:2:TALENT_SPEC_PRIMARY and SECONDARY, client string constants rather than calls
UI/Chart.lua:3:the world position trio, which decides whether a map can be drawn at all
UI/Log.lua:1:SetItemRef, so a link in a log line opens the client's own tooltip
UnitFrames/Group.lua:1:GetRaidRosterInfo, absent on the flavour with no raids
"

# The list against src/, both directions, on the same terms as the four above.
probe_list() {
	local list="$1" allowed="$2"
	local derived listed entry held

	derived=$(grep -rlE 'type\(_G[.[]' --include='*.lua' . \
		| sed 's|^\./||' | grep -v '^Core/' | sort)
	listed=""

	while IFS= read -r entry; do
		[ -n "$entry" ] || continue
		marker_entry "$list" "$entry" || continue

		[ -n "${entry_why# }" ] || {
			echo "$list allow-lists $entry_path with no reason given"
			status=1
		}

		held=$(grep -cE 'type\(_G[.[]' "$entry_path")
		if [ "$held" -ne "$entry_count" ]; then
			echo "$list says $entry_path probes the client $entry_count times and it probes $held: one added needs the count raised and defending, one moved into Core needs it lowered in the same commit"
			status=1
		fi

		listed="$listed$entry_path"$'\n'
	done <<< "$allowed"

	while IFS= read -r entry; do
		[ -n "$entry" ] || continue
		grep -qxF "$entry" <<< "$listed" || {
			echo "src/$entry probes the client for a call it means to make, and only Core/ may: put the probe in Core/Core.lua beside ns.Questie, or add an entry with its count and its reason"
			status=1
		}
	done <<< "$derived"
}

probe_list PROBED_ALLOWED "$PROBED_ALLOWED"

# No tooltip carries a blue line naming a switch.
#
# UI/Tip.lua used to build a fourth band called `hint`: one quiet blue sentence
# at the bottom of a box saying what to press, what to type, or which setting
# turns the thing off. It reached twenty five call sites, which is what killed
# it. A footnote under every hover in the addon is not a footnote, it is
# furniture, and on the world hover it sat over the fight for the whole evening.
#
# The band is gone from UI/Tip.lua and UI/Tooltip.lua, so a `hint` on a subject
# today draws nothing at all. That is the reason for the gate rather than an
# argument against one: a field that is silently ignored is a field somebody
# writes again, tests by eye, and cannot tell is doing nothing.
#
# UI/Widgets.lua is exempt and is a different thing wearing the same word:
# `ui.Hint` is the sentence under a control in the settings window, it is drawn
# in that window and not in a tooltip, and it is the place the deleted lines
# should have been all along. Core/BlizzHide.lua, Buffs/Upkeep.lua and the
# class files carry `hint` fields on their own tables that feed one of those or
# feed a body line, so the rule reads assignments at the indentation a table
# constructor puts them at rather than any mention of the word.
while IFS= read -r bad; do
	echo "the tooltip's blue hint line is gone, and a subject may not carry one: $bad"
	status=1
done < <(grep -rnE '^[[:space:]]+hint = ' --include='*.lua' . 	| grep -v '^\./UI/Widgets\.lua:' 	| grep -v '^\./Core/BlizzHide\.lua:' 	| grep -v '^\./Buffs/Upkeep\.lua:' 	| grep -v '^\./Class/' || true)

# The drawing layer does not know the name of a setting.
#
# UI/Window.lua and UI/Tooltip.lua have both said so in a comment for a while,
# and both were keeping their word. The rule is written down now because
# UI/Placeable.lua is the file that had to work for it. A placeable frame is a
# setting made visible: it saves where you dragged it. The obvious shape was to
# hand it the key and let it write ns.db itself, and that shape is what put a
# setting's name in every widget in every other addon anybody has read.
#
# So it takes a function that receives the finished anchor, the same way UI.Size
# takes a number Settings/Settings.lua pushed in rather than reading the slider
# it came off. What the layer below decides, the layer above names.
#
# Written while it is already satisfied, which is the only cheap moment. A rule
# added after it breaks costs a refactor; this one costs nothing today and stops
# the next widget being handed a key.
#
# Comments count, for the reason the GameTooltip rule reads them: a file
# explaining what it does with ns.db is a file that thinks it may. The two
# comments that say the layer must not are exempt by name, and so is this one's
# own explanation in Placeable.lua's header.
while IFS= read -r bad; do
	echo "src/UI/ may not name a setting, and a widget takes a getter rather than a key: $bad"
	status=1
done < <(grep -rn 'ns\.db' --include='*.lua' ./UI 	| grep -v '^\./UI/Window\.lua:.*is held here rather than read out of ns\.db' 	| grep -v '^\./UI/Tooltip\.lua:.*ns\.db for the reason UI\.Size is' 	| grep -v '^\./UI/Placeable\.lua:.*so ns\.db stays' || true)

# A frame handler names a function, and never opens a closure.
#
# This is what makes the list above derivable. scripts/hot.lua walks out from
# whatever the handler is set to, and a closure written in place is a root it
# cannot name and a body the scan cannot find: the tick would run with nothing
# above checking it, and nothing would say so. There were eight of these.
#
# Both forms are covered because both set a handler. ns.UI.Ticker is the one
# nearly every part uses; a raw SetScript is left for the two handlers that are
# not ticks, the drag follow in UI/Placeable.lua and the one-shot in Core.
while IFS= read -r bad; do
	echo "a frame handler takes a named function, not a closure written in place: $bad"
	status=1
done < <(grep -rnE 'SetScript\("OnUpdate", *function|UI\.Ticker\([^)]*, *function' \
	--include='*.lua' . | grep -v '^\./UI/Ticker\.lua:.*function UI\.Ticker' || true)

# Every ticker is timed, and every slot times a ticker.
#
# ns.Perf.Start looks a tick's name up in Perf's ORDER and returns without doing
# anything for a name that is not on it, so a ticker missing from that list is
# not measured at all and its row on the performance tab reads as unavailable.
# Ten of the twenty four were missing and two of those run on every frame: the
# tooltip's sweep and the chart's drift. The tab written to find an expensive
# tick was the one place an expensive tick could hide, and nothing said a word,
# because a lookup that misses is what "not timed" and "no such ticker" both
# look like from inside Perf.Start.
#
# The other direction is the same debt spelled backwards. A slot left behind by
# a ticker that was renamed or deleted draws a row nobody is filling in, which
# reads as a part that costs nothing rather than as a part that is not there.
#
# A slot can also time something that is not a ticker, and one does: the bag
# window brackets its refresh in ns.Perf.Start and ns.Perf.Stop by a literal
# name, because the bag events book it up to ten times a second at a vendor
# and a cost that shape has to be on the tab. So a literal name handed to
# ns.Perf.Start counts as armed the same as a ticker name does, and the two
# directions stay exact: a bracket with no slot and a slot with no bracket
# both fail here.
armed=$({ grep -rhoE 'UI\.Ticker\([^)]*"[a-z]+"' --include='*.lua' . ; \
	grep -rhoE 'ns\.Perf\.Start\("[a-z]+"\)' --include='*.lua' . ; } \
	| grep -oE '"[a-z]+"' | tr -d '"' | sort -u)
timed=$(sed -n '/^local ORDER = {/,/}/p' Perf/Perf.lua \
	| grep -oE '"[a-z]+"' | tr -d '"' | sort -u)
if [ -z "$armed" ] || [ -z "$timed" ]; then
	echo "the ticker names or Perf's slot list are no longer a list this gate can read"
	status=1
elif [ "$armed" != "$timed" ]; then
	echo "the tickers and Perf's slot list disagree:"
	diff <(printf '%s\n' "$armed") <(printf '%s\n' "$timed") | sed 's/^/  /'
	status=1
fi

# A tick that never stops hangs off one frame, and which frame stays the
# caller's word.
#
# The client makes a Lua call per frame for every frame carrying an OnUpdate,
# before anything inside it compares an accumulator against an interval.
# Eighteen parts of the addon armed a tick at login on a private frame of their
# own, which was eighteen of those calls to run twenty ticks. They hang off
# ns.UI.Forever now and it is one call.
#
# UI/Ticker.lua's header says why that file does not work out which tick is
# which. Parentage is the probe that suggests itself and it answers a different
# question: two parts here build a parentless frame for a tick and then hide and
# show it to gate that tick, which is exactly what hanging a tick off a frame is
# for. So the word is the caller's, and this is what stops it being forgotten. A
# tick on a frame of its own needs an entry here saying why that frame can hide,
# and a part that quietly takes a frame back for itself fails at the commit
# rather than in somebody's frame budget.
#
# path:how many ticks in that file hang off a frame of their own:why it can hide
FRAMED_TICKERS_ALLOWED="
Character/Paperdoll.lua:1:the turn hangs off the figure it turns, so a sheet shut mid drag stops it with no line anywhere to remember
Feeds/Stream.lua:1:the strip is a region of the feed window and goes with it
Perf/Hud.lua:1:the repaint goes with the window it draws, which is the whole of what hanging a tick off a frame buys
UI/Chart.lua:2:the follow and the drift both go with the board they are drawn on
UI/Feed.lua:1:the repaint goes with the feed's own frame
UI/Fresh.lua:1:the frame is hidden and shown to gate the refresh, which runs only while a box with something moving in it is on screen
UI/Tip.lua:1:the frame is hidden and shown to gate the wait, which is armed by a hover and runs for a few frames
UI/Tooltip.lua:1:the frame is hidden and shown to gate the sweep, which is the whole of what hanging a tick off a frame buys
World/World.lua:1:the frame is hidden and shown to gate the sweep
"

framed_count() {
	local file="$1" held
	held=$(grep -E '(ns\.)?UI\.Ticker\(' "$file" \
		| grep -cvE 'UI\.Ticker\((ns\.)?UI\.Forever,' || true)
	printf '%s' "${held:-0}"
}

framed_derived=$(grep -rlE '(ns\.)?UI\.Ticker\(' --include='*.lua' . \
	| sed 's|^\./||' | grep -v '^UI/Ticker\.lua$' | sort | while IFS= read -r file; do
		[ "$(framed_count "$file")" -gt 0 ] && printf '%s\n' "$file"
	done)

framed_listed=""
while IFS= read -r entry; do
	[ -n "$entry" ] || continue
	marker_entry FRAMED_TICKERS_ALLOWED "$entry" || continue

	[ -n "${entry_why# }" ] || {
		echo "FRAMED_TICKERS_ALLOWED allow-lists $entry_path with no reason given"
		status=1
	}

	held=$(framed_count "$entry_path")
	if [ "$held" -ne "$entry_count" ]; then
		echo "FRAMED_TICKERS_ALLOWED says $entry_path hangs $entry_count ticks off a frame of its own and it hangs $held: one added needs the count raised and defending, one moved to ns.UI.Forever needs it lowered in the same commit"
		status=1
	fi

	framed_listed="$framed_listed$entry_path"$'\n'
done <<< "$FRAMED_TICKERS_ALLOWED"

while IFS= read -r entry; do
	[ -n "$entry" ] || continue
	grep -qxF "$entry" <<< "$framed_listed" || {
		echo "src/$entry arms a ticker on a frame of its own: hang it off ns.UI.Forever, or add an entry with its count and why that frame can hide"
		status=1
	}
done <<< "$framed_derived"

# The options window's own rules, in the half a grep can settle.
#
# The harness measures the strings a feature actually produced, which is the
# only way to check a label built by concatenation or a lede that reports live
# state. This is the other half: a call that is wrong on the face of it, caught
# on a file that does not have to load. It is here as well as in the harness
# because a grep is instant and because the message can name the call to use
# instead, which a measurement after the fact cannot.
#
# Each entry is a pattern, then what to write instead, separated by a pipe. That
# means no pattern may contain one: `read` splits on the first, so an
# alternation would land half in the pattern and half in the message, and the
# only symptom is grep complaining about an unmatched bracket while the rule
# quietly stops checking anything. Write two entries instead.
#
# A label finished by concatenation is not here and cannot be: `"collect " ..
# entry.collects` reads correctly only once the feed's name is glued on, and no
# grep can tell that from a label somebody left a space on the end of. The
# harness checks the string the feature actually produced, which is the only
# place that question can be answered.
PANEL_RULES='
ui\.Header\(|ui.Section(title, group): a section names the group it belongs in
ui\.Note\(|ui.Lede for what the section does, ui.Hint for one control, ui.Reading for a live number
ui\.Text\(|ui.Lede, ui.Hint or ui.Reading
ui\.Stepper\("zoom"|ui.Zoom(get, set): there is one zoom range and it is 1 to 3
ui\.Slider\("zoom"|ui.Zoom(get, set)
ui\.Slider\("background"|ui.Opacity(label, get, set): there is one opacity range and it is 0 to 100 in fives
ui\.Slider\("opacity"|ui.Opacity(label, get, set)
ui\.Slider\("bar opacity"|ui.Opacity("background", get, set): all three of these do the same thing and are called the same thing
ui\.Stepper\("rows"|ui.Count(label, low, high, get, set)
ui\.Stepper\("list bars"|ui.Count("rows", low, high, get, set)
ui\.[A-Za-z]*\("[^"]*in pixels"|ui.Size(label, low, high, step, get, set): the widget writes px after the number
^local [A-Z_, ]*LOW_ZOOM|ns.UI.ZOOM_LOW and ns.UI.ZOOM_HIGH
^local [A-Z_, ]*HIGH_ZOOM|ns.UI.ZOOM_LOW and ns.UI.ZOOM_HIGH
^local [A-Z_, ]*ALPHA_LOW|ns.UI.ALPHA_LOW, ns.UI.ALPHA_HIGH and ns.UI.ALPHA_STEP
^local [A-Z_, ]*LOW_ALPHA|ns.UI.ALPHA_LOW, ns.UI.ALPHA_HIGH and ns.UI.ALPHA_STEP
'

while IFS='|' read -r pattern instead; do
	[ -n "$pattern" ] || continue
	# UI/Widgets.lua is where all of these are defined and where the kit calls
	# its own Stepper and Slider, so it is the one file the rules do not read.
	hits=$(grep -rnE "$pattern" --include='*.lua' . | grep -v '^\./UI/Widgets\.lua:' || true)
	if [ -n "$hits" ]; then
		printf '%s\n' "$hits" | sed "s|^|use $instead -- |"
		status=1
	fi
done <<PANELEOF
$PANEL_RULES
PANELEOF

# Every section names a group, which means two arguments. A one argument call
# would load and then fail at login, which is later than it needs to.
while IFS= read -r bad; do
	echo "a section names no group: $bad"
	status=1
done < <(grep -rnE 'ui\.Section\("[^"]*"\)' --include='*.lua' . || true)

# A font size is a pixel height, never a unit measurement.
#
# Every number in a widget file is a design pixel multiplied by the zoom, so
# `16 * unit` is the shape of nearly every line in UI/. A font size is the one
# thing that is not: inside a frame ns.UI.Adopt has taken onto the grid, a font
# size already is a pixel height, which is why UI.Metric keeps the three of them
# beside the pixel measurements and why every call in the addon passes one of
# them raw.
#
# The loot feed's filter chips got this wrong and it is worth writing the gate
# rather than the fix. `UI.Glyph(chip, CHIP_MARK * unit, ...)` asked for 26.25,
# SetFont refuses a fraction, the readback in UI/Text.lua then failed the
# fallback too, GetFont came back nil, and every chip drew an empty square. The
# geometry was correct and only the picture was missing, so nothing that
# measures a rectangle could see it, and the harness runs at one unit per pixel
# where the fraction never appears at all. It took a screenshot to find.
#
# One line calls only, which is every one of them: a font size is an argument
# short enough that nobody wraps it.
while IFS= read -r bad; do
	echo "a font size is multiplied by a unit, and a font size is already pixels: $bad"
	status=1
done < <(grep -rnE 'UI\.(Label|Glyph|Font|GlyphFont|NumberFont)\([^)]*\*[[:space:]]*[A-Za-z_.]*unit' \
	--include='*.lua' . || true)

# Every string in the addon names the role it is drawn in.
#
# UI/Text.lua has three: flat over a surface this addon painted, shadowed over
# art it did not, outlined over the world. Which one a string wants is a fact
# about what is behind it, the caller is the only thing that knows it, and until
# now a caller that said nothing got an outline.
#
# That default is what the gate replaces. It went wrong the way an unnamed
# default always does: nowhere anybody looked. The purse along the bottom of the
# loot feed and every row of the feed above it are painted on an opaque
# background this addon owns and asked for no role, so they were drawn with a
# rim meant for a health number over a mob, and twelve pixel Arial Narrow with a
# rim round it closes up the counters of its own digits. Nothing was wrong at
# any one site. The reviewer would have had to know the default to see it.
#
# UI/Text.lua is skipped: it is where the three roles are defined and where the
# fallback lives.
font_roles='
function depth(s,   i, c, d) {
	d = 0
	for (i = 1; i <= length(s); i++) {
		c = substr(s, i, 1)
		if (c == "(") d++
		else if (c == ")") d--
	}
	return d
}
FNR == 1 { pending = "" }
{
	if (pending == "") {
		if ($0 !~ /UI[.](Label|Font)[(]/) next
		start = FNR
		pending = $0
	} else {
		pending = pending " " $0
	}
	# A call wrapped onto a second line carries its role there, so the check
	# waits for the brackets to close rather than reading half of one.
	if (depth(pending) > 0) next
	if (pending !~ /UI[.](FLAT|SHADOW|OUTLINE)/) {
		sub(/^[\t ]+/, "", pending)
		printf "%s:%d: names no font role: %s\n", FILENAME, start, pending
	}
	pending = ""
}
'

while IFS= read -r f; do
	f="${f#./}"
	# The file the three roles are defined in, and the one that holds the
	# fallback a call the gate never sees still draws with.
	if [ "$f" = "UI/Text.lua" ]; then
		continue
	fi
	found=$(awk "$font_roles" "$f")
	if [ -n "$found" ]; then
		echo "$found"
		status=1
	fi
done < <(find . -name '*.lua' -type f | sort)

# An outlined string is at least as tall as UI.OutlineFloor.
#
# The floor is a size, not a switch. An outline costs a pixel on every stroke
# whatever the glyph is, so under fourteen the rim closes the hole in a 6 and
# the waist of an 8 and the two digits stop being different shapes: text asking
# for a rim below the floor comes out less readable than the flat text it
# replaced, which is the opposite of what the caller wanted and is invisible in
# a screenshot until somebody misreads a number.
#
# Written down here because the count on a bag square now depends on it. That
# number is fourteen exactly, and it is fourteen so that it can carry a rim
# over an item's own picture; a later edit trimming it to thirteen to fit a
# tighter square would leave the rim on and silently take the legibility the
# size was bought for. Every outlined string in the addon sits at the floor
# today, so the gate ships with no allow-list.
#
# A size the gate cannot resolve fails. There is no third answer: a call whose
# size is an expression nobody can follow is a call nobody can say is above the
# floor, and "probably fine" is how the unnamed default got in.
outline_floor='
function depth(s,   i, c, d) {
	d = 0
	for (i = 1; i <= length(s); i++) {
		c = substr(s, i, 1)
		if (c == "(") d++
		else if (c == ")") d--
	}
	return d
}
# The nth argument of the first bracket group, split at the commas that are in
# that group rather than inside something nested in it.
function arg(s, n,   i, c, d, out, part) {
	s = substr(s, index(s, "(") + 1)
	d = 0
	part = 1
	for (i = 1; i <= length(s); i++) {
		c = substr(s, i, 1)
		if (c == "(" || c == "{") d++
		else if (c == ")" || c == "}") {
			if (d == 0) break
			d--
		}
		if (c == "," && d == 0) {
			part++
			continue
		}
		if (part == n) out = out c
	}
	gsub(/^[\t ]+|[\t ]+$/, "", out)
	return out
}
# The size a call passes, in pixels, or -1 for one nothing here can follow.
function size(text,   name) {
	# A call built on the floor itself, or a max with it in, is above the floor
	# by construction and needs no number read out of it.
	if (text ~ /OutlineFloor[\t ]*\(/) return floor
	if (text ~ /^[0-9]+$/) return text + 0
	name = text
	sub(/^.*[.]/, "", name)
	if (name in METRIC) return METRIC[name]
	if (name in CONST) return CONST[name]
	return -1
}
BEGIN {
	split(metrics, pairs, ";")
	for (i in pairs) {
		c = index(pairs[i], "=")
		if (c) METRIC[substr(pairs[i], 1, c - 1)] = substr(pairs[i], c + 1) + 0
	}
}
# One pass for the file own constants, because a size is named above the call
# that passes it as often as it is written into it. A name standing on the
# floor counts as one of them: Buffs/Nag.lua reads the floor into CAPTION at the
# head of the file and passes the name, which is the same fact as passing the
# call and has to resolve the same way.
NR == FNR {
	if (match($0, /^[\t ]*local [A-Za-z_][A-Za-z0-9_]*[\t ]*=.*OutlineFloor[\t ]*[(]/)) {
		name = $0
		sub(/^[\t ]*local[\t ]*/, "", name)
		sub(/[\t ]*=.*$/, "", name)
		CONST[name] = floor
		next
	}
	if (match($0, /^[\t ]*local [A-Za-z_][A-Za-z0-9_]*[\t ]*=[\t ]*[0-9]+([\t ]|$|-)/)) {
		line = $0
		sub(/^[\t ]*local[\t ]*/, "", line)
		name = line
		sub(/[\t ]*=.*$/, "", name)
		value = line
		sub(/^[^=]*=[\t ]*/, "", value)
		sub(/[^0-9].*$/, "", value)
		CONST[name] = value + 0
	}
	next
}
FNR == 1 { pending = "" }
{
	if (pending == "") {
		if ($0 !~ /UI[.](Label|Font)[(]/) next
		start = FNR
		pending = $0
	} else {
		pending = pending " " $0
	}
	if (depth(pending) > 0) next
	if (pending ~ /UI[.]OUTLINE/) {
		# UI.Label takes the parent first and UI.Font does not.
		which = (pending ~ /UI[.]Label[(]/) ? 2 : 1
		sub(/^.*UI[.](Label|Font)/, "", pending)
		px = size(arg(pending, which))
		if (px < 0) {
			printf "%s:%d: outlined text whose size cannot be read: %s\n", FILENAME, start, arg(pending, which)
		} else if (px < floor) {
			printf "%s:%d: outlined text at %d, under the %d pixel outline floor\n", FILENAME, start, px, floor
		}
	}
	pending = ""
}
'

# The floor and the metrics the gate resolves names against, read out of the
# two files that own them rather than repeated here.
floor_px=$(sed -n 's/^local OUTLINE_FLOOR = \([0-9]*\).*/\1/p' UI/Text.lua)
metric_px=$(sed -n '/^UI.Metric = {/,/^}/s/^\t\([A-Za-z][A-Za-z0-9]*\) *= *\([0-9]*\),.*/\1=\2;/p' \
	UI/Theme.lua | tr -d '\n')
if [ -z "$floor_px" ]; then
	echo "UI/Text.lua: the outline floor is no longer a number this gate can read"
	status=1
fi

while IFS= read -r f; do
	f="${f#./}"
	# Where the floor and the three roles are defined.
	if [ "$f" = "UI/Text.lua" ]; then
		continue
	fi
	found=$(awk -v floor="${floor_px:-14}" -v metrics="$metric_px" "$outline_floor" "$f" "$f")
	if [ -n "$found" ]; then
		echo "$found"
		status=1
	fi
done < <(find . -name '*.lua' -type f | sort)

# What shape the code is in, measured per function.
#
# This replaced a per-file line ceiling and the replacement is the point. A
# line count per file says how much there is and nothing about whether it can
# be read, and the only move it rewards is cutting a file in half, which
# changes no function and no dependency. Both things it rewarded happened here
# in one afternoon: one change hit the ceiling and raised the number, another
# took a split it had not gone looking for, and neither wrote a better
# function. The gate was measuring size and calling it structure.
#
# scripts/shape.lua measures three things that survive a file being cut in
# half, because each belongs to a function rather than to a file: a function's
# own lines with nested functions taken out, how deep it nests, and how many
# branches it takes. The numbers, the allow-list and the reason for every entry
# on it are in that file, next to the code that enforces them.
if [ -f ../scripts/shape.lua ]; then
	if ! lua5.1 ../scripts/shape.lua $(find . -name '*.lua' -type f | sort); then
		status=1
	fi
else
	echo "scripts/shape.lua is missing and nothing is measuring the code's shape"
	status=1
fi

# Which tree is allowed to name which.
#
# The addon is one namespace, so nothing in the language stops a feature from
# reaching into another feature's file, and until this landed nothing else did
# either: the rule was a sentence in a comment in Core/Piles.lua and there were
# thirty-six edges crossing trees that nobody had decided on. scripts/trees.lua
# derives who owns what from the source, holds the base set the rest may name
# freely, and carries the reason for every crossing that is allowed.
if [ -f ../scripts/trees.lua ]; then
	if ! lua5.1 ../scripts/trees.lua $(find . -name '*.lua' -type f | sort); then
		status=1
	fi
else
	echo "scripts/trees.lua is missing and a feature can reach into any other"
	status=1
fi

# And which way the numbers in those gates are allowed to move.
#
# Every ceiling in shape.lua and every one further down this file is a ratchet,
# and both files enforced one direction of that. A function measuring under its
# own entry fails until the entry comes down. A function that grew past its
# entry could have the entry raised instead, and nothing said a word: the same
# failure the paragraph above describes as the reason the file ceiling was
# replaced, on the gate that replaced it.
#
# A raise is only visible against history, so this is the one rule here that
# reads git. The committed copy of each watched file against the one on disk.
# A tree with no commit yet has nothing to compare and is skipped, which is the
# only hole and it closes on the first commit.
if [ -f ../scripts/ratchet.lua ]; then
	if git rev-parse --verify HEAD >/dev/null 2>&1; then
		for watched in scripts/shape.lua scripts/trees.lua scripts/check.sh; do
			committed=$(mktemp)
			if git show "HEAD:$watched" > "$committed" 2>/dev/null; then
				lua5.1 ../scripts/ratchet.lua "$watched" "$committed" "../$watched" \
					|| status=1
			fi
			rm -f "$committed"
		done
	fi
else
	echo "scripts/ratchet.lua is missing and a ceiling can be raised by the change it blocks"
	status=1
fi

# The addon, loaded and driven under a stub of the client. Syntax and lint say
# the files parse and read cleanly; this is the only layer that says the pixel
# arithmetic lands where it should and that a tick does not allocate. It runs
# before luacheck because a stack trace is a more useful first failure than a
# style warning.
# Once per shape a character can be, because what the addon builds is decided at
# PLAYER_LOGIN off what Class/<yours>.lua registered and there is no way to flip
# that mid-run.
#
# A shape is a class and a spec now, not a class. A warrior fills in all six of
# the fields nothing else fills in, so those runs are the only ones where the
# charge button, the world marker, the reaction windows and the swing band are
# built at all. A mage and a shaman fill in two, so those runs prove the other
# four parts are absent rather than merely quiet: a hidden charge button is
# still a secure frame holding a key override, and the action targeting CVar has
# to come out with the value it went in with. A priest fills in one, and it is
# the field that opens no page: the rail entry named after you is dropped, which
# is a branch neither of the other two files reaches, because both carry a bar
# plan and a plan opens a page. A hunter has no file, which is a supported class
# and the one that proves the ten class-agnostic parts still stand up with
# nothing registered.
#
# Per spec rather than per class because a spec decides more than a class does.
# The cooldown row, the debuff row and the bar plan are all read off it, and a
# spec that overruns a cap or writes a plan out of shape fails at PLAYER_LOGIN
# as a Lua error in somebody's game. Two of the twelve are only reachable this
# way: an elemental shaman and an arcane mage carry no bar plan, so those runs
# are the ones where a class that has a plan for one spec and none for another
# has to refuse without falling over.
#
# The list is read off the files rather than written out here, because a class
# file or a spec this loop did not name got no run at all and what that hid was
# a login error rather than a wrong answer. The cap of eight entries on the
# cooldown row, six on the rotation line and four on the upkeep row is an assert
# inside Cooldowns.All and Upkeep.Fixed, and it fires on the client, at
# PLAYER_LOGIN, as a Lua error. The only thing that reaches it before a game
# does is a harness run as that spec. HUNTER stays written out because having no
# file is the whole of what it proves.
#
# Everything else in the addon is asserted again on every run, which is the
# point: a part that quietly needed a warrior fails here rather than in
# someone's game.
if [ -f ../scripts/harness.lua ]; then
	# The token the file registers, not the file's name: what the harness is
	# handed is what Class.Register was called with.
	classes=$(sed -n 's/^ns\.Class\.Register("\([A-Z_]*\)".*/\1/p' Class/*.lua | sort)
	if [ -z "$classes" ]; then
		echo "no file in Class/ calls ns.Class.Register, so no class shape is covered"
		status=1
	fi

	# One run per spec, and one run for a class that registered none. A spec
	# entry is the only line in a class file that carries a key and a label
	# together, which is what this matches on: a cooldown entry is a key and a
	# list of spell ids, and neither shape can be mistaken for the other.
	runs=""
	for class in $classes; do
		file=$(grep -lF "ns.Class.Register(\"$class\"" Class/*.lua)
		specs=$(sed -n 's/^[[:space:]]*key = "\([a-z]*\)", label = .*/\1/p' "$file")
		if [ -z "$specs" ]; then
			runs="$runs $class"
		else
			for spec in $specs; do
				runs="$runs $class:$spec"
			done
		fi
	done

	for run in $runs HUNTER; do
		if ! lua5.1 ../scripts/harness.lua . "$run"; then
			echo "harness FAIL as $run"
			status=1
		fi
		echo
	done
else
	echo "scripts/harness.lua is missing"
	status=1
fi

# The harness itself, held to the shape it was split into.
#
# It was one file of eleven thousand lines and it nearly stopped loading. Lua
# 5.1 gives one function two hundred locals, a chunk is a function, and the
# count had reached a hundred and seventy one. Nothing measured that. The file
# carried a comment asking whoever came next to scope their section in a
# `do ... end`, which is a request rather than a gate, and eleven of the thirty
# six sections had not.
#
# So the three things the split is worth are measured here rather than asked
# for. The name budget is the one that actually broke. The line limit is the
# rule the addon is already held to above. The manifest is TOC parity by
# another name, because a section file the runner does not list is a test that
# looks like it covers something and does not.
harness_status=0

# Names declared at the top of a chunk, against Lua's ceiling of 200. Both of
# these are ratchets: the general limit and every entry beside it sit at what
# is measured today, so an improvement lowers the number in the same commit and
# growth fails here instead of passing unremarked. Growth of the number itself
# fails further up, in scripts/ratchet.lua, which is the half of that sentence
# neither this file nor shape.lua could enforce on its own.
HARNESS_NAME_LIMIT=40

# path:ceiling:why it is exempt
HARNESS_NAME_ALLOWED="
sections/25-meters.lua:57:one scene held across damage, threat, the clock and both panes
"

# The same 800 the addon is held to, and the same allow-list shape.
HARNESS_LINE_LIMIT=800

# path:ceiling:why it is exempt
HARNESS_LINE_ALLOWED="
sections/29-social.lua:817:one subject, the chat window; the rooms, what routes into them, what is unread in them and what each one draws are four readings of the same scene
client/02-text.lua:776:one class, the Region stub; every line is a method of the client's own frame, and a frame API split across two files is two halves of one object
sections/05-action-bars.lua:1061:one subject, five bars; splits at the keys, the paging and the churn
sections/52-character.lua:832:one subject, the character sheet window; the gear page and the standings are files of their own, and what is left is the sheet's key, its secure drag and the miss maths the badge on it is built from, which move together
sections/55-bags.lua:806:one subject, the bag window; what it draws, what a square answers and where the window sits are one window and one bag fixture
sections/39-party-raid.lua:950:one subject, two lists, two directions each; the party line and the raid grid share a tile, a roster fixture and a header model, and splitting them copies all three
sections/42-cooldown-row.lua:734:one subject, the cooldown row; what is on it, what a square draws, when the row is up and what the tick costs are four readings of one row and every one of them moves when an entry does
sections/54-world-map.lua:809:one subject, the world map; the column, the picture, Questie's markers and the gestures over them are one window under one zone fixture, and splitting them copies the map tree, the standing position and the icon frames three ways
sections/47-quest-log.lua:823:one subject, the quest log; the fold, the shared cursor, one quest's own text and the two numbers inside its objectives are four readings of one log under one fixture, and a file of their own would carry the cursor model and the fixture twice
sections/40-loot-feed.lua:908:one subject, the loot feed; what it is dressed in, how a chip filters it, what a hover on a row says, the arithmetic of folding a repeat onto a row and why a row matters are readings of one column under one feed instance, one item fixture and one clock, and a file of their own would carry all three twice
"

harness_names='
/^local[ \t]+function[ \t]+[A-Za-z_]/ { n += 1; next }
/^local[ \t]/ {
	line = $0
	sub(/=.*/, "", line)
	sub(/^local[ \t]+/, "", line)
	gsub(/[^A-Za-z0-9_]+/, " ", line)
	count = split(line, parts, " ")
	for (i = 1; i <= count; i++) if (parts[i] != "") n += 1
}
END { print n + 0 }
'

# One measurement against one limit and one allow-list. Called twice per file
# because the two numbers are the same rule about two different things.
harness_budget() {
	local rel="$1" what="$2" measured="$3" limit="$4" allowed="$5"
	local ceiling="" why="" entry

	while IFS= read -r entry; do
		[ -n "$entry" ] || continue
		case "$entry" in
			"$rel":*)
				ceiling=$(printf '%s' "$entry" | cut -d: -f2)
				why=$(printf '%s' "$entry" | cut -d: -f3-)
				[ -n "$why" ] || {
					echo "harness/$rel is allow-listed for $what with no reason given"
					harness_status=1
				}
				;;
		esac
	done <<< "$allowed"

	if [ -n "$ceiling" ]; then
		if [ "$measured" -gt "$ceiling" ]; then
			echo "harness/$rel is $measured $what, over its own ceiling of $ceiling"
			harness_status=1
		elif [ "$measured" -lt "$ceiling" ]; then
			echo "harness/$rel is $measured $what and its ceiling still says $ceiling: lower it"
			harness_status=1
		fi
	elif [ "$measured" -gt "$limit" ]; then
		echo "harness/$rel is $measured $what, over the limit of $limit and not allow-listed"
		harness_status=1
	fi
}

while IFS= read -r f; do
	rel="${f#../scripts/harness/}"
	harness_budget "$rel" "names at chunk level" "$(awk "$harness_names" "$f")" \
		"$HARNESS_NAME_LIMIT" "$HARNESS_NAME_ALLOWED"
	harness_budget "$rel" "lines" "$(wc -l < "$f")" \
		"$HARNESS_LINE_LIMIT" "$HARNESS_LINE_ALLOWED"
done < <(find ../scripts/harness -name '*.lua' -type f | sort)

# Every section on disk is listed by the runner, and every section the runner
# lists is on disk.
listed=$(sed -n 's/^[[:space:]]*"\([0-9][0-9]-[a-z-]*\)",$/\1/p' \
	../scripts/harness/runner.lua | sort)
ondisk=$(find ../scripts/harness/sections -name '*.lua' -type f -printf '%f\n' \
	| sed 's/\.lua$//' | sort)
if [ "$listed" != "$ondisk" ]; then
	echo "the runner's section list and harness/sections disagree:"
	diff <(printf '%s\n' "$listed") <(printf '%s\n' "$ondisk") | sed 's/^/  /'
	harness_status=1
fi

[ "$harness_status" -eq 0 ] || status=1

luacheck=$(command -v luacheck || echo "$HOME/.luarocks/bin/luacheck")
if [ -x "$luacheck" ]; then
	"$luacheck" . || status=1
else
	echo "luacheck missing: luarocks install --local --lua-version 5.1 luacheck"
	status=1
fi

exit $status
