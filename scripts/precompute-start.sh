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

# Abort hint: already mid-feature on another issue (any sillok type EXCEPT
# story — starting a sub-feature FROM the story integration worktree is the
# documented loop, so a story branch is a sanctioned starting point).
prefix_regex=$(sillok_branch_prefix_regex)
if [[ -n "$prefix_regex" && "$branch" =~ ^${prefix_regex}([0-9]+)- ]]; then
  # The template may inject capture groups (e.g. {type} alternation), so walk
  # BASH_REMATCH from index 1: the first numeric capture is the issue number,
  # the first non-numeric capture is the matched type token.
  matched_n=""
  matched_type=""
  for cap in "${BASH_REMATCH[@]:1}"; do
    if [[ "$cap" =~ ^[0-9]+$ ]]; then
      if [[ -z "$matched_n" ]]; then
        matched_n="$cap"
      fi
    elif [[ -z "$matched_type" ]]; then
      matched_type="$cap"
    fi
  done
  if [[ "$matched_type" == "story" ]]; then
    echo "- STORY-BRANCH: \`$branch\` (issue #${matched_n:-?}) — sanctioned starting point for \`--parent ${matched_n:-<N>}\`"
  else
    echo "- ABORT: already on issue branch for #${matched_n:-?} — finish or stash before starting a new feature"
    exit 0
  fi
fi

# Open epics (for parent suggestion)
echo
echo "### Open epics"

# Local-repo stories/epics (for parent suggestion).
# orgMode=true: query by Issue Type. orgMode=false: query by label fallback.
ORG_MODE=$(sillok_config orgMode)
if [[ "$ORG_MODE" == "true" ]]; then
  # IssueFilters has no issueType argument (#41) — the Search API's type:
  # qualifier is the supported server-side filter for Issue Types.
  local_stories=$(gh api graphql \
    -f query="{ search(query: \"repo:$REPO is:issue is:open type:Story\", type: ISSUE, first: 20) {
      nodes { ... on Issue { number title } }
    } }" --jq '.data.search.nodes[]? | "  - (in this repo) #\(.number) [Story] \(.title)"' 2>/dev/null) || {
    echo "[precompute-start] open-epics query failed (type:Story, repo $REPO) — continuing with empty list" >&2
    local_stories=""
  }
else
  # User repo: Issue Types unavailable. Fall back to label-based query.
  local_stories=$(gh issue list --repo "$REPO" --label story --state open --limit 20 --json number,title \
    --jq '.[]? | "  - (in this repo) #\(.number) [story] \(.title)"' 2>/dev/null || echo "")
fi

# Cross-repo PRD epics from prdRepo, if configured.
PRD_REPO=$(sillok_config prdRepo)
prd_epics=""
if [[ -n "$PRD_REPO" ]]; then
  if [[ "$ORG_MODE" == "true" ]]; then
    prd_epics=$(gh api graphql \
      -f query="{ search(query: \"repo:$PRD_REPO is:issue is:open type:Epic\", type: ISSUE, first: 20) {
        nodes { ... on Issue { number title } }
      } }" --jq ".data.search.nodes[]? | \"  - (in $PRD_REPO) #\(.number) [Epic] \(.title)\"" 2>/dev/null) || {
      echo "[precompute-start] open-epics query failed (type:Epic, repo $PRD_REPO) — continuing with empty list" >&2
      prd_epics=""
    }
  else
    prd_epics=$(gh issue list --repo "$PRD_REPO" --label epic --state open --limit 20 --json number,title \
      --jq ".[]? | \"  - (in $PRD_REPO) #\(.number) [epic] \(.title)\"" 2>/dev/null || echo "")
  fi
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

# Language preference
echo
echo "### Language"
LANG_PREF=$(sillok_config language)
echo "- Config: \`${LANG_PREF:-auto}\`"

exit 0
