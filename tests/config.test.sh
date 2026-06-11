#!/usr/bin/env bash
# Tests for scripts/lib/config.sh
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export CLAUDE_PLUGIN_ROOT="$REPO_ROOT"

# shellcheck source=../scripts/lib/config.sh
source "$REPO_ROOT/scripts/lib/config.sh"

fail() { echo "FAIL: $1" >&2; exit 1; }
pass() { echo "  ok: $1"; }

# Run "default template" tests from a sandbox that has NO project-level
# .claude/sillok/workflow.config.json. Otherwise, this repo's own self-hosting
# config (gitignored, but visible to git rev-parse) would override the template
# and make these assertions read project values instead of template defaults.
TMPDIR_SANDBOX=$(mktemp -d)
trap 'rm -rf "$TMPDIR_SANDBOX"' EXIT
(
  cd "$TMPDIR_SANDBOX"
  git init -q

  echo "test: sillok_config reads scalar from default template"
  val=$(sillok_config baseBranch)
  [[ "$val" == "main" ]] || { echo "FAIL: expected main, got '$val'"; exit 1; }
  echo "  ok: baseBranch = main"

  echo "test: sillok_config returns empty for unset scalar"
  val=$(sillok_config repo)
  [[ "$val" == "" ]] || { echo "FAIL: expected empty, got '$val'"; exit 1; }
  echo "  ok: unset repo returns empty"

  echo "test: sillok_config returns nested key"
  val=$(sillok_config milestone.naming)
  [[ "$val" == "YYYY-MM-Wn" ]] || { echo "FAIL: expected YYYY-MM-Wn, got '$val'"; exit 1; }
  echo "  ok: milestone.naming = YYYY-MM-Wn"

  echo "test: sillok_config_array reads array (labels.natures from v2 template)"
  natures=()
  while IFS= read -r line; do natures+=("$line"); done < <(sillok_config_array labels.natures)
  [[ "${#natures[@]}" == "6" ]] || { echo "FAIL: expected 6 natures, got ${#natures[@]}"; exit 1; }
  [[ "${natures[0]}" == "improvement" ]] || { echo "FAIL: expected first nature 'improvement', got '${natures[0]}'"; exit 1; }
  echo "  ok: labels.natures has 6 entries starting with improvement"

  echo "test: sillok_config returns nested project.statusField"
  val=$(sillok_config project.statusField)
  [[ "$val" == "Status" ]] || { echo "FAIL: expected 'Status', got '$val'"; exit 1; }
  echo "  ok: project.statusField = Status"

  echo "test: types.defaults.composite reads as 'Story'"
  val=$(sillok_config types.defaults.composite)
  [[ "$val" == "Story" ]] || { echo "FAIL: expected 'Story', got '$val'"; exit 1; }
  echo "  ok: types.defaults.composite = Story"

  echo "test: sillok_config_required exits non-zero for empty"
  if (sillok_config_required repo 2>/dev/null); then
    echo "FAIL: expected non-zero exit for empty required key"; exit 1
  fi
  echo "  ok: sillok_config_required exits non-zero for empty 'repo'"
) || exit 1

echo "test: project override beats plugin default"
TMPDIR_PROJECT=$(mktemp -d)
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
rm -rf "$TMPDIR_PROJECT"
pass "project config overrides plugin default"

echo "test: array key absent in project config falls back to template default"
TMPDIR_ARRFALL=$(mktemp -d)
(
  cd "$TMPDIR_ARRFALL"
  git init -q
  mkdir -p .claude/sillok
  # Minimal project config — has scalars but NO labels.natures array.
  cat > .claude/sillok/workflow.config.json <<JSON
{ "version": 1, "repo": "x/y", "baseBranch": "main" }
JSON
  natures=()
  while IFS= read -r line; do natures+=("$line"); done < <(sillok_config_array labels.natures)
  [[ "${#natures[@]}" == "6" ]] || { echo "FAIL: expected 6 natures from template fallback, got ${#natures[@]}"; exit 1; }
  [[ "${natures[0]}" == "improvement" ]] || { echo "FAIL: expected 'improvement', got '${natures[0]}'"; exit 1; }
)
rm -rf "$TMPDIR_ARRFALL"
pass "missing array key in project config → template default (not empty)"

echo "test: sillok_branch_prefix_resolve substitutes {type}"
TMPDIR_RESOLVE=$(mktemp -d)
(
  cd "$TMPDIR_RESOLVE"
  git init -q
  val=$(sillok_branch_prefix_resolve feature)
  [[ "$val" == "feature/issue-" ]] || { echo "FAIL: expected 'feature/issue-', got '$val'"; exit 1; }
)
rm -rf "$TMPDIR_RESOLVE"
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
TMPDIR_REGEX=$(mktemp -d)
(
  cd "$TMPDIR_REGEX"
  git init -q
  regex=$(sillok_branch_prefix_regex)
  # v2: types.list (Title-cased) is lowercased and Epic is filtered out
  # (PRDs live in the PRD repo; no epic/* code branches). The default
  # template ships Story/Feature/Task/Bug, so the regex should contain
  # those four lowercased and NOT contain epic.
  for needle in story feature task bug; do
    [[ "$regex" == *"$needle"* ]] \
      || { echo "FAIL: expected regex to contain '$needle', got '$regex'"; exit 1; }
  done
  [[ "$regex" != *"epic"* ]] \
    || { echo "FAIL: expected Epic to be filtered out, got '$regex'"; exit 1; }
  [[ "$regex" == *"/issue-" ]] || { echo "FAIL: expected to end with /issue-, got '$regex'"; exit 1; }
)
rm -rf "$TMPDIR_REGEX"
pass "default regex contains v2 type alternation + /issue-, no epic"

echo "test: feature branch name matches generated regex"
TMPDIR_MATCH=$(mktemp -d)
(
  cd "$TMPDIR_MATCH"
  git init -q
  regex=$(sillok_branch_prefix_regex)
  test_branch="feature/issue-42-add-haptics"
  if [[ "$test_branch" =~ ^${regex}([0-9]+)-(.+)$ ]]; then
    # BASH_REMATCH[1] = "feature" (from {type} alternation)
    # BASH_REMATCH[2] = "42"
    # BASH_REMATCH[3] = "add-haptics"
    [[ "${BASH_REMATCH[2]}" == "42" ]] || { echo "FAIL: expected #42, got '${BASH_REMATCH[2]}'"; exit 1; }
    [[ "${BASH_REMATCH[3]}" == "add-haptics" ]] || { echo "FAIL: expected slug 'add-haptics', got '${BASH_REMATCH[3]}'"; exit 1; }
  else
    echo "FAIL: branch '$test_branch' did not match regex '$regex'"; exit 1
  fi
)
rm -rf "$TMPDIR_MATCH"
pass "feature/issue-42-add-haptics parsed via regex"

echo "test: story branch also matches (v2 in-repo integration branch)"
TMPDIR_STORY=$(mktemp -d)
(
  cd "$TMPDIR_STORY"
  git init -q
  regex=$(sillok_branch_prefix_regex)
  test_branch="story/issue-42-notification-system"
  if [[ "$test_branch" =~ ^${regex}([0-9]+)-(.+)$ ]]; then
    [[ "${BASH_REMATCH[2]}" == "42" ]] || { echo "FAIL: expected #42, got '${BASH_REMATCH[2]}'"; exit 1; }
  else
    echo "FAIL: branch '$test_branch' did not match regex '$regex'"; exit 1
  fi
)
rm -rf "$TMPDIR_STORY"
pass "story/issue-42-notification-system parsed via regex"

echo "test: epic branch does NOT match (v2 PRDs live in PRD repo)"
TMPDIR_NOEPIC=$(mktemp -d)
(
  cd "$TMPDIR_NOEPIC"
  git init -q
  regex=$(sillok_branch_prefix_regex)
  test_branch="epic/issue-42-notification-system"
  if [[ "$test_branch" =~ ^${regex}([0-9]+)-(.+)$ ]]; then
    echo "FAIL: epic/* branch should NOT match v2 regex, but did: '$regex'"; exit 1
  fi
)
rm -rf "$TMPDIR_NOEPIC"
pass "epic/* branches correctly excluded from v2 regex"

echo "test: project.statuses.backlog falls back to template default"
TMPDIR_BACKLOG=$(mktemp -d)
(
  cd "$TMPDIR_BACKLOG"
  git init -q
  mkdir -p .claude/sillok
  # Old consumer config: has statuses but NO backlog key (pre-#33 config).
  cat > .claude/sillok/workflow.config.json <<JSON
{ "version": 1, "repo": "x/y",
  "project": { "statuses": { "todo": "Todo", "done": "Done" } } }
JSON
  val=$(sillok_config project.statuses.backlog)
  [[ "$val" == "Backlog" ]] || { echo "FAIL: expected 'Backlog' via template fallback, got '$val'"; exit 1; }
)
rm -rf "$TMPDIR_BACKLOG"
pass "missing backlog key in project config → template default 'Backlog'"

echo
echo "All config.sh tests passed."
