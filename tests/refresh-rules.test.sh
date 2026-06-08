#!/usr/bin/env bash
# Tests for scripts/refresh-rules.sh
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$REPO_ROOT/scripts/refresh-rules.sh"

fail() { echo "FAIL: $1" >&2; exit 1; }
pass() { echo "  ok: $1"; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

mkdir -p "$TMP/src"
echo "rule one v1" > "$TMP/src/one.md"
echo "rule two v1" > "$TMP/src/two.md"
echo "rule three v1" > "$TMP/src/three.md"

echo "test: empty dest — all files copied and summarized"
mkdir -p "$TMP/destA"
out=$(bash "$SCRIPT" "$TMP/destA" "$TMP/src")
[[ -f "$TMP/destA/one.md" && -f "$TMP/destA/two.md" && -f "$TMP/destA/three.md" ]] || fail "A: not all copied"
echo "$out" | grep -q "one.md" || fail "A: one.md missing from summary"
echo "$out" | grep -q "three.md" || fail "A: three.md missing from summary"
pass "empty dest"

echo "test: identical dest — no-op, empty summary"
out=$(bash "$SCRIPT" "$TMP/destA" "$TMP/src")
[[ -z "$out" ]] || fail "B: expected empty summary, got '$out'"
pass "identical dest"

echo "test: differing dest — only changed file refreshed + overwritten"
echo "rule two EDITED" > "$TMP/destA/two.md"
out=$(bash "$SCRIPT" "$TMP/destA" "$TMP/src")
echo "$out" | grep -q "two.md" || fail "C: two.md should refresh"
echo "$out" | grep -q "one.md" && fail "C: one.md should NOT refresh"
[[ "$(cat "$TMP/destA/two.md")" == "rule two v1" ]] || fail "C: two.md not overwritten"
pass "differing dest"

echo "test: mixed — only missing + differing refreshed"
mkdir -p "$TMP/destD"
echo "rule one v1" > "$TMP/destD/one.md"
echo "rule two OLD" > "$TMP/destD/two.md"
out=$(bash "$SCRIPT" "$TMP/destD" "$TMP/src")
echo "$out" | grep -q "two.md" || fail "D: two.md (differing) should refresh"
echo "$out" | grep -q "three.md" || fail "D: three.md (missing) should refresh"
echo "$out" | grep -q "one.md" && fail "D: one.md (identical) should not refresh"
pass "mixed dest"

echo "test: empty src dir — no-op, no error"
mkdir -p "$TMP/srcE" "$TMP/destE"
out=$(bash "$SCRIPT" "$TMP/destE" "$TMP/srcE")
[[ -z "$out" ]] || fail "E: expected empty on empty src"
pass "empty src"

echo "test: dest dir auto-created"
bash "$SCRIPT" "$TMP/destF/rules" "$TMP/src" >/dev/null
[[ -d "$TMP/destF/rules" ]] || fail "F: dest dir not created"
pass "dest dir auto-created"

echo "test: missing arg — non-zero exit"
if bash "$SCRIPT" "$TMP/destA" 2>/dev/null; then
  fail "G: expected non-zero exit with one arg"
fi
pass "arg guard"

echo
echo "All refresh-rules.sh tests passed."
