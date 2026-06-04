#!/usr/bin/env bash
# Structural tests for sillok-init.md project detection (Step 2a-2).
# Markdown command blocks are LLM-executed, not directly runnable, so we
# anchor the contract via grep on the spec file.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
INIT_MD="$REPO_ROOT/commands/sillok-init.md"

fail() { echo "FAIL: $1" >&2; exit 1; }
pass() { echo "  ok: $1"; }

echo "test: Step 2a-2 references the URL-parser helper"
grep -q "parse-project-url.sh" "$INIT_MD" \
  || fail "expected commands/sillok-init.md to reference parse-project-url.sh"
pass "parse-project-url.sh referenced"

echo "test: Step 2a-2 has an empty-case URL prompt branch"
grep -q "paste its URL" "$INIT_MD" \
  || fail "expected an empty-case URL prompt in sillok-init.md"
pass "empty-case URL prompt present"

echo "test: Step 2a-2 notes closed/hidden project case"
grep -Eq "closed|hidden" "$INIT_MD" \
  || fail "expected a closed/hidden project note when totalCount > 0 but list empty"
pass "closed-project note present"

echo
echo "All sillok-init detection structural tests passed."
