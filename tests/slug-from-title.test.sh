#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$REPO_ROOT/scripts/slug-from-title.sh"

fail() { echo "FAIL: $1" >&2; exit 1; }
pass() { echo "  ok: $1"; }

run_case() {
  local n="$1"; local title="$2"; local expected="$3"
  local actual
  actual=$("$SCRIPT" "$n" "$title")
  [[ "$actual" == "$expected" ]] || fail "input='$title' expected='$expected' got='$actual'"
  pass "$title → $expected"
}

run_case 79  "Add haptic feedback to record button" "79-add-haptic-feedback-to-record-button"
run_case 12  "The Quick Brown Fox"                    "12-quick-brown-fox"
run_case 1   "A Quick Test"                           "1-quick-test"
run_case 42  "Fix: timer NaN issue"                   "42-fix-timer-nan-issue"
run_case 102 "Implement comprehensive analytics dashboard for tracking user engagement" \
             "102-implement-comprehensive-analytics"

# Empty-slug guard: titles that reduce to "" fall back to issue-<N>.
run_case 10  "The"                                    "10-issue-10"
run_case 11  '!@#$%'                                  "11-issue-11"
# Non-ASCII (e.g. Korean) titles are stripped by the alnum filter; the guard
# prevents a trailing-hyphen branch. (Commands translate to English upstream;
# this is the defensive fallback if a raw non-ASCII title reaches the script.)
run_case 42  "녹음 버튼에 햅틱 피드백 추가"           "42-issue-42"

echo
echo "All slug-from-title.sh tests passed."
