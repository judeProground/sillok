#!/usr/bin/env bash
# Tests for scripts/lib/epics.sh — sillok_open_epics_section output.
set -euo pipefail
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/.." && pwd)
export CLAUDE_PLUGIN_ROOT="$REPO_ROOT"
fail() { echo "FAIL: $1" >&2; exit 1; }
pass() { echo "  ok: $1"; }

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin"
# gh stub: emits pre-jq'd output matching what the function expects.
# gh applies --jq internally, so the stub prints the already-filtered result
# directly (the function uses --jq on the gh call, not a separate jq pipe).
cat > "$TMP/bin/gh" <<'GH'
#!/usr/bin/env bash
args="$*"
case "$args" in
  *"type:Story"*)     echo '  - (in this repo) #7 [Story] Notif system';;
  *"type:Epic"*)      echo '  - (in acme/projects) #5 [Epic] Onboarding';;
  *"--label story"*)  echo '  - (in this repo) #7 [story] Notif system';;
  *"--label epic"*)   echo '  - (in acme/projects) #5 [epic] Onboarding';;
  *) ;;
esac
GH
chmod +x "$TMP/bin/gh"
export PATH="$TMP/bin:$PATH"

mkproject() { # $1=orgMode $2=epicRepo
  local p="$TMP/p-$RANDOM"; mkdir -p "$p/.claude/sillok"
  cat > "$p/.claude/sillok/workflow.config.json" <<EOF
{ "repo": "acme/widget", "orgMode": $1, "epicRepo": "$2", "branchPrefix": "{type}/issue-" }
EOF
  ( cd "$p"; git init -q; source "$REPO_ROOT/scripts/lib/epics.sh"; sillok_open_epics_section )
}

echo "test: org mode + epicRepo → epic candidate first, then local story"
out=$(mkproject true "acme/projects")
echo "$out" | grep -q '^### Open epics$' || fail "missing ### Open epics header"
echo "$out" | grep -q '(in acme/projects) #5 \[Epic\] Onboarding' || fail "missing epic candidate, got: $out"
echo "$out" | grep -q '(in this repo) #7 \[Story\] Notif system' || fail "missing local story, got: $out"
# epicRepo line must come before local story line
[ "$(echo "$out" | grep -n 'Epic\] Onboarding' | cut -d: -f1)" -lt "$(echo "$out" | grep -n 'Story\] Notif' | cut -d: -f1)" ] || fail "epic must precede local story"
pass "org mode lists epic then story"

echo "test: user mode (orgMode=false) uses label queries"
out=$(mkproject false "acme/projects")
echo "$out" | grep -q '(in acme/projects) #5 \[epic\] Onboarding' || fail "user-mode epic label query, got: $out"
echo "$out" | grep -q '(in this repo) #7 \[story\] Notif system' || fail "user-mode story label query, got: $out"
pass "user mode lists via labels"

echo "test: epicRepo unset → only local, no epic candidates"
out=$(mkproject true "")
echo "$out" | grep -q '\[Story\] Notif system' || fail "local story expected"
echo "$out" | grep -q 'acme/projects' && fail "no epicRepo configured — must not query it"
pass "epicRepo unset → local only"

echo "test: nothing found → standalone line"
# gh stub returns empty output for all queries → both local_stories and epic_candidates are empty.
cat > "$TMP/bin/gh" <<'GH'
#!/usr/bin/env bash
exit 0
GH
chmod +x "$TMP/bin/gh"
out=$(mkproject true "acme/projects")
echo "$out" | grep -q '^- (none — standalone unless --parent specified)$' || fail "expected standalone line, got: $out"
pass "empty → standalone line"

echo; echo "All epics.sh tests passed."
