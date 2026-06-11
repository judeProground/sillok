#!/usr/bin/env bash
# Tests for scripts/precompute-add.sh (#33).
# /sillok-add is a capture command: it must NOT abort on an issue branch
# (mid-session discovery is its primary use case).
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/.." && pwd)
export CLAUDE_PLUGIN_ROOT="$REPO_ROOT"

TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

fail() { echo "FAIL: $1" >&2; exit 1; }
pass() { echo "  ok: $1"; }

# gh stub: all lookups masked-fail (epics list is best-effort).
mkdir -p "$TMP_DIR/bin"
printf '#!/usr/bin/env bash\nexit 1\n' > "$TMP_DIR/bin/gh"
chmod +x "$TMP_DIR/bin/gh"
export PATH="$TMP_DIR/bin:$PATH"

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

echo "test: runs from base branch"
out=$(bash "$REPO_ROOT/scripts/precompute-add.sh")
echo "$out" | grep -q '## precomputed state for /sillok-add' || fail "missing header, got: $out"
echo "$out" | grep -q '### Open epics' || fail "missing epics section, got: $out"
echo "$out" | grep -q '### Language' || fail "missing language section, got: $out"
pass "base branch run emits header + epics + language"

echo "test: does NOT abort on an issue branch (mid-session capture)"
git checkout -qb feature/issue-7-current-work
out=$(bash "$REPO_ROOT/scripts/precompute-add.sh")
echo "$out" | grep -q 'ABORT' && fail "/sillok-add must never abort on an issue branch, got: $out"
echo "$out" | grep -q '### Open epics' || fail "script must proceed on issue branch, got: $out"
pass "issue branch run proceeds without guard"

echo
echo "All precompute-add tests passed."
