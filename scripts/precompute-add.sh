#!/usr/bin/env bash
# sillok — precompute deterministic state for /sillok-add (backlog capture).
# Deliberately NO branch guard and NO sprint-milestone section: capture must
# work from ANY branch (mid-session discovery), and backlog issues are not
# sprint-committed (the milestone is attached later, at adopt time).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/config.sh
source "$SCRIPT_DIR/lib/config.sh"

REPO=$(sillok_config_required repo)

need_missing=""
for cmd in git gh jq; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    need_missing="$need_missing $cmd"
  fi
done
if [[ -n "$need_missing" ]]; then
  echo "[precompute-add] missing tools:$need_missing" >&2
  exit 1
fi

branch=$(git branch --show-current 2>/dev/null || echo "")

echo "## precomputed state for /sillok-add"
echo
echo "- Current branch: \`$branch\` (no guard — capture is allowed from any branch)"

# Open epics/stories (for optional parent suggestion) — same lookup as
# precompute-start.sh, kept duplicated: the two scripts diverge on guards
# and sections, and bash has no cheap shared-fragment mechanism beyond lib/.
echo
echo "### Open epics"

ORG_MODE=$(sillok_config orgMode)
if [[ "$ORG_MODE" == "true" ]]; then
  local_stories=$(gh api graphql -H "X-GitHub-Api-Version: 2026-03-10" \
    -f query="{ repository(owner: \"${REPO%%/*}\", name: \"${REPO##*/}\") {
      issues(first: 20, states: OPEN, filterBy: {issueType: \"Story\"}) {
        nodes { number title }
      }
    } }" --jq '.data.repository.issues.nodes[]? | "  - (in this repo) #\(.number) [Story] \(.title)"' 2>/dev/null || echo "")
else
  local_stories=$(gh issue list --repo "$REPO" --label story --state open --limit 20 --json number,title \
    --jq '.[]? | "  - (in this repo) #\(.number) [story] \(.title)"' 2>/dev/null || echo "")
fi

PRD_REPO=$(sillok_config prdRepo)
prd_epics=""
if [[ -n "$PRD_REPO" ]]; then
  if [[ "$ORG_MODE" == "true" ]]; then
    prd_epics=$(gh api graphql -H "X-GitHub-Api-Version: 2026-03-10" \
      -f query="{ repository(owner: \"${PRD_REPO%%/*}\", name: \"${PRD_REPO##*/}\") {
        issues(first: 20, states: OPEN, filterBy: {issueType: \"Epic\"}) {
          nodes { number title }
        }
      } }" --jq ".data.repository.issues.nodes[]? | \"  - (in $PRD_REPO) #\(.number) [Epic] \(.title)\"" 2>/dev/null || echo "")
  else
    prd_epics=$(gh issue list --repo "$PRD_REPO" --label epic --state open --limit 20 --json number,title \
      --jq ".[]? | \"  - (in $PRD_REPO) #\(.number) [epic] \(.title)\"" 2>/dev/null || echo "")
  fi
fi

if [[ -z "$local_stories" && -z "$prd_epics" ]]; then
  echo "- (none — standalone unless a parent is requested)"
else
  if [[ -n "$prd_epics" ]]; then
    printf '%s\n' "$prd_epics"
  fi
  if [[ -n "$local_stories" ]]; then
    printf '%s\n' "$local_stories"
  fi
fi

# Language preference
echo
echo "### Language"
LANG_PREF=$(sillok_config language)
echo "- Config: \`${LANG_PREF:-auto}\`"

exit 0
