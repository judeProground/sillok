#!/usr/bin/env bash
# sillok — precompute deterministic state for /sillok-design.
# Outputs current branch + mode (single-issue / umbrella / other), issue
# metadata, project status, spec existence, and a CWD warning if the
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
prefix_regex=$(sillok_branch_prefix_regex)
if [[ -n "$prefix_regex" && "$branch" =~ ^${prefix_regex}([0-9]+)-(.+)$ ]]; then
  # Walk BASH_REMATCH from index 1: find first numeric (issue#) and the next capture (slug).
  n=""
  slug=""
  seen_n=0
  for cap in "${BASH_REMATCH[@]:1}"; do
    if [[ "$seen_n" == "0" && "$cap" =~ ^[0-9]+$ ]]; then
      n="$cap"
      seen_n=1
    elif [[ "$seen_n" == "1" ]]; then
      slug="$cap"
      break
    fi
  done
  echo
  echo "### Mode: single-issue"
  echo "- Issue #: $n"
  echo "- Slug: \`$slug\`"

  if issue_json=$(gh issue view "$n" --repo "$REPO" --json title,labels,body 2>/dev/null); then
    title=$(echo "$issue_json" | jq -r '.title')
    labels=$(echo "$issue_json" | jq -r '[.labels[].name] | join(", ")')
    issue_body=$(echo "$issue_json" | jq -r '.body // ""')
    echo "- Title: $title"
    echo "- Labels: $labels"
  else
    echo "- ⚠️  \`gh issue view #$n\` failed (auth?) — LLM must fetch manually"
    issue_body=""
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

  # Parse parent (could be same-repo "Parent: #N" or cross-repo "Parent: owner/repo#N")
  parent_line=$(echo "$issue_body" | grep -m1 -E '^Parent:' || true)
  parent_repo=""
  parent_n=""
  if [[ "$parent_line" =~ Parent:[[:space:]]+([^/]+/[^#]+)#([0-9]+) ]]; then
    parent_repo="${BASH_REMATCH[1]}"
    parent_n="${BASH_REMATCH[2]}"
  elif [[ "$parent_line" =~ Parent:[[:space:]]+#([0-9]+) ]]; then
    parent_repo="$REPO"
    parent_n="${BASH_REMATCH[1]}"
  fi

  if [[ -n "$parent_n" ]]; then
    echo
    echo "### Parent"
    if [[ "$parent_repo" == "$REPO" ]]; then
      echo "- Same-repo parent: #$parent_n"
    else
      echo "- Cross-repo parent: $parent_repo#$parent_n (PRD epic)"
    fi
  fi

  # Project status
  echo
  echo "### Project status"
  # shellcheck source=lib/project.sh
  source "${SCRIPT_DIR}/lib/project.sh" 2>/dev/null || true
  if command -v sillok_project_item_for_issue >/dev/null 2>&1; then
    item_id=$(sillok_project_item_for_issue "https://github.com/$REPO/issues/$n" || echo "")
    if [[ -n "$item_id" ]]; then
      status=$(sillok_project_status_get "$item_id" || echo "")
      echo "- Item ID: $item_id"
      echo "- Status: ${status:-unknown}"
    else
      echo "- (not in project — will be added at /sillok-design step)"
    fi
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

# Language preference
echo
echo "### Language"
LANG_PREF=$(sillok_config language)
echo "- Config: \`${LANG_PREF:-auto}\`"

exit 0
