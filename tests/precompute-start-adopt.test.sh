#!/usr/bin/env bash
# Tests for scripts/precompute-start.sh adopt mode (#33).
# Covers: ### Adopt block emission, ADOPT-OK / ADOPT-WARN / ADOPT-ABORT verdicts,
# and the no-arg regression (output must not contain an Adopt section).
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/.." && pwd)
export CLAUDE_PLUGIN_ROOT="$REPO_ROOT"

TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

fail() { echo "FAIL: $1" >&2; exit 1; }
pass() { echo "  ok: $1"; }

# --- gh stub -----------------------------------------------------------
# /repos/acme/widget/issues/<n> → fixture JSON (the script captures raw JSON
# and runs jq itself).
# graphql / project view → only answered when GH_STUB_BOARD=1, emitting the
# post-jq output the lib functions expect (gh applies --jq internally, so
# the stub prints the filtered result directly).
export GH_FIXTURE_DIR="$TMP_DIR/fixtures"
mkdir -p "$GH_FIXTURE_DIR" "$TMP_DIR/bin"
cat > "$TMP_DIR/bin/gh" <<'STUB'
#!/usr/bin/env bash
args="$*"
case "$args" in
  *"/repos/acme/widget/issues/"*)
    n=$(printf '%s' "$args" | grep -oE 'issues/[0-9]+' | grep -oE '[0-9]+')
    [[ -f "$GH_FIXTURE_DIR/issue-$n.json" ]] && { cat "$GH_FIXTURE_DIR/issue-$n.json"; exit 0; }
    exit 1 ;;
  *"project view"*)
    [[ "${GH_STUB_BOARD:-}" == "1" ]] && { echo "PVT_kwTEST"; exit 0; }
    exit 1 ;;
  *projectItems*)
    [[ "${GH_STUB_BOARD:-}" == "1" ]] && { echo "PVTI_item1"; exit 0; }
    exit 1 ;;
  *fieldValueByName*)
    if [[ "${GH_STUB_BOARD:-}" == "1" ]]; then
      echo "${GH_STUB_STATUS:-In Progress}"
      exit 0
    fi
    exit 1 ;;
esac
exit 1
STUB
chmod +x "$TMP_DIR/bin/gh"
export PATH="$TMP_DIR/bin:$PATH"

# --- fixtures ----------------------------------------------------------
cat > "$GH_FIXTURE_DIR/issue-33.json" <<'EOF'
{ "number": 33, "state": "open", "title": "Add adopt mode",
  "type": null, "labels": [{"name": "feature"}, {"name": "p3"}],
  "milestone": null, "assignees": [], "body": "## Summary\nx" }
EOF
cat > "$GH_FIXTURE_DIR/issue-90.json" <<'EOF'
{ "number": 90, "state": "closed", "title": "Old thing",
  "type": null, "labels": [{"name": "feature"}],
  "milestone": null, "assignees": [], "body": "" }
EOF
cat > "$GH_FIXTURE_DIR/issue-91.json" <<'EOF'
{ "number": 91, "state": "open", "title": "Big composite",
  "type": {"name": "Story"}, "labels": [{"name": "story"}],
  "milestone": null, "assignees": [], "body": "" }
EOF
cat > "$GH_FIXTURE_DIR/issue-92.json" <<'EOF'
{ "number": 92, "state": "open", "title": "Already running",
  "type": null, "labels": [{"name": "feature"}],
  "milestone": {"title": "2026-06-W2"}, "assignees": [{"login": "jude"}],
  "body": "Parent: #5\n\n## Summary\nx" }
EOF

# --- project sandbox ---------------------------------------------------
PROJECT="$TMP_DIR/project"
mkdir -p "$PROJECT/.claude/sillok"
cat > "$PROJECT/.claude/sillok/workflow.config.json" <<'EOF'
{
  "repo": "acme/widget",
  "branchPrefix": "{type}/issue-",
  "types": { "list": ["Story", "Feature", "Bug", "Task"] },
  "project": { "owner": "acme", "number": 4, "statusField": "Status",
    "statuses": { "todo": "Todo", "progress": "In Progress", "review": "In QA", "done": "Done" } }
}
EOF
git -C "$PROJECT" init -q
git -C "$PROJECT" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
cd "$PROJECT"

echo "test: no-arg run has no Adopt section (regression)"
out=$(bash "$REPO_ROOT/scripts/precompute-start.sh")
echo "$out" | grep -q '### Adopt' && fail "no-arg run must not emit Adopt section"
echo "$out" | grep -q '### Sprint milestone' || fail "no-arg run lost existing sections"
pass "no-arg output unchanged"

echo "test: adopt open backlog-ish issue → ADOPT-OK"
out=$(bash "$REPO_ROOT/scripts/precompute-start.sh" 33)
echo "$out" | grep -q '### Adopt' || fail "expected Adopt section, got: $out"
echo "$out" | grep -q 'ADOPT-OK' || fail "expected ADOPT-OK, got: $out"
echo "$out" | grep -q -- '- Type: feature' || fail "expected user-mode type from label, got: $out"
echo "$out" | grep -q -- '- Branch type: feature' || fail "expected precomputed branch type, got: $out"
pass "#33 → ADOPT-OK with label-derived type"

echo "test: '#33' argument form is accepted"
out=$(bash "$REPO_ROOT/scripts/precompute-start.sh" '#33')
echo "$out" | grep -q 'ADOPT-OK' || fail "expected ADOPT-OK for '#33', got: $out"
pass "leading # stripped"

echo "test: closed issue → ADOPT-ABORT"
out=$(bash "$REPO_ROOT/scripts/precompute-start.sh" 90)
echo "$out" | grep -q 'ADOPT-ABORT: issue #90 is closed' || fail "expected closed abort, got: $out"
pass "#90 closed → ADOPT-ABORT"

echo "test: Story issue → ADOPT-ABORT pointing at /sillok-story"
out=$(bash "$REPO_ROOT/scripts/precompute-start.sh" 91)
echo "$out" | grep -q 'ADOPT-ABORT' || fail "expected abort for Story, got: $out"
echo "$out" | grep -qi 'sillok-story' || fail "expected /sillok-story pointer, got: $out"
pass "#91 Story → ADOPT-ABORT with story pointer"

echo "test: existing local branch for issue → ADOPT-ABORT"
base_branch=$(git branch --show-current)
git checkout -qb feature/issue-33-some-slug
git checkout -q "$base_branch"   # back off the issue branch, or the guard aborts first
out=$(bash "$REPO_ROOT/scripts/precompute-start.sh" 33)
echo "$out" | grep -q 'ADOPT-ABORT' || fail "expected abort for existing branch, got: $out"
echo "$out" | grep -q 'feature/issue-33-some-slug' || fail "expected branch name in abort, got: $out"
git branch -qD feature/issue-33-some-slug
pass "existing feature/issue-33-* → ADOPT-ABORT"

echo "test: active board status → ADOPT-WARN, status kept"
export GH_STUB_BOARD=1
out=$(bash "$REPO_ROOT/scripts/precompute-start.sh" 92)
echo "$out" | grep -q "ADOPT-WARN" || fail "expected ADOPT-WARN, got: $out"
echo "$out" | grep -q "In Progress" || fail "expected current status in warn, got: $out"
echo "$out" | grep -q -- '- Parent: #5' || fail "expected parent line, got: $out"
unset GH_STUB_BOARD
pass "#92 In Progress → ADOPT-WARN with parent line"

echo "test: Done board status → ADOPT-WARN (not OK)"
export GH_STUB_BOARD=1 GH_STUB_STATUS="Done"
out=$(bash "$REPO_ROOT/scripts/precompute-start.sh" 92)
echo "$out" | grep -q "ADOPT-WARN" || fail "expected ADOPT-WARN for Done status, got: $out"
echo "$out" | grep -q "'Done'" || fail "expected Done quoted in warn, got: $out"
unset GH_STUB_BOARD GH_STUB_STATUS
pass "#92 Done → ADOPT-WARN"

echo "test: In Design board status → ADOPT-WARN (whitelist gate)"
export GH_STUB_BOARD=1 GH_STUB_STATUS="In Design"
out=$(bash "$REPO_ROOT/scripts/precompute-start.sh" 92)
echo "$out" | grep -q "ADOPT-WARN" || fail "expected ADOPT-WARN for In Design status, got: $out"
unset GH_STUB_BOARD GH_STUB_STATUS
pass "#92 In Design → ADOPT-WARN"

echo "test: Todo board status → ADOPT-OK (pre-work whitelist)"
export GH_STUB_BOARD=1 GH_STUB_STATUS="Todo"
out=$(bash "$REPO_ROOT/scripts/precompute-start.sh" 92)
echo "$out" | grep -q "ADOPT-OK" || fail "expected ADOPT-OK for Todo status, got: $out"
unset GH_STUB_BOARD GH_STUB_STATUS
pass "#92 Todo → ADOPT-OK"

echo
echo "All precompute-start adopt tests passed."
