#!/usr/bin/env bash
# Lint: every commands/sillok-*.md is a pointer wrapper (story #15, sub-issue #58).
#
# After the skill-wrapper refactor, command bodies live in skills/<stage>/SKILL.md;
# each command file is a version-stable pointer: frontmatter `description` plus one
# prose line invoking the skill. Wrappers must not depend on `$ARGUMENTS`
# substitution (consumer shims raw-read the wrapper) and must not carry
# `${CLAUDE_PLUGIN_ROOT}` or procedural step content.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

fail() { echo "FAIL: $1" >&2; exit 1; }
pass() { echo "  ok: $1"; }

# Print the YAML frontmatter block (between the first two `---` lines).
frontmatter() {
  awk 'NR==1 && $0=="---"{inside=1; next} inside && $0=="---"{exit} inside{print}' "$1"
}

expected=(sillok-start sillok-add sillok-design sillok-execute sillok-end sillok-story sillok-init)

checked=0
for name in "${expected[@]}"; do
  cmd_md="$REPO_ROOT/commands/$name.md"
  rel="commands/$name.md"
  [[ -f "$cmd_md" ]] || fail "$rel missing — all seven commands must exist as wrappers"
  checked=$((checked + 1))

  fm=$(frontmatter "$cmd_md")
  [[ -n "$fm" ]] || fail "$rel: missing YAML frontmatter"
  echo "$fm" | grep -q '^description:' \
    || fail "$rel: frontmatter must carry a 'description' (shown in the command menu)"

  lines=$(wc -l < "$cmd_md" | tr -d ' ')
  [[ "$lines" -le 15 ]] \
    || fail "$rel: $lines lines — pointer wrappers must be <= 15 lines (body belongs in skills/)"

  stage="${name#sillok-}"
  grep -Fq "Invoke the \`sillok:$stage\`" "$cmd_md" \
    || fail "$rel: must invoke its MATCHING stage skill (missing 'Invoke the \`sillok:$stage\`')"

  grep -Fq 'follow it exactly' "$cmd_md" \
    || fail "$rel: must instruct to follow the skill exactly"

  grep -Fq '${CLAUDE_PLUGIN_ROOT}' "$cmd_md" \
    && fail "$rel: contains \${CLAUDE_PLUGIN_ROOT} — script invocations belong in SKILL.md bodies"

  grep -Fq '$ARGUMENTS' "$cmd_md" \
    && fail "$rel: contains \$ARGUMENTS — wrappers must use prose argument pass-through (consumer shims raw-read them)"

  grep -Fq '## Step' "$cmd_md" \
    && fail "$rel: contains '## Step' — procedural content must live in skills/, not the wrapper"

  pass "$rel is a pointer wrapper"
done

echo
echo "All command-wrapper lint checks passed ($checked wrapper(s) checked)."
