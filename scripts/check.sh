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

# Three kinds of file live in Media/ and each has its own rule.
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
# A licence is that file, and it is allowed here only because a font it belongs
# to is here too.
#
# Everything is named by something in the addon, licences apart, because an
# asset nothing names is weight in every download and nobody notices it.
while IFS= read -r asset; do
	asset="${asset#./}"
	named=1
	case "$asset" in
		*.tga|*.blp) kind=texture ;;
		*.ttf) kind=font ;;
		*-LICENSE.txt)
			kind=licence
			named=0
			[ -f "${asset%-LICENSE.txt}.ttf" ] \
				|| { echo "$asset is a licence for a font that is not here"; status=1; }
			;;
		*) echo "$asset is not a format the client reads"; status=1; continue ;;
	esac

	if [ "$named" -eq 1 ]; then
		grep -qrF "$(basename "$asset")" --include='*.lua' --include='*.toc' --include='*.xml' . \
			|| { echo "nothing in the addon names $asset"; status=1; }
	fi

	if [ "$kind" = "font" ]; then
		[ -f "${asset%.ttf}-LICENSE.txt" ] \
			|| { echo "$asset ships with no ${asset%.ttf}-LICENSE.txt beside it"; status=1; }
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
UI/Ability.lua:Quantum
Buttons/Bars.lua:Bars.Update
Buttons/Trace.lua:Trace.Sample
Buttons/Reaction.lua:Reaction.Of
Buttons/Reaction.lua:Reaction.Open
Buttons/Reaction.lua:Reaction.Name
Buttons/Reaction.lua:KeyForSpell
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
UnitFrames/EnemyBars.lua:UpdateWidget
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
Feeds/Purse.lua:Purse.Coin
Feeds/Purse.lua:Others
Feeds/Purse.lua:Purse.Mine
Feeds/Purse.lua:Who
Feeds/Purse.lua:Purse.Note
Feeds/Purse.lua:Purse.Start
Feeds/Purse.lua:Money
Feeds/Purse.lua:Group
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
Swing/Gauges.lua:Whole
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
# Once per shape a class can be, because what the addon builds is decided at
# PLAYER_LOGIN off what Class/<yours>.lua registered and there is no way to flip
# that mid-run.
#
# There are four shapes and one class each proves. A warrior fills in all six
# fields, so that run is the only one where the charge button, the world marker,
# the reaction windows and the swing band are built at all. A mage and a shaman
# fill in two, so those runs prove the other four parts are absent rather than
# merely quiet: a hidden charge button is still a secure frame holding a key
# override, and the action targeting CVar has to come out with the value it went
# in with. A priest fills in one, and it is the field that opens no page: the
# rail entry named after you is dropped, which is a branch neither of the other
# two files reaches, because both carry a bar plan and a plan opens a page. A
# hunter has no file, which is a supported class and the one that proves the ten
# class-agnostic parts still stand up with nothing registered.
#
# Everything else in the addon is asserted again on every run, which is the
# point: a part that quietly needed a warrior fails here rather than in
# someone's game.
if [ -f ../scripts/harness.lua ]; then
	for class in WARRIOR MAGE SHAMAN PRIEST HUNTER; do
		if ! lua5.1 ../scripts/harness.lua . "$class"; then
			echo "harness FAIL as $class"
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
sections/25-meters.lua:58:one scene held across damage, threat, the clock and both panes
"

# The same 800 the addon is held to, and the same allow-list shape.
HARNESS_LINE_LIMIT=800

# path:ceiling:why it is exempt
HARNESS_LINE_ALLOWED="
sections/05-action-bars.lua:1053:one subject, five bars; splits at the keys, the paging and the churn
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
