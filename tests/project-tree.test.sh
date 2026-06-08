#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$REPO_ROOT/scripts/project-tree.sh"

fail() { echo "FAIL: $1" >&2; exit 1; }
pass() { echo "  ok: $1"; }

# --- temp project: features at multiple depths + junk dirs ---
PROJ=$(mktemp -d)
trap 'rm -rf "$PROJ"' EXIT
mkdir -p "$PROJ/src/service/abuse"
mkdir -p "$PROJ/src/service/wallet"
mkdir -p "$PROJ/src/service/v2/raffle"
mkdir -p "$PROJ/src/service/v2/super-draw"
mkdir -p "$PROJ/src/a/b/c/deep-feature"   # 5 levels deep (no depth cap)
mkdir -p "$PROJ/node_modules/lodash"
mkdir -p "$PROJ/dist/assets"
mkdir -p "$PROJ/.git/refs"
mkdir -p "$PROJ/coverage"

out=$(bash "$SCRIPT" "$PROJ")

echo "test: junk dirs and dot-dirs are pruned"
for j in node_modules lodash dist coverage; do
  if printf '%s\n' "$out" | grep -qw "$j"; then fail "$j not pruned"; fi
done
if printf '%s\n' "$out" | grep -q '\.git'; then fail ".git not pruned"; fi
pass "junk pruned"

echo "test: features present at multiple depths (no depth assumption)"
printf '%s\n' "$out" | grep -qx "src" || fail "src (depth 0) missing"
printf '%s\n' "$out" | grep -qx "  service" || fail "service (depth 1, 2sp) missing/wrong indent"
printf '%s\n' "$out" | grep -qx "    abuse" || fail "abuse (depth 2, 4sp) missing/wrong indent"
printf '%s\n' "$out" | grep -qx "      raffle" || fail "v2/raffle (depth 3, 6sp) missing — nesting the old scanner dropped"
printf '%s\n' "$out" | grep -qx "        deep-feature" || fail "depth-5 feature missing — there must be NO depth cap"
pass "multi-depth features present"

echo "test: normal project does NOT trigger the line-cap marker"
if printf '%s\n' "$out" | grep -q "truncated"; then fail "normal project should not truncate"; fi
pass "no spurious truncation"

echo "test: line-cap backstop truncates with a marker"
BIG=$(mktemp -d)
i=0; while [[ $i -lt 600 ]]; do mkdir -p "$BIG/d$i"; i=$((i+1)); done
bigout=$(bash "$SCRIPT" "$BIG")
if ! printf '%s\n' "$bigout" | grep -q "truncated"; then fail "600 dirs: expected truncation marker"; fi
lines=$(printf '%s\n' "$bigout" | wc -l | tr -d ' ')
[[ "$lines" -le 501 ]] || fail "expected <=501 lines (500 + marker), got $lines"
rm -rf "$BIG"
pass "line-cap backstop fires with marker"

echo "test: empty project → empty output, exit 0"
EMPTY=$(mktemp -d)
eout=$(bash "$SCRIPT" "$EMPTY")
[[ -z "$eout" ]] || fail "empty project: expected empty output, got '$eout'"
rm -rf "$EMPTY"
pass "empty project → empty output"

echo "test: junk-only project → empty output"
JUNK=$(mktemp -d); mkdir -p "$JUNK/node_modules/x" "$JUNK/.git/y"
jout=$(bash "$SCRIPT" "$JUNK")
[[ -z "$jout" ]] || fail "junk-only project: expected empty, got '$jout'"
rm -rf "$JUNK"
pass "junk-only project → empty output"

echo
echo "All project-tree.sh tests passed."
