#!/usr/bin/env bash
# Tests for scripts/lib/config.sh
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export CLAUDE_PLUGIN_ROOT="$REPO_ROOT"

# shellcheck source=../scripts/lib/config.sh
source "$REPO_ROOT/scripts/lib/config.sh"

fail() { echo "FAIL: $1" >&2; exit 1; }
pass() { echo "  ok: $1"; }

echo "test: sillok_config reads scalar from default template"
val=$(sillok_config baseBranch)
[[ "$val" == "main" ]] || fail "expected main, got '$val'"
pass "baseBranch = main"

echo "test: sillok_config returns empty for unset scalar"
val=$(sillok_config repo)
[[ "$val" == "" ]] || fail "expected empty, got '$val'"
pass "unset repo returns empty"

echo "test: sillok_config returns nested key"
val=$(sillok_config milestone.naming)
[[ "$val" == "YYYY-MM-Wn" ]] || fail "expected YYYY-MM-Wn, got '$val'"
pass "milestone.naming = YYYY-MM-Wn"

echo "test: sillok_config_array reads array"
types=()
while IFS= read -r line; do types+=("$line"); done < <(sillok_config_array labels.types)
[[ "${#types[@]}" == "5" ]] || fail "expected 5 types, got ${#types[@]}"
[[ "${types[0]}" == "feature" ]] || fail "expected feature, got '${types[0]}'"
pass "labels.types has 5 entries starting with feature"

echo "test: sillok_config_required exits non-zero for empty"
if (sillok_config_required repo 2>/dev/null); then
  fail "expected non-zero exit for empty required key"
fi
pass "sillok_config_required exits non-zero for empty 'repo'"

echo "test: project override beats plugin default"
TMPDIR_PROJECT=$(mktemp -d)
trap 'rm -rf "$TMPDIR_PROJECT"' EXIT
(
  cd "$TMPDIR_PROJECT"
  git init -q
  mkdir -p .claude/sillok
  cat > .claude/sillok/workflow.config.json <<JSON
{ "version": 1, "repo": "judeProground/sillok", "baseBranch": "develop" }
JSON
  val=$(sillok_config baseBranch)
  [[ "$val" == "develop" ]] || { echo "FAIL: expected develop, got '$val'"; exit 1; }
  val=$(sillok_config repo)
  [[ "$val" == "judeProground/sillok" ]] || { echo "FAIL: expected judeProground/sillok, got '$val'"; exit 1; }
)
pass "project config overrides plugin default"

echo
echo "All config.sh tests passed."
