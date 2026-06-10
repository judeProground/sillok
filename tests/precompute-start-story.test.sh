#!/usr/bin/env bash
# Tests for scripts/precompute-start.sh abort-guard type handling.
#
# The guard must abort when already on a non-story issue branch
# (feature/issue-N-*, bug/..., etc.) but NOT on a story integration branch —
# `start --parent N` FROM the story worktree is the documented story loop, so
# story/issue-N-* is a sanctioned starting point and the script must emit a
# STORY-BRANCH context line instead of ABORT.
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/.." && pwd)
export CLAUDE_PLUGIN_ROOT="$REPO_ROOT"

TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

fail() { echo "FAIL: $1" >&2; exit 1; }
pass() { echo "  ok: $1"; }

# Stub gh so the non-abort path (epics + milestone lookups) stays hermetic —
# every gh call in precompute-start.sh is failure-masked, so exit 1 is fine.
mkdir -p "$TMP_DIR/bin"
printf '#!/usr/bin/env bash\nexit 1\n' > "$TMP_DIR/bin/gh"
chmod +x "$TMP_DIR/bin/gh"
export PATH="$TMP_DIR/bin:$PATH"

# Minimal consumer project with the templated branch prefix.
PROJECT="$TMP_DIR/project"
mkdir -p "$PROJECT/.claude/sillok"
cat > "$PROJECT/.claude/sillok/workflow.config.json" <<'EOF'
{
  "repo": "acme/widget",
  "branchPrefix": "{type}/issue-",
  "types": { "list": ["Story", "Feature", "Bug", "Task"] }
}
EOF
git -C "$PROJECT" init -q
git -C "$PROJECT" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init

cd "$PROJECT"

echo "test: feature/issue-N-* branch still aborts"
git checkout -qb feature/issue-7-some-fix
out=$(bash "$REPO_ROOT/scripts/precompute-start.sh")
echo "$out" | grep -q 'ABORT: already on issue branch for #7' \
  || fail "expected ABORT for feature branch, got: $out"
echo "$out" | grep -q 'STORY-BRANCH' \
  && fail "feature branch must not emit STORY-BRANCH, got: $out"
pass "feature/issue-7-some-fix → ABORT, no STORY-BRANCH"

echo "test: story/issue-N-* branch is exempt and emits story context"
git checkout -qb story/issue-9-big-epic
out=$(bash "$REPO_ROOT/scripts/precompute-start.sh")
echo "$out" | grep -q 'ABORT' \
  && fail "story branch must not abort, got: $out"
echo "$out" | grep -q 'STORY-BRANCH: `story/issue-9-big-epic` (issue #9)' \
  || fail "expected STORY-BRANCH context line, got: $out"
echo "$out" | grep -q '### Sprint milestone' \
  || fail "script must proceed past the guard on a story branch, got: $out"
pass "story/issue-9-big-epic → STORY-BRANCH line, script proceeds"

echo
echo "All precompute-start story-exemption tests passed."
