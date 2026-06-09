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
mkdir -p "$PROJ/src/a/b/c/deep-feature"   # depth 4 (4 slashes → 8-space indent), no depth cap
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

echo "test: unreadable subdir → readable dirs still emitted, exit 0 (regression)"
PERM=$(mktemp -d)
mkdir -p "$PERM/src/visible" "$PERM/src/locked"
chmod 000 "$PERM/src/locked"
set +e
permout=$(bash "$SCRIPT" "$PERM"); permrc=$?
set -e
chmod 755 "$PERM/src/locked"   # restore so cleanup can remove it
rm -rf "$PERM"
[[ "$permrc" -eq 0 ]] || fail "unreadable subdir: expected exit 0, got $permrc"
printf '%s\n' "$permout" | grep -qx "  visible" || fail "unreadable subdir: readable sibling 'visible' missing from output"
pass "resilient to unreadable subdir"

echo "test: trailing-slash root arg → correct depth-0 basename (regression)"
tsout=$(bash "$SCRIPT" "$PROJ/")
printf '%s\n' "$tsout" | grep -qx "src" || fail "trailing-slash root: 'src' should be depth-0 (no indent), got: $(printf '%s\n' "$tsout" | grep -n src)"
pass "trailing-slash root normalized"

echo "test: built-in language/platform junk pruned (python venv, RN android/ios, target, Pods)"
HARD=$(mktemp -d)
mkdir -p "$HARD/src/billing"
mkdir -p "$HARD/__pycache__/x" "$HARD/venv/lib" "$HARD/target/debug" \
         "$HARD/Pods/Foo" "$HARD/android/app" "$HARD/ios/build"
hardout=$(bash "$SCRIPT" "$HARD")
for j in __pycache__ venv target Pods android ios; do
  if printf '%s\n' "$hardout" | grep -qw "$j"; then fail "built-in junk '$j' not pruned"; fi
done
printf '%s\n' "$hardout" | grep -qx "  billing" || fail "real feature 'billing' missing"
rm -rf "$HARD"
pass "built-in language/platform junk pruned, real feature kept"

echo "test: .gitignore-based pruning in a git repo (custom ignored dir dropped, feature kept)"
if command -v git >/dev/null 2>&1; then
  GREPO=$(mktemp -d)
  git -C "$GREPO" init -q
  printf 'generated/\n' > "$GREPO/.gitignore"
  mkdir -p "$GREPO/src/payments" "$GREPO/generated/code"
  grepout=$(bash "$SCRIPT" "$GREPO")
  if printf '%s\n' "$grepout" | grep -qw "generated"; then fail ".gitignore: 'generated' should be pruned via git check-ignore"; fi
  printf '%s\n' "$grepout" | grep -qx "  payments" || fail ".gitignore: real feature 'payments' missing"
  rm -rf "$GREPO"
  pass ".gitignore-based pruning works (non-hardcoded ignored dir dropped)"
else
  echo "  (git not available — skipping .gitignore pruning test)"
fi

echo
echo "All project-tree.sh tests passed."
