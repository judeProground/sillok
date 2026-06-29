#!/usr/bin/env bash
# precompute-story.sh — state derivation for /sillok-story.
# Classifies the current branch (standalone / promotion / already-on-story ABORT)
# and emits open epics for parent suggestion + the language setting.
set -euo pipefail
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=lib/config.sh
source "$SCRIPT_DIR/lib/config.sh"
# shellcheck source=lib/epics.sh
source "$SCRIPT_DIR/lib/epics.sh"

REPO=$(sillok_config_required repo)
prefix_regex=$(sillok_branch_prefix_regex)
branch=$(git branch --show-current 2>/dev/null || echo "")

echo "## precomputed state for /sillok-story"
echo
echo "- Current branch: \`${branch:-<detached>}\`"
echo
echo "### Mode"

if [[ "$branch" =~ ^story/issue-([0-9]+)- ]]; then
  echo "- ABORT: already on a story branch (\`$branch\`). To add a sub-feature run \`/sillok-start --parent <N>\`."
elif [[ -n "$prefix_regex" && "$branch" =~ ^${prefix_regex}([0-9]+)-(.+)$ ]]; then
  # {type} alternation injects a capture group BEFORE the issue number; walk
  # BASH_REMATCH for the first numeric capture (the issue) then the slug.
  n=""; slug=""
  for cap in "${BASH_REMATCH[@]:1}"; do
    if [[ -z "$n" && "$cap" =~ ^[0-9]+$ ]]; then n="$cap"; continue; fi
    if [[ -n "$n" && -z "$slug" && -n "$cap" ]]; then slug="$cap"; fi
  done
  echo "- promotion"
  echo "- Issue #: ${n:-?}"
  echo "- Slug: \`${slug:-?}\`"
else
  echo "- standalone"
fi

echo
sillok_open_epics_section

echo
echo "### Language"
echo "- Config: \`$(sillok_config language)\`"
