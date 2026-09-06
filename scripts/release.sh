#!/usr/bin/env bash
# Builds the addon zip CurseForge expects, and uploads it when asked.
#
#   ./scripts/release.sh                 build dist/WarriorKit-<version>.zip
#   ./scripts/release.sh --upload        build, then upload it
#   ./scripts/release.sh --upload --type beta
#
# Upload needs two things in the environment:
#
#   CF_API_TOKEN   from https://legacy.curseforge.com/account/api-tokens
#   CF_PROJECT_ID  the numeric id on the project page
#
# NOT YET RUN AGAINST A LIVE PROJECT. The endpoints, the header name and the
# metadata shape below come from the upload API documentation, not from a
# publish that succeeded. The build half is exercised every time; the upload
# half is inference until the first real release proves it. Same convention as
# the API notes in docs/README.md.
set -euo pipefail
cd "$(dirname "$0")/.."

API="https://wow.curseforge.com/api"

# Dev files that live in src/ and must not reach a player. Everything else in
# src/ ships, so a new feature folder is included without touching this list,
# which is the right default because check.sh already fails if a Lua file is
# missing from either TOC. Each entry needs a reason.
IGNORE=(
	".luacheckrc"                    # luacheck config, meaningless outside the repo
	"Media/BestAround.mp3"           # somebody else's recording, not ours to distribute
	"Media/BestAround-LICENSE.txt"   # the licence for it, pointless once it is gone
)

upload=0
release_type="release"
while [ $# -gt 0 ]; do
	case "$1" in
		--upload) upload=1 ;;
		--type) shift; release_type="${1:-}" ;;
		*) echo "unknown argument: $1" >&2; exit 2 ;;
	esac
	shift
done

case "$release_type" in
	alpha|beta|release) ;;
	*) echo "--type must be alpha, beta or release, not '$release_type'" >&2; exit 2 ;;
esac

# Nothing gets built from a tree that does not pass. A release is the one
# moment where shipping a warning is permanent.
echo "== gate =="
./scripts/check.sh || { echo "check.sh failed, nothing built" >&2; exit 1; }

# check.sh has already proved every TOC agrees with this, so one read is enough.
version=$(sed -n 's/^ns\.version = "\(.*\)"$/\1/p' src/Core/Core.lua)
[ -n "$version" ] || { echo "no ns.version in src/Core/Core.lua" >&2; exit 1; }

echo
echo "== build =="
stage=$(mktemp -d)
trap 'rm -rf "$stage"' EXIT

# The zip's top level entry must be a folder named exactly as the TOC, because
# that folder name is what the client matches WarriorKit.toc against. src/ is
# a repo layout choice and the player never sees it.
mkdir "$stage/WarriorKit"
cp -R src/. "$stage/WarriorKit/"
for name in "${IGNORE[@]}"; do
	rm -rf "$stage/WarriorKit/${name:?}"
done
# The licence travels with the copy, which is the whole point of MIT's
# "included in all copies" clause, and CurseForge shows a licence per project.
for extra in README.md LICENSE; do
	if [ -f "$extra" ]; then cp "$extra" "$stage/WarriorKit/$extra"; fi
done

mkdir -p dist
zip_path="dist/WarriorKit-$version.zip"
rm -f "$zip_path"
( cd "$stage" && zip -qr - WarriorKit ) > "$zip_path"

# Listed once into a variable rather than piped per check. `unzip -l | grep -q`
# races: grep exits on the first match, unzip takes SIGPIPE, and pipefail turns
# a passing check into a failing one depending on where the match landed.
listing=$(unzip -l "$zip_path")

# A zip that is missing a TOC installs as a folder the client ignores, and the
# symptom is an addon that simply never appears in the list. Media/Glyphs.ttf is
# here because a font that did not travel takes the chevrons back to the letter
# v and says nothing about it, and its licence is here because the OFL says the
# licence goes wherever the font goes.
#
# Media/BestAround.mp3 went the other way and is in IGNORE. It is five seconds
# of a record somebody else made, this addon is downloaded by strangers, and a
# snippet that is not ours to relicense is not ours to put in a zip either. It
# is still in src/ on the machine that built this, because src/ is what the
# author's client loads, which is exactly why it is on the list rather than
# left to a deletion somebody has to remember: the copy step takes all of src/.
for required in WarriorKit/WarriorKit.toc WarriorKit/WarriorKit_Vanilla.toc WarriorKit/Bindings.xml \
	WarriorKit/Media/Icon.tga WarriorKit/Media/Glyphs.ttf WarriorKit/Media/Glyphs-LICENSE.txt; do
	if ! grep -qF "$required" <<<"$listing"; then
		echo "the zip is missing $required" >&2
		exit 1
	fi
done
for name in "${IGNORE[@]}"; do
	if grep -qF "WarriorKit/$name" <<<"$listing"; then
		echo "the zip contains $name, which IGNORE says it must not" >&2
		exit 1
	fi
done

echo "$zip_path  ($(du -h "$zip_path" | cut -f1), $(tail -1 <<<"$listing" | awk '{print $2}') files)"

[ "$upload" -eq 1 ] || {
	echo
	echo "built only. Add --upload to publish it."
	exit 0
}

echo
echo "== upload =="
: "${CF_API_TOKEN:?set CF_API_TOKEN, from legacy.curseforge.com/account/api-tokens}"
: "${CF_PROJECT_ID:?set CF_PROJECT_ID, the numeric id on the project page}"

# 20506 is 2.5.6 and 11509 is 1.15.9. The last two digits are the patch, the
# two before that the minor, whatever is left the major, which is why this
# also handles the six digit retail numbers.
iface_to_name() {
	local n="$1"
	printf '%d.%d.%d\n' \
		"$((10#${n:0:${#n}-4}))" "$((10#${n: -4:2}))" "$((10#${n: -2}))"
}

wanted=()
for toc in src/WarriorKit*.toc; do
	iface=$(sed -n 's/^## Interface: //p' "$toc" | tr -d '[:space:]')
	wanted+=("$(iface_to_name "$iface")")
done
echo "game versions from the TOCs: ${wanted[*]}"

# Into a file, not a variable. Everything that crosses into python below goes
# by path for the same reason: the kernel caps one argument or one environment
# string at 128 KiB, docs/CHANGELOG.md passed that a long time ago, and the
# failure is execve returning E2BIG, which bash reports as "Argument list too
# long" against python rather than against the string that was too long.
versions_file=$(mktemp)
# The build's trap is replaced rather than added to, because bash keeps one
# handler per signal and a second `trap ... EXIT` silently drops the first. So
# $stage is named here too, or the staging directory outlives every upload.
trap 'rm -rf "$stage"; rm -f "$versions_file" "${meta_file:-}"' EXIT
curl -sS -f -H "X-Api-Token: $CF_API_TOKEN" "$API/game/versions" > "$versions_file" || {
	echo "could not read $API/game/versions. Is the token right?" >&2
	exit 1
}

# Resolving names to ids rather than hardcoding ids, because CurseForge issues
# a new id for every patch and a stale one is accepted as a silent mistag.
#
# The versions file is argv, not stdin. It used to be a here-string alongside
# the script's own heredoc, and a command can only have one stdin: the last
# redirection won, python read the version list as its own source, and a JSON
# array of objects happens to be a valid python expression. So it evaluated the
# list, printed nothing and exited 0. An empty $ids sailed past `|| exit 1` and
# died four steps later somewhere else.
ids=$(WANTED="${wanted[*]}" python3 - "$versions_file" <<'PY'
import json, os, sys
versions = json.load(open(sys.argv[1]))
wanted = os.environ["WANTED"].split()
by_name = {}
for v in versions:
    by_name.setdefault(v["name"], v["id"])
missing = [w for w in wanted if w not in by_name]
if missing:
    sys.stderr.write("CurseForge does not list: %s\n" % ", ".join(missing))
    sys.stderr.write("It does list: %s\n" % ", ".join(sorted(by_name)[-30:]))
    sys.exit(1)
print(json.dumps([by_name[w] for w in wanted]))
PY
) || exit 1

# The check that was missing when the redirection bug made $ids empty. An
# empty tag list is an upload against no game version at all, which the client
# never offers to anybody.
[ -n "$ids" ] || { echo "resolved no game version ids at all" >&2; exit 1; }
echo "resolved to ids: $ids"

changelog_file="docs/CHANGELOG.md"
[ -f "$changelog_file" ] || changelog_file=""

# The other addons this one talks to, declared to CurseForge so that the
# project page lists them and an addon manager offers to fetch them alongside
# this one. That offer is the whole of "install Questie with WarriorKit". The
# client has no package manager and an addon cannot install another addon, so
# the manager is the only thing in the chain that can.
#
# optionalDependency, not requiredDependency. Every feature that asks Questie
# a question says in words when it is not answering, and a required dependency
# would push Questie on a player who wants the character sheet and the meters
# and nothing to do with quests. src/WarriorKit*.toc carries the same name in
# ## OptionalDeps and check.sh fails if the two ever disagree.
#
# Slug, not id, because a slug is the last part of the project URL and stays
# put. legacy.curseforge.com/wow/addons/questie is Questie's.
relations=$(python3 - <<'REL'
import json
print(json.dumps({"projects": [{"slug": "questie", "type": "optionalDependency"}]}))
REL
)

# The changelog goes in by path and the finished metadata comes out by path,
# because it carries the changelog inside it. docs/CHANGELOG.md is 428 KB and
# every entry the addon has ever had is in it, so it is over the 128 KiB
# per-string execve limit three times over in either direction. Neither the
# environment nor argv can hold it.
meta_file=$(mktemp)
CHANGELOG_FILE="$changelog_file" VERSION="$version" DISPLAY="WarriorKit $version" \
	TYPE="$release_type" IDS="$ids" RELATIONS="$relations" \
	python3 - "$meta_file" <<'META'
import json, os, sys
path = os.environ["CHANGELOG_FILE"]
changelog = open(path, encoding="utf-8").read() if path else "Release %s." % os.environ["VERSION"]
json.dump({
    "changelog": changelog,
    "changelogType": "markdown",
    "displayName": os.environ["DISPLAY"],
    "gameVersions": json.loads(os.environ["IDS"]),
    "releaseType": os.environ["TYPE"],
    "relations": json.loads(os.environ["RELATIONS"]),
}, open(sys.argv[1], "w", encoding="utf-8"))
META

response=$(curl -sS -w '\n%{http_code}' \
	-H "X-Api-Token: $CF_API_TOKEN" \
	-F "metadata=<$meta_file" \
	-F "file=@$zip_path" \
	"$API/projects/$CF_PROJECT_ID/upload-file")

code=$(tail -n1 <<<"$response")
body=$(sed '$d' <<<"$response")

if [ "$code" != "200" ]; then
	echo "upload failed, HTTP $code" >&2
	echo "$body" >&2
	exit 1
fi
echo "$body"
echo "uploaded WarriorKit $version as $release_type"
