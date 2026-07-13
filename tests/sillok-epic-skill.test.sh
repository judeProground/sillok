#!/usr/bin/env bash
# Grep-anchor test for skills/epic/SKILL.md — verifies required literals
# and the absence of addSubIssue (sub-issue linking belongs to /sillok-start).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SKILL_MD="$REPO_ROOT/skills/epic/SKILL.md"

fail() { echo "FAIL: $1" >&2; exit 1; }
pass() { echo "  ok: $1"; }

[[ -f "$SKILL_MD" ]] || fail "skills/epic/SKILL.md does not exist"

# 1. Must invoke the precompute script
grep -q 'precompute-epic.sh' "$SKILL_MD" \
  || fail "skills/epic/SKILL.md: missing 'precompute-epic.sh' invocation"
pass "contains precompute-epic.sh"

# 2. Must read the validation checklist subfile
grep -q 'prd-template.md' "$SKILL_MD" \
  || fail "skills/epic/SKILL.md: missing 'prd-template.md' reference"
pass "contains prd-template.md"

# 3. Must set issue type via PATCH (type= assignment)
grep -q 'type=' "$SKILL_MD" \
  || fail "skills/epic/SKILL.md: missing 'type=' for Issue Type PATCH"
pass "contains type="

# 4. Must NOT link sub-issues — that is /sillok-start --parent's job
grep -q 'addSubIssue' "$SKILL_MD" \
  && fail "skills/epic/SKILL.md: must NOT contain 'addSubIssue' — sub-issue linking belongs to /sillok-start" \
  || true
pass "does not contain addSubIssue"

# 5. Must output the /sillok-start --parent command for next step
grep -q '/sillok-start --parent' "$SKILL_MD" \
  || fail "skills/epic/SKILL.md: missing '/sillok-start --parent' output line"
pass "contains /sillok-start --parent"

# 6. Must include the graceful Notion-MCP-absent message AND the marketplace install command
grep -q 'Notion MCP' "$SKILL_MD" \
  || fail "skills/epic/SKILL.md: missing Notion-MCP-absent graceful message"
grep -q '/mcp' "$SKILL_MD" \
  || fail "skills/epic/SKILL.md: Notion-absent message must tell users to install Notion MCP and authenticate via /mcp"
pass "contains Notion MCP absent message + marketplace install command"

echo
echo "All sillok-epic-skill checks passed."
