#!/usr/bin/env bash
# Structural tests for skills/init/SKILL.md config/rules migration (Steps 6 & 7).
# Markdown skill blocks are LLM-executed, not directly runnable, so we anchor
# the contract via grep on the spec file.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
INIT_MD="$REPO_ROOT/skills/init/SKILL.md"

fail() { echo "FAIL: $1" >&2; exit 1; }
pass() { echo "  ok: $1"; }

# The real invocations now live in scripts/init-bootstrap.sh (phase1); SKILL.md
# only describes them. Guard the IMPLEMENTATION so dropping the call is actually
# caught (a prose-only grep on SKILL.md would silently keep passing).
BOOT="$REPO_ROOT/scripts/init-bootstrap.sh"

echo "test: phase1 invokes migrate-config.sh (and the skill documents it)"
grep -q "migrate-config.sh" "$BOOT" \
  || fail "expected scripts/init-bootstrap.sh to invoke migrate-config.sh"
grep -q "migrate-config.sh" "$INIT_MD" \
  || fail "expected skills/init/SKILL.md to document migrate-config.sh"
pass "migrate-config.sh invoked (script) + documented (skill)"

echo "test: phase1 invokes refresh-rules.sh (and the skill documents it)"
grep -q "refresh-rules.sh" "$BOOT" \
  || fail "expected scripts/init-bootstrap.sh to invoke refresh-rules.sh"
grep -q "refresh-rules.sh" "$INIT_MD" \
  || fail "expected skills/init/SKILL.md to document refresh-rules.sh"
pass "refresh-rules.sh invoked (script) + documented (skill)"

echo "test: old skip-if-exists config notice is gone"
grep -q "already exists — leaving as-is" "$INIT_MD" \
  && fail "old config skip notice still present"
pass "config skip notice removed"

echo "test: SKIPPED_RULES accumulator is gone"
grep -q "SKIPPED_RULES" "$INIT_MD" \
  && fail "SKIPPED_RULES still present"
pass "SKIPPED_RULES removed"

echo "test: CONFIG_STATUS legend lists 'migrated'"
grep -q "migrated" "$INIT_MD" \
  || fail "expected CONFIG_STATUS legend to include 'migrated'"
pass "migrated status present"

echo
echo "All sillok-init migration structural tests passed."
