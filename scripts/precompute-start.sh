#!/usr/bin/env bash
# sillok — precompute deterministic state for /sillok-start.
# Outputs a markdown block listing: current branch, open epics, computed sprint
# milestone (and whether it already exists in the repo). The command body reads
# this once instead of running 3 separate tool round-trips.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/config.sh
source "$SCRIPT_DIR/lib/config.sh"

REPO=$(sillok_config_required repo)
BRANCH_PREFIX=$(sillok_config_required branchPrefix)

need_missing=""
for cmd in git gh jq date; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    need_missing="$need_missing $cmd"
  fi
done
if [[ -n "$need_missing" ]]; then
  echo "[precompute-start] missing tools:$need_missing" >&2
  exit 1
fi

branch=$(git branch --show-current 2>/dev/null || echo "")

echo "## precomputed state for /sillok-start"
echo
echo "- Current branch: \`$branch\`"

# Abort hint: already mid-feature on another issue (any sillok type)
prefix_regex=$(sillok_branch_prefix_regex)
if [[ -n "$prefix_regex" && "$branch" =~ ^${prefix_regex}([0-9]+)- ]]; then
  # The template may inject capture groups (e.g. {type} alternation), so the
  # issue number is the first numeric capture in BASH_REMATCH from index 1.
  matched_n=""
  for cap in "${BASH_REMATCH[@]:1}"; do
    if [[ -z "$matched_n" && "$cap" =~ ^[0-9]+$ ]]; then
      matched_n="$cap"
    fi
  done
  echo "- ABORT: already on issue branch for #${matched_n:-?} — finish or stash before starting a new feature"
  exit 0
fi

# Open epics (for parent suggestion)
echo
echo "### Open epics"

# Local-repo stories (formerly epics). Still relevant for in-repo composite work.
local_stories=$(gh api graphql -H "X-GitHub-Api-Version: 2026-03-10" \
  -f query="{ repository(owner: \"${REPO%%/*}\", name: \"${REPO##*/}\") {
    issues(first: 20, states: OPEN, filterBy: {issueType: \"Story\"}) {
      nodes { number title }
    }
  } }" --jq '.data.repository.issues.nodes[]? | "  - (in this repo) #\(.number) \(.title)"' 2>/dev/null || echo "")

# Cross-repo PRD epics from prdRepo, if configured.
PRD_REPO=$(sillok_config prdRepo)
prd_epics=""
if [[ -n "$PRD_REPO" ]]; then
  prd_epics=$(gh api graphql -H "X-GitHub-Api-Version: 2026-03-10" \
    -f query="{ repository(owner: \"${PRD_REPO%%/*}\", name: \"${PRD_REPO##*/}\") {
      issues(first: 20, states: OPEN, filterBy: {issueType: \"Epic\"}) {
        nodes { number title }
      }
    } }" --jq ".data.repository.issues.nodes[]? | \"  - (in $PRD_REPO) #\(.number) \(.title)\"" 2>/dev/null || echo "")
fi

if [[ -z "$local_stories" && -z "$prd_epics" ]]; then
  echo "- (none — standalone unless --parent specified)"
else
  if [[ -n "$prd_epics" ]]; then
    printf '%s\n' "$prd_epics"
  fi
  if [[ -n "$local_stories" ]]; then
    printf '%s\n' "$local_stories"
  fi
fi

# Sprint milestone: YYYY-MM-Wn where n = ceil(sprint_start_day / 7), sprint starts Monday
echo
echo "### Sprint milestone"
dow=$(date +%u)                                  # 1=Mon ... 7=Sun
monday=$(date -v-$((dow - 1))d +%Y-%m-%d)        # most recent Monday (today if today is Monday)
monday_day=$(date -j -f "%Y-%m-%d" "$monday" +%d | sed 's/^0*//')
monday_year=$(date -j -f "%Y-%m-%d" "$monday" +%Y)
monday_month=$(date -j -f "%Y-%m-%d" "$monday" +%m)
week_n=$(( (monday_day + 6) / 7 ))
milestone="${monday_year}-${monday_month}-W${week_n}"
echo "- Computed: \`$milestone\` (sprint start: $monday)"

ms_number=$(gh api "repos/$REPO/milestones" \
  --jq ".[] | select(.state==\"open\" and .title==\"$milestone\") | .number" 2>/dev/null || echo "")
if [[ -n "$ms_number" ]]; then
  echo "- Exists in repo: yes (number $ms_number)"
else
  echo "- Exists in repo: no (prompt user to create)"
fi

exit 0
