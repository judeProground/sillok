#!/usr/bin/env bash
# sillok — Open epics discovery helpers.
# Provides sillok_open_epics_section, which prints the ### Open epics markdown
# block (header + bullets) consumed by precompute-start and precompute-story.
set -euo pipefail

# Resolve this file's directory under bash AND zsh (nounset-safe), so the
# plugin root can be derived when CLAUDE_PLUGIN_ROOT is not exported.
# zsh: ${(%):-%x} expands to the file currently being sourced; eval defers
# the zsh-only syntax so bash never parses it.
if [[ -n "${BASH_VERSION:-}" ]]; then
  _SILLOK_LIB_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
elif [[ -n "${ZSH_VERSION:-}" ]]; then
  eval '_SILLOK_LIB_DIR=$(cd "$(dirname "${(%):-%x}")" && pwd)'
else
  _SILLOK_LIB_DIR=$(cd "$(dirname "$0")" && pwd)
fi
# shellcheck source=config.sh
source "$_SILLOK_LIB_DIR/config.sh"

# Print the ### Open epics markdown block to stdout.
# Reads repo, orgMode, and epicRepo from sillok_config.
# gh failures degrade gracefully to an empty list with a stderr warning.
# epicRepo candidates are listed first, then local stories.
sillok_open_epics_section() {
  echo "### Open epics"

  local repo org_mode epic_repo local_stories epic_candidates
  repo=$(sillok_config repo)
  org_mode=$(sillok_config orgMode)

  if [ "$org_mode" = "true" ]; then
    local_stories=$(gh api graphql \
      -f query="{ search(query: \"repo:$repo is:issue is:open type:Story\", type: ISSUE, first: 20) {
        nodes { ... on Issue { number title } }
      } }" --jq '.data.search.nodes[]? | "  - (in this repo) #\(.number) [Story] \(.title)"' 2>/dev/null) || {
      echo "[sillok] open-epics query failed (type:Story, repo $repo) — continuing with empty list" >&2
      local_stories=""
    }
  else
    local_stories=$(gh issue list --repo "$repo" --label story --state open --limit 20 --json number,title \
      --jq '.[]? | "  - (in this repo) #\(.number) [story] \(.title)"' 2>/dev/null || echo "")
  fi

  epic_repo=$(sillok_config epicRepo)
  epic_candidates=""
  if [ -n "$epic_repo" ]; then
    if [ "$org_mode" = "true" ]; then
      epic_candidates=$(gh api graphql \
        -f query="{ search(query: \"repo:$epic_repo is:issue is:open type:Epic\", type: ISSUE, first: 20) {
          nodes { ... on Issue { number title } }
        } }" --jq ".data.search.nodes[]? | \"  - (in $epic_repo) #\(.number) [Epic] \(.title)\"" 2>/dev/null) || {
        echo "[sillok] open-epics query failed (type:Epic, repo $epic_repo) — continuing with empty list" >&2
        epic_candidates=""
      }
    else
      epic_candidates=$(gh issue list --repo "$epic_repo" --label epic --state open --limit 20 --json number,title \
        --jq ".[]? | \"  - (in $epic_repo) #\(.number) [epic] \(.title)\"" 2>/dev/null || echo "")
    fi
  fi

  if [ -z "$local_stories" ] && [ -z "$epic_candidates" ]; then
    echo "- (none — standalone unless --parent specified)"
  else
    [ -n "$epic_candidates" ] && printf '%s\n' "$epic_candidates"
    [ -n "$local_stories" ] && printf '%s\n' "$local_stories"
  fi

  # A bare `[ -n ... ] && printf` as the function's last command leaks the
  # test's exit status as the return value — 1 whenever that list is empty,
  # killing set -e callers (precompute-start/add/story) mid-output.
  return 0
}
