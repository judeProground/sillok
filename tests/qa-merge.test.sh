#!/usr/bin/env bash
# Tests for scripts/qa-merge.sh
#
# The script reads `qaBranch` from config, checks the branch on origin via
# `git ls-remote`, then POSTs to the GitHub merges API via `gh`. Each case runs
# in its own subshell with stubbed `git` (only ls-remote intercepted; everything
# else — including config.sh's `git rev-parse` — delegates to real git) and a
# stubbed `gh`, so no network is touched and the stubs never leak.
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
export CLAUDE_PLUGIN_ROOT="$REPO_ROOT"
SCRIPT="$REPO_ROOT/scripts/qa-merge.sh"

fail() { echo "FAIL: $1" >&2; exit 1; }
pass() { echo "  ok: $1"; }

[[ -f "$SCRIPT" ]] || fail "$SCRIPT does not exist"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# Build a real git project with a config carrying $qaBranch.
make_project() {  # $1 = qaBranch value
  local dir="$TMP/proj-$(echo "$1" | tr -cd '[:alnum:]')-$RANDOM"
  mkdir -p "$dir/.claude/sillok"
  (cd "$dir" && git init -q)
  printf '{ "repo": "acme/app", "qaBranch": "%s" }\n' "$1" > "$dir/.claude/sillok/workflow.config.json"
  echo "$dir"
}

# qa-merge.sh runs top-level code (not a function), so each case invokes it as a
# subprocess with git/gh defined as functions inside the same bash -c. Env in:
# PROJ, SCRIPT, LS_OUT (git ls-remote stdout),
# GH_MODE (success-201|success-204|http-409|http-404).
run_case() {  # $1=name $2=qaBranch $3=LS_OUT $4=GH_MODE ; sets OUT, RC
  local proj; proj=$(make_project "$2")
  set +e
  OUT=$(PROJ="$proj" SCRIPT="$SCRIPT" LS_OUT="$3" GH_MODE="$4" \
    bash -c '
      cd "$PROJ"
      git() { if [[ "${1:-}" == "ls-remote" ]]; then [[ -n "$LS_OUT" ]] && printf "%s\n" "$LS_OUT"; return 0; fi; command git "$@"; }
      gh() {
        case "$GH_MODE" in
          success-201) printf "{\"sha\":\"abc123def\",\"merged\":true}\n"; return 0 ;;
          success-204) return 0 ;;
          http-409) echo "gh: Merge conflict (HTTP 409)" >&2; return 1 ;;
          http-404) echo "gh: Not Found (HTTP 404)" >&2; return 1 ;;
        esac
      }
      export -f git gh
      bash "$SCRIPT" acme/app feature/issue-76-x 76
    ' 2>&1)
  RC=$?
  set -e
}

# --- Case 1: not configured -> skipped, exit 0, no gh call -------------------
run_case "not-configured" "" "" "unused"
[[ $RC -eq 0 ]] || fail "case1: expected rc 0, got $RC"
echo "$OUT" | grep -q "QA-MERGE: skipped (not configured)" || { echo "$OUT"; fail "case1: wrong output"; }
pass "unconfigured qaBranch -> skipped"

# --- Case 2: configured but branch absent on origin -> skipped --------------
run_case "branch-absent" "deploy/qa" "" "success-201"
[[ $RC -eq 0 ]] || fail "case2: expected rc 0, got $RC"
echo "$OUT" | grep -q "QA-MERGE: skipped (branch 'deploy/qa' not found on origin)" || { echo "$OUT"; fail "case2: wrong output"; }
pass "missing origin branch -> skipped"

# --- Case 3: 201 Created -> merged with sha ---------------------------------
run_case "merged" "deploy/qa" "abc\trefs/heads/deploy/qa" "success-201"
[[ $RC -eq 0 ]] || fail "case3: expected rc 0, got $RC"
echo "$OUT" | grep -q "QA-MERGE: merged abc123def" || { echo "$OUT"; fail "case3: wrong output"; }
pass "201 -> merged <sha>"

# --- Case 4: 204 No Content -> already-up-to-date ---------------------------
run_case "up-to-date" "deploy/qa" "abc\trefs/heads/deploy/qa" "success-204"
[[ $RC -eq 0 ]] || fail "case4: expected rc 0, got $RC"
echo "$OUT" | grep -q "QA-MERGE: already-up-to-date" || { echo "$OUT"; fail "case4: wrong output"; }
pass "204 -> already-up-to-date"

# --- Case 5: 409 conflict -> conflict + manual steps, exit 0 ----------------
run_case "conflict" "deploy/qa" "abc\trefs/heads/deploy/qa" "http-409"
[[ $RC -eq 0 ]] || fail "case5: expected rc 0 (non-fatal), got $RC"
echo "$OUT" | grep -q "QA-MERGE: conflict" || { echo "$OUT"; fail "case5: missing conflict line"; }
echo "$OUT" | grep -q "git merge feature/issue-76-x" || { echo "$OUT"; fail "case5: missing manual steps"; }
pass "409 -> conflict + manual steps, exit 0"

# --- Case 6: 404/other failure -> failed, exit 0 ----------------------------
run_case "failed" "deploy/qa" "abc\trefs/heads/deploy/qa" "http-404"
[[ $RC -eq 0 ]] || fail "case6: expected rc 0 (non-fatal), got $RC"
echo "$OUT" | grep -q "QA-MERGE: failed" || { echo "$OUT"; fail "case6: missing failed line"; }
pass "404 -> failed, exit 0"

# --- Case 7: usage error (missing args) -> exit 2 ---------------------------
set +e
bash "$SCRIPT" acme/app >/dev/null 2>&1
rc=$?
set -e
[[ $rc -eq 2 ]] || fail "case7: expected rc 2 for missing args, got $rc"
pass "missing args -> exit 2"

echo
echo "All qa-merge.sh tests passed."
