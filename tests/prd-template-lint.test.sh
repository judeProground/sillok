#!/usr/bin/env bash
# Lint: skills/epic/prd-template.md must exist and contain the required validation
# checklist content — 5 required H1 section names, all 9 frontmatter keys, and
# the literal strings "block" and "frontmatter".
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SUBFILE="$REPO_ROOT/skills/epic/prd-template.md"

fail() { echo "FAIL: $1" >&2; exit 1; }
pass() { echo "  ok: $1"; }

# --- file existence ---
[[ -f "$SUBFILE" ]] || fail "skills/epic/prd-template.md does not exist"
pass "skills/epic/prd-template.md exists"

# --- 5 required H1 section names ---
echo "test: required H1 section names"
for section in "배경" "목표" "실행" "AI Agent Role" "평가"; do
  grep -q "$section" "$SUBFILE" \
    || fail "section '$section' not found in prd-template.md"
  pass "section '$section' present"
done

# --- 9 frontmatter keys ---
echo "test: 9 frontmatter metadata keys"
for key in feature_goal task_type sprint dev_period owners status metric release_date eval_dates; do
  grep -q "$key" "$SUBFILE" \
    || fail "frontmatter key '$key' not found in prd-template.md"
  pass "key '$key' present"
done

# --- required strings ---
echo "test: required strings 'block' and 'frontmatter'"
grep -q "block" "$SUBFILE" \
  || fail "string 'block' not found in prd-template.md"
pass "string 'block' present"

grep -q "frontmatter" "$SUBFILE" \
  || fail "string 'frontmatter' not found in prd-template.md"
pass "string 'frontmatter' present"

echo
echo "All prd-template-lint checks passed."
