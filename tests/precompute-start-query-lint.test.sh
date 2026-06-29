#!/usr/bin/env bash
# Lint: open-Stories/Epics lookups must use the Search API (#41) and must
# live exclusively in lib/epics.sh — precompute-*.sh files must all delegate.
#
# GitHub's GraphQL IssueFilters input object has NO issueType argument — a query
# using filterBy:{issueType} is rejected with argumentNotAccepted, and the
# script's error masking turned that into a silently empty "Open epics" list.
# The Search API's `type:` qualifier is the supported server-side filter.
# lib/epics.sh is the single canonical source; precompute-*.sh files must
# call sillok_open_epics_section instead of inlining their own gh queries.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
EPICS_LIB="$REPO_ROOT/scripts/lib/epics.sh"

fail() { echo "FAIL: $1" >&2; exit 1; }
pass() { echo "  ok: $1"; }

# 1. The non-existent GraphQL argument must not reappear — anywhere in scripts/.
if grep -rE 'filterBy:.*issueType' "$REPO_ROOT/scripts/" >/dev/null; then
  fail "a script under scripts/ uses filterBy:{issueType} — IssueFilters has no such argument (#41): $(grep -rlE 'filterBy:.*issueType' "$REPO_ROOT/scripts/" | tr '\n' ' ')"
fi
pass "no filterBy:{issueType} usage anywhere under scripts/"

# 2. lib/epics.sh uses the Search API with the type: qualifier.
grep -F 'type:Story' "$EPICS_LIB" >/dev/null || fail "epics.sh Story query missing type:Story search qualifier"
pass "epics.sh Story query uses type:Story"

grep -F 'type:Epic' "$EPICS_LIB" >/dev/null || fail "epics.sh Epic query missing type:Epic search qualifier"
pass "epics.sh Epic query uses type:Epic"

[[ "$(grep -c 'search(query:' "$EPICS_LIB")" -ge 2 ]] \
  || fail "expected both Story and Epic call sites in epics.sh to use search(query: ...)"
pass "epics.sh both call sites use search(query: ...)"

# 3. Failures must be visible — graceful degradation with a stderr warning.
# The warning must go to stderr: precompute stdout is a markdown contract.
grep -F 'open-epics query failed' "$EPICS_LIB" >/dev/null \
  || fail "epics.sh missing stderr warning on open-epics query failure (silent masking is how #41 shipped unnoticed)"
while IFS= read -r warn_line; do
  case "$warn_line" in
    *'>&2'*) : ;;
    *) fail "epics.sh open-epics warning must be redirected to stderr (>&2) — stdout is markdown-only: $warn_line" ;;
  esac
done < <(grep -F 'open-epics query failed' "$EPICS_LIB")
pass "epics.sh stderr warning present on query failure (and redirected with >&2)"

# 4. No precompute-*.sh file may inline its own search(query: ...) — all must
# delegate to sillok_open_epics_section in lib/epics.sh.
while IFS= read -r precompute_file; do
  if grep -F 'search(query:' "$precompute_file" >/dev/null 2>&1; then
    fail "$(basename "$precompute_file") contains an inline search(query: ...) — must delegate to sillok_open_epics_section in lib/epics.sh"
  fi
done < <(find "$REPO_ROOT/scripts" -maxdepth 1 -name 'precompute-*.sh')
pass "no precompute-*.sh file contains an inline search(query: ...)"

# 5. Both precompute-start.sh and precompute-add.sh must call sillok_open_epics_section.
grep -F 'sillok_open_epics_section' "$REPO_ROOT/scripts/precompute-start.sh" >/dev/null \
  || fail "precompute-start.sh must call sillok_open_epics_section"
pass "precompute-start.sh calls sillok_open_epics_section"

grep -F 'sillok_open_epics_section' "$REPO_ROOT/scripts/precompute-add.sh" >/dev/null \
  || fail "precompute-add.sh must call sillok_open_epics_section"
pass "precompute-add.sh calls sillok_open_epics_section"

echo
echo "All precompute query lint checks passed."
