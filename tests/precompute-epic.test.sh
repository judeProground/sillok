#!/usr/bin/env bash
# Tests for scripts/precompute-epic.sh
# Verifies source classification, PRD repo output, and abort-on-unset-epicRepo.
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/.." && pwd)
export CLAUDE_PLUGIN_ROOT="$REPO_ROOT"

TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

fail() { echo "FAIL: $1" >&2; exit 1; }
pass() { echo "  ok: $1"; }

# gh stub: best-effort candidates list — returns empty JSON array so the
# script continues (never aborts on gh failure).
mkdir -p "$TMP_DIR/bin"
cat > "$TMP_DIR/bin/gh" <<'GHSTUB'
#!/usr/bin/env bash
# Stub: return empty JSON array for all calls.
echo "[]"
exit 0
GHSTUB
chmod +x "$TMP_DIR/bin/gh"
export PATH="$TMP_DIR/bin:$PATH"

PROJECT="$TMP_DIR/project"
mkdir -p "$PROJECT/.claude/sillok"
cat > "$PROJECT/.claude/sillok/workflow.config.json" <<'EOF'
{
  "repo": "acme/widget",
  "epicRepo": "acme/projects",
  "orgMode": false,
  "branchPrefix": "{type}/issue-",
  "language": "ko"
}
EOF
git -C "$PROJECT" init -q
git -C "$PROJECT" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
cd "$PROJECT"

echo "test: no-arg run emits mode: pick and ### PRD repo"
out=$(bash "$REPO_ROOT/scripts/precompute-epic.sh")
echo "$out" | grep -q '### Source' || fail "missing ### Source section, got: $out"
echo "$out" | grep -q 'mode: pick' || fail "no-arg must emit mode: pick, got: $out"
echo "$out" | grep -q '### PRD repo' || fail "missing ### PRD repo section, got: $out"
echo "$out" | grep -q 'acme/projects' || fail "### PRD repo must show configured repo, got: $out"
echo "$out" | grep -q '### Candidate PRDs' || fail "missing ### Candidate PRDs section, got: $out"
echo "$out" | grep -q '### Language' || fail "missing ### Language section, got: $out"
pass "no-arg run emits mode: pick + PRD repo + candidates + language"

echo "test: a PRD path arg emits mode: path"
out=$(bash "$REPO_ROOT/scripts/precompute-epic.sh" "basic/my-feature/prd.md")
echo "$out" | grep -q 'mode: path' || fail "path arg must emit mode: path, got: $out"
pass "path argument emits mode: path"

echo "test: a bare project dir arg also emits mode: path"
out=$(bash "$REPO_ROOT/scripts/precompute-epic.sh" "basic/my-feature")
echo "$out" | grep -q 'mode: path' || fail "dir-path arg must emit mode: path, got: $out"
pass "dir-path argument emits mode: path"

echo "test: notion URL emits mode: notion"
out=$(bash "$REPO_ROOT/scripts/precompute-epic.sh" "https://notion.so/My-PRD-abc123")
echo "$out" | grep -q 'mode: notion' || fail "notion URL must emit mode: notion, got: $out"
pass "notion URL emits mode: notion"

echo "test: notion URL with a target dir emits mode: notion + target line"
out=$(bash "$REPO_ROOT/scripts/precompute-epic.sh" "https://notion.so/My-PRD-abc123" "basic/my-feature")
echo "$out" | grep -q 'mode: notion' || fail "notion URL must emit mode: notion, got: $out"
echo "$out" | grep -q 'target:' || fail "notion + target arg must emit a target line, got: $out"
pass "notion URL + target emits mode: notion with target"

echo "test: aborts non-zero when epicRepo unset"
PROJECT_NOPRD="$TMP_DIR/project-noprd"
mkdir -p "$PROJECT_NOPRD/.claude/sillok"
cat > "$PROJECT_NOPRD/.claude/sillok/workflow.config.json" <<'EOF'
{
  "repo": "acme/widget",
  "branchPrefix": "{type}/issue-"
}
EOF
git -C "$PROJECT_NOPRD" init -q
git -C "$PROJECT_NOPRD" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
cd "$PROJECT_NOPRD"
if bash "$REPO_ROOT/scripts/precompute-epic.sh" 2>/dev/null; then
  fail "must abort non-zero when epicRepo is unset"
fi
pass "aborts non-zero when epicRepo unset"

echo
echo "All precompute-epic tests passed."
