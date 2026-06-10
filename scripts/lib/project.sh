#!/usr/bin/env bash
# sillok — Projects v2 helpers.
# Wraps GraphQL mutations for project item add + status field update.
# Status writes are idempotent at the GitHub level (re-setting same value = no-op).
set -euo pipefail

# Resolve this file's directory under bash AND zsh (nounset-safe).
# zsh: ${(%):-%x} expands to the file being sourced; eval defers the
# zsh-only syntax so bash never parses it. ${BASH_SOURCE[0]:-$0} is NOT
# usable — zsh trips nounset on the unset array subscript itself.
if [[ -n "${BASH_VERSION:-}" ]]; then
  _SILLOK_LIB_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
elif [[ -n "${ZSH_VERSION:-}" ]]; then
  eval '_SILLOK_LIB_DIR=$(cd "$(dirname "${(%):-%x}")" && pwd)'
else
  _SILLOK_LIB_DIR=$(cd "$(dirname "$0")" && pwd)
fi
# shellcheck source=config.sh
source "$_SILLOK_LIB_DIR/config.sh"

_SILLOK_PROJECT_ID=""
_SILLOK_FIELD_ID_CACHE=""
_SILLOK_OPTION_ID_CACHE=""

# Fetch project node ID via the owner-type-agnostic `gh project` CLI. Cached
# per command run. Works for both user- and org-owned ProjectV2 boards.
sillok_project_id() {
  if [[ -n "$_SILLOK_PROJECT_ID" ]]; then
    printf '%s' "$_SILLOK_PROJECT_ID"
    return 0
  fi
  local owner number
  owner=$(sillok_config project.owner) || return 1
  number=$(sillok_config project.number) || return 1
  if [[ -z "$owner" || -z "$number" || "$number" == "0" ]]; then
    echo "[sillok] project.owner or project.number not configured" >&2
    return 1
  fi
  _SILLOK_PROJECT_ID=$(gh project view "$number" --owner "$owner" --format json --jq '.id' 2>/dev/null) || return 1
  if [[ -z "$_SILLOK_PROJECT_ID" ]]; then
    echo "[sillok] could not resolve project $owner/projects/$number — check it exists and you have access" >&2
    return 1
  fi
  printf '%s' "$_SILLOK_PROJECT_ID"
}

# Get the project item ID for a given issue URL.
# Queries from the issue side (issue → projectItems) instead of scanning the
# full project items list, so it works regardless of project size.
# Returns empty if the issue is not in the configured project.
# Usage: sillok_project_item_for_issue <issue-url>
sillok_project_item_for_issue() {
  local issue_url="$1"
  local owner repo issue_n
  # Parse https://github.com/<owner>/<repo>/issues/<N> via parameter expansion.
  # (BASH_REMATCH is bash-only and stays empty under zsh; this is portable.)
  local rest="${issue_url#*github.com/}"   # owner/repo/issues/N
  owner="${rest%%/*}"
  rest="${rest#*/}"                        # repo/issues/N
  repo="${rest%%/*}"
  issue_n="${issue_url##*/}"               # N
  if [[ -z "$owner" || -z "$repo" || -z "$issue_n" || "$issue_url" != *"/issues/"* ]]; then
    echo "[sillok] cannot parse issue URL: $issue_url" >&2
    return 1
  fi

  local project_id
  project_id=$(sillok_project_id) || return 1

  gh api graphql -f query="{
    repository(owner: \"$owner\", name: \"$repo\") {
      issue(number: $issue_n) {
        projectItems(first: 20) {
          nodes { id project { id } }
        }
      }
    }
  }" --jq ".data.repository.issue.projectItems.nodes
    | map(select(.project.id == \"$project_id\"))
    | .[0].id // empty"
}

# Idempotent project item add. Returns item ID (existing or newly added).
# Usage: sillok_project_item_add <issue-url>
sillok_project_item_add() {
  local issue_url="$1"
  # Check if already in project
  local existing
  existing=$(sillok_project_item_for_issue "$issue_url") || true
  if [[ -n "$existing" ]]; then
    printf '%s' "$existing"
    return 0
  fi

  local owner number
  owner=$(sillok_config project.owner)
  number=$(sillok_config project.number)

  # gh project item-add returns the URL; we re-query for ID after add.
  gh project item-add "$number" --owner "$owner" --url "$issue_url" >/dev/null

  # Re-query for the new item ID
  sillok_project_item_for_issue "$issue_url"
}

# Get the field ID for a named field on the project. Cached.
# Resolves via node(id: $projectId) so it works for both user- and org-owned boards.
# Usage: sillok_project_field_id <field-name>
sillok_project_field_id() {
  local name="$1"

  if [[ -n "$_SILLOK_FIELD_ID_CACHE" ]]; then
    local cached
    cached=$(printf '%s' "$_SILLOK_FIELD_ID_CACHE" | tr '|' '\n' | awk -F: -v n="$name" '$1 == n { print $2; exit }')
    if [[ -n "$cached" ]]; then
      printf '%s' "$cached"
      return 0
    fi
  fi

  local project_id
  project_id=$(sillok_project_id) || return 1

  local fields_json
  fields_json=$(gh api graphql -f query="{
    node(id: \"$project_id\") {
      ... on ProjectV2 {
        fields(first: 50) { nodes { ... on ProjectV2Field { id name } ... on ProjectV2SingleSelectField { id name } } }
      }
    }
  }" --jq '.data.node.fields.nodes[] | "\(.name):\(.id)"') || return 1

  _SILLOK_FIELD_ID_CACHE=$(printf '%s' "$fields_json" | tr '\n' '|')

  printf '%s' "$_SILLOK_FIELD_ID_CACHE" | tr '|' '\n' | awk -F: -v n="$name" '$1 == n { print $2; exit }'
}

# Get the option ID for a named status option. Cached per field+option key.
# Resolves via node(id: $projectId) so it works for both user- and org-owned boards.
# Usage: sillok_project_option_id <field-name> <option-name>
sillok_project_option_id() {
  local field_name="$1"
  local option_name="$2"
  local cache_key="${field_name}::${option_name}"

  if [[ -n "$_SILLOK_OPTION_ID_CACHE" ]]; then
    local cached
    cached=$(printf '%s' "$_SILLOK_OPTION_ID_CACHE" | tr '|' '\n' | awk -F'#' -v k="$cache_key" '$1 == k { print $2; exit }')
    if [[ -n "$cached" ]]; then
      printf '%s' "$cached"
      return 0
    fi
  fi

  local project_id
  project_id=$(sillok_project_id) || return 1

  local options_json
  options_json=$(gh api graphql -f query="{
    node(id: \"$project_id\") {
      ... on ProjectV2 {
        field(name: \"$field_name\") {
          ... on ProjectV2SingleSelectField {
            options { id name }
          }
        }
      }
    }
  }" --jq '.data.node.field.options[]? | "\(.name):\(.id)"') || return 1

  # Append to cache
  while IFS= read -r line; do
    local opt_name opt_id
    opt_name="${line%:*}"
    opt_id="${line#*:}"
    _SILLOK_OPTION_ID_CACHE="${_SILLOK_OPTION_ID_CACHE}${field_name}::${opt_name}#${opt_id}|"
  done <<< "$options_json"

  printf '%s' "$_SILLOK_OPTION_ID_CACHE" | tr '|' '\n' | awk -F'#' -v k="$cache_key" '$1 == k { print $2; exit }'
}

# Read current status name for an item.
sillok_project_status_get() {
  local item_id="$1"
  local field_name
  field_name=$(sillok_config project.statusField)
  gh api graphql -f query="{
    node(id: \"$item_id\") {
      ... on ProjectV2Item {
        fieldValueByName(name: \"$field_name\") {
          ... on ProjectV2ItemFieldSingleSelectValue { name }
        }
      }
    }
  }" --jq '.data.node.fieldValueByName.name // empty'
}

# Set status for a project item.
# Usage: sillok_project_status_set <item-id> <status-key>
#   status-key: one of todo, design, progress, review, done
sillok_project_status_set() {
  local item_id="$1"
  local status_key="$2"

  local field_name option_name
  field_name=$(sillok_config project.statusField)
  option_name=$(sillok_config "project.statuses.$status_key")

  if [[ -z "$option_name" ]]; then
    echo "[sillok] no project.statuses.$status_key configured" >&2
    return 1
  fi

  local project_id field_id option_id
  project_id=$(sillok_project_id)
  field_id=$(sillok_project_field_id "$field_name")
  option_id=$(sillok_project_option_id "$field_name" "$option_name")

  if [[ -z "$project_id" || -z "$field_id" || -z "$option_id" ]]; then
    echo "[sillok] could not resolve project_id=$project_id field_id=$field_id option_id=$option_id" >&2
    return 1
  fi

  gh api graphql -f query="mutation {
    updateProjectV2ItemFieldValue(input: {
      projectId: \"$project_id\",
      itemId: \"$item_id\",
      fieldId: \"$field_id\",
      value: { singleSelectOptionId: \"$option_id\" }
    }) { projectV2Item { id } }
  }" --jq '.data.updateProjectV2ItemFieldValue.projectV2Item.id' >/dev/null
}
