#!/usr/bin/env bash
# Lint: open-Stories/Epics lookups must use the Search API (#41).
#
# GitHub's GraphQL IssueFilters input object has NO issueType argument — a query
# using filterBy:{issueType} is rejected with argumentNotAccepted, and the
# script's error masking turned that into a silently empty "Open epics" list.
# The Search API's `type:` qualifier is the supported server-side filter.
# Checked repo-wide across scripts/ so any future duplicated lookup
# (e.g. precompute-add.sh, which copies the open-epics block) regresses loudly.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$REPO_ROOT/scripts/precompute-start.sh"
ADD_SCRIPT="$REPO_ROOT/scripts/precompute-add.sh"

fail() { echo "FAIL: $1" >&2; exit 1; }
pass() { echo "  ok: $1"; }

# 1. The non-existent GraphQL argument must not reappear — anywhere in scripts/.
if grep -rE 'filterBy:.*issueType' "$REPO_ROOT/scripts/" >/dev/null; then
  fail "a script under scripts/ uses filterBy:{issueType} — IssueFilters has no such argument (#41): $(grep -rlE 'filterBy:.*issueType' "$REPO_ROOT/scripts/" | tr '\n' ' ')"
fi
pass "no filterBy:{issueType} usage anywhere under scripts/"

# 2. Both org-mode call sites use the Search API with the type: qualifier.
grep -F 'type:Story' "$SCRIPT" >/dev/null || fail "Story query missing type:Story search qualifier"
pass "Story query uses type:Story"

grep -F 'type:Epic' "$SCRIPT" >/dev/null || fail "Epic query missing type:Epic search qualifier"
pass "Epic query uses type:Epic"

[[ "$(grep -c 'search(query:' "$SCRIPT")" -ge 2 ]] \
  || fail "expected both Story and Epic call sites to use search(query: ...)"
pass "both call sites use search(query: ...)"

# 3. Failures must be visible — graceful degradation with a stderr warning.
# The warning must go to stderr: precompute stdout is a markdown contract.
grep -F 'open-epics query failed' "$SCRIPT" >/dev/null \
  || fail "missing stderr warning on open-epics query failure (silent masking is how #41 shipped unnoticed)"
while IFS= read -r warn_line; do
  case "$warn_line" in
    *'>&2'*) : ;;
    *) fail "open-epics warning must be redirected to stderr (>&2) — stdout is markdown-only: $warn_line" ;;
  esac
done < <(grep -F 'open-epics query failed' "$SCRIPT")
pass "stderr warning present on query failure (and redirected with >&2)"

# 4. precompute-add.sh duplicates the open-epics lookup — hold it to the same
# contract: Search API queries plus a visible stderr warning on failure.
grep -F 'search(query:' "$ADD_SCRIPT" >/dev/null \
  || fail "precompute-add.sh open-epics lookup must use search(query: ...) like precompute-start.sh (#41)"
pass "precompute-add.sh uses search(query: ...)"

grep -F 'open-epics query failed' "$ADD_SCRIPT" >/dev/null \
  || fail "precompute-add.sh missing stderr warning on open-epics query failure"
while IFS= read -r warn_line; do
  case "$warn_line" in
    *'>&2'*) : ;;
    *) fail "precompute-add open-epics warning must be redirected to stderr (>&2): $warn_line" ;;
  esac
done < <(grep -F 'open-epics query failed' "$ADD_SCRIPT")
pass "precompute-add.sh stderr warning present on query failure (and redirected with >&2)"

echo
echo "All precompute query lint checks passed."
