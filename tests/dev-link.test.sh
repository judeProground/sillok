#!/usr/bin/env bash
# Tests for scripts/lib/dev-link.sh
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
export CLAUDE_PLUGIN_ROOT="$REPO_ROOT"
LIB="$REPO_ROOT/scripts/lib/dev-link.sh"

fail() { echo "FAIL: $1" >&2; exit 1; }
pass() { echo "  ok: $1"; }

[[ -f "$LIB" ]] || fail "$LIB does not exist"

echo "test: required functions exist"
result=$(bash -c "source '$LIB' && declare -F sillok_issue_node_id sillok_link_branch" 2>&1)
echo "$result" | grep -q "sillok_issue_node_id" || { echo "$result"; fail "missing sillok_issue_node_id"; }
echo "$result" | grep -q "sillok_link_branch" || { echo "$result"; fail "missing sillok_link_branch"; }
pass "required functions exist"

# ---------------------------------------------------------------------------
# Unit tests for sillok_link_branch with a stubbed gh (no network).
# Each case runs in its own bash -c subshell so the gh stub never leaks.
# The stub replaces gh entirely, so it emits exactly what `gh --jq` WOULD
# print: the mutation call (query contains createLinkedBranch) prints
# $MUT_OUT; the verification call (query contains linkedBranches) prints
# $VERIFY_OUT as newline-separated ref names.
# ---------------------------------------------------------------------------

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

BRANCH="feature/issue-7-x"

make_project() {  # $1 = orgMode value (true|false)
  local dir="$TMP/proj-$1"
  mkdir -p "$dir/.claude/sillok"
  (cd "$dir" && git init -q)
  printf '{ "orgMode": %s }\n' "$1" > "$dir/.claude/sillok/workflow.config.json"
  echo "$dir"
}

PROJ_ORG=$(make_project true)
PROJ_USER=$(make_project false)

# Shared case body for org-mode cases (a)(b)(c).
read -r -d '' CASE_ORG <<'EOS' || true
set -euo pipefail
cd "$PROJ"
gh() {
  local all="$*"
  if [[ "$all" == *createLinkedBranch* ]]; then
    printf '%s\n' "$MUT_OUT"
  elif [[ "$all" == *linkedBranches* ]]; then
    [[ -n "$VERIFY_OUT" ]] && printf '%s\n' "$VERIFY_OUT"
    true
  fi
}
source "$LIB"
sillok_link_branch "I_kwIssue1" "$BRANCH" "deadbeef"
EOS

echo "test: (a) mutation returns null -> rc 0 + 'NOT created' warning"
set +e
PROJ="$PROJ_ORG" LIB="$LIB" BRANCH="$BRANCH" MUT_OUT="null" VERIFY_OUT="" \
  bash -c "$CASE_ORG" >"$TMP/out_a" 2>"$TMP/err_a"
rc=$?
set -e
[[ $rc -eq 0 ]] || { cat "$TMP/err_a" >&2; fail "case a: expected rc 0, got $rc"; }
grep -q "NOT created" "$TMP/err_a" || { cat "$TMP/err_a" >&2; fail "case a: stderr missing 'NOT created'"; }
pass "null mutation -> rc 0, NOT created warning"

echo "test: (b) mutation returns id but verification misses branch -> 'verification failed' warning"
set +e
PROJ="$PROJ_ORG" LIB="$LIB" BRANCH="$BRANCH" MUT_OUT="LB_x" VERIFY_OUT="some-other-branch" \
  bash -c "$CASE_ORG" >"$TMP/out_b" 2>"$TMP/err_b"
rc=$?
set -e
[[ $rc -eq 0 ]] || { cat "$TMP/err_b" >&2; fail "case b: expected rc 0, got $rc"; }
grep -q "verification failed" "$TMP/err_b" || { cat "$TMP/err_b" >&2; fail "case b: stderr missing 'verification failed'"; }
pass "unverifiable link -> verification failed warning"

echo "test: (c) mutation returns id and verification lists branch -> rc 0, stderr empty"
set +e
PROJ="$PROJ_ORG" LIB="$LIB" BRANCH="$BRANCH" MUT_OUT="LB_x" VERIFY_OUT="$BRANCH" \
  bash -c "$CASE_ORG" >"$TMP/out_c" 2>"$TMP/err_c"
rc=$?
set -e
[[ $rc -eq 0 ]] || { cat "$TMP/err_c" >&2; fail "case c: expected rc 0, got $rc"; }
[[ ! -s "$TMP/err_c" ]] || { cat "$TMP/err_c" >&2; fail "case c: expected empty stderr"; }
pass "happy path -> rc 0, no warnings"

echo "test: (d) orgMode=false -> rc 0 and gh never invoked"
MARKER="$TMP/gh-was-called"
read -r -d '' CASE_USER <<'EOS' || true
set -euo pipefail
cd "$PROJ"
gh() { touch "$MARKER"; }
source "$LIB"
sillok_link_branch "I_kwIssue1" "$BRANCH" "deadbeef"
EOS
set +e
PROJ="$PROJ_USER" LIB="$LIB" BRANCH="$BRANCH" MARKER="$MARKER" \
  bash -c "$CASE_USER" >"$TMP/out_d" 2>"$TMP/err_d"
rc=$?
set -e
[[ $rc -eq 0 ]] || { cat "$TMP/err_d" >&2; fail "case d: expected rc 0, got $rc"; }
[[ ! -f "$MARKER" ]] || fail "case d: gh stub was invoked despite orgMode=false"
pass "orgMode=false -> no-op, gh untouched"

echo "test: (e) mutation call fails (gh exits 1) -> rc 0 + 'call failed' warning"
read -r -d '' CASE_FAIL <<'EOS' || true
set -euo pipefail
cd "$PROJ"
gh() {
  local all="$*"
  if [[ "$all" == *createLinkedBranch* ]]; then
    return 1
  fi
}
source "$LIB"
sillok_link_branch "I_kwIssue1" "$BRANCH" "deadbeef"
EOS
set +e
PROJ="$PROJ_ORG" LIB="$LIB" BRANCH="$BRANCH" \
  bash -c "$CASE_FAIL" >"$TMP/out_e" 2>"$TMP/err_e"
rc=$?
set -e
[[ $rc -eq 0 ]] || { cat "$TMP/err_e" >&2; fail "case e: expected rc 0, got $rc"; }
grep -q "call failed" "$TMP/err_e" || { cat "$TMP/err_e" >&2; fail "case e: stderr missing 'call failed'"; }
pass "failed mutation call -> rc 0, call failed warning"

echo "OK: all dev-link tests passed"
