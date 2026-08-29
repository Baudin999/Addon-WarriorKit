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
	".luacheckrc"   # luacheck config, meaningless outside the repo
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
# Media/BestAround.mp3 is here for the first of those reasons and its licence
# for the second. A sound that did not travel is a level up that plays nothing
# and says nothing about why, and the file beside it is the only record in the
# zip of whose recording it is. If this addon is ever put where strangers
# download it, that pair is the thing to decide about first: the snippet is not
# ours to relicense, and taking it out is one line here and one file in Media.
for required in WarriorKit/WarriorKit.toc WarriorKit/WarriorKit_Vanilla.toc WarriorKit/Bindings.xml \
	WarriorKit/Media/Icon.tga WarriorKit/Media/Glyphs.ttf WarriorKit/Media/Glyphs-LICENSE.txt \
	WarriorKit/Media/BestAround.mp3 WarriorKit/Media/BestAround-LICENSE.txt; do
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

versions_json=$(curl -sS -f -H "X-Api-Token: $CF_API_TOKEN" "$API/game/versions") || {
	echo "could not read $API/game/versions. Is the token right?" >&2
	exit 1
}

# Resolving names to ids rather than hardcoding ids, because CurseForge issues
# a new id for every patch and a stale one is accepted as a silent mistag.
ids=$(WANTED="${wanted[*]}" python3 - <<'PY' <<<"$versions_json"
import json, os, sys
versions = json.load(sys.stdin)
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
echo "resolved to ids: $ids"

changelog_file="docs/CHANGELOG.md"
changelog="Release $version."
if [ -f "$changelog_file" ]; then changelog=$(cat "$changelog_file"); fi

metadata=$(CHANGELOG="$changelog" DISPLAY="WarriorKit $version" TYPE="$release_type" IDS="$ids" python3 - <<'PY'
import json, os
print(json.dumps({
    "changelog": os.environ["CHANGELOG"],
    "changelogType": "markdown",
    "displayName": os.environ["DISPLAY"],
    "gameVersions": json.loads(os.environ["IDS"]),
    "releaseType": os.environ["TYPE"],
}))
PY
)

response=$(curl -sS -w '\n%{http_code}' \
	-H "X-Api-Token: $CF_API_TOKEN" \
	-F "metadata=$metadata" \
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
