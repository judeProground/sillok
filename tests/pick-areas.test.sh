#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$REPO_ROOT/scripts/pick-areas.sh"

fail() { echo "FAIL: $1" >&2; exit 1; }
pass() { echo "  ok: $1"; }

echo "test: keeps rank>=2 names, drops rank-1 noise"
input=$'auth\t4\nbilling\t3\ndashboard\t2\nfoo\t1\nbar\t1\n'
out=$(printf '%s' "$input" | bash "$SCRIPT")
expected=$'auth\nbilling\ndashboard'
[[ "$out" == "$expected" ]] || fail "expected '$expected', got '$out'"
pass "rank-1 entries filtered"

echo "test: hard-cap at 15 even with 150 rank-4 entries"
big_input=""
for i in $(seq 1 150); do big_input="${big_input}name-${i}	4
"; done
out=$(printf '%s' "$big_input" | bash "$SCRIPT")
n=$(echo "$out" | wc -l | tr -d ' ')
[[ "$n" == "15" ]] || fail "expected 15 lines, got $n"
pass "150 rank-4 → exactly 15 output lines"

echo "test: empty stdin → empty output (exit 0)"
out=$(printf '' | bash "$SCRIPT")
[[ -z "$out" ]] || fail "expected empty, got '$out'"
pass "empty input → empty output"

echo "test: all rank-1 input → empty output"
input=$'foo\t1\nbar\t1\nbaz\t1\n'
out=$(printf '%s' "$input" | bash "$SCRIPT")
[[ -z "$out" ]] || fail "expected empty, got '$out'"
pass "all rank-1 → empty (none-confident case)"

echo "test: preserves input ordering (does not sort)"
input=$'zebra\t4\nalpha\t3\nmango\t2\n'
out=$(printf '%s' "$input" | bash "$SCRIPT")
expected=$'zebra\nalpha\nmango'
[[ "$out" == "$expected" ]] || fail "expected '$expected', got '$out'"
pass "ordering preserved from input (detect-slices already sorts)"

echo
echo "All pick-areas.sh tests passed."
