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

echo "test: project verification is owner-agnostic (gh project field-list, not organization(login:))"
# The real project-verify call now lives in scripts/init-bootstrap.sh (phase2);
# SKILL.md only describes it. Guard the IMPLEMENTATION, not just the prose — the
# owner-scoped GraphQL query (organization(login:) breaks user-owned boards (#39),
# so it must never reappear in the script that actually runs the check.
BOOT="$REPO_ROOT/scripts/init-bootstrap.sh"
grep -q "gh project field-list" "$BOOT" \
  || fail "init-bootstrap.sh should verify the project via 'gh project field-list'"
if grep -q "organization(login:" "$BOOT"; then
  fail "init-bootstrap.sh uses organization(login:) — must use gh project field-list (owner-scoped query breaks user boards)"
fi
if grep -q "organization(login:" "$INIT_MD"; then
  fail "skills/init/SKILL.md mentions organization(login: — owner-scoped query is wrong"
fi
pass "project verification is owner-agnostic (script + skill)"

echo
echo "All sillok-init detection structural tests passed."
