#!/usr/bin/env bash
# sillok — Projects v2 helpers.
# Wraps GraphQL mutations for project item add + status/priority field updates.
# Field writes are idempotent at the GitHub level (re-setting same value = no-op).
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

  # Cache line format: <name>:<id>| — `|` is the line separator, so field
  # names containing it are unsupported. `:` IS allowed in names ("Sev: ops"):
  # ids never contain `:`, so match the line prefix up to the LAST colon —
  # a first-colon split (awk -F:) would truncate the name at its own colon
  # and never match (the ensure path would then create a duplicate field).
  if [[ -n "$_SILLOK_FIELD_ID_CACHE" ]]; then
    local cached
    cached=$(printf '%s' "$_SILLOK_FIELD_ID_CACHE" | tr '|' '\n' | awk -v n="$name" 'match($0, /:[^:]*$/) && substr($0, 1, RSTART - 1) == n { print substr($0, RSTART + 1); exit }')
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

  printf '%s' "$_SILLOK_FIELD_ID_CACHE" | tr '|' '\n' | awk -v n="$name" 'match($0, /:[^:]*$/) && substr($0, 1, RSTART - 1) == n { print substr($0, RSTART + 1); exit }'
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

  # Append to cache. Declare ONCE above the loop: zsh prints `name=value` to
  # stdout when an existing variable is re-declared with local/typeset and no
  # assignment, so an in-loop declaration leaks from iteration 2 onward (#65).
  #
  # Cache line format: <field>::<name>#<id>| — `#` and `|` are separators, so
  # option names containing them are unsupported. `:` IS allowed in names
  # ("P1: urgent"): each line is "<name>:<id>" and ids never contain `:`, so
  # split on the LAST colon (%:* / ##*:), never the first.
  local opt_name opt_id
  while IFS= read -r line; do
    opt_name="${line%:*}"
    opt_id="${line##*:}"
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

# Shared core for single-select field writes (status + priority — they began
# as byte-copies and had already drifted). Carries: the #47 empty-item_id
# early guard, the project/field/option resolvers, the option-not-found
# guard, the combined -z check, the malformed-id tripwire, and the mutation.
# The public wrappers below map their config keys to <field-name> /
# <option-name> and delegate here.
# Usage: _sillok_project_single_select_set <item-id> <field-name> <option-name> <kind> [field-missing-msg]
#   kind: short noun for error messages ("status" / "priority").
#   field-missing-msg: optional remediation hint printed when the field itself
#   cannot be resolved (empty field_id on a resolvable project); when absent,
#   the generic could-not-resolve line is printed instead.
_sillok_project_single_select_set() {
  local item_id="$1"
  local field_name="$2"
  local option_name="$3"
  local kind="$4"
  local field_missing_msg="${5-}"

  # Early guard (#47): an empty item id can never succeed, so refuse before the
  # resolvers below spend gh round-trips. The combined -z check further down
  # still covers resolver failures (empty project/field/option ids).
  if [[ -z "$item_id" ]]; then
    echo "[sillok] empty project item id — issue not on the project board?" >&2
    return 1
  fi

  local project_id field_id option_id
  project_id=$(sillok_project_id)
  field_id=$(sillok_project_field_id "$field_name")
  option_id=$(sillok_project_option_id "$field_name" "$option_name")

  if [[ -z "$item_id" || -z "$project_id" || -z "$field_id" || -z "$option_id" ]]; then
    if [[ -n "$project_id" && -z "$field_id" && -n "$field_missing_msg" ]]; then
      # The board resolved but the field itself doesn't exist on it.
      echo "$field_missing_msg" >&2
    elif [[ -n "$project_id" && -n "$field_id" && -z "$option_id" ]]; then
      # Everything resolved except the option: the board simply lacks it.
      echo "[sillok] $kind option '$option_name' not found on the board's '$field_name' field — add it in the project's field settings (Settings → Fields → $field_name)" >&2
    else
      echo "[sillok] could not resolve item_id=$item_id project_id=$project_id field_id=$field_id option_id=$option_id" >&2
    fi
    return 1
  fi

  # Tripwire (#47): a resolver that leaks debug text to stdout (or a caller
  # passing a contaminated item_id captured the same way) would pollute these
  # ids and produce a malformed mutation (GraphQL "Expected string"). Refuse
  # loudly instead of sending garbage. Ids are base64ish node ids / hex option
  # ids — never contain whitespace or shell-noise characters.
  local _id
  for _id in "$item_id" "$project_id" "$field_id" "$option_id"; do
    case "$_id" in
      *[![:alnum:]_=-]*)
        echo "[sillok] malformed GraphQL id '$_id' — refusing to send mutation (a resolver leaked non-id output to stdout?)" >&2
        return 1 ;;
    esac
  done

  gh api graphql -f query="mutation {
    updateProjectV2ItemFieldValue(input: {
      projectId: \"$project_id\",
      itemId: \"$item_id\",
      fieldId: \"$field_id\",
      value: { singleSelectOptionId: \"$option_id\" }
    }) { projectV2Item { id } }
  }" --jq '.data.updateProjectV2ItemFieldValue.projectV2Item.id' >/dev/null
}

# Set status for a project item.
# Usage: sillok_project_status_set <item-id> <status-key>
#   status-key: one of backlog, todo, design, progress, review, done
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

  _sillok_project_single_select_set "$item_id" "$field_name" "$option_name" status
}

# Set priority for a project item (org mode — user repos keep p1–p4 labels).
# Usage: sillok_project_priority_set <item-id> <priority-key>
#   priority-key: one of p1, p2, p3, p4 — mapped to the board's option name
#   via project.priorities.<key>; the field name comes from project.priorityField.
sillok_project_priority_set() {
  local item_id="$1"
  local priority_key="$2"

  local field_name option_name
  field_name=$(sillok_config project.priorityField)
  option_name=$(sillok_config "project.priorities.$priority_key")

  if [[ -z "$option_name" ]]; then
    echo "[sillok] no project.priorities.$priority_key configured" >&2
    return 1
  fi

  # The field-missing hint covers the v2.x → priority-field upgrade path:
  # boards initialized before #66 have no Priority field until re-init.
  _sillok_project_single_select_set "$item_id" "$field_name" "$option_name" priority \
    "[sillok] Priority field '$field_name' not found on the project board — re-run /sillok-init to create it (org-mode priority moved off p-labels)"
}

# Ensure the configured Priority single-select field exists on the board.
# Present → return 0 silently. Absent → create it via createProjectV2Field
# with options built from project.priorities in p1→p4 order (one stderr
# notice). Returns non-zero only when creation fails (or config is unusable).
sillok_project_priority_field_ensure() {
  local field_name
  field_name=$(sillok_config project.priorityField)
  if [[ -z "$field_name" ]]; then
    echo "[sillok] no project.priorityField configured" >&2
    return 1
  fi

  local field_id
  field_id=$(sillok_project_field_id "$field_name") || return 1
  if [[ -n "$field_id" ]]; then
    return 0
  fi

  local project_id
  project_id=$(sillok_project_id) || return 1

  # Build singleSelectOptions in p1→p4 order. The GraphQL input type
  # (ProjectV2SingleSelectFieldOptionInput) requires name, color AND
  # description per option — description is String! but may be empty.
  # Locals declared ONCE above the loop (#65).
  local options="" key option_name color
  for key in p1 p2 p3 p4; do
    option_name=$(sillok_config "project.priorities.$key")
    if [[ -n "$option_name" ]]; then
      case "$key" in
        p1) color=RED ;;
        p2) color=ORANGE ;;
        p3) color=YELLOW ;;
        *)  color=GRAY ;;
      esac
      options="${options:+$options, }{name: \"$option_name\", color: $color, description: \"\"}"
    fi
  done

  if [[ -z "$options" ]]; then
    echo "[sillok] project.priorities has no option names configured — cannot create field '$field_name'" >&2
    return 1
  fi

  echo "[sillok] creating single-select field '$field_name' on the project board (options from project.priorities, p1→p4)" >&2
  gh api graphql -f query="mutation {
    createProjectV2Field(input: {
      projectId: \"$project_id\",
      dataType: SINGLE_SELECT,
      name: \"$field_name\",
      singleSelectOptions: [$options]
    }) { projectV2Field { ... on ProjectV2SingleSelectField { id } } }
  }" --jq '.data.createProjectV2Field.projectV2Field.id' >/dev/null || return 1

  # Defensive reset for hypothetical future same-shell callers. Today the
  # field_id lookup above ran in a command-substitution subshell, so its cache
  # write died with that subshell — this parent shell's cache is still empty
  # and the reset is a no-op. It only matters if a future caller resolves
  # field ids in this shell directly and would otherwise read a list cached
  # before the field was created.
  _SILLOK_FIELD_ID_CACHE=""
}
