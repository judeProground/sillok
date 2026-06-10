#!/usr/bin/env bash
# Lint: stage-skill SKILL.md frontmatter contract (story #15, sub-issue #56).
#
# Stage skills (start/design/execute/end/story/init) must:
#   - have `name:` matching their directory name
#   - declare `user-invocable: false` (single auto-fire entry point — design decision 8)
#   - have a NEUTRAL description that does NOT start with "Use when"
# The orchestrator (skills/workflow) is the ONLY skill whose description starts
# with "Use when". Stage dirs that don't exist yet are skipped, so this test
# stays green as sub-issues C/D add more skills.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

fail() { echo "FAIL: $1" >&2; exit 1; }
pass() { echo "  ok: $1"; }

# Print the YAML frontmatter block (between the first two `---` lines).
frontmatter() {
  awk 'NR==1 && $0=="---"{inside=1; next} inside && $0=="---"{exit} inside{print}' "$1"
}

description_of() {
  frontmatter "$1" | sed -n 's/^description:[[:space:]]*//p' | head -1
}

checked=0
for stage in start design execute end story init; do
  skill_md="$REPO_ROOT/skills/$stage/SKILL.md"
  [[ -f "$skill_md" ]] || continue
  checked=$((checked + 1))

  fm=$(frontmatter "$skill_md")
  [[ -n "$fm" ]] || fail "skills/$stage/SKILL.md: missing YAML frontmatter"

  echo "$fm" | grep -q "^name: ${stage}$" \
    || fail "skills/$stage/SKILL.md: frontmatter 'name' must be exactly '$stage'"

  echo "$fm" | grep -q '^user-invocable: false$' \
    || fail "skills/$stage/SKILL.md: stage skills must declare 'user-invocable: false'"

  desc=$(description_of "$skill_md")
  [[ -n "$desc" ]] || fail "skills/$stage/SKILL.md: missing 'description' in frontmatter"
  case "$desc" in
    "Use when"*)
      fail "skills/$stage/SKILL.md: stage-skill description must be neutral — 'Use when' trigger phrasing belongs to sillok:workflow only"
      ;;
  esac

  pass "skills/$stage/SKILL.md frontmatter contract"
done

if [[ "$checked" -eq 0 ]]; then
  echo "  note: no stage-skill dirs exist yet — nothing to lint"
fi

# Orchestrator: the ONLY skill with a "Use when..." trigger description.
workflow_md="$REPO_ROOT/skills/workflow/SKILL.md"
if [[ -f "$workflow_md" ]]; then
  desc=$(description_of "$workflow_md")
  case "$desc" in
    "Use when"*) pass "skills/workflow/SKILL.md description starts with 'Use when'" ;;
    *) fail "skills/workflow/SKILL.md: orchestrator description must start with 'Use when'" ;;
  esac
else
  echo "  note: skills/workflow/SKILL.md absent on this branch — skipping orchestrator check"
fi

echo
echo "All skill-frontmatter lint checks passed ($checked stage skill(s) checked)."
