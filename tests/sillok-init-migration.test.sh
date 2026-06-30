#!/usr/bin/env bash
# Structural tests for skills/init/SKILL.md config/rules migration (Steps 6 & 7).
# Markdown skill blocks are LLM-executed, not directly runnable, so we anchor
# the contract via grep on the spec file.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
INIT_MD="$REPO_ROOT/skills/init/SKILL.md"
# W7 (#43): the per-step "Handled by phaseN → emits X" prose, the Step 11 summary
# template, and the Idempotency guarantees moved out of SKILL.md into this
# on-demand reference subfile. The skill keeps a pointer; the substance lives here.
PHASE_REF="$REPO_ROOT/skills/init/phase-reference.md"

fail() { echo "FAIL: $1" >&2; exit 1; }
pass() { echo "  ok: $1"; }

# The real invocations now live in scripts/init-bootstrap.sh (phase1); the skill
# only describes them. Guard the IMPLEMENTATION so dropping the call is actually
# caught (a prose-only grep would silently keep passing). The skill body keeps a
# pointer; the per-step contract lives in phase-reference.md.
BOOT="$REPO_ROOT/scripts/init-bootstrap.sh"

[[ -f "$PHASE_REF" ]] || fail "expected skills/init/phase-reference.md to exist (W7 disclosure)"

echo "test: phase1 invokes migrate-config.sh (and the skill points at the reference that documents it)"
grep -q "migrate-config.sh" "$BOOT" \
  || fail "expected scripts/init-bootstrap.sh to invoke migrate-config.sh"
grep -q "migrate-config.sh" "$INIT_MD" \
  || fail "expected skills/init/SKILL.md to keep a pointer mentioning migrate-config.sh"
grep -q "migrate-config.sh" "$PHASE_REF" \
  || fail "expected skills/init/phase-reference.md to document migrate-config.sh (Step 6)"
pass "migrate-config.sh invoked (script) + pointer (skill) + documented (reference)"

echo "test: phase1 invokes refresh-rules.sh (and the skill points at the reference that documents it)"
grep -q "refresh-rules.sh" "$BOOT" \
  || fail "expected scripts/init-bootstrap.sh to invoke refresh-rules.sh"
grep -q "refresh-rules.sh" "$INIT_MD" \
  || fail "expected skills/init/SKILL.md to keep a pointer mentioning refresh-rules.sh"
grep -q "refresh-rules.sh" "$PHASE_REF" \
  || fail "expected skills/init/phase-reference.md to document refresh-rules.sh (Step 7)"
pass "refresh-rules.sh invoked (script) + pointer (skill) + documented (reference)"

echo "test: old skip-if-exists config notice is gone (skill + reference)"
grep -q "already exists — leaving as-is" "$INIT_MD" \
  && fail "old config skip notice still present in SKILL.md"
grep -q "already exists — leaving as-is" "$PHASE_REF" \
  && fail "old config skip notice still present in phase-reference.md"
pass "config skip notice removed"

echo "test: SKIPPED_RULES accumulator is gone (skill + reference)"
grep -q "SKIPPED_RULES" "$INIT_MD" \
  && fail "SKIPPED_RULES still present in SKILL.md"
grep -q "SKIPPED_RULES" "$PHASE_REF" \
  && fail "SKIPPED_RULES still present in phase-reference.md"
pass "SKIPPED_RULES removed"

echo "test: CONFIG_STATUS legend lists 'migrated' (now in the reference)"
grep -q "migrated" "$PHASE_REF" \
  || fail "expected CONFIG_STATUS legend in phase-reference.md to include 'migrated'"
pass "migrated status present"

echo
echo "All sillok-init migration structural tests passed."
