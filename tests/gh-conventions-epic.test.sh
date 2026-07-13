#!/usr/bin/env bash
# Structural tests for the Epic template section of skills/gh-issue-management/body-templates.md.
# The Epic body is intentionally LIGHT (Summary + Metadata + PRD link — not the full PRD inline).
# Markdown is LLM-consumed, not runnable, so we anchor the contract via grep.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONV_MD="$REPO_ROOT/skills/gh-issue-management/body-templates.md"

fail() { echo "FAIL: $1" >&2; exit 1; }
pass() { echo "  ok: $1"; }

# Extract the Epic template section (from the heading to the next ### heading).
epic_section=$(awk '/^### Epic template/{flag=1} /^### /{if(flag && !/^### Epic template/) exit} flag' "$CONV_MD")

[[ -n "$epic_section" ]] || fail "Epic template section not found in $CONV_MD"

echo "test: Epic section contains '## Summary' body block"
echo "$epic_section" | grep -q '## Summary' \
  || fail "expected '## Summary' in Epic template section"
pass "## Summary present"

echo "test: Epic section contains '## Metadata' body block"
echo "$epic_section" | grep -q '## Metadata' \
  || fail "expected '## Metadata' in Epic template section"
pass "## Metadata present"

echo "test: Epic section contains '## PRD' body block"
echo "$epic_section" | grep -q '## PRD' \
  || fail "expected '## PRD' in Epic template section"
pass "## PRD present"

echo "test: Epic section references Notion link (원본 or Notion)"
echo "$epic_section" | grep -qE '원본|Notion' \
  || fail "expected a Notion/원본 link reference in Epic template section"
pass "Notion/원본 reference present"

echo "test: Epic section references the PRD path (prd.md or 위치)"
echo "$epic_section" | grep -qiE 'prd\.md|위치' \
  || fail "expected a PRD path (prd.md / 위치) reference in Epic template section"
pass "PRD path reference present"

echo "test: Epic section conveys that the full PRD is NOT inline (not inline or link)"
echo "$epic_section" | grep -qiE 'not inline|NOT inline|not.*full.*prd|full prd.*not|inline.*않|않.*inline|박제하지|link' \
  || fail "expected an explicit 'not inline' / link-only note in Epic template section"
pass "not-inline intent stated"

echo "test: Epic section references team PRD section 배경"
echo "$epic_section" | grep -q '배경' \
  || fail "expected '배경' (Background section name) in Epic template section"
pass "배경 section referenced"

echo "test: Epic section references team PRD section 목표"
echo "$epic_section" | grep -q '목표' \
  || fail "expected '목표' (Goal section name) in Epic template section"
pass "목표 section referenced"

echo "test: Epic section references team PRD section 실행"
echo "$epic_section" | grep -q '실행' \
  || fail "expected '실행' (Execution section name) in Epic template section"
pass "실행 section referenced"

echo "test: Epic section references team PRD section 평가"
echo "$epic_section" | grep -q '평가' \
  || fail "expected '평가' (Evaluation section name) in Epic template section"
pass "평가 section referenced"

echo "test: Epic section references /sillok-epic command"
echo "$epic_section" | grep -q 'sillok-epic' \
  || fail "expected '/sillok-epic' reference in Epic template section"
pass "/sillok-epic referenced"

echo "test: Epic section references epicRepo or prd repo"
echo "$epic_section" | grep -qiE 'epicRepo|prd repo|prd_repo' \
  || fail "expected epicRepo reference in Epic template section"
pass "epicRepo referenced"

echo
echo "All gh-conventions Epic template structural tests passed."
