#!/usr/bin/env bash
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MD="$REPO_ROOT/skills/story/SKILL.md"
fail() { echo "FAIL: $1" >&2; exit 1; }
pass() { echo "  ok: $1"; }

grep -q 'precompute-story.sh' "$MD" || fail "story skill must run precompute-story.sh"
grep -q -- '--parent' "$MD" || fail "story skill must document --parent"
grep -q 'addSubIssue' "$MD" || fail "story skill must link epic via addSubIssue"
grep -qi 'Open epics' "$MD" || fail "story skill must read Open epics"
grep -q 'standalone' "$MD" || fail "story skill must offer standalone"
grep -qiE 'preserve|보존' "$MD" || fail "promotion must preserve an existing parent"
echo; echo "story epic-parenting contract present."
