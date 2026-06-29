#!/usr/bin/env bash
# sillok — precompute deterministic state for /sillok-add (backlog capture).
# Deliberately NO branch guard and NO sprint-milestone section: capture must
# work from ANY branch (mid-session discovery), and backlog issues are not
# sprint-committed (the milestone is attached later, at adopt time).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/config.sh
source "$SCRIPT_DIR/lib/config.sh"
# shellcheck source=lib/epics.sh
source "$SCRIPT_DIR/lib/epics.sh"

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

# Open epics/stories (for optional parent suggestion) — delegated to lib/epics.sh.
echo
sillok_open_epics_section

# Language preference
echo
echo "### Language"
LANG_PREF=$(sillok_config language)
echo "- Config: \`${LANG_PREF:-auto}\`"

exit 0
