#!/usr/bin/env bash
# sillok — precompute deterministic state for /sillok-design.
# Outputs current branch + mode (single-issue / umbrella / other), issue
# metadata, current stage label, spec existence, and a CWD warning if the
# session is not actually inside the expected worktree (common after session
# resume — git/gh work fine but file paths break silently).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/config.sh
source "$SCRIPT_DIR/lib/config.sh"

REPO=$(sillok_config_required repo)
BRANCH_PREFIX=$(sillok_config_required branchPrefix)
SPEC_DIR=$(sillok_config docs.specs)
SPEC_DIR=${SPEC_DIR:-docs/superpowers/specs}

need_missing=""
for cmd in git gh jq; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    need_missing="$need_missing $cmd"
  fi
done
if [[ -n "$need_missing" ]]; then
  echo "[precompute-design] missing tools:$need_missing" >&2
  exit 1
fi

branch=$(git branch --show-current 2>/dev/null || echo "")

echo "## precomputed state for /sillok-design"
echo
echo "- Current branch: \`$branch\`"

# CWD vs worktree check — git itself works from any worktree dir, but issue/spec
# file paths are relative to the worktree root, so the LLM must cd in first.
expected_worktree=$(git worktree list --porcelain 2>/dev/null \
  | awk -v b="refs/heads/$branch" '/^worktree/{wt=$2} /^branch/{if($2==b){print wt; exit}}')
current_pwd=$(pwd)
if [[ -n "$expected_worktree" && "$current_pwd" != "$expected_worktree" ]]; then
  echo "- ⚠️  CWD MISMATCH: pwd=\`$current_pwd\`, expected=\`$expected_worktree\`"
  echo "  EXEC FIRST: \`cd $expected_worktree\`"
elif [[ -n "$expected_worktree" ]]; then
  echo "- CWD: ✓ in worktree (\`$expected_worktree\`)"
fi

# Mode detection
ESCAPED_PREFIX=$(printf '%s' "$BRANCH_PREFIX" | sed -e 's/[]\/$*.^[]/\\&/g')
if [[ "$branch" =~ ^${ESCAPED_PREFIX}([0-9]+)-(.+)$ ]]; then
  n="${BASH_REMATCH[1]}"
  slug="${BASH_REMATCH[2]}"
  echo
  echo "### Mode: single-issue"
  echo "- Issue #: $n"
  echo "- Slug: \`$slug\`"

  if issue_json=$(gh issue view "$n" --repo "$REPO" --json title,labels 2>/dev/null); then
    title=$(echo "$issue_json" | jq -r '.title')
    labels=$(echo "$issue_json" | jq -r '[.labels[].name] | join(", ")')
    echo "- Title: $title"
    echo "- Labels: $labels"

    stage=$(echo "$issue_json" \
      | jq -r '[.labels[].name] | map(select(. == "backlog" or . == "todo" or . == "designed" or . == "in-progress" or . == "in-review")) | .[0] // "none"')
    echo "- Stage: \`$stage\`"

    case "$stage" in
      todo) ;;
      designed)
        echo "- ⚠️  Stage already \`designed\` — spec exists. Run \`/sillok-execute\` instead, or confirm redesign with user."
        ;;
      in-progress|in-review)
        echo "- ⚠️  Stage \`$stage\` — design phase normally complete. Confirm intent with user before proceeding."
        ;;
      *)
        echo "- ⚠️  Stage \`$stage\` — unexpected for design step."
        ;;
    esac
  else
    echo "- ⚠️  \`gh issue view #$n\` failed (auth?) — LLM must fetch manually"
  fi

  # Spec existence — slug-only glob (any earlier date matches)
  echo
  echo "### Spec existence"
  spec_match=$(ls "$SPEC_DIR"/*-"$slug".md 2>/dev/null | head -1 || true)
  if [[ -n "$spec_match" ]]; then
    echo "- Found: \`$spec_match\` — prompt user: continue / overwrite / cancel"
  else
    echo "- None — will create at \`$SPEC_DIR/$(date +%Y-%m-%d)-$slug.md\`"
  fi

elif [[ "$branch" =~ ^feature/(.+)$ ]]; then
  umbrella="${BASH_REMATCH[1]}"
  echo
  echo "### Mode: umbrella"
  echo "- Umbrella: \`feature/$umbrella\`"
  echo "- LLM must prompt user for which active sub-issue to design (no single \`<N>\` derivable from branch alone)."
else
  echo
  echo "- ⚠️  Branch \`$branch\` does not match the configured branch prefix or \`feature/...\` — workflow not applicable; abort."
fi

exit 0
