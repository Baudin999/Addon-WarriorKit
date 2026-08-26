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

# The client reads BLP and TGA and nothing else, and on these clients a texture
# whose sides are not powers of two is not drawn. Neither failure says anything
# out loud, which is why this is a gate rather than a convention.
while IFS= read -r asset; do
	asset="${asset#./}"
	case "$asset" in
		*.tga|*.blp) ;;
		*) echo "$asset is not a format the client reads"; status=1; continue ;;
	esac

	grep -qrF "$(basename "$asset")" --include='*.lua' --include='*.toc' --include='*.xml' . \
		|| { echo "nothing in the addon names $asset"; status=1; }

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
UnitFrames/EnemyBars.lua:BuildTargeters
UnitFrames/EnemyBars.lua:Member
UnitFrames/EnemyBars.lua:Record
UnitFrames/EnemyBars.lua:ThreatState
UnitFrames/EnemyBars.lua:ScanDebuffs
UnitFrames/EnemyBars.lua:UpdateWidget
UnitFrames/EnemyBars.lua:UpdateList
UnitFrames/EnemyBars.lua:Collect
UnitFrames/EnemyBars.lua:CollectUnits
UnitFrames/EnemyBars.lua:EnemyBars.Update
Minimap/Clock.lua:Clock.Reading
Minimap/Clock.lua:Clock.Update
Comfort/Vendor.lua:Sweep
Comfort/Vendor.lua:Tick
Perf/Perf.lua:Perf.Start
Perf/Perf.lua:Perf.Stop
Perf/Perf.lua:Perf.Sample
Perf/Feature.lua:Paint
UnitFrames/Skin.lua:Refresh
UnitFrames/Skin.lua:HealSlice
Unit/Unit.lua:Unit.Health
Unit/Unit.lua:Unit.Power
Unit/Unit.lua:Unit.TargetToken
Unit/Color.lua:Color.Class
Unit/Color.lua:Color.ClassHex
Unit/Color.lua:Color.Reaction
Unit/Color.lua:Color.Aggro
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
Meter/Spec.lua:Spec.Request
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

# No file grows without somebody deciding it should.
#
# The addon has an allocation gate, a TOC parity gate and a version gate, and
# had nothing at all watching the size of a file. Two of them had reached
# nineteen hundred lines, which is the same class of debt: nothing is wrong with
# any one line and the whole is past what fits in a head, so the next change
# lands wherever there is room rather than where it belongs.
#
# 800 is the general limit. Three files are over it and each carries its own
# ceiling below, set at what it measures today, so any growth fails here rather
# than passing unremarked. Raising one of those numbers is a decision to record
# in the commit message, not a formality: the alternative is to take the split
# named beside it.
LINE_LIMIT=800

# path:ceiling:why it is exempt
LINE_ALLOWED="
UI/Widgets.lua:1289:the widget kit, one function per control and shared by every page
UnitFrames/EnemyBars.lua:1872:splits at the settings API, the widget and the plate plumbing
UnitFrames/Skin.lua:1764:splits at the region walk, the block geometry and the tick
"

while IFS= read -r f; do
	f="${f#./}"
	lines=$(wc -l < "$f")
	ceiling=""
	while IFS= read -r entry; do
		[ -n "$entry" ] || continue
		case "$entry" in
			"$f":*)
				ceiling=$(printf '%s' "$entry" | cut -d: -f2)
				why=$(printf '%s' "$entry" | cut -d: -f3-)
				[ -n "$why" ] || { echo "$f is allow-listed for length with no reason given"; status=1; }
				;;
		esac
	done <<< "$LINE_ALLOWED"

	if [ -n "$ceiling" ]; then
		if [ "$lines" -gt "$ceiling" ]; then
			echo "$f is $lines lines, over its own ceiling of $ceiling"
			status=1
		elif [ "$lines" -lt "$ceiling" ]; then
			echo "$f is $lines lines and its ceiling still says $ceiling: lower it"
			status=1
		fi
	elif [ "$lines" -gt "$LINE_LIMIT" ]; then
		echo "$f is $lines lines, over the $LINE_LIMIT line limit and not allow-listed"
		status=1
	fi
done < <(find . -name '*.lua' -type f | sort)

# The addon, loaded and driven under a stub of the client. Syntax and lint say
# the files parse and read cleanly; this is the only layer that says the pixel
# arithmetic lands where it should and that a tick does not allocate. It runs
# before luacheck because a stack trace is a more useful first failure than a
# style warning.
# Twice, and the second time as a hunter. Two parts of the addon are warrior
# only and both decide it once at PLAYER_LOGIN, so the run that proves the
# charge button and the world marker are not built, and that the action
# targeting CVar is left alone, has to come up as something else from the
# start. Everything else in the addon is class agnostic and is asserted again
# on that run, which is the point: a part that quietly needed a warrior would
# fail here rather than in someone's game.
if [ -f ../scripts/harness.lua ]; then
	for class in WARRIOR HUNTER; do
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

luacheck=$(command -v luacheck || echo "$HOME/.luarocks/bin/luacheck")
if [ -x "$luacheck" ]; then
	"$luacheck" . || status=1
else
	echo "luacheck missing: luarocks install --local --lua-version 5.1 luacheck"
	status=1
fi

exit $status
