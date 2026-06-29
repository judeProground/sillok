#!/usr/bin/env bash
# bootstrap-labels.sh orgMode gating (#66, #17): org repos track priority on the
# org-level Priority issue field (set via setIssueFieldValue, #17), so p1–p4
# labels must NOT be created there; user repos keep them. Type labels were
# already gated the same way; nature labels are created in both modes.
# Hermetic: gh is stubbed to a call logger.
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/.." && pwd)
export CLAUDE_PLUGIN_ROOT="$REPO_ROOT"

TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

fail() { echo "FAIL: $1" >&2; exit 1; }
pass() { echo "  ok: $1"; }

# gh stub: log every `gh label create <name>` by name, succeed on everything.
STUB_BIN="$TMP_DIR/stub-bin"
mkdir -p "$STUB_BIN"
cat > "$STUB_BIN/gh" <<'STUB'
#!/bin/sh
if [ "$1" = "label" ] && [ "$2" = "create" ]; then
  echo "$3" >> "$GH_LABEL_LOG"
fi
exit 0
STUB
chmod +x "$STUB_BIN/gh"

# Build a consumer project with the given orgMode and run bootstrap-labels.sh
# from inside it (lib/config.sh resolves the config from the cwd's git root).
run_bootstrap() {
  local org_mode="$1" log="$2"
  local dir="$TMP_DIR/proj-$org_mode"
  mkdir -p "$dir/.claude/sillok"
  git -C "$dir" init -q 2>/dev/null || git init -q "$dir"
  cat > "$dir/.claude/sillok/workflow.config.json" <<EOF
{ "version": 1, "repo": "test/test", "baseBranch": "main", "branchPrefix": "{type}/issue-", "orgMode": $org_mode, "project": { "owner": "testorg", "number": 7 } }
EOF
  (cd "$dir" && GH_LABEL_LOG="$log" PATH="$STUB_BIN:$PATH" \
    bash "$REPO_ROOT/scripts/bootstrap-labels.sh" test/test >/dev/null)
}

count_label() { grep -cx "$2" "$1" 2>/dev/null || true; }

# --- orgMode=true: p-labels skipped -------------------------------------
echo "test: orgMode=true skips p1–p4 label creation"
LOG_ORG="$TMP_DIR/org.log"
run_bootstrap true "$LOG_ORG"
for p in p1 p2 p3 p4; do
  n=$(count_label "$LOG_ORG" "$p")
  [[ "$n" == "0" ]] || fail "orgMode=true: expected 0 'label create $p' calls, got $n"
done
pass "orgMode=true: no p1–p4 label create calls"

# Natures still created in org mode (gating must not over-reach).
n=$(count_label "$LOG_ORG" "improvement")
[[ "$n" == "1" ]] || fail "orgMode=true: expected nature label 'improvement' to be created once, got $n"
n=$(count_label "$LOG_ORG" "feature")
[[ "$n" == "0" ]] || fail "orgMode=true: type label 'feature' should remain skipped, got $n"
pass "orgMode=true: nature labels still created, type labels still skipped"

# --- orgMode=false: p-labels created ------------------------------------
echo "test: orgMode=false creates p1–p4 labels"
LOG_USER="$TMP_DIR/user.log"
run_bootstrap false "$LOG_USER"
for p in p1 p2 p3 p4; do
  n=$(count_label "$LOG_USER" "$p")
  [[ "$n" == "1" ]] || fail "orgMode=false: expected exactly 1 'label create $p' call, got $n"
done
pass "orgMode=false: p1–p4 each created exactly once"

n=$(count_label "$LOG_USER" "feature")
[[ "$n" == "1" ]] || fail "orgMode=false: expected type label 'feature' to be created once, got $n"
pass "orgMode=false: type labels created (user-repo fallback unchanged)"

echo
echo "All bootstrap-labels-orgmode tests passed."
