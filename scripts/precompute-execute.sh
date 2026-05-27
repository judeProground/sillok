#!/usr/bin/env bash
# sillok — precompute deterministic state for /sillok-execute.
# Outputs current branch + mode + issue metadata + project status + spec existence +
# plan existence + CWD check. Same shape as precompute-design.sh but with
# spec REQUIRED (abort) and plan existence informational (write vs resume).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/config.sh
source "$SCRIPT_DIR/lib/config.sh"

REPO=$(sillok_config_required repo)
BRANCH_PREFIX=$(sillok_config_required branchPrefix)
SPEC_DIR=$(sillok_config docs.specs)
SPEC_DIR=${SPEC_DIR:-docs/superpowers/specs}
PLAN_DIR=$(sillok_config docs.plans)
PLAN_DIR=${PLAN_DIR:-docs/superpowers/plans}

need_missing=""
for cmd in git gh jq; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    need_missing="$need_missing $cmd"
  fi
done
if [[ -n "$need_missing" ]]; then
  echo "[precompute-execute] missing tools:$need_missing" >&2
  exit 1
fi

branch=$(git branch --show-current 2>/dev/null || echo "")

echo "## precomputed state for /sillok-execute"
echo
echo "- Current branch: \`$branch\`"

# CWD vs worktree check
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

  if issue_json=$(gh issue view "$n" --repo "$REPO" --json title,labels 2>/dev/null); then
    title=$(echo "$issue_json" | jq -r '.title')
    labels=$(echo "$issue_json" | jq -r '[.labels[].name] | join(", ")')
    echo "- Title: $title"
    echo "- Labels: $labels"
  else
    echo "- ⚠️  \`gh issue view #$n\` failed (auth?) — LLM must fetch manually"
  fi

  # Spec existence — REQUIRED.
  echo
  echo "### Spec"
  spec_match=$(ls "$SPEC_DIR"/*-"$slug".md 2>/dev/null | sort | tail -1 || true)
  if [[ -n "$spec_match" ]]; then
    echo "- Path: \`$spec_match\`"
  else
    echo "- ⚠️  Spec: none. ABORT: run \`/sillok-design\` first."
  fi

  # Plan existence — informational.
  echo
  echo "### Plan"
  plan_match=$(ls "$PLAN_DIR"/*-"$slug".md 2>/dev/null | sort | tail -1 || true)
  if [[ -n "$plan_match" ]]; then
    echo "- Path: \`$plan_match\` (plan already written; this is a resume — skip step 4)"
  else
    echo "- None — will create at \`$PLAN_DIR/$(date +%Y-%m-%d)-$slug.md\` (step 4)"
  fi

  # Project status
  echo
  echo "### Project status"
  # shellcheck source=lib/project.sh
  source "${SCRIPT_DIR}/lib/project.sh" 2>/dev/null || true
  if command -v sillok_project_item_for_issue >/dev/null 2>&1; then
    item_id=$(sillok_project_item_for_issue "https://github.com/$REPO/issues/$n")
    if [[ -n "$item_id" ]]; then
      status=$(sillok_project_status_get "$item_id" || echo "")
      echo "- Item ID: $item_id"
      echo "- Status: ${status:-unknown}"
    else
      echo "- (not in project)"
    fi
  fi

elif [[ "$branch" =~ ^feature/(.+)$ ]]; then
  umbrella="${BASH_REMATCH[1]}"
  echo
  echo "### Mode: umbrella"
  echo "- Umbrella: \`feature/$umbrella\`"
  echo "- LLM must prompt user for which active sub-issue to execute (no single \`<N>\` derivable from branch alone)."
else
  echo
  echo "- ⚠️  Branch \`$branch\` does not match the configured branch prefix or \`feature/...\` — workflow not applicable; abort."
fi

exit 0
