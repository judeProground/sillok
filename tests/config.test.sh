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

echo "test: sillok_branch_prefix_resolve substitutes {type}"
val=$(sillok_branch_prefix_resolve feature)
[[ "$val" == "feature/issue-" ]] || fail "expected 'feature/issue-', got '$val'"
pass "{type}/issue- + feature → feature/issue-"

echo "test: sillok_branch_prefix_resolve handles {user}"
TMPDIR_USERCFG=$(mktemp -d)
(
  cd "$TMPDIR_USERCFG"
  git init -q
  mkdir -p .claude/sillok
  cat > .claude/sillok/workflow.config.json <<JSON
{ "version": 1, "repo": "x/y", "baseBranch": "main", "branchPrefix": "{user}/{type}-" }
JSON
  val=$(sillok_branch_prefix_resolve feature jude)
  [[ "$val" == "jude/feature-" ]] || { echo "FAIL: expected 'jude/feature-', got '$val'"; exit 1; }
)
rm -rf "$TMPDIR_USERCFG"
pass "{user}/{type}- + (feature, jude) → jude/feature-"

echo "test: sillok_branch_prefix_resolve handles literal-only template"
TMPDIR_LITERAL=$(mktemp -d)
(
  cd "$TMPDIR_LITERAL"
  git init -q
  mkdir -p .claude/sillok
  cat > .claude/sillok/workflow.config.json <<JSON
{ "version": 1, "repo": "x/y", "baseBranch": "main", "branchPrefix": "feat/" }
JSON
  val=$(sillok_branch_prefix_resolve feature anyone)
  [[ "$val" == "feat/" ]] || { echo "FAIL: expected 'feat/', got '$val'"; exit 1; }
)
rm -rf "$TMPDIR_LITERAL"
pass "literal 'feat/' ignores placeholders"

echo "test: sillok_branch_prefix_regex matches any sillok type"
regex=$(sillok_branch_prefix_regex)
[[ "$regex" == *"(feature|bug|improvement|infra|epic)"* ]] \
  || fail "expected (feature|bug|...) alternation, got '$regex'"
[[ "$regex" == *"/issue-" ]] || fail "expected to end with /issue-, got '$regex'"
pass "default regex contains type alternation + /issue-"

echo "test: feature branch name matches generated regex"
regex=$(sillok_branch_prefix_regex)
test_branch="feature/issue-42-add-haptics"
if [[ "$test_branch" =~ ^${regex}([0-9]+)-(.+)$ ]]; then
  # BASH_REMATCH[1] = "feature" (from {type} alternation)
  # BASH_REMATCH[2] = "42"
  # BASH_REMATCH[3] = "add-haptics"
  [[ "${BASH_REMATCH[2]}" == "42" ]] || fail "expected #42, got '${BASH_REMATCH[2]}'"
  [[ "${BASH_REMATCH[3]}" == "add-haptics" ]] || fail "expected slug 'add-haptics', got '${BASH_REMATCH[3]}'"
  pass "$test_branch parsed via regex"
else
  fail "branch '$test_branch' did not match regex '$regex'"
fi

echo "test: epic branch also matches"
regex=$(sillok_branch_prefix_regex)
test_branch="epic/issue-42-notification-system"
if [[ "$test_branch" =~ ^${regex}([0-9]+)-(.+)$ ]]; then
  [[ "${BASH_REMATCH[2]}" == "42" ]] || fail "expected #42, got '${BASH_REMATCH[2]}'"
  pass "$test_branch parsed via regex (epic case)"
else
  fail "branch '$test_branch' did not match regex '$regex'"
fi

echo
echo "All config.sh tests passed."
