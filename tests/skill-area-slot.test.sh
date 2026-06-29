#!/usr/bin/env bash
# Lint: the copyable create-issue.sh block in start/ and add/ skills must carry a
# visible `--label "area:<name>"` slot.
#
# Regression guard for the 3.x area-label bug (#50 / #51): when the slot was
# demoted from the copyable command block to a prose sentence, org-mode issues
# (type -> REST, priority -> board field) were created with ZERO labels, because
# the executing agent copies the command block, not the surrounding prose. This
# test asserts the slot stays in the block. `story` is intentionally NOT checked
# — Story/Epic parent issues carry no area/nature labels by convention.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

fail() { echo "FAIL: $1" >&2; exit 1; }
pass() { echo "  ok: $1"; }

checked=0
for stage in start add; do
  skill="$REPO_ROOT/skills/$stage/SKILL.md"
  rel="skills/$stage/SKILL.md"
  [[ -f "$skill" ]] || fail "$rel missing"

  grep -Fq 'scripts/create-issue.sh' "$skill" \
    || fail "$rel: no create-issue.sh invocation found"

  grep -qF -- '--label "area:<name>"' "$skill" \
    || fail "$rel: missing the '--label \"area:<name>\"' slot in the create-issue.sh block — org-mode issues would be created with no area label (3.x regression guard, see #50)"

  pass "$rel carries the --label \"area:<name>\" slot"
  checked=$((checked + 1))
done

echo "PASS: skill-area-slot ($checked skills checked)"
