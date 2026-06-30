#!/usr/bin/env bash
# Tests for scripts/init-bootstrap.sh (#35).
# init-bootstrap.sh relocates the deterministic, side-effecting bash from
# skills/init/SKILL.md into a standalone two-phase script. It prints a flat
# KEY=value status block on stdout (read by the skill with a field-reader, not
# eval) and human notices on stderr. This test exercises phase1 + phase2 against
# a temp git project with a stubbed gh, asserting the status keys, the written
# config, idempotent re-run, the project-tree sentinels, and a missing-tool exit.
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/.." && pwd)
export CLAUDE_PLUGIN_ROOT="$REPO_ROOT"

TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

fail() { echo "FAIL: $1" >&2; exit 1; }
pass() { echo "  ok: $1"; }

# --- gh stub --------------------------------------------------------------
# Returns a User-owned repo + base branch, an empty project list, and a
# succeeding label create. User-owned so ORG_MODE=false (skips Issue Types and
# the org Priority issue field — no real network/org access needed).
mkdir -p "$TMP_DIR/bin"
cat > "$TMP_DIR/bin/gh" <<'GH'
#!/usr/bin/env bash
case "$1 $2" in
  "repo view")
    # Distinguish the two repo-view calls by the requested fields.
    if printf '%s\n' "$@" | grep -q 'defaultBranchRef'; then
      echo "main"
    else
      echo "acme/widget"
    fi
    ;;
  "api /repos/acme/widget")
    echo "User"
    ;;
  "project list")
    echo '{"projects":[],"totalCount":0}'
    ;;
  "label create")
    # Pretend creation succeeds.
    exit 0
    ;;
  "project field-list")
    echo ""
    ;;
  *)
    exit 0
    ;;
esac
GH
chmod +x "$TMP_DIR/bin/gh"
export PATH="$TMP_DIR/bin:$PATH"

# --- temp project ---------------------------------------------------------
PROJECT="$TMP_DIR/project"
mkdir -p "$PROJECT"
git -C "$PROJECT" init -q
git -C "$PROJECT" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
cd "$PROJECT"

CFG="$PROJECT/.claude/sillok/workflow.config.json"

echo "test: phase1 emits the status block + tree sentinels and writes config"
out=$(bash "$REPO_ROOT/scripts/init-bootstrap.sh" phase1 2>/dev/null)
echo "$out" | grep -q '## sillok init phase1' || fail "missing phase1 header, got: $out"
echo "$out" | grep -q '^CONFIG_STATUS=ok$' || fail "expected CONFIG_STATUS=ok, got: $out"
echo "$out" | grep -q '^ORG_MODE=' || fail "missing ORG_MODE line, got: $out"
echo "$out" | grep -q '^PROJ_NUM=' || fail "missing PROJ_NUM line, got: $out"
echo "$out" | grep -q '^CFG_PATH=' || fail "missing CFG_PATH line, got: $out"
echo "$out" | grep -q '^### project-tree$' || fail "missing ### project-tree sentinel, got: $out"
echo "$out" | grep -q '^### end-project-tree$' || fail "missing ### end-project-tree sentinel, got: $out"
[[ -f "$CFG" ]] || fail "phase1 did not write $CFG"
jq -e . "$CFG" >/dev/null 2>&1 || fail "written config is not valid JSON"
pass "phase1 status block, sentinels, and config write"

echo "test: phase1 reports user-repo skip values (User-owned stub)"
echo "$out" | grep -q '^ORG_MODE=false$' || fail "expected ORG_MODE=false, got: $out"
echo "$out" | grep -q '^TYPES_STATUS=skip-user-repo$' || fail "expected TYPES_STATUS=skip-user-repo, got: $out"
echo "$out" | grep -q '^PROJ_NUM=0$' || fail "expected empty-case PROJ_NUM=0, got: $out"
pass "user-repo skip values present"

echo "test: phase1 re-run is idempotent (migrated|ok, no duplicate CLAUDE.md marker)"
out2=$(bash "$REPO_ROOT/scripts/init-bootstrap.sh" phase1 2>/dev/null)
echo "$out2" | grep -Eq '^CONFIG_STATUS=(migrated|ok)$' || fail "re-run CONFIG_STATUS not migrated|ok, got: $out2"
marker_count=$(grep -c '## Sillok workflow rules' "$PROJECT/CLAUDE.md" 2>/dev/null || echo 0)
[[ "$marker_count" -eq 1 ]] || fail "CLAUDE.md marker duplicated on re-run (count=$marker_count)"
pass "idempotent re-run"

echo "test: every snippet @import line is present in CLAUDE.md after init"
SNIPPET="$REPO_ROOT/templates/claude-md-snippet.md"
while IFS= read -r imp; do
  grep -Fxq -- "$imp" "$PROJECT/CLAUDE.md" || fail "missing import line in CLAUDE.md: $imp"
done < <(grep -E '^- @\.claude/sillok/rules/.*\.md$' "$SNIPPET")
pass "all snippet imports present"

echo "test: re-init backfills a missing @import line (existing-consumer upgrade) without duplicating"
# Simulate an existing consumer whose CLAUDE.md predates a newly-added rule:
# delete one @import line (marker stays), then re-run phase1.
grep -vF -- '- @.claude/sillok/rules/output-language.md' "$PROJECT/CLAUDE.md" > "$PROJECT/CLAUDE.md.tmp"
mv "$PROJECT/CLAUDE.md.tmp" "$PROJECT/CLAUDE.md"
grep -Fxq -- '- @.claude/sillok/rules/output-language.md' "$PROJECT/CLAUDE.md" && fail "precondition: import line should be absent before backfill"
bash "$REPO_ROOT/scripts/init-bootstrap.sh" phase1 >/dev/null 2>&1
backfill_count=$(grep -cF -- '- @.claude/sillok/rules/output-language.md' "$PROJECT/CLAUDE.md" 2>/dev/null || echo 0)
[[ "$backfill_count" -eq 1 ]] || fail "backfill did not add exactly one import line (count=$backfill_count)"
marker_count2=$(grep -c '## Sillok workflow rules' "$PROJECT/CLAUDE.md" 2>/dev/null || echo 0)
[[ "$marker_count2" -eq 1 ]] || fail "backfill duplicated marker block (count=$marker_count2)"
# A further re-run must not duplicate the backfilled line.
bash "$REPO_ROOT/scripts/init-bootstrap.sh" phase1 >/dev/null 2>&1
backfill_count2=$(grep -cF -- '- @.claude/sillok/rules/output-language.md' "$PROJECT/CLAUDE.md" 2>/dev/null || echo 0)
[[ "$backfill_count2" -eq 1 ]] || fail "second re-run duplicated backfilled import line (count=$backfill_count2)"
pass "idempotent import backfill"

echo "test: phase2 emits LABELS_STATUS and the phase2 header"
out3=$(bash "$REPO_ROOT/scripts/init-bootstrap.sh" phase2 2>/dev/null)
echo "$out3" | grep -q '## sillok init phase2' || fail "missing phase2 header, got: $out3"
echo "$out3" | grep -q '^LABELS_STATUS=' || fail "missing LABELS_STATUS line, got: $out3"
echo "$out3" | grep -q '^LABELS_STATUS=ok$' || fail "expected LABELS_STATUS=ok, got: $out3"
echo "$out3" | grep -q '^PRIORITY_STATUS=skip-user-repo$' || fail "expected PRIORITY_STATUS=skip-user-repo, got: $out3"
pass "phase2 status block"

echo "test: missing tool yields non-zero exit"
# Keep bash + git reachable (so the script can run and reach its own prereq
# check) but drop gh/jq from PATH → Step 1 prereq guard fires `exit 1`.
TOOL_BIN="$TMP_DIR/toolbin"
mkdir -p "$TOOL_BIN"
for tool in bash sh git; do
  src=$(command -v "$tool" || true)
  [[ -n "$src" ]] && ln -sf "$src" "$TOOL_BIN/$tool"
done
set +e
PATH="$TOOL_BIN" bash "$REPO_ROOT/scripts/init-bootstrap.sh" phase1 >/dev/null 2>&1
rc=$?
set -e
[[ "$rc" -ne 0 ]] || fail "expected non-zero exit when gh/jq are missing"
pass "missing-tool case exits non-zero (rc=$rc)"

echo "test: unknown phase exits non-zero"
set +e
bash "$REPO_ROOT/scripts/init-bootstrap.sh" bogus >/dev/null 2>&1
rc=$?
set -e
[[ "$rc" -ne 0 ]] || fail "expected non-zero exit for unknown phase"
pass "unknown phase exits non-zero (rc=$rc)"

# --- org-mode coverage (phase1 Issue Types + phase2 project verify) -------
# The earlier fixture is User-owned, so the org branches (Step 2b Issue Types,
# the phase2 proj_missing option-coverage loop, Step 9c priority) never ran.
# This fixture exercises them with an Organization-owned repo + a configured
# project whose Status field has all six options.
echo "test: org-mode — phase1 ORG_MODE/Issue Types + phase2 project verify"
ORG_BIN="$TMP_DIR/orgbin"
mkdir -p "$ORG_BIN"
cat > "$ORG_BIN/gh" <<'GH'
#!/usr/bin/env bash
case "$1 $2" in
  "repo view")
    if printf '%s\n' "$@" | grep -q 'defaultBranchRef'; then echo "main"; else echo "acme/widget"; fi ;;
  "api /repos/acme/widget") echo "Organization" ;;
  "project list") echo '{"projects":[],"totalCount":0}' ;;
  "project field-list") printf 'Backlog\nTodo\nIn Design\nIn Progress\nIn QA\nDone\n' ;;
  "label create") exit 0 ;;
  *)
    if printf '%s\n' "$@" | grep -q 'issue-types'; then
      printf 'Epic\nStory\nFeature\nTask\nBug\n'
    elif printf '%s\n' "$@" | grep -q 'graphql'; then
      cat <<'JSON'
{"data":{"organization":{"issueFields":{"nodes":[{"__typename":"IssueFieldSingleSelect","id":"IFSS_x","name":"Priority","options":[{"id":"o1","name":"Urgent"},{"id":"o2","name":"High"},{"id":"o3","name":"Medium"},{"id":"o4","name":"Low"}]}]}}}}
JSON
    else
      exit 0
    fi ;;
esac
GH
chmod +x "$ORG_BIN/gh"

ORGPROJ="$TMP_DIR/orgproject"
mkdir -p "$ORGPROJ/.claude/sillok"
git -C "$ORGPROJ" init -q
git -C "$ORGPROJ" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
cat > "$ORGPROJ/.claude/sillok/workflow.config.json" <<'OCFG'
{ "version":1, "repo":"acme/widget", "baseBranch":"main", "branchPrefix":"{type}/issue-",
  "orgMode": true,
  "project": { "owner":"acme", "number":7, "statusField":"Status",
    "statuses": {"backlog":"Backlog","todo":"Todo","design":"In Design","progress":"In Progress","review":"In QA","done":"Done"},
    "priorityField":"Priority", "priorities": {"p1":"Urgent","p2":"High","p3":"Medium","p4":"Low"} },
  "docs": { "specs":"docs/superpowers/specs", "plans":"docs/superpowers/plans" },
  "labels": { "areas": [], "defaults": {"priority":"p3"} } }
OCFG

org_out=$( cd "$ORGPROJ" && PATH="$ORG_BIN:$PATH" bash "$REPO_ROOT/scripts/init-bootstrap.sh" phase1 2>/dev/null )
echo "$org_out" | grep -q '^ORG_MODE=true$' || fail "org phase1: expected ORG_MODE=true, got: $org_out"
echo "$org_out" | grep -q '^TYPES_STATUS=ok$' || fail "org phase1: expected TYPES_STATUS=ok (issue-types stub returns all 5), got: $org_out"
pass "org phase1: ORG_MODE=true + TYPES_STATUS=ok"

org_out2=$( cd "$ORGPROJ" && PATH="$ORG_BIN:$PATH" bash "$REPO_ROOT/scripts/init-bootstrap.sh" phase2 2>/dev/null )
echo "$org_out2" | grep -q '^PROJECT_STATUS=ok$' || fail "org phase2: expected PROJECT_STATUS=ok (field-list returns all six Status options), got: $org_out2"
echo "$org_out2" | grep -q '^PRIORITY_STATUS=' || fail "org phase2: missing PRIORITY_STATUS line, got: $org_out2"
pass "org phase2: PROJECT_STATUS=ok + PRIORITY_STATUS emitted"

echo
echo "All init-bootstrap tests passed."
