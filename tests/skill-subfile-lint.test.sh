#!/usr/bin/env bash
# Lint: skill subfiles must not contain ${CLAUDE_PLUGIN_ROOT} (story #15, sub-issue #56).
#
# Claude Code substitutes ${CLAUDE_PLUGIN_ROOT} in SKILL.md bodies ONLY; subfiles
# are read raw, so the literal would leak into the conversation unexpanded.
# Every script invocation must live in SKILL.md; subfiles are pure templates/prose.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

fail() { echo "FAIL: $1" >&2; exit 1; }
pass() { echo "  ok: $1"; }

checked=0
bad=0
while IFS= read -r f; do
  checked=$((checked + 1))
  if grep -Fq '${CLAUDE_PLUGIN_ROOT}' "$f"; then
    echo "FAIL: ${f#"$REPO_ROOT"/} contains \${CLAUDE_PLUGIN_ROOT} (substitution only happens in SKILL.md bodies — subfiles are read raw)" >&2
    bad=$((bad + 1))
  else
    pass "${f#"$REPO_ROOT"/} clean"
  fi
done < <(find "$REPO_ROOT/skills" -mindepth 2 -name '*.md' ! -name 'SKILL.md' | sort)

[[ "$bad" -eq 0 ]] || exit 1

echo
echo "All skill-subfile lint checks passed ($checked subfile(s) checked)."
