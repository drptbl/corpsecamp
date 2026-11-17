#!/usr/bin/env bash
# Uploads dist/CorpseCamp-<version>.zip (built by `make dist`) to CurseForge.
#
#   CF_API_TOKEN=... scripts/curseforge-upload.sh v0.2.0
#
# The project ID, version and interface come from CorpseCamp/CorpseCamp.toc. The
# changelog is the GitHub release's body (read with `gh`). The game version is the
# TOC interface mapped the way BigWigsMods/packager maps it: 16001 -> "1.60.1" on
# CurseForge's Forever version type (88568).
set -euo pipefail

API="https://wow.curseforge.com/api"
TOC="CorpseCamp/CorpseCamp.toc"
FOREVER_TYPE_ID=88568

die() { echo "curseforge-upload: $*" >&2; exit 1; }

tag="${1:-}"
[[ "$tag" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "usage: $0 vX.Y.Z (got '$tag')"
[ -n "${CF_API_TOKEN:-}" ] || die "CF_API_TOKEN is not set"

field() { awk -v key="## $1:" 'index($0, key) == 1 { sub(key, ""); gsub(/^[ \t]+|[ \t\r]+$/, ""); print; exit }' "$TOC"; }
project_id="$(field X-Curse-Project-ID)"
version="$(field Version)"
interface="$(field Interface)"

[[ "$project_id" =~ ^[0-9]+$ ]] || die "no numeric X-Curse-Project-ID in $TOC"
[ "v$version" = "$tag" ] || die "tag $tag does not match $TOC version $version"
[[ "$interface" =~ ^16[0-9]{3}$ ]] || die "interface '$interface' is not a Forever (16xxx) interface"
game_version="$((interface / 10000)).$((interface / 100 % 100)).$((interface % 100))"

zip="dist/CorpseCamp-$version.zip"
[ -f "$zip" ] || die "$zip not found (run make dist)"

response="$(mktemp)"
trap 'rm -f "$response"' EXIT

# Prints CurseForge's error message for a failed call. Its auth errors echo the
# token back ("Token provided: ..."), so that part and the token itself are redacted.
fail_with_response() {
    local message
    message="$(jq -r '.errorMessage // empty' "$response" 2>/dev/null || true)"
    [ -n "$message" ] || message="$(head -c 300 "$response")"
    message="${message//"$CF_API_TOKEN"/<REDACTED>}"
    printf 'curseforge-upload: %s failed with HTTP %s: %s\n' "$1" "$2" \
        "$(printf '%s' "$message" | sed -E 's/(Token provided:).*/\1 <REDACTED>/')" >&2
    exit 1
}

status="$(curl -sS --retry 3 --max-time 30 -o "$response" -w '%{http_code}' \
    -H "x-api-token: $CF_API_TOKEN" "$API/game/wow/versions")" || die "could not list CurseForge game versions"
[ "$status" = "200" ] || fail_with_response "listing game versions" "$status"
versions="$(cat "$response")"
version_id="$(jq -r --argjson t "$FOREVER_TYPE_ID" --arg v "$game_version" \
    '[.[] | select(.gameVersionTypeID == $t and .name == $v) | .id] | if length == 1 then .[0] else empty end' \
    <<<"$versions")"
[ -n "$version_id" ] || die "no single CurseForge game version '$game_version' of type $FOREVER_TYPE_ID"

changelog="$(gh release view "$tag" --json body --jq .body)" || die "could not read the $tag release notes"
metadata="$(jq -cn --arg changelog "$changelog" --arg name "CorpseCamp $version" --argjson gv "$version_id" \
    '{changelog: $changelog, changelogType: "markdown", displayName: $name, gameVersions: [$gv], releaseType: "release"}')"

# No --retry here: a retried POST could upload the file twice.
status="$(curl -sS --max-time 300 -o "$response" -w '%{http_code}' \
    -H "x-api-token: $CF_API_TOKEN" \
    --form-string "metadata=$metadata" \
    -F "file=@$zip" \
    "$API/projects/$project_id/upload-file")" || die "upload request failed"

[ "$status" = "200" ] || fail_with_response "upload" "$status"
echo "uploaded $zip to CurseForge project $project_id as game version $game_version (file $(jq -r '.id' "$response"))"
