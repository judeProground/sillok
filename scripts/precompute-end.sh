#!/usr/bin/env bash
# sillok — precompute deterministic state for /sillok-end.
# Outputs branch + mode + issue meta + project status + plan stats (task completion)
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
prefix_regex=$(sillok_branch_prefix_regex)
if [[ -n "$prefix_regex" && "$branch" =~ ^${prefix_regex}([0-9]+)-(.+)$ ]]; then
  # Walk BASH_REMATCH from index 1: find first numeric (issue#), next capture (slug),
  # and also remember the matched type token (if any) so we can detect story-finalize mode.
  n=""
  slug=""
  matched_type=""
  seen_n=0
  for cap in "${BASH_REMATCH[@]:1}"; do
    if [[ "$seen_n" == "0" && "$cap" =~ ^[0-9]+$ ]]; then
      n="$cap"
      seen_n=1
    elif [[ "$seen_n" == "0" ]]; then
      # First non-numeric cap before the issue number = the {type} alternation match
      matched_type="$cap"
    elif [[ "$seen_n" == "1" ]]; then
      slug="$cap"
      break
    fi
  done

  if [[ "$matched_type" == "story" ]]; then
    # Story-finalize mode: branch is the integration branch story/issue-N-slug.
    # PR target = configured baseBranch; merge strategy = merge (not squash) to
    # preserve sub-feature commits.
    echo
    echo "### Mode: story-finalize"
    echo "- Story issue: #$n"
    echo "- Branch (integration): \`$branch\`"
    echo "- Merge strategy: merge (preserves sub-feature commits)"
    echo "- PR base: $(sillok_config baseBranch)"

    # List sub-feature issues that have closed PRs (for the PR body)
    sub_issues=$(gh api graphql -f query="{
      repository(owner: \"${REPO%%/*}\", name: \"${REPO##*/}\") {
        issue(number: $n) {
          subIssues(first: 50) {
            nodes { number title state }
          }
        }
      }
    }" --jq '.data.repository.issue.subIssues.nodes[]? | "- #\(.number) \(.title) [\(.state)]"' 2>/dev/null || echo "")

    if [[ -n "$sub_issues" ]]; then
      echo
      echo "### Sub-issues"
      printf '%s\n' "$sub_issues"
    fi

  else
    # Single-issue mode (sub-feature, bug, improvement, or infra branch).
    echo
    echo "### Mode: single-issue"
    echo "- Active issue #: $n"
    echo "- Slug: \`$slug\`"

    if issue_json=$(gh issue view "$n" --repo "$REPO" --json title,labels,body 2>/dev/null); then
      title=$(echo "$issue_json" | jq -r '.title')
      labels=$(echo "$issue_json" | jq -r '[.labels[].name] | join(", ")')
      echo "- Title: $title"
      echo "- Labels: $labels"

      # Parent reference — supports both same-repo (`Parent: #N`) and
      # cross-repo (`Parent: owner/repo#N`) forms.
      parent_line=$(echo "$issue_json" | jq -r '.body' | grep -m1 -E '^Parent:' || true)
      parent_m=""
      if [[ "$parent_line" =~ Parent:[[:space:]]+([^/]+/[^#]+)#([0-9]+) ]]; then
        parent_m="${BASH_REMATCH[1]}#${BASH_REMATCH[2]}"
      elif [[ "$parent_line" =~ Parent:[[:space:]]+#([0-9]+) ]]; then
        parent_m="${BASH_REMATCH[1]}"
      fi
      if [[ -z "$parent_m" ]]; then
        echo "- Parent: none (standalone)"
      elif [[ "$parent_m" == *"#"* ]]; then
        echo "- Parent: $parent_m (cross-repo PRD)"
      else
        echo "- Parent: #$parent_m (sub-issue)"
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

echo
echo "### Project status"
source "${SCRIPT_DIR}/lib/project.sh" 2>/dev/null || true
if command -v sillok_project_item_for_issue >/dev/null 2>&1; then
  if [[ -n "${n:-}" ]]; then
    item_id=$(sillok_project_item_for_issue "https://github.com/$REPO/issues/$n")
    if [[ -n "$item_id" ]]; then
      status=$(sillok_project_status_get "$item_id" || echo "")
      echo "- Item ID: $item_id"
      echo "- Status: ${status:-unknown}"
    fi
  fi
fi

# Language preference
echo
echo "### Language"
LANG_PREF=$(sillok_config language)
echo "- Config: \`${LANG_PREF:-auto}\`"

exit 0
