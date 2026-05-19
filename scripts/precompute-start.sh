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

# Abort hint: already mid-feature on another issue
ESCAPED_PREFIX=$(printf '%s' "$BRANCH_PREFIX" | sed -e 's/[]\/$*.^[]/\\&/g')
if [[ "$branch" =~ ^${ESCAPED_PREFIX}([0-9]+)- ]]; then
  echo "- ABORT: already on issue branch for #${BASH_REMATCH[1]} — finish or stash before starting a new feature"
  exit 0
fi

# Open epics (for parent suggestion)
echo
echo "### Open epics"
epics_json=$(gh issue list --repo "$REPO" --label epic --state open --json number,title --limit 10 2>/dev/null || echo "[]")
if [[ "$(echo "$epics_json" | jq 'length')" == "0" ]]; then
  echo "- (none — standalone unless --parent specified)"
else
  echo "$epics_json" | jq -r '.[] | "- #\(.number) \(.title)"'
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
