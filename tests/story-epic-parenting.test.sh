#!/usr/bin/env bash
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MD="$REPO_ROOT/skills/story/SKILL.md"
fail() { echo "FAIL: $1" >&2; exit 1; }
pass() { echo "  ok: $1"; }

grep -q 'precompute-story.sh' "$MD" || fail "story skill must run precompute-story.sh"
grep -q -- '--parent' "$MD" || fail "story skill must document --parent"
# Sub-issue linking: accept the inline addSubIssue mutation OR the extracted
# sillok_subissue_link helper (W3, #43) — the invariant moved into scripts/lib/subissue.sh.
grep -qE 'addSubIssue|sillok_subissue_link' "$MD" || fail "story skill must link epic via addSubIssue / sillok_subissue_link"
grep -qi 'Open epics' "$MD" || fail "story skill must read Open epics"
grep -q 'standalone' "$MD" || fail "story skill must offer standalone"
grep -qiE 'preserve|보존' "$MD" || fail "promotion must preserve an existing parent"
echo; echo "story epic-parenting contract present."
