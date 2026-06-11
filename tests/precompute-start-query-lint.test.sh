#!/usr/bin/env bash
# Lint: precompute-start.sh must query open Stories/Epics via the Search API (#41).
#
# GitHub's GraphQL IssueFilters input object has NO issueType argument — a query
# using filterBy:{issueType} is rejected with argumentNotAccepted, and the
# script's error masking turned that into a silently empty "Open epics" list.
# The Search API's `type:` qualifier is the supported server-side filter.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$REPO_ROOT/scripts/precompute-start.sh"

fail() { echo "FAIL: $1" >&2; exit 1; }
pass() { echo "  ok: $1"; }

# 1. The non-existent GraphQL argument must not reappear.
if grep -E 'filterBy:.*issueType' "$SCRIPT" >/dev/null; then
  fail "precompute-start.sh uses filterBy:{issueType} — IssueFilters has no such argument (#41)"
fi
pass "no filterBy:{issueType} usage"

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

echo
echo "All precompute-start query lint checks passed."
