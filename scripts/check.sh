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

for field in Version Title Notes; do
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
Charge/Charge.lua:Charge.Pick
Charge/Charge.lua:Charge.State
Charge/Charge.lua:Charge.PlateFor
Charge/Icon.lua:ChargeIcon.SyncMacro
Charge/Icon.lua:ChargeIcon.Update
Charge/Icon.lua:Fade
Charge/Marker.lua:AttachTo
Charge/Marker.lua:ChargeMarker.Update
UnitFrames/EnemyBars.lua:BuildTargeters
UnitFrames/EnemyBars.lua:Record
UnitFrames/EnemyBars.lua:ThreatState
UnitFrames/EnemyBars.lua:TargetState
UnitFrames/EnemyBars.lua:Difficulty
UnitFrames/EnemyBars.lua:Reaction
UnitFrames/EnemyBars.lua:ScanDebuffs
UnitFrames/EnemyBars.lua:UpdateWidget
UnitFrames/EnemyBars.lua:UpdateList
UnitFrames/EnemyBars.lua:Collect
UnitFrames/EnemyBars.lua:CollectUnits
UnitFrames/EnemyBars.lua:EnemyBars.Update
Perf/Perf.lua:Perf.Start
Perf/Perf.lua:Perf.Stop
Perf/Perf.lua:Perf.Sample
Perf/Feature.lua:Paint
UnitFrames/Skin.lua:Refresh
UnitFrames/Skin.lua:HealSlice
UnitFrames/Skin.lua:Tint
UnitFrames/Skin.lua:ClassTint
UnitFrames/Skin.lua:LevelTag
UnitFrames/Skin.lua:Flatten
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

# The addon, loaded and driven under a stub of the client. Syntax and lint say
# the files parse and read cleanly; this is the only layer that says the pixel
# arithmetic lands where it should and that a tick does not allocate. It runs
# before luacheck because a stack trace is a more useful first failure than a
# style warning.
if [ -f ../scripts/harness.lua ]; then
	if ! lua5.1 ../scripts/harness.lua .; then
		echo "harness FAIL"
		status=1
	fi
	echo
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
