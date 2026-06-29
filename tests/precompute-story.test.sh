#!/usr/bin/env bash
# Tests for scripts/precompute-story.sh
# Verifies mode detection (standalone / promotion / ABORT) and section output.
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/.." && pwd)
export CLAUDE_PLUGIN_ROOT="$REPO_ROOT"

TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

fail() { echo "FAIL: $1" >&2; exit 1; }
pass() { echo "  ok: $1"; }

# gh stub: returns empty JSON array for all calls so sillok_open_epics_section
# continues gracefully without a real GitHub auth.
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

echo "test: on main branch → standalone + ### Open epics + ### Language"
( cd "$PROJECT" && git checkout -q -b main 2>/dev/null || true )
out=$(cd "$PROJECT" && bash "$REPO_ROOT/scripts/precompute-story.sh")
echo "$out" | grep -q '### Mode' || fail "missing ### Mode section, got: $out"
echo "$out" | grep -qi 'standalone' || fail "main branch → should be standalone, got: $out"
echo "$out" | grep -q '### Open epics' || fail "missing ### Open epics section, got: $out"
echo "$out" | grep -q '### Language' || fail "missing ### Language section, got: $out"
pass "main branch → standalone + Open epics + Language"

echo "test: on feature/issue-42-foo → promotion with issue 42"
( cd "$PROJECT" && git checkout -q -b feature/issue-42-foo )
out=$(cd "$PROJECT" && bash "$REPO_ROOT/scripts/precompute-story.sh")
echo "$out" | grep -qi 'promotion' || fail "feature branch → should be promotion, got: $out"
echo "$out" | grep -q '42' || fail "promotion must surface issue 42, got: $out"
pass "feature/issue-42-foo → promotion with issue #42"

echo "test: on story/issue-9-bar → ABORT line"
( cd "$PROJECT" && git checkout -q -b story/issue-9-bar )
out=$(cd "$PROJECT" && bash "$REPO_ROOT/scripts/precompute-story.sh")
echo "$out" | grep -q 'ABORT:' || fail "story branch → should emit ABORT:, got: $out"
pass "story/issue-9-bar → ABORT:"

echo "test: promotion mode also includes slug"
( cd "$PROJECT" && git checkout -q feature/issue-42-foo )
out=$(cd "$PROJECT" && bash "$REPO_ROOT/scripts/precompute-story.sh")
echo "$out" | grep -q 'foo' || fail "promotion must surface slug 'foo', got: $out"
pass "promotion mode surfaces slug"

echo "test: language section shows configured value"
( cd "$PROJECT" && git checkout -q main )
out=$(cd "$PROJECT" && bash "$REPO_ROOT/scripts/precompute-story.sh")
echo "$out" | grep -q 'ko' || fail "### Language must show configured value 'ko', got: $out"
pass "### Language shows configured value"

echo
echo "All precompute-story tests passed."
