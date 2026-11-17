#!/usr/bin/env bash
# Tests scripts/curseforge-upload.sh with stubbed curl and gh: bash tests/test_upload.sh
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$ROOT/scripts/curseforge-upload.sh"
passed=0 failed=0

VERSIONS='[{"id":111,"gameVersionTypeID":67408,"name":"1.15.8"},{"id":333,"gameVersionTypeID":88568,"name":"1.60.0"},{"id":222,"gameVersionTypeID":88568,"name":"1.60.1"}]'

# A scratch checkout: TOC, zip, and stub curl/gh that log their arguments.
setup() {
    work="$(mktemp -d)"
    mkdir -p "$work/CorpseCamp" "$work/dist" "$work/bin"
    printf '## Interface: 16001\n## Version: 0.2.1\n## X-Curse-Project-ID: 4242\n' > "$work/CorpseCamp/CorpseCamp.toc"
    echo zip > "$work/dist/CorpseCamp-0.2.1.zip"
    cat > "$work/bin/curl" <<'EOF'
#!/usr/bin/env bash
{ echo "---CALL---"; printf '%s\n' "$@"; } >> "$STUB_LOG"
out=""
for ((i = 1; i <= $#; i++)); do [ "${!i}" = "-o" ] && { j=$((i + 1)); out="${!j}"; }; done
case "$*" in
  *game/wow/versions*) [ "${FAKE_VERSIONS_EXIT:-0}" = 0 ] || exit "$FAKE_VERSIONS_EXIT"; printf '%s' "$FAKE_VERSIONS" ;;
  *upload-file*) [ "${FAKE_UPLOAD_EXIT:-0}" = 0 ] || exit "$FAKE_UPLOAD_EXIT"
                 printf '%s' "$FAKE_BODY" > "$out"; printf '%s' "$FAKE_STATUS" ;;
esac
EOF
    printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$*" >> "$GH_LOG"\n[ "${FAKE_GH_EXIT:-0}" = 0 ] || exit "$FAKE_GH_EXIT"\nprintf "%%s" "$FAKE_CHANGELOG"\n' > "$work/bin/gh"
    chmod +x "$work/bin/curl" "$work/bin/gh"
    export STUB_LOG="$work/curl.log" GH_LOG="$work/gh.log" FAKE_VERSIONS="$VERSIONS" FAKE_STATUS=200 FAKE_BODY='{"id":9001}'
    export FAKE_CHANGELOG='- fixed; type=evil @/etc/passwd' CF_API_TOKEN=secret-token
    unset FAKE_VERSIONS_EXIT FAKE_UPLOAD_EXIT FAKE_GH_EXIT
    : > "$STUB_LOG"
}

run() { (cd "$work" && PATH="$work/bin:$PATH" bash "$SCRIPT" "$@") > "$work/out" 2>&1; }

check() {
    local name="$1"; shift
    if "$@"; then passed=$((passed + 1)); else failed=$((failed + 1)); echo "FAIL $name"; cat "$work/out"; fi
    rm -rf "$work"
}

uploaded() { grep -q 'upload-file' "$STUB_LOG"; }
# Arguments of one curl call, picked by a URL pattern (the log holds one block per call).
call_matching() { awk -v pat="$1" '/^---CALL---$/ { n++ } { block[n] = block[n] $0 "\n" } END { for (i = 1; i <= n; i++) if (block[i] ~ pat) printf "%s", block[i] }' "$STUB_LOG"; }
upload_call() { call_matching 'upload-file'; }
versions_call() { call_matching 'game/wow/versions'; }
no_token_in_output() { ! grep -q 'secret-token' "$work/out"; }

case_success() {
    run v0.2.1 || return 1
    grep -q 'file 9001' "$work/out" || return 1
    grep -q 'https://wow.curseforge.com/api/projects/4242/upload-file' "$STUB_LOG" || return 1
    versions_call | grep -qx 'x-api-token: secret-token' || return 1
    upload_call | grep -qx 'x-api-token: secret-token' || return 1
    grep -qx 'release view v0.2.1 --json body --jq .body' "$GH_LOG" || return 1
    local meta; meta="$(grep '^metadata=' "$STUB_LOG" | sed 's/^metadata=//')"
    [ "$(jq -c '.gameVersions' <<<"$meta")" = "[222]" ] || return 1
    [ "$(jq -r '.displayName' <<<"$meta")" = "CorpseCamp 0.2.1" ] || return 1
    [ "$(jq -r '.changelog' <<<"$meta")" = "$FAKE_CHANGELOG" ] || return 1
    # The metadata goes through --form-string, so ';type=' and '@' in it stay literal.
    grep -B1 '^metadata=' "$STUB_LOG" | head -1 | grep -qx -- '--form-string' || return 1
    upload_call | grep -qx 'file=@dist/CorpseCamp-0.2.1.zip' || return 1
    ! upload_call | grep -qx -- '--retry' || return 1
    no_token_in_output
}
setup; check "uploads the zip with the Forever version id and release notes" case_success

case_tag_mismatch() { ! run v0.2.0 && grep -q 'does not match' "$work/out" && ! uploaded; }
setup; check "refuses a tag that doesn't match the TOC version" case_tag_mismatch

case_bad_tag() { ! run 'v1; rm -rf /' && grep -q 'usage' "$work/out" && [ ! -s "$STUB_LOG" ]; }
setup; check "refuses a malformed tag before any request" case_bad_tag

case_no_token() { unset CF_API_TOKEN; ! run v0.2.1 && grep -q 'CF_API_TOKEN' "$work/out" && [ ! -s "$STUB_LOG" ]; }
setup; check "refuses to run without a token" case_no_token

case_no_project() {
    sed -i.bak '/X-Curse-Project-ID/d' "$work/CorpseCamp/CorpseCamp.toc"
    ! run v0.2.1 && grep -q 'X-Curse-Project-ID' "$work/out" && [ ! -s "$STUB_LOG" ]
}
setup; check "refuses a TOC without a project id" case_no_project

case_no_version() {
    export FAKE_VERSIONS='[{"id":111,"gameVersionTypeID":67408,"name":"1.60.1"}]'
    ! run v0.2.1 && grep -q 'no single CurseForge game version' "$work/out" && ! uploaded
}
setup; check "refuses when Forever has no matching game version" case_no_version

case_wrong_patch_only() {
    export FAKE_VERSIONS='[{"id":333,"gameVersionTypeID":88568,"name":"1.60.0"}]'
    ! run v0.2.1 && grep -q 'no single CurseForge game version' "$work/out" && ! uploaded
}
setup; check "refuses a Forever version of another patch" case_wrong_patch_only

case_ambiguous_version() {
    export FAKE_VERSIONS='[{"id":1,"gameVersionTypeID":88568,"name":"1.60.1"},{"id":2,"gameVersionTypeID":88568,"name":"1.60.1"}]'
    ! run v0.2.1 && grep -q 'no single CurseForge game version' "$work/out" && ! uploaded
}
setup; check "refuses an ambiguous game version" case_ambiguous_version

case_http_error() {
    export FAKE_STATUS=403 FAKE_BODY='{"errorMessage":"bad token"}'
    ! run v0.2.1 && grep -q 'HTTP 403' "$work/out" && grep -q 'bad token' "$work/out" && no_token_in_output
}
setup; check "fails loudly on a non-200 upload response" case_http_error

case_no_zip() { rm "$work/dist/CorpseCamp-0.2.1.zip"; ! run v0.2.1 && grep -q 'not found' "$work/out" && [ ! -s "$STUB_LOG" ]; }
setup; check "refuses when the zip wasn't built" case_no_zip

case_versions_down() { export FAKE_VERSIONS_EXIT=22; ! run v0.2.1 && grep -q 'could not list' "$work/out" && ! uploaded; }
setup; check "fails when the game version list can't be fetched" case_versions_down

case_no_release() { export FAKE_GH_EXIT=1; ! run v0.2.1 && grep -q 'could not read the v0.2.1 release notes' "$work/out" && ! uploaded; }
setup; check "fails when the GitHub release can't be read" case_no_release

case_upload_network() { export FAKE_UPLOAD_EXIT=28; ! run v0.2.1 && grep -q 'upload request failed' "$work/out" && no_token_in_output; }
setup; check "fails when the upload request itself fails" case_upload_network

case_not_forever() {
    sed -i.bak 's/## Interface: 16001/## Interface: 11508/' "$work/CorpseCamp/CorpseCamp.toc"
    ! run v0.2.1 && grep -q 'not a Forever' "$work/out" && [ ! -s "$STUB_LOG" ]
}
setup; check "refuses a non-Forever interface" case_not_forever

echo "$passed passed, $failed failed"
[ "$failed" -eq 0 ]
