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

# ---------------------------------------------------------------------------
# org-mode priority — org-level Issue Fields, NOT regular project fields (#17)
#
# On real org boards the "Priority" column is an org Issue Field projected onto
# the board. Read through the old Projects v2 API it looks like a regular
# ProjectV2SingleSelectField but always reports options:[] and item values:null
# (the definition + value live on the org / the issue), so updateProjectV2-
# ItemFieldValue can never be constructed. The value is set on the ISSUE via
# setIssueFieldValue instead, and discovered via organization.issueFields.
# ---------------------------------------------------------------------------

# Resolve an org single-select Issue Field's id AND a named option's id in one
# query. Org login = the configured repo's owner. Prints "<field_id> <option_id>"
# (option_id empty when the option — or the option-name arg — is absent; field
# part empty when the field itself is absent). Returns 1 only on transport
# error, so callers distinguish "field missing" (empty stdout, rc 0) from
# "query failed" (rc 1).
# Usage: sillok_org_issue_field_resolve <field-name> [option-name]
sillok_org_issue_field_resolve() {
  local field_name="$1"
  local option_name="${2-}"

  local org
  org=$(sillok_config_required repo) || return 1
  org="${org%%/*}"

  local raw
  raw=$(gh api graphql -f query="{
    organization(login: \"$org\") {
      issueFields(first: 50) {
        nodes {
          __typename
          ... on IssueFieldSingleSelect { id name options { id name } }
        }
      }
    }
  }") || return 1

  printf '%s' "$raw" | jq -r --arg f "$field_name" --arg o "$option_name" '
    .data.organization.issueFields.nodes[]?
    | select(.__typename == "IssueFieldSingleSelect" and .name == $f)
    | .id as $fid
    | ([.options[]? | select(.name == $o) | .id] | first // "") as $oid
    | "\($fid) \($oid)"
  ' 2>/dev/null | head -1
}

# Resolve an issue's GraphQL node id from owner/repo/number. Factored out so
# tests can stub it (it is the only gh round-trip in the write path before the
# id tripwire), keeping the "no gh call before refusing" guarantee testable.
_sillok_issue_node_id() {
  local owner="$1" repo="$2" number="$3"
  gh api graphql -f query="{
    repository(owner: \"$owner\", name: \"$repo\") { issue(number: $number) { id } }
  }" --jq '.data.repository.issue.id'
}

# Set an issue's org-mode priority via setIssueFieldValue (org mode only — user
# repos keep p1–p4 labels). Takes the issue URL (the issue node id is all the
# write needs — no board item id lookup) and a priority key.
# Usage: sillok_issue_priority_set <issue-url> <priority-key>
#   priority-key: one of p1, p2, p3, p4 — mapped to the org field's option name
#   via project.priorities.<key>; the field name comes from project.priorityField.
sillok_issue_priority_set() {
  local issue_url="$1"
  local priority_key="$2"

  # Early guard: an empty url can never succeed; refuse before any gh round-trip.
  if [[ -z "$issue_url" ]]; then
    echo "[sillok] empty issue url — cannot set priority" >&2
    return 1
  fi

  local field_name option_name
  field_name=$(sillok_config project.priorityField)
  option_name=$(sillok_config "project.priorities.$priority_key")
  if [[ -z "$option_name" ]]; then
    echo "[sillok] no project.priorities.$priority_key configured" >&2
    return 1
  fi

  # Parse https://github.com/<owner>/<repo>/issues/<N> via parameter expansion
  # (BASH_REMATCH is empty under zsh; this is portable).
  local rest owner repo issue_n
  rest="${issue_url#*github.com/}"
  owner="${rest%%/*}"
  rest="${rest#*/}"
  repo="${rest%%/*}"
  issue_n="${issue_url##*/}"
  if [[ -z "$owner" || -z "$repo" || -z "$issue_n" || "$issue_url" != *"/issues/"* ]]; then
    echo "[sillok] cannot parse issue URL: $issue_url" >&2
    return 1
  fi

  local issue_id
  issue_id=$(_sillok_issue_node_id "$owner" "$repo" "$issue_n") || return 1

  local resolved field_id option_id
  resolved=$(sillok_org_issue_field_resolve "$field_name" "$option_name") || return 1
  field_id="${resolved%% *}"
  option_id="${resolved#* }"

  if [[ -z "$field_id" ]]; then
    echo "[sillok] org issue field '$field_name' not found — re-run /sillok-init to create the org Priority issue field" >&2
    return 1
  fi
  if [[ -z "$option_id" ]]; then
    echo "[sillok] priority option '$option_name' not found on org issue field '$field_name' — check the project.priorities mapping" >&2
    return 1
  fi

  # Tripwire (#47): refuse to send a mutation if any id carries shell-noise (a
  # resolver leaking debug text to stdout). Node/option ids are base64ish /
  # prefixed hex — never whitespace or punctuation beyond _ = -.
  local _id
  for _id in "$issue_id" "$field_id" "$option_id"; do
    case "$_id" in
      *[![:alnum:]_=-]*)
        echo "[sillok] malformed GraphQL id '$_id' — refusing to send mutation (a resolver leaked non-id output to stdout?)" >&2
        return 1 ;;
    esac
  done

  gh api graphql -f query="mutation {
    setIssueFieldValue(input: {
      issueId: \"$issue_id\",
      issueFields: [{ fieldId: \"$field_id\", singleSelectOptionId: \"$option_id\" }]
    }) { issue { number } }
  }" --jq '.data.setIssueFieldValue.issue.number' >/dev/null
}

# Org-guarded, NON-FATAL priority set. In org mode priority lives on the org
# Priority *issue field* (set on the issue, projected onto the board); in user
# mode the p-label applied at issue-create time IS the priority record, so this
# is a no-op. Wrapping the guard + fail-soft warning makes the org/user fork and
# the never-roll-back-over-a-board-error semantics identical everywhere.
# Returns 0 always (priority is an enhancement, never a blocker).
# Usage: sillok_priority_apply <issue-url> <priority-key>
sillok_priority_apply() {
  local issue_url="$1"
  local priority_key="$2"

  if [[ "$(sillok_config orgMode)" == "true" ]]; then
    sillok_issue_priority_set "$issue_url" "$priority_key" \
      || echo "[sillok] priority not set — re-run /sillok-init to create the org Priority issue field" >&2
  fi
  return 0
}

# Ensure the org-level Priority Issue Field exists, then project it onto the
# configured board. Org Priority issue fields cannot be created in the GitHub
# GUI (preview, API-only), so init provisions one when absent.
# Present → ensure projection, return 0. Absent → createIssueField (p1→p4
# options from project.priorities), then project. Returns non-zero only when
# creation fails (e.g. missing org-admin permission) or config is unusable.
sillok_org_priority_field_ensure() {
  local field_name
  field_name=$(sillok_config project.priorityField)
  if [[ -z "$field_name" ]]; then
    echo "[sillok] no project.priorityField configured" >&2
    return 1
  fi

  local org
  org=$(sillok_config_required repo) || return 1
  org="${org%%/*}"

  # Already exists? Discover via organization.issueFields (the field part of
  # the resolve output; option arg omitted).
  local resolved existing_id
  resolved=$(sillok_org_issue_field_resolve "$field_name") || return 1
  existing_id="${resolved%% *}"
  if [[ -n "$existing_id" ]]; then
    _sillok_org_field_project "$existing_id"
    return 0
  fi

  # Build options p1→p4. The org option input type
  # (IssueFieldSingleSelectOptionInput) needs name, color (enum), priority
  # (Int!) AND description — colors hardcoded by position to match the standard
  # board (Urgent=PINK/High=RED/Medium=YELLOW/Low=GREEN). Locals declared ONCE
  # above the loop (#65 zsh leak).
  local options="" key option_name color pri=1
  for key in p1 p2 p3 p4; do
    option_name=$(sillok_config "project.priorities.$key")
    if [[ -n "$option_name" ]]; then
      case "$key" in
        p1) color=PINK ;;
        p2) color=RED ;;
        p3) color=YELLOW ;;
        *)  color=GREEN ;;
      esac
      options="${options:+$options, }{name: \"$option_name\", color: $color, priority: $pri, description: \"\"}"
    fi
    pri=$((pri + 1))
  done
  if [[ -z "$options" ]]; then
    echo "[sillok] project.priorities has no option names configured — cannot create issue field '$field_name'" >&2
    return 1
  fi

  local owner_id
  owner_id=$(gh api graphql -f query="{ organization(login: \"$org\") { id } }" --jq '.data.organization.id') || return 1
  if [[ -z "$owner_id" ]]; then
    echo "[sillok] could not resolve org node id for '$org'" >&2
    return 1
  fi

  echo "[sillok] creating org issue field '$field_name' (single-select, options from project.priorities p1→p4)" >&2
  local new_id
  new_id=$(gh api graphql -f query="mutation {
    createIssueField(input: {
      ownerId: \"$owner_id\",
      name: \"$field_name\",
      dataType: SINGLE_SELECT,
      options: [$options]
    }) { issueField { ... on IssueFieldSingleSelect { id } } }
  }" --jq '.data.createIssueField.issueField.id') || {
    echo "[sillok] failed to create org issue field '$field_name' — an org owner must create it (org-admin permission required)" >&2
    return 1
  }
  if [[ -z "$new_id" ]]; then
    echo "[sillok] createIssueField returned no id for '$field_name'" >&2
    return 1
  fi

  _sillok_org_field_project "$new_id"
}

# Project an org Issue Field onto the configured board so the board shows the
# column (createProjectV2IssueField is API-only; not in the GUI). Non-fatal: a
# same-named regular project field blocks projection ("Name has already been
# taken") and an already-projected field re-errors — both are warnings.
_sillok_org_field_project() {
  local issue_field_id="$1"

  local project_id
  project_id=$(sillok_project_id) || {
    echo "[sillok] could not resolve project board — skipping projection of issue field onto the board (non-fatal)" >&2
    return 0
  }

  local err
  if err=$(gh api graphql -f query="mutation {
    createProjectV2IssueField(input: { projectId: \"$project_id\", issueFieldId: \"$issue_field_id\" }) {
      projectV2Field { ... on ProjectV2SingleSelectField { id } }
    }
  }" 2>&1 >/dev/null); then
    return 0
  fi

  case "$err" in
    *"already"*)
      echo "[sillok] Priority issue field is already projected onto the board (or a same-named project field blocks it) — skipping projection (this is fine)" >&2 ;;
    *)
      echo "[sillok] could not project Priority issue field onto the board (non-fatal): $err" >&2 ;;
  esac
  return 0
}
