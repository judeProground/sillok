#!/usr/bin/env bash
# Tests for hooks/session-start.sh
#
# Hard contract under test: the hook ALWAYS exits 0 and produces ZERO
# stdout/stderr unless the CWD is inside a git repo with a valid
# .claude/sillok/workflow.config.json. When the config exists, it prints
# a compact context block (automation mode + branch ↔ issue) with no
# network or gh calls.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export CLAUDE_PLUGIN_ROOT="$REPO_ROOT"
HOOK="$REPO_ROOT/hooks/session-start.sh"

fail() { echo "FAIL: $1" >&2; exit 1; }
pass() { echo "  ok: $1"; }

[[ -f "$HOOK" ]] || fail "hook script not found at $HOOK"

# Run the hook from a given directory; captures stdout, stderr, exit code.
# Globals set: HOOK_OUT, HOOK_ERR, HOOK_RC
run_hook() {
  local dir="$1"
  local errfile
  errfile=$(mktemp)
  HOOK_RC=0
  HOOK_OUT=$(cd "$dir" && bash "$HOOK" 2>"$errfile") || HOOK_RC=$?
  HOOK_ERR=$(cat "$errfile")
  rm -f "$errfile"
}

make_git_repo() {
  local dir="$1"
  (
    cd "$dir"
    git init -q
    git config user.email "test@example.com"
    git config user.name "Test"
    git commit --allow-empty -q -m "init"
  )
}

echo "test: config present + issue branch → context block with mode and issue number"
TMP1=$(mktemp -d)
make_git_repo "$TMP1"
mkdir -p "$TMP1/.claude/sillok"
jq '.repo = "acme/widgets" | .branchPrefix = "{type}/issue-"' \
  "$REPO_ROOT/templates/workflow.config.json" > "$TMP1/.claude/sillok/workflow.config.json"
(cd "$TMP1" && git checkout -q -b feature/issue-77-test-thing)
run_hook "$TMP1"
[[ "$HOOK_RC" == "0" ]] || fail "expected exit 0, got $HOOK_RC"
echo "$HOOK_OUT" | grep -qi "propose" || fail "expected automation mode line (propose), got: $HOOK_OUT"
echo "$HOOK_OUT" | grep -q "#77" || fail "expected issue '#77' in output, got: $HOOK_OUT"
[[ -z "$HOOK_ERR" ]] || fail "expected empty stderr, got: $HOOK_ERR"
rm -rf "$TMP1"
pass "config + feature/issue-77 branch → mode line + #77, exit 0"

echo "test: automation.fullAuto true → output indicates full-auto"
TMP2=$(mktemp -d)
make_git_repo "$TMP2"
mkdir -p "$TMP2/.claude/sillok"
jq '.repo = "acme/widgets" | .branchPrefix = "{type}/issue-" | .automation = {"fullAuto": true}' \
  "$REPO_ROOT/templates/workflow.config.json" > "$TMP2/.claude/sillok/workflow.config.json"
(cd "$TMP2" && git checkout -q -b feature/issue-77-test-thing)
run_hook "$TMP2"
[[ "$HOOK_RC" == "0" ]] || fail "expected exit 0, got $HOOK_RC"
echo "$HOOK_OUT" | grep -qi "full-auto" || fail "expected full-auto indicator, got: $HOOK_OUT"
rm -rf "$TMP2"
pass "fullAuto: true → full-auto mode in output, exit 0"

echo "test: git repo WITHOUT config → silent, exit 0"
TMP3=$(mktemp -d)
make_git_repo "$TMP3"
run_hook "$TMP3"
[[ "$HOOK_RC" == "0" ]] || fail "expected exit 0, got $HOOK_RC"
[[ -z "$HOOK_OUT" ]] || fail "expected empty stdout, got: $HOOK_OUT"
[[ -z "$HOOK_ERR" ]] || fail "expected empty stderr, got: $HOOK_ERR"
rm -rf "$TMP3"
pass "no config → zero output, exit 0"

echo "test: non-git directory → silent, exit 0"
TMP4=$(mktemp -d)
run_hook "$TMP4"
[[ "$HOOK_RC" == "0" ]] || fail "expected exit 0, got $HOOK_RC"
[[ -z "$HOOK_OUT" ]] || fail "expected empty stdout, got: $HOOK_OUT"
[[ -z "$HOOK_ERR" ]] || fail "expected empty stderr, got: $HOOK_ERR"
rm -rf "$TMP4"
pass "non-git dir → zero output, exit 0"

echo "test: malformed config JSON → silent, exit 0"
TMP5=$(mktemp -d)
make_git_repo "$TMP5"
mkdir -p "$TMP5/.claude/sillok"
echo '{ "repo": "acme/widgets", broken' > "$TMP5/.claude/sillok/workflow.config.json"
run_hook "$TMP5"
[[ "$HOOK_RC" == "0" ]] || fail "expected exit 0, got $HOOK_RC"
[[ -z "$HOOK_OUT" ]] || fail "expected empty stdout, got: $HOOK_OUT"
[[ -z "$HOOK_ERR" ]] || fail "expected empty stderr, got: $HOOK_ERR"
rm -rf "$TMP5"
pass "malformed JSON → zero output, exit 0"

echo "test: config without automation key (pre-upgrade consumer) → propose mode, exit 0"
TMP6=$(mktemp -d)
make_git_repo "$TMP6"
mkdir -p "$TMP6/.claude/sillok"
jq '.repo = "acme/widgets" | .branchPrefix = "{type}/issue-" | del(.automation)' \
  "$REPO_ROOT/templates/workflow.config.json" > "$TMP6/.claude/sillok/workflow.config.json"
jq -e 'has("automation") | not' "$TMP6/.claude/sillok/workflow.config.json" >/dev/null \
  || fail "test setup broken: automation key still present"
(cd "$TMP6" && git checkout -q -b feature/issue-77-test-thing)
run_hook "$TMP6"
[[ "$HOOK_RC" == "0" ]] || fail "expected exit 0, got $HOOK_RC"
echo "$HOOK_OUT" | grep -qi "propose" || fail "expected propose-mode line for absent automation key, got: $HOOK_OUT"
[[ -z "$HOOK_ERR" ]] || fail "expected empty stderr, got: $HOOK_ERR"
rm -rf "$TMP6"
pass "del(.automation) config → propose mode fallback, exit 0"

echo "test: no-network contract — gh/curl stubs never invoked, output unchanged, exit 0"
TMP7=$(mktemp -d)
make_git_repo "$TMP7"
mkdir -p "$TMP7/.claude/sillok"
jq '.repo = "acme/widgets" | .branchPrefix = "{type}/issue-"' \
  "$REPO_ROOT/templates/workflow.config.json" > "$TMP7/.claude/sillok/workflow.config.json"
(cd "$TMP7" && git checkout -q -b feature/issue-77-test-thing)
STUB_BIN=$(mktemp -d)
SENTINEL="$STUB_BIN/network-was-called"
for tool in gh curl; do
  printf '#!/bin/sh\ntouch "%s"\nexit 1\n' "$SENTINEL" > "$STUB_BIN/$tool"
  chmod +x "$STUB_BIN/$tool"
done
# Stubs shadow real gh/curl; real git/jq/coreutils stay reachable via appended PATH.
ERRFILE=$(mktemp)
HOOK_RC=0
HOOK_OUT=$(cd "$TMP7" && PATH="$STUB_BIN:$PATH" bash "$HOOK" 2>"$ERRFILE") || HOOK_RC=$?
HOOK_ERR=$(cat "$ERRFILE")
rm -f "$ERRFILE"
[[ "$HOOK_RC" == "0" ]] || fail "expected exit 0 with gh/curl stubbed, got $HOOK_RC"
[[ ! -e "$SENTINEL" ]] || fail "hook invoked gh or curl (sentinel created) — no-network contract violated"
echo "$HOOK_OUT" | grep -qi "propose" || fail "expected automation mode line (propose) with stubs, got: $HOOK_OUT"
echo "$HOOK_OUT" | grep -q "#77" || fail "expected issue '#77' in output with stubs, got: $HOOK_OUT"
[[ -z "$HOOK_ERR" ]] || fail "expected empty stderr with stubs, got: $HOOK_ERR"
rm -rf "$TMP7" "$STUB_BIN"
pass "gh/curl stubbed to fail → never called, same output, exit 0"

echo
echo "All session-start-hook tests passed."
