#!/usr/bin/env bash
# Structural tests for sillok-init.md config/rules migration (Steps 6 & 7).
# Markdown command blocks are LLM-executed, not directly runnable, so we anchor
# the contract via grep on the spec file.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
INIT_MD="$REPO_ROOT/commands/sillok-init.md"

fail() { echo "FAIL: $1" >&2; exit 1; }
pass() { echo "  ok: $1"; }

echo "test: Step 6 calls migrate-config.sh"
grep -q "migrate-config.sh" "$INIT_MD" \
  || fail "expected sillok-init.md to call migrate-config.sh"
pass "migrate-config.sh referenced"

echo "test: Step 7 calls refresh-rules.sh"
grep -q "refresh-rules.sh" "$INIT_MD" \
  || fail "expected sillok-init.md to call refresh-rules.sh"
pass "refresh-rules.sh referenced"

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
