#!/usr/bin/env bash
# Tests for scripts/migrate-config.sh
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$REPO_ROOT/scripts/migrate-config.sh"

fail() { echo "FAIL: $1" >&2; exit 1; }
pass() { echo "  ok: $1"; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/template.json" <<'JSON'
{
  "version": 1,
  "repo": "",
  "baseBranch": "main",
  "orgMode": false,
  "language": "auto",
  "verify": { "lint": "", "typecheck": "", "format": "" },
  "labels": { "areas": ["tmpl-a", "tmpl-b"], "priorities": ["p1", "p2", "p3", "p4"] }
}
JSON

echo "test: minimal config — defaults added, user values preserved"
cat > "$TMP/c1.json" <<'JSON'
{ "repo": "me/proj", "baseBranch": "develop" }
JSON
out=$(bash "$SCRIPT" "$TMP/c1.json" "$TMP/template.json")
[[ "$(jq -r '.repo' "$TMP/c1.json")" == "me/proj" ]] || fail "c1: repo not preserved"
[[ "$(jq -r '.baseBranch' "$TMP/c1.json")" == "develop" ]] || fail "c1: baseBranch not preserved"
[[ "$(jq -r '.language' "$TMP/c1.json")" == "auto" ]] || fail "c1: language not added"
[[ "$(jq -r '.orgMode' "$TMP/c1.json")" == "false" ]] || fail "c1: orgMode not added"
echo "$out" | grep -q "added" || fail "c1: summary missing 'added'"
pass "minimal config merged"

echo "test: array preserved verbatim (not unioned)"
cat > "$TMP/c2.json" <<'JSON'
{ "repo": "x/y", "baseBranch": "main", "labels": { "areas": ["alerts", "backtest"] } }
JSON
bash "$SCRIPT" "$TMP/c2.json" "$TMP/template.json" >/dev/null
got=$(jq -c '.labels.areas' "$TMP/c2.json")
[[ "$got" == '["alerts","backtest"]' ]] || fail "c2: areas should be verbatim, got $got"
pass "array verbatim"

echo "test: nested merge — existing subkey preserved, missing subkey added"
cat > "$TMP/c3.json" <<'JSON'
{ "repo": "x/y", "baseBranch": "main", "verify": { "lint": "pnpm lint" } }
JSON
bash "$SCRIPT" "$TMP/c3.json" "$TMP/template.json" >/dev/null
[[ "$(jq -r '.verify.lint' "$TMP/c3.json")" == "pnpm lint" ]] || fail "c3: verify.lint not preserved"
[[ "$(jq -r '.verify.format' "$TMP/c3.json")" == "" ]] || fail "c3: verify.format not added"
[[ "$(jq -r '.verify.typecheck' "$TMP/c3.json")" == "" ]] || fail "c3: verify.typecheck not added"
pass "nested merge"

echo "test: all keys present — no-op, file byte-identical, empty stdout"
cp "$TMP/template.json" "$TMP/c4.json"
before=$(cat "$TMP/c4.json")
out=$(bash "$SCRIPT" "$TMP/c4.json" "$TMP/template.json")
[[ -z "$out" ]] || fail "c4: expected empty summary, got '$out'"
[[ "$(cat "$TMP/c4.json")" == "$before" ]] || fail "c4: file changed on no-op"
pass "no-op leaves file untouched"

echo "test: version preserved (user value wins)"
cat > "$TMP/c5.json" <<'JSON'
{ "repo": "x/y", "baseBranch": "main", "version": 1 }
JSON
cat > "$TMP/template2.json" <<'JSON'
{ "version": 2, "repo": "", "baseBranch": "main" }
JSON
bash "$SCRIPT" "$TMP/c5.json" "$TMP/template2.json" >/dev/null
[[ "$(jq -r '.version' "$TMP/c5.json")" == "1" ]] || fail "c5: version should stay 1"
pass "version preserved"

echo "test: invalid JSON — non-zero exit, file unchanged"
printf '{ broken json' > "$TMP/c6.json"
before=$(cat "$TMP/c6.json")
if bash "$SCRIPT" "$TMP/c6.json" "$TMP/template.json" 2>/dev/null; then
  fail "c6: expected non-zero exit on invalid JSON"
fi
[[ "$(cat "$TMP/c6.json")" == "$before" ]] || fail "c6: file changed despite invalid JSON"
pass "invalid JSON guarded"

echo "test: missing project file — non-zero exit"
if bash "$SCRIPT" "$TMP/nope.json" "$TMP/template.json" 2>/dev/null; then
  fail "c7: expected non-zero exit for missing project file"
fi
pass "missing project file guarded"

echo "test: missing arg — non-zero exit"
if bash "$SCRIPT" 2>/dev/null; then
  fail "c8: expected non-zero exit with no args"
fi
pass "no-arg guarded"

echo "test: legacy keys migrated — prdRepo->epicRepo, prdDir/epicDir dropped, types.defaults.prd->.epic"
cat > "$TMP/c9.json" <<'JSON'
{ "repo": "x/y", "baseBranch": "main", "prdRepo": "org/projects", "prdDir": "prd", "types": { "defaults": { "prd": "Epic" } } }
JSON
bash "$SCRIPT" "$TMP/c9.json" "$TMP/template.json" >/dev/null
[[ "$(jq -r '.epicRepo' "$TMP/c9.json")" == "org/projects" ]] || fail "c9: prdRepo not renamed to epicRepo"
[[ "$(jq 'has("epicDir")' "$TMP/c9.json")" == "false" ]] || fail "c9: obsolete epicDir must not be created"
[[ "$(jq -r '.types.defaults.epic' "$TMP/c9.json")" == "Epic" ]] || fail "c9: types.defaults.prd not renamed to .epic"
[[ "$(jq 'has("prdRepo")' "$TMP/c9.json")" == "false" ]] || fail "c9: old prdRepo still present"
[[ "$(jq 'has("prdDir")' "$TMP/c9.json")" == "false" ]] || fail "c9: old prdDir still present"
[[ "$(jq -r '.types.defaults | has("prd")' "$TMP/c9.json")" == "false" ]] || fail "c9: old types.defaults.prd still present"
pass "legacy keys renamed to epic*"

echo "test: legacy rename is idempotent / does not clobber an existing epicRepo"
cat > "$TMP/c10.json" <<'JSON'
{ "repo": "x/y", "baseBranch": "main", "prdRepo": "old/one", "epicRepo": "new/two" }
JSON
bash "$SCRIPT" "$TMP/c10.json" "$TMP/template.json" >/dev/null
[[ "$(jq -r '.epicRepo' "$TMP/c10.json")" == "new/two" ]] || fail "c10: existing epicRepo clobbered by legacy prdRepo"
[[ "$(jq 'has("prdRepo")' "$TMP/c10.json")" == "false" ]] || fail "c10: stale prdRepo not removed"
pass "rename never clobbers existing new key"

echo
echo "All migrate-config.sh tests passed."
