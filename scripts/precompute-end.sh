#!/usr/bin/env bash
# sillok — precompute deterministic state for /sillok-end.
# Outputs branch + mode + issue meta + stage + plan stats (task completion)
# + existing PR + parent reference + CWD check.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/config.sh
source "$SCRIPT_DIR/lib/config.sh"

REPO=$(sillok_config_required repo)
BRANCH_PREFIX=$(sillok_config_required branchPrefix)
PLAN_DIR=$(sillok_config docs.plans)
PLAN_DIR=${PLAN_DIR:-docs/superpowers/plans}

need_missing=""
for cmd in git gh jq; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    need_missing="$need_missing $cmd"
  fi
done
if [[ -n "$need_missing" ]]; then
  echo "[precompute-end] missing tools:$need_missing" >&2
  exit 1
fi

branch=$(git branch --show-current 2>/dev/null || echo "")

echo "## precomputed state for /sillok-end"
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
ESCAPED_PREFIX=$(printf '%s' "$BRANCH_PREFIX" | sed -e 's/[]\/$*.^[]/\\&/g')
if [[ "$branch" =~ ^${ESCAPED_PREFIX}([0-9]+)-(.+)$ ]]; then
  n="${BASH_REMATCH[1]}"
  slug="${BASH_REMATCH[2]}"
  echo
  echo "### Mode: single-issue"
  echo "- Active issue #: $n"
  echo "- Slug: \`$slug\`"

  if issue_json=$(gh issue view "$n" --repo "$REPO" --json title,labels,body 2>/dev/null); then
    title=$(echo "$issue_json" | jq -r '.title')
    labels=$(echo "$issue_json" | jq -r '[.labels[].name] | join(", ")')
    echo "- Title: $title"
    echo "- Labels: $labels"

    stage=$(echo "$issue_json" \
      | jq -r '[.labels[].name] | map(select(. == "backlog" or . == "todo" or . == "designed" or . == "in-progress" or . == "in-review")) | .[0] // "none"')
    echo "- Stage: \`$stage\`"

    case "$stage" in
      in-progress) ;;
      in-review)
        echo "- ⚠️  Stage \`in-review\` — PR likely already exists. Will detect below."
        ;;
      *)
        echo "- ⚠️  Stage \`$stage\` — expected \`in-progress\`. ABORT or fix label."
        ;;
    esac

    # Parent reference (sub-issue case)
    parent_m=$(echo "$issue_json" | jq -r '.body' | (grep -oE '^Parent: #[0-9]+' || true) | head -1 | sed 's/Parent: #//')
    if [[ -n "$parent_m" ]]; then
      echo "- Parent: #$parent_m (sub-issue)"
    else
      echo "- Parent: none (standalone)"
    fi
  else
    echo "- ⚠️  \`gh issue view #$n\` failed (auth?) — LLM must fetch manually"
  fi

  # Plan existence + task completion stats
  echo
  echo "### Plan"
  plan_match=$(ls "$PLAN_DIR"/*-"$slug".md 2>/dev/null | sort | tail -1 || true)
  if [[ -n "$plan_match" ]]; then
    echo "- Path: \`$plan_match\`"
    open_count=$(grep -c '^- \[ \]' "$plan_match" 2>/dev/null || true)
    done_count=$(grep -c '^- \[x\]' "$plan_match" 2>/dev/null || true)
    open_count=${open_count:-0}
    done_count=${done_count:-0}
    echo "- Tasks: $done_count done / $open_count open"
    if [[ "$open_count" != "0" ]]; then
      echo "- ⚠️  $open_count open task(s) — confirm with user before proceeding (allowed to punt to follow-up)."
    fi
  else
    echo "- ⚠️  No plan found at \`$PLAN_DIR/*-$slug.md\`. ABORT or run \`/sillok-execute\` first."
  fi

  # Existing PR
  echo
  echo "### Existing PR"
  pr_json=$(gh pr list --repo "$REPO" --head "$branch" --json number,url,state 2>/dev/null || echo "[]")
  pr_count=$(echo "$pr_json" | jq 'length')
  if [[ "$pr_count" == "0" ]]; then
    echo "- None — will create."
  else
    pr_url=$(echo "$pr_json" | jq -r '.[0].url')
    pr_state=$(echo "$pr_json" | jq -r '.[0].state')
    echo "- Found: $pr_url (state: $pr_state) — prompt user: update body/labels only, or skip."
  fi

elif [[ "$branch" =~ ^feature/(.+)$ ]]; then
  umbrella="${BASH_REMATCH[1]}"
  echo
  echo "### Mode: umbrella"
  echo "- Umbrella: \`feature/$umbrella\`"
  echo "- LLM must prompt user for which sub-issue is closing with this PR (no single \`<N>\` derivable)."
  echo "- LLM must also list other still-open sub-issues of the umbrella's parent and add \`Closes #N\` lines for each."
else
  echo
  echo "- ⚠️  Branch \`$branch\` does not match the configured branch prefix or \`feature/...\` — workflow not applicable; abort."
fi

# Working tree drift (informational — does not auto-stash)
echo
echo "### Working tree"
dirty=$(git status --porcelain 2>/dev/null)
if [[ -z "$dirty" ]]; then
  echo "- Clean ✓"
else
  echo "- Dirty (lines below). Decide commit / stash / abort with user before pushing:"
  echo "$dirty" | sed 's/^/    /'
fi

exit 0
