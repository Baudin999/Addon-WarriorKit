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
# To exempt one line, put `-- unguarded: <reason>` or `-- allocates: <reason>`
# on it. A reason is required, because an exemption without one is the same
# invisible debt as a warning.
HOT="
Core/Core.lua:ns.OutOfRange
UI/Ability.lua:Ability.Look
UI/Ability.lua:Ability.Draw
UI/Ability.lua:Countdown
UI/Ability.lua:Quantum
Buttons/Bars.lua:Bars.Update
Buttons/Trace.lua:Trace.Sample
Buttons/Reaction.lua:Reaction.Of
Buttons/Reaction.lua:Reaction.OfSpell
Buttons/Reaction.lua:Reaction.Open
Buttons/Reaction.lua:Reaction.Name
Buttons/Reaction.lua:KeyForSpell
Buttons/Requires.lua:Requires.State
Buttons/Requires.lua:EntryFor
Buttons/Requires.lua:NameOf
Buttons/Requires.lua:Unmet
Core/Core.lua:ns.SpellNameHeld
Buttons/Slot.lua:Slot.Spell
Buttons/Slot.lua:Beyond
Buttons/Slot.lua:Refused
Buttons/Slot.lua:Slot.CanName
Buttons/Slot.lua:Slot.CanRead
Buttons/Slot.lua:Slot.State
Buttons/Slot.lua:Slot.Active
Buttons/Slot.lua:Slot.Equipped
Buttons/Slot.lua:Slot.Texture
Buttons/Slot.lua:Slot.Count
Charge/Charge.lua:Charge.Pick
Charge/Charge.lua:Charge.State
Charge/Charge.lua:Charge.PlateFor
Charge/Icon.lua:ChargeIcon.SyncMacro
Charge/Icon.lua:ChargeIcon.Update
Charge/Marker.lua:AttachTo
Charge/Marker.lua:ChargeMarker.Update
UI/Gauge.lua:Gauge.Flatten
UI/Gauge.lua:Gauge.Paint
UI/Aura.lua:Aura.Draw
UnitFrames/EnemyBars.lua:BuildTargeters
UnitFrames/EnemyBars.lua:Member
UnitFrames/EnemyBars.lua:Record
UnitFrames/EnemyBars.lua:ThreatState
UnitFrames/EnemyBars.lua:ScanDebuffs
UnitFrames/EnemyBars.lua:DrawDebuffs
UnitFrames/EnemyBars.lua:PaintAlpha
UnitFrames/EnemyBars.lua:PaintQuest
UnitFrames/EnemyBars.lua:UpdateWidget
Quests/Drops.lua:Drops.Badge
UnitFrames/EnemyBars.lua:StartFade
UnitFrames/EnemyBars.lua:Fades
UnitFrames/EnemyBars.lua:UpdateList
UnitFrames/EnemyBars.lua:EnemyBars.Sweep
UnitFrames/Cast.lua:Cast.Seconds
UnitFrames/Cast.lua:Cast.Preview
UnitFrames/Cast.lua:Cast.Live
UnitFrames/Cast.lua:Cast.Fraction
UnitFrames/Cast.lua:Show
UnitFrames/Cast.lua:Chamber
UnitFrames/Cast.lua:Cast.Update
UnitFrames/Cast.lua:Cast.Sweep
UnitFrames/PlayerCast.lua:Look
UnitFrames/PlayerCast.lua:Spell
UnitFrames/PlayerCast.lua:Note
UnitFrames/PlayerCast.lua:Draw
UnitFrames/PlayerCast.lua:PlayerCast.Clear
UnitFrames/PlayerCast.lua:PlayerCast.Update
UnitFrames/PlayerCast.lua:PlayerCast.Sweep
UnitFrames/EnemyBars.lua:Collect
UnitFrames/EnemyBars.lua:CollectUnits
UnitFrames/EnemyBars.lua:EnemyBars.Update
Minimap/Clock.lua:Clock.Reading
Minimap/Clock.lua:Clock.Update
Comfort/Vendor.lua:Sweep
Comfort/Vendor.lua:Tick
Feeds/Stream.lua:Refresh
Feeds/Purse.lua:Purse.Line
Feeds/Purse.lua:Purse.Account
Feeds/Purse.lua:Purse.Rate
Core/Core.lua:ns.Coin
Core/Core.lua:ns.Coined
Core/Core.lua:Spell
Core/Core.lua:Parts
Core/Core.lua:Push
Core/Core.lua:Plain
Core/Core.lua:Painted
Core/Core.lua:Thousands
Feeds/Purse.lua:Others
Feeds/Purse.lua:Purse.Mine
Feeds/Purse.lua:Who
Feeds/Purse.lua:Purse.Note
Feeds/Purse.lua:Purse.Start
Feeds/Purse.lua:Money
Feeds/Purse.lua:RateText
Feeds/Purse.lua:Tone
Perf/Perf.lua:Perf.Start
Perf/Perf.lua:Perf.Stop
Perf/Perf.lua:Perf.Sample
Perf/Feature.lua:Paint
UnitFrames/Auras.lua:AuraAt
UnitFrames/Auras.lua:Scan
UnitFrames/Auras.lua:Sweep
UnitFrames/Auras.lua:Hang
UnitFrames/Auras.lua:Fill
UnitFrames/Auras.lua:Auras.Update
UnitFrames/Paint.lua:Paint.Refresh
UnitFrames/Paint.lua:HealSlice
UnitFrames/Skin.lua:Tick
UnitFrames/Group.lua:Group.Update
UnitFrames/Member.lua:Member.Update
UnitFrames/Member.lua:Member.Clear
UnitFrames/Member.lua:Member.Shade
UnitFrames/Member.lua:Member.Paint
UnitFrames/Member.lua:Member.Divider
UnitFrames/Member.lua:Member.Numbers
UnitFrames/Member.lua:Member.Label
Unit/Unit.lua:Unit.Health
Unit/Unit.lua:Unit.Power
Unit/Unit.lua:Unit.TargetToken
Unit/Color.lua:Color.Class
Unit/Color.lua:Color.ClassHex
Unit/Color.lua:Color.Reaction
Unit/Color.lua:Color.Frame
Unit/Color.lua:Color.OfUnit
Unit/Color.lua:Color.Dim
Unit/Level.lua:Level.Tag
Unit/Level.lua:Level.WorthOf
Unit/Level.lua:Level.Worth
Unit/Level.lua:Level.Of
Unit/Roster.lua:Roster.Units
Unit/Threat.lua:Threat.On
Unit/Threat.lua:Threat.Top
Unit/Threat.lua:Threat.Shade
Unit/Threat.lua:Threat.State
Unit/Threat.lua:Threat.Swinging
Meter/Meter.lua:Meter.Rank
Meter/Meter.lua:Meter.Total
Unit/Spec.lua:Spec.Request
Meter/Threat.lua:Sample
Meter/Threat.lua:ThreatMeter.Update
Meter/Threat.lua:ThreatMeter.Rank
Meter/Threat.lua:ThreatMeter.Soonest
Meter/Window.lua:Short
Meter/Window.lua:Blank
Meter/Window.lua:PaintRow
Meter/Window.lua:PaintBar
Meter/Window.lua:SetLeft
Meter/Window.lua:SetRight
Meter/Window.lua:PaintDamage
Meter/Window.lua:PaintThreat
Meter/Window.lua:MeterWindow.Update
Swing/Swing.lua:Swing.Speed
Swing/Swing.lua:Swing.Duration
Swing/Swing.lua:Swing.Armed
Swing/Swing.lua:Swing.Fraction
Swing/Slam.lua:Slam.Name
Swing/Slam.lua:Slam.Estimate
Swing/Slam.lua:Slam.Cast
Swing/Slam.lua:Slam.Known
Swing/Slam.lua:Slam.Window
UI/Pixel.lua:UI.Whole
Swing/Gauges.lua:DrawHand
Swing/Gauges.lua:DrawWindow
Swing/Gauges.lua:SwingGauges.Update
Buffs/Upkeep.lua:Upkeep.EnchantShape
Buffs/Upkeep.lua:Upkeep.Enchants
Buffs/Upkeep.lua:Upkeep.Bare
Buffs/Upkeep.lua:Upkeep.Missing
Buffs/Racials.lua:Racials.Mine
Buffs/Racials.lua:Racials.Spell
Buffs/Racials.lua:Racials.Name
Buffs/Racials.lua:Racials.Worth
Buffs/Racials.lua:Racials.Ready
Buffs/Racials.lua:Racials.Idle
Buffs/Nag.lua:Nag.Resting
Buffs/Nag.lua:Nag.Dead
Buffs/Nag.lua:Nag.MissingMask
Buffs/Nag.lua:Pulse
Buffs/Nag.lua:Paint
Buffs/Nag.lua:Nag.Update
Cooldowns/Cooldowns.lua:Cooldowns.State
Cooldowns/Cooldowns.lua:Cooldowns.Busy
Cooldowns/Row.lua:Row.Wanted
Cooldowns/Row.lua:Paint
Cooldowns/Row.lua:Row.Update
Core/Attic.lua:Attic.Take
Core/Attic.lua:Attic.Vanish
Core/Attic.lua:Attic.Sweep
UnitFrames/Blizzard.lua:Walk
UnitFrames/Blizzard.lua:Blizz.Apply
Chat/Blizzard.lua:Blizz.Apply
UnitFrames/Blizzard.lua:MoveKey
World/World.lua:World.Sweep
UI/Tooltip.lua:Tooltip.Sweep
UI/Chart.lua:Track
UI/Chart.lua:Aim
UI/Chart.lua:Chart.Spot
UI/Chart.lua:Chart.Here
UI/Chart.lua:Chart.Facing
UI/Placeable.lua:Follow
UI/Placeable.lua:Push
"

hot_scan='
BEGIN { inside = 0 }
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

	writes = (body ~ /:Set[A-Z][A-Za-z]*\(/)
	allocates = (body ~ /\{/ || body ~ /function[ ]*\(/)
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

hot_files=""
while IFS=: read -r file fn; do
	[ -n "$file" ] || continue
	[ -f "$file" ] || { echo "HOT names a missing file: $file"; status=1; continue; }
	if ! grep -qE "^(local )?function ${fn//./\\.} *\(" "$file"; then
		echo "HOT names a missing function: $file:$fn"
		status=1
		continue
	fi
	case "$hot_files" in *"|$file|"*) ;; *) hot_files="$hot_files|$file|" ;; esac
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
# The addon draws its own tooltip: a flat box, the theme's palette, Arial
# Narrow, one physical pixel of edge. GameTooltip is a tiled parchment with a
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
# should have been all along. UnitFrames/Blizzard.lua, Buffs/Upkeep.lua and the
# class files carry `hint` fields on their own tables that feed one of those or
# feed a body line, so the rule reads assignments at the indentation a table
# constructor puts them at rather than any mention of the word.
while IFS= read -r bad; do
	echo "the tooltip's blue hint line is gone, and a subject may not carry one: $bad"
	status=1
done < <(grep -rnE '^[[:space:]]+hint = ' --include='*.lua' . 	| grep -v '^\./UI/Widgets\.lua:' 	| grep -v '^\./UnitFrames/Blizzard\.lua:' 	| grep -v '^\./Buffs/Upkeep\.lua:' 	| grep -v '^\./Class/' || true)

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

# A ticker in a file HOT says nothing about is a ticker nothing above checked.
while IFS= read -r f; do
	f="${f#./}"
	case "$hot_files" in
		*"|$f|"*) ;;
		*) echo "$f registers an OnUpdate and names no function in HOT"; status=1 ;;
	esac
done < <(grep -lE 'SetScript\("OnUpdate"' --include='*.lua' -r . | sort)

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
# growth fails here instead of passing unremarked.
HARNESS_NAME_LIMIT=40

# path:ceiling:why it is exempt
HARNESS_NAME_ALLOWED="
sections/25-meters.lua:57:one scene held across damage, threat, the clock and both panes
"

# The same 800 the addon is held to, and the same allow-list shape.
HARNESS_LINE_LIMIT=800

# path:ceiling:why it is exempt
HARNESS_LINE_ALLOWED="
sections/05-action-bars.lua:1061:one subject, five bars; splits at the keys, the paging and the churn
sections/39-party-raid.lua:833:one subject, two shapes; the party and the raid are one header and one block
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
