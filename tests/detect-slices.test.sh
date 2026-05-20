#!/usr/bin/env bash
# Tests for scripts/detect-slices.sh
#
# All fixtures use synthetic domain names (auth/billing/dashboard/…) — never
# pull real names from any private codebase. The script's correctness against
# real codebases is validated locally during development, not in CI.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$REPO_ROOT/scripts/detect-slices.sh"

fail() { echo "FAIL: $1" >&2; exit 1; }
pass() { echo "  ok: $1"; }

# Helper to scaffold a fixture project under $1 with directories from $2..$N.
make_fixture() {
  local root="$1"; shift
  mkdir -p "$root"
  for path in "$@"; do
    mkdir -p "$root/$path"
  done
}

# Fixture 1: FSD-layout with three real domains, one generic-name folder, one underscore-prefixed.
TMP1=$(mktemp -d)
trap 'rm -rf "$TMP1" "$TMP2" "$TMP3" "$TMP4" "$TMP5"' EXIT
make_fixture "$TMP1" \
  src/entities/auth src/entities/billing src/entities/dashboard \
  src/features/auth src/features/billing \
  src/widgets/dashboard \
  src/pages/auth src/pages/billing \
  src/entities/utils src/features/components \
  src/entities/_internal

echo "test: FSD layout — auth appears in 3 families (entities, features, pages)"
out=$(bash "$SCRIPT" "$TMP1")
auth_rank=$(echo "$out" | awk -F'\t' '$1=="auth"{print $2}')
[[ "$auth_rank" == "3" ]] || fail "expected auth rank 3, got '$auth_rank'; full:\n$out"
pass "auth rank = 3"

echo "test: generic-name 'utils' is filtered"
echo "$out" | awk -F'\t' '{print $1}' | grep -qx utils && fail "utils should be filtered; full:\n$out"
pass "utils not in output"

echo "test: generic-name 'components' is filtered"
echo "$out" | awk -F'\t' '{print $1}' | grep -qx components && fail "components should be filtered"
pass "components not in output"

echo "test: underscore-prefixed names are skipped"
echo "$out" | awk -F'\t' '{print $1}' | grep -qx _internal && fail "_internal should be skipped"
pass "_internal not in output"

# Fixture 2: monorepo layout, packages + apps.
TMP2=$(mktemp -d)
make_fixture "$TMP2" \
  packages/auth packages/api-client packages/ui-kit \
  apps/web apps/admin

echo "test: monorepo packages and apps both scanned, names from each appear"
out=$(bash "$SCRIPT" "$TMP2")
echo "$out" | awk -F'\t' '{print $1}' | grep -qx auth || fail "expected auth in monorepo output"
echo "$out" | awk -F'\t' '{print $1}' | grep -qx web || fail "expected web in monorepo output"
pass "auth and web both detected"

# Fixture 3: empty project.
TMP3=$(mktemp -d)
echo "test: empty project produces empty output"
out=$(bash "$SCRIPT" "$TMP3")
[[ -z "$out" ]] || fail "expected empty output, got: $out"
pass "empty output for empty project"

# Fixture 4: only generic-name dirs.
TMP4=$(mktemp -d)
make_fixture "$TMP4" \
  src/entities/components src/entities/utils src/entities/types \
  src/features/hooks src/features/helpers

echo "test: project with only generic-name dirs produces empty output"
out=$(bash "$SCRIPT" "$TMP4")
[[ -z "$out" ]] || fail "expected empty output, got: $out"
pass "empty output when all candidates are generic"

# Fixture 5: route-group brackets are skipped.
TMP5=$(mktemp -d)
make_fixture "$TMP5" \
  "app/(auth-group)" "app/[id]" "app/profile"

echo "test: route-group bracketed names are skipped"
out=$(bash "$SCRIPT" "$TMP5")
echo "$out" | awk -F'\t' '{print $1}' | grep -q '(' && fail "bracketed names should be filtered"
echo "$out" | awk -F'\t' '{print $1}' | grep -qx profile || fail "expected profile through"
pass "brackets filtered; plain names pass"

echo "test: hard cap at 100 results"
TMP_BIG=$(mktemp -d)
# Use single-family with 150 distinct names → only single-family rank-1.
for i in $(seq 1 150); do
  mkdir -p "$TMP_BIG/packages/dom-$i"
done
out=$(bash "$SCRIPT" "$TMP_BIG")
n=$(echo "$out" | wc -l | tr -d ' ')
[[ "$n" -le 100 ]] || fail "expected ≤100 lines, got $n"
rm -rf "$TMP_BIG"
pass "result count capped at 100"

echo "test: missing arg exits non-zero"
if bash "$SCRIPT" 2>/dev/null; then
  fail "expected non-zero exit with no args"
fi
pass "no-arg invocation exits non-zero"

echo "test: missing project root exits non-zero"
if bash "$SCRIPT" /this/path/does/not/exist 2>/dev/null; then
  fail "expected non-zero exit for missing root"
fi
pass "missing root exits non-zero"

echo
echo "All detect-slices.sh tests passed."
