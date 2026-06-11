#!/usr/bin/env bash
# Structural tests for skills/init/SKILL.md project detection (Step 2a-2).
# Markdown skill blocks are LLM-executed, not directly runnable, so we
# anchor the contract via grep on the spec file.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
INIT_MD="$REPO_ROOT/skills/init/SKILL.md"

fail() { echo "FAIL: $1" >&2; exit 1; }
pass() { echo "  ok: $1"; }

echo "test: Step 2a-2 references the URL-parser helper"
grep -q "parse-project-url.sh" "$INIT_MD" \
  || fail "expected skills/init/SKILL.md to reference parse-project-url.sh"
pass "parse-project-url.sh referenced"

echo "test: Step 2a-2 has an empty-case URL prompt branch"
grep -q "paste its URL" "$INIT_MD" \
  || fail "expected an empty-case URL prompt in skills/init/SKILL.md"
pass "empty-case URL prompt present"

echo "test: Step 2a-2 notes closed/hidden project case"
step2a2=$(awk '/^## Step 2a-2:/{flag=1} /^## Step /{if(flag && !/^## Step 2a-2:/) exit} flag' "$INIT_MD")
if ! echo "$step2a2" | grep -Eq "closed|hidden"; then
  fail "expected a closed/hidden project note inside Step 2a-2"
fi
pass "closed-project note present in Step 2a-2"

echo "test: Step 9b verification does NOT use organization(login:)"
# Extract Step 9b block. The block starts at the Step 9b heading and ends at the
# next "## Step" heading.
step9b=$(awk '/^## Step 9b:/{flag=1} /^## Step /{if(flag && !/^## Step 9b:/) exit} flag' "$INIT_MD")
if echo "$step9b" | grep -q "organization(login:"; then
  fail "Step 9b still uses organization(login:) — should use gh project field-list"
fi
pass "Step 9b verification is owner-agnostic"

echo
echo "All sillok-init detection structural tests passed."
