#!/usr/bin/env bash
# sillok — GitHub Issue Types helpers.
# Wraps the 2026-03-10 REST API for org-level Issue Types.
#
# Requires gh CLI authenticated. All functions assume the active gh user has
# at minimum read scope on the org for ID lookups, and write scope (issue
# editor) for `_set` calls. Type CREATE/UPDATE/DELETE requires admin:org —
# sillok never calls those; admin sets up types out-of-band.
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=config.sh
source "$SCRIPT_DIR/config.sh"

# Cache for type IDs: avoids repeated API calls within one command run.
_SILLOK_TYPE_ID_CACHE=""

# Look up the org-level Issue Type ID by name.
# Usage: sillok_issue_type_id <type-name>
#   e.g. sillok_issue_type_id Story → "21731"
# Returns empty + non-zero exit if not found.
sillok_issue_type_id() {
  local name="$1"
  local repo owner

  repo=$(sillok_config_required repo) || return 1
  owner="${repo%%/*}"

  # Cache lookup: format is "Name:ID|Name:ID|..."
  if [[ -n "$_SILLOK_TYPE_ID_CACHE" ]]; then
    local cached
    cached=$(printf '%s' "$_SILLOK_TYPE_ID_CACHE" | tr '|' '\n' | awk -F: -v n="$name" '$1 == n { print $2; exit }')
    if [[ -n "$cached" ]]; then
      printf '%s' "$cached"
      return 0
    fi
  fi

  # Fetch all types for the org, build cache
  local types_json
  types_json=$(gh api -H "X-GitHub-Api-Version: 2026-03-10" "/orgs/$owner/issue-types" 2>/dev/null) || {
    echo "[sillok] failed to fetch issue types for org $owner" >&2
    return 1
  }

  _SILLOK_TYPE_ID_CACHE=$(printf '%s' "$types_json" | jq -r '.[] | "\(.name):\(.id)"' | tr '\n' '|')

  # Look up again from cache
  local id
  id=$(printf '%s' "$_SILLOK_TYPE_ID_CACHE" | tr '|' '\n' | awk -F: -v n="$name" '$1 == n { print $2; exit }')
  if [[ -z "$id" ]]; then
    echo "[sillok] issue type '$name' not found in org $owner" >&2
    return 1
  fi
  printf '%s' "$id"
}

# Apply an Issue Type to an existing issue.
# Usage: sillok_issue_type_set <repo> <issue-N> <type-name>
#   e.g. sillok_issue_type_set myorg/frontend 42 Feature
sillok_issue_type_set() {
  local repo="$1"
  local issue_n="$2"
  local type_name="$3"

  gh api -X PATCH \
    -H "X-GitHub-Api-Version: 2026-03-10" \
    "/repos/$repo/issues/$issue_n" \
    -f "type=$type_name" >/dev/null
}
