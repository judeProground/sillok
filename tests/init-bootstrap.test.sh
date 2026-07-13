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

echo "test: phase1 gitignores the per-user local config override"
grep -Fxq -- '.claude/sillok/workflow.config.local.json' "$PROJECT/.gitignore" \
  || fail "phase1 did not add local config to .gitignore"
# idempotent — re-running must not duplicate the line
bash "$REPO_ROOT/scripts/init-bootstrap.sh" phase1 >/dev/null 2>&1
ignore_count=$(grep -Fxc -- '.claude/sillok/workflow.config.local.json' "$PROJECT/.gitignore" 2>/dev/null || echo 0)
[[ "$ignore_count" -eq 1 ]] || fail ".gitignore local-config line duplicated on re-run (count=$ignore_count)"
pass "local config gitignored, idempotent"

echo "test: phase1 scaffolds a discoverable, INERT local config override"
LOCAL_CFG="$PROJECT/.claude/sillok/workflow.config.local.json"
[[ -f "$LOCAL_CFG" ]] || fail "phase1 did not scaffold $LOCAL_CFG"
jq -e . "$LOCAL_CFG" >/dev/null 2>&1 || fail "scaffolded local config is not valid JSON"
# INERT: the per-user keys are DOCUMENTED under __overridable, NOT at the top
# level, so config.sh (which reads top-level keys) sees no override.
top_keys=$(jq -r 'keys | join(",")' "$LOCAL_CFG")
[[ "$top_keys" == "__doc,__overridable" ]] || fail "unexpected top-level keys (must be inert): $top_keys"
# __overridable documents each key as a description STRING stating its default —
# not a value block that could read as an active setting.
jq -e '.__overridable.qaBranch | type == "string" and test("DEFAULT")' "$LOCAL_CFG" >/dev/null 2>&1 \
  || fail "expected __overridable.qaBranch to be a default-stating description string"
jq -e '.__overridable.language | test("auto")' "$LOCAL_CFG" >/dev/null 2>&1 \
  || fail "expected __overridable.language to state the real default (auto)"
# prove inertness end-to-end: a team qaBranch still resolves through the scaffold.
TMP_INERT=$(mktemp -d)
cp -R "$PROJECT/.claude" "$TMP_INERT/.claude"
( cd "$TMP_INERT" && git init -q
  # config.sh isn't sourced at this test's top level — source it here to use sillok_config.
  source "$REPO_ROOT/scripts/lib/config.sh"
  tmp=$(mktemp); jq '. + {qaBranch:"deploy/qa"}' .claude/sillok/workflow.config.json > "$tmp" && mv "$tmp" .claude/sillok/workflow.config.json
  val=$(sillok_config qaBranch)
  [[ "$val" == "deploy/qa" ]] || { echo "FAIL: scaffold overrode qaBranch (got '$val', expected deploy/qa)"; exit 1; }
) || fail "scaffold is not inert"
rm -rf "$TMP_INERT"
pass "local config scaffolded, valid, inert (docs under __overridable state defaults)"

echo "test: phase1 does NOT clobber an existing (customized) local config"
printf '{ "qaBranch": "deploy/qa/mine" }\n' > "$LOCAL_CFG"
bash "$REPO_ROOT/scripts/init-bootstrap.sh" phase1 >/dev/null 2>&1
jq -e '.qaBranch == "deploy/qa/mine"' "$LOCAL_CFG" >/dev/null 2>&1 \
  || fail "re-init clobbered a customized local config"
pass "existing local config preserved on re-init"

echo "test: phase1 emits QA_CANDIDATES (empty when no origin/qa branches)"
# The temp project has no 'origin' remote, so git ls-remote yields nothing.
echo "$out" | grep -q '^QA_CANDIDATES=$' || fail "expected empty QA_CANDIDATES line, got: $out"
jq -e '.qaBranch == ""' "$CFG" >/dev/null 2>&1 || fail "fresh config missing qaBranch:\"\", got: $(jq .qaBranch "$CFG")"
pass "QA_CANDIDATES empty-case + qaBranch key present"

echo "test: phase1 detects qa/deploy branches as QA_CANDIDATES"
# git wrapper: intercept ls-remote to advertise deploy/qa + main; delegate the
# rest to real git (captured before any PATH shadowing). Isolated bin dir used
# for this single phase1 run only.
REAL_GIT=$(command -v git)
QA_BIN="$TMP_DIR/qabin"
mkdir -p "$QA_BIN"
cat > "$QA_BIN/git" <<GITW
#!/usr/bin/env bash
if [[ "\$1" == "ls-remote" ]]; then
  printf '%s\trefs/heads/main\n' aaa
  printf '%s\trefs/heads/deploy/qa\n' bbb
  printf '%s\trefs/heads/deploy/qa/test\n' ccc
  exit 0
fi
exec "$REAL_GIT" "\$@"
GITW
chmod +x "$QA_BIN/git"
qa_out=$(PATH="$QA_BIN:$PATH" bash "$REPO_ROOT/scripts/init-bootstrap.sh" phase1 2>/dev/null)
echo "$qa_out" | grep -q '^QA_CANDIDATES=deploy/qa,deploy/qa/test$' \
  || fail "expected QA_CANDIDATES=deploy/qa,deploy/qa/test, got: $(echo "$qa_out" | grep '^QA_CANDIDATES=')"
pass "QA_CANDIDATES detects deploy/qa branches, excludes main"

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

echo "test: re-init removes a dead sillok-rule @import line while preserving user-custom imports (reconcile)"
# Simulate an existing consumer whose CLAUDE.md carries an import line for a
# rule file that has since been removed upstream (not in the current
# claude-md-snippet.md), plus a user-custom @import to an unrelated path that
# must survive untouched.
printf '%s\n' '- @.claude/sillok/rules/some-removed-rule.md' >> "$PROJECT/CLAUDE.md"
printf '%s\n' '- @docs/my-custom-notes.md' >> "$PROJECT/CLAUDE.md"
bash "$REPO_ROOT/scripts/init-bootstrap.sh" phase1 >/dev/null 2>&1
grep -Fxq -- '- @.claude/sillok/rules/some-removed-rule.md' "$PROJECT/CLAUDE.md" && fail "dead sillok-rule import line was not removed"
grep -Fxq -- '- @docs/my-custom-notes.md' "$PROJECT/CLAUDE.md" || fail "user-custom @import line was removed (should be preserved)"
grep -Fxq -- '- @.claude/sillok/rules/commit-conventions.md' "$PROJECT/CLAUDE.md" || fail "current sillok-rule import line was removed (should survive)"
marker_count3=$(grep -c '## Sillok workflow rules' "$PROJECT/CLAUDE.md" 2>/dev/null || echo 0)
[[ "$marker_count3" -eq 1 ]] || fail "removal pass duplicated marker block (count=$marker_count3)"
pass "dead import removed, user-custom + current imports preserved"

echo "test: removal pass is idempotent (second re-run makes no further change)"
bash "$REPO_ROOT/scripts/init-bootstrap.sh" phase1 >/dev/null 2>&1
grep -Fxq -- '- @.claude/sillok/rules/some-removed-rule.md' "$PROJECT/CLAUDE.md" && fail "dead sillok-rule import line reappeared on second re-run"
grep -Fxq -- '- @docs/my-custom-notes.md' "$PROJECT/CLAUDE.md" || fail "user-custom @import line lost on second re-run"
marker_count4=$(grep -c '## Sillok workflow rules' "$PROJECT/CLAUDE.md" 2>/dev/null || echo 0)
[[ "$marker_count4" -eq 1 ]] || fail "second re-run duplicated marker block (count=$marker_count4)"
pass "idempotent removal pass"

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
