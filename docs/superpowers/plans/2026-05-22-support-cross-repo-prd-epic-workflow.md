# Cross-repo PRD epic workflow (sillok v2) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship sillok v2 — moves type categorization from labels to GitHub Issue Types, moves lifecycle stage from labels to Projects v2 status field, adds cross-repo PRD parent linking, hardens Development panel auto-population and project add.

**Architecture:** Three new bash helper libraries (`issue-types.sh`, `project.sh`, `dev-link.sh`) wrap REST + GraphQL calls. All five sillok slash-command markdown files are rewritten to use these helpers + apply the new status-transition model (Todo → In Design → In Progress → In QA → Done — three sillok-driven transitions, start + done are project workflows). The `epic` label / `/sillok-epic` command rename to `story` / `/sillok-story` everywhere. A one-shot migration script handles 1.x → 2.0 label-to-type and label-to-status conversion.

**Tech Stack:** Bash 3.2 compatible (macOS), `gh` CLI (REST + GraphQL via `gh api`), `jq`. No new runtime deps.

**Working directory for all tasks:** `/Users/jihoopark/sillok/.worktrees/14-support-cross-repo-prd-epic-workflow`

**Branch:** `feature/issue-14-support-cross-repo-prd-epic-workflow`

**Spec reference:** `docs/superpowers/specs/2026-05-21-support-cross-repo-prd-epic-workflow.md`

---

## Task 1: Update schema/v1.json with new fields

**Files:**
- Modify: `schema/v1.json`

- [ ] **Step 1: Read existing schema and identify insertion points**

Open `schema/v1.json`. The current top-level properties include `repo`, `baseBranch`, `branchPrefix`, `worktree`, `install`, `verify`, `docs`, `commit`, `milestone`, `labels`.

Required: `["version", "repo", "baseBranch", "branchPrefix"]`.

- [ ] **Step 2: Add `prdRepo`, `project`, `types` to properties**

Insert after `branchPrefix` property:

```json
"prdRepo": {
  "type": "string",
  "pattern": "^[^/]+/[^/]+$",
  "description": "Optional cross-repo PRD repository slug ('<owner>/<name>'). When set, /sillok-start auto-suggests open epics from this repo and accepts cross-repo parent linking."
},
"project": {
  "type": "object",
  "required": ["owner", "number", "statusField", "statuses"],
  "properties": {
    "owner": { "type": "string", "description": "Org owning the Projects v2 board." },
    "number": { "type": "integer", "minimum": 1, "description": "Project number." },
    "statusField": { "type": "string", "default": "Status", "description": "Status field name on the project." },
    "statuses": {
      "type": "object",
      "required": ["todo", "design", "progress", "review", "done"],
      "properties": {
        "todo":     { "type": "string", "default": "Todo" },
        "design":   { "type": "string", "default": "In Design" },
        "progress": { "type": "string", "default": "In Progress" },
        "review":   { "type": "string", "default": "In QA" },
        "done":     { "type": "string", "default": "Done" }
      }
    }
  },
  "description": "Projects v2 integration. Required for v2 status transitions to function."
},
"types": {
  "type": "object",
  "properties": {
    "list": {
      "type": "array",
      "items": { "type": "string" },
      "default": ["Epic", "Story", "Feature", "Task", "Bug"]
    },
    "defaults": {
      "type": "object",
      "properties": {
        "feature":   { "type": "string", "default": "Feature" },
        "composite": { "type": "string", "default": "Story" },
        "prd":       { "type": "string", "default": "Epic" }
      }
    }
  },
  "description": "Expected GitHub Issue Types. Sillok verifies these exist at /sillok-init."
},
```

- [ ] **Step 3: Update `labels` properties — remove types/stages from defaults, add natures**

Replace the `labels.properties` block:

```json
"labels": {
  "type": "object",
  "properties": {
    "priorities": { "type": "array", "items": { "type": "string" } },
    "areas": {
      "type": "array",
      "items": { "type": "string", "pattern": "^[a-z0-9-]+$" },
      "description": "Optional vertical-slice labels. Detected from project structure during /sillok-init."
    },
    "natures": {
      "type": "array",
      "items": { "type": "string", "pattern": "^[a-z0-9-]+$" },
      "default": ["improvement", "refactor", "infra", "docs", "security", "performance"],
      "description": "Cross-cutting nature labels (orthogonal to Issue Type)."
    },
    "defaults": {
      "type": "object",
      "properties": {
        "priority": { "type": "string" }
      }
    }
  }
}
```

- [ ] **Step 4: Add `project` to required array**

Update top-level `required`:

```json
"required": ["version", "repo", "baseBranch", "branchPrefix", "project"]
```

(`prdRepo`, `types` stay optional.)

- [ ] **Step 5: Validate the schema is well-formed JSON**

Run:

```bash
cd /Users/jihoopark/sillok/.worktrees/14-support-cross-repo-prd-epic-workflow
jq empty schema/v1.json && echo "OK: valid JSON"
```

Expected: `OK: valid JSON`

- [ ] **Step 6: Commit**

```bash
git add schema/v1.json
git commit -m "feat(schema): add prdRepo, project, types; restructure labels for v2 (#14)"
```

---

## Task 2: Update templates/workflow.config.json to match schema

**Files:**
- Modify: `templates/workflow.config.json`

- [ ] **Step 1: Read existing template**

Confirm current structure: `$schema`, `version`, `repo`, `baseBranch`, `branchPrefix`, `worktree`, `install`, `verify`, `docs`, `commit`, `milestone`, `labels`.

- [ ] **Step 2: Replace `templates/workflow.config.json` content**

Write the new full file content:

```json
{
  "$schema": "https://raw.githubusercontent.com/judeProground/sillok/main/schema/v1.json",
  "version": 1,

  "repo": "",
  "baseBranch": "main",
  "branchPrefix": "{type}/issue-",

  "prdRepo": "",

  "project": {
    "owner": "",
    "number": 0,
    "statusField": "Status",
    "statuses": {
      "todo":     "Todo",
      "design":   "In Design",
      "progress": "In Progress",
      "review":   "In QA",
      "done":     "Done"
    }
  },

  "types": {
    "list": ["Epic", "Story", "Feature", "Task", "Bug"],
    "defaults": {
      "feature":   "Feature",
      "composite": "Story",
      "prd":       "Epic"
    }
  },

  "worktree": {
    "enabled": true,
    "dir": ".worktrees",
    "copyFiles": []
  },

  "install": "",

  "verify": {
    "lint": "",
    "typecheck": "",
    "format": ""
  },

  "docs": {
    "specs": "docs/superpowers/specs",
    "plans": "docs/superpowers/plans"
  },

  "commit": {
    "coAuthor": ""
  },

  "milestone": {
    "naming": "YYYY-MM-Wn",
    "sprintWeeks": 2,
    "weekStart": "monday"
  },

  "labels": {
    "priorities": ["p1", "p2", "p3", "p4"],
    "areas": [],
    "natures": ["improvement", "refactor", "infra", "docs", "security", "performance"],
    "defaults": {
      "priority": "p3"
    }
  }
}
```

- [ ] **Step 3: Validate JSON**

```bash
jq empty templates/workflow.config.json && echo "OK: valid JSON"
```

Expected: `OK: valid JSON`

- [ ] **Step 4: Commit**

```bash
git add templates/workflow.config.json
git commit -m "feat(templates): match config template to v2 schema (#14)"
```

---

## Task 3: Create scripts/lib/issue-types.sh helper

**Files:**
- Create: `scripts/lib/issue-types.sh`
- Test: `tests/issue-types.test.sh`

- [ ] **Step 1: Write the failing test**

Create `tests/issue-types.test.sh`:

```bash
#!/usr/bin/env bash
# Verify scripts/lib/issue-types.sh exposes the expected function names.
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
LIB="$SCRIPT_DIR/../scripts/lib/issue-types.sh"

if [[ ! -f "$LIB" ]]; then
  echo "FAIL: $LIB does not exist"
  exit 1
fi

# Source in subshell and check function existence
result=$(bash -c "source '$LIB' && declare -F sillok_issue_type_id sillok_issue_type_set" 2>&1)

if echo "$result" | grep -q "sillok_issue_type_id" && echo "$result" | grep -q "sillok_issue_type_set"; then
  echo "OK: required functions exist"
else
  echo "FAIL: missing functions"
  echo "$result"
  exit 1
fi
```

- [ ] **Step 2: Run test to verify it fails**

```bash
bash tests/issue-types.test.sh
```

Expected: `FAIL: scripts/lib/issue-types.sh does not exist`

- [ ] **Step 3: Create `scripts/lib/issue-types.sh`**

```bash
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
```

- [ ] **Step 4: Run test to verify it passes**

```bash
bash tests/issue-types.test.sh
```

Expected: `OK: required functions exist`

- [ ] **Step 5: Commit**

```bash
git add scripts/lib/issue-types.sh tests/issue-types.test.sh
git commit -m "feat(scripts): add issue-types.sh helper library (#14)"
```

---

## Task 4: Create scripts/lib/project.sh helper

**Files:**
- Create: `scripts/lib/project.sh`
- Test: `tests/project-lib.test.sh`

- [ ] **Step 1: Write the failing test**

Create `tests/project-lib.test.sh`:

```bash
#!/usr/bin/env bash
# Verify scripts/lib/project.sh exposes the expected function names.
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
LIB="$SCRIPT_DIR/../scripts/lib/project.sh"

if [[ ! -f "$LIB" ]]; then
  echo "FAIL: $LIB does not exist"
  exit 1
fi

expected=(
  sillok_project_id
  sillok_project_item_for_issue
  sillok_project_item_add
  sillok_project_field_id
  sillok_project_option_id
  sillok_project_status_get
  sillok_project_status_set
)

result=$(bash -c "source '$LIB' && declare -F ${expected[*]}" 2>&1)

ok=1
for fn in "${expected[@]}"; do
  if ! echo "$result" | grep -q "$fn"; then
    echo "FAIL: missing function $fn"
    ok=0
  fi
done

if [[ "$ok" == "1" ]]; then
  echo "OK: all required functions exist"
else
  exit 1
fi
```

- [ ] **Step 2: Run test to verify it fails**

```bash
bash tests/project-lib.test.sh
```

Expected: `FAIL: scripts/lib/project.sh does not exist`

- [ ] **Step 3: Create `scripts/lib/project.sh`**

```bash
#!/usr/bin/env bash
# sillok — Projects v2 helpers.
# Wraps GraphQL mutations for project item add + status field update.
# Status writes are idempotent at the GitHub level (re-setting same value = no-op).
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=config.sh
source "$SCRIPT_DIR/config.sh"

_SILLOK_PROJECT_ID=""
_SILLOK_FIELD_ID_CACHE=""
_SILLOK_OPTION_ID_CACHE=""

# Fetch project node ID via GraphQL. Cached per command run.
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
  _SILLOK_PROJECT_ID=$(gh api graphql -f query="{ organization(login: \"$owner\") { projectV2(number: $number) { id } } }" \
    --jq '.data.organization.projectV2.id') || return 1
  printf '%s' "$_SILLOK_PROJECT_ID"
}

# Get the project item ID for a given issue URL (or content node id).
# Returns empty if not found.
# Usage: sillok_project_item_for_issue <issue-url>
sillok_project_item_for_issue() {
  local issue_url="$1"
  local owner repo issue_n
  # Parse URL: https://github.com/<owner>/<repo>/issues/<N>
  if [[ "$issue_url" =~ github\.com/([^/]+)/([^/]+)/issues/([0-9]+) ]]; then
    owner="${BASH_REMATCH[1]}"
    repo="${BASH_REMATCH[2]}"
    issue_n="${BASH_REMATCH[3]}"
  else
    echo "[sillok] cannot parse issue URL: $issue_url" >&2
    return 1
  fi

  local project_owner project_number
  project_owner=$(sillok_config project.owner)
  project_number=$(sillok_config project.number)

  # GraphQL: query the project's items, filter for matching content
  gh api graphql -f query="{
    organization(login: \"$project_owner\") {
      projectV2(number: $project_number) {
        items(first: 200) {
          nodes {
            id
            content { ... on Issue { number repository { name owner { login } } } }
          }
        }
      }
    }
  }" --jq ".data.organization.projectV2.items.nodes
    | map(select(.content.number == $issue_n and .content.repository.owner.login == \"$owner\" and .content.repository.name == \"$repo\"))
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

  # gh project item-add returns the URL or empty; capture via GraphQL instead
  # for ID return.
  gh project item-add "$number" --owner "$owner" --url "$issue_url" >/dev/null

  # Re-query for the new item ID
  sillok_project_item_for_issue "$issue_url"
}

# Get the field ID for a named field on the project. Cached.
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

  local owner number
  owner=$(sillok_config project.owner)
  number=$(sillok_config project.number)

  local fields_json
  fields_json=$(gh api graphql -f query="{
    organization(login: \"$owner\") {
      projectV2(number: $number) {
        fields(first: 50) { nodes { ... on ProjectV2Field { id name } ... on ProjectV2SingleSelectField { id name } } }
      }
    }
  }" --jq '.data.organization.projectV2.fields.nodes[] | "\(.name):\(.id)"') || return 1

  _SILLOK_FIELD_ID_CACHE=$(printf '%s' "$fields_json" | tr '\n' '|')

  printf '%s' "$_SILLOK_FIELD_ID_CACHE" | tr '|' '\n' | awk -F: -v n="$name" '$1 == n { print $2; exit }'
}

# Get the option ID for a named status option. Cached per field+option key.
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

  local owner number
  owner=$(sillok_config project.owner)
  number=$(sillok_config project.number)

  local options_json
  options_json=$(gh api graphql -f query="{
    organization(login: \"$owner\") {
      projectV2(number: $number) {
        field(name: \"$field_name\") {
          ... on ProjectV2SingleSelectField {
            options { id name }
          }
        }
      }
    }
  }" --jq '.data.organization.projectV2.field.options[]? | "\(.name):\(.id)"') || return 1

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
```

- [ ] **Step 4: Run test to verify it passes**

```bash
bash tests/project-lib.test.sh
```

Expected: `OK: all required functions exist`

- [ ] **Step 5: Commit**

```bash
git add scripts/lib/project.sh tests/project-lib.test.sh
git commit -m "feat(scripts): add project.sh helper library (#14)"
```

---

## Task 5: Create scripts/lib/dev-link.sh helper

**Files:**
- Create: `scripts/lib/dev-link.sh`
- Test: `tests/dev-link.test.sh`

- [ ] **Step 1: Write the failing test**

Create `tests/dev-link.test.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
LIB="$SCRIPT_DIR/../scripts/lib/dev-link.sh"

if [[ ! -f "$LIB" ]]; then
  echo "FAIL: $LIB does not exist"
  exit 1
fi

result=$(bash -c "source '$LIB' && declare -F sillok_issue_node_id sillok_link_branch" 2>&1)

if echo "$result" | grep -q "sillok_issue_node_id" && echo "$result" | grep -q "sillok_link_branch"; then
  echo "OK: required functions exist"
else
  echo "FAIL: missing functions"
  echo "$result"
  exit 1
fi
```

- [ ] **Step 2: Run test to verify it fails**

```bash
bash tests/dev-link.test.sh
```

Expected: `FAIL: scripts/lib/dev-link.sh does not exist`

- [ ] **Step 3: Create `scripts/lib/dev-link.sh`**

```bash
#!/usr/bin/env bash
# sillok — Development panel helpers.
# Wraps the createLinkedBranch GraphQL mutation so the issue's Development
# panel shows linked branches (not just PRs).
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=config.sh
source "$SCRIPT_DIR/config.sh"

# Get the GraphQL node ID for an issue.
# Usage: sillok_issue_node_id <repo> <issue-N>
sillok_issue_node_id() {
  local repo="$1"
  local issue_n="$2"
  local owner="${repo%%/*}"
  local name="${repo##*/}"
  gh api graphql -f query="{
    repository(owner: \"$owner\", name: \"$name\") {
      issue(number: $issue_n) { id }
    }
  }" --jq '.data.repository.issue.id'
}

# Get the repository GraphQL node ID.
# Usage: sillok_repo_node_id <repo>
sillok_repo_node_id() {
  local repo="$1"
  local owner="${repo%%/*}"
  local name="${repo##*/}"
  gh api graphql -f query="{
    repository(owner: \"$owner\", name: \"$name\") { id }
  }" --jq '.data.repository.id'
}

# Create a linked branch on an issue (Development panel).
# Usage: sillok_link_branch <issue-node-id> <branch-name> <commit-sha> [repo-node-id]
# Idempotent on re-call with same args (GitHub returns the existing link).
sillok_link_branch() {
  local issue_id="$1"
  local branch_name="$2"
  local oid="$3"
  local repo_id="${4:-}"

  local input="issueId: \"$issue_id\", name: \"$branch_name\", oid: \"$oid\""
  if [[ -n "$repo_id" ]]; then
    input="$input, repositoryId: \"$repo_id\""
  fi

  gh api graphql -f query="mutation {
    createLinkedBranch(input: { $input }) {
      linkedBranch { id ref { name } }
    }
  }" --jq '.data.createLinkedBranch.linkedBranch.id' 2>/dev/null || {
    # If the branch is already linked, GitHub returns an error; treat as idempotent
    echo "[sillok] linked branch creation returned non-zero (may already be linked); continuing" >&2
    return 0
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

```bash
bash tests/dev-link.test.sh
```

Expected: `OK: required functions exist`

- [ ] **Step 5: Commit**

```bash
git add scripts/lib/dev-link.sh tests/dev-link.test.sh
git commit -m "feat(scripts): add dev-link.sh for createLinkedBranch (#14)"
```

---

## Task 6: Update scripts/bootstrap-labels.sh — drop types/stages, add natures

**Files:**
- Modify: `scripts/bootstrap-labels.sh`

- [ ] **Step 1: Read existing script**

The current script reads `labels.types`, `labels.stages`, `labels.priorities`, `labels.areas` from config and creates corresponding GitHub labels.

- [ ] **Step 2: Replace label-class enumeration**

Find the block that iterates over label classes. Change from:

```bash
for class in types stages priorities areas; do
```

to:

```bash
for class in priorities natures areas; do
```

- [ ] **Step 3: Remove any hardcoded `type:` or `stage:` color logic**

If the script branches on class name to pick colors, the branches for `types` and `stages` can be removed. Keep:
- `priorities`: red-orange gradient or similar
- `natures`: green-ish (new — pick a neutral color like `0e8a16` or use a default)
- `areas`: blue-gray (`c9d4dd` per CLAUDE.md)

For `natures` specifically, color suggestion: `0e8a16` (green).

- [ ] **Step 4: Smoke test against a temp config**

Create `/tmp/sillok-bootstrap-test-config.json` with new label classes:

```bash
cat > /tmp/sillok-bootstrap-test-config.json <<'EOF'
{
  "labels": {
    "priorities": ["p1", "p2"],
    "natures": ["improvement", "refactor"],
    "areas": ["auth"]
  }
}
EOF
```

Then dry-run (if the script supports `--dry-run`) or inspect that the script reads the new fields without error:

```bash
bash -n scripts/bootstrap-labels.sh && echo "OK: script parses"
```

Expected: `OK: script parses`

- [ ] **Step 5: Commit**

```bash
git add scripts/bootstrap-labels.sh
git commit -m "feat(scripts): bootstrap natures instead of types/stages (#14)"
```

---

## Task 7: Update scripts/precompute-start.sh — cross-repo open epics

**Files:**
- Modify: `scripts/precompute-start.sh`

- [ ] **Step 1: Read current script**

Identify the `### Open epics` section. Currently it lists epics from the local repo only.

- [ ] **Step 2: Modify the open-epics enumeration**

Replace the existing epics-listing block with:

```bash
echo
echo "### Open epics"

# Local-repo stories (formerly epics). Still relevant for in-repo composite work.
local_stories=$(gh api graphql -H "X-GitHub-Api-Version: 2026-03-10" \
  -f query="{ repository(owner: \"${REPO%%/*}\", name: \"${REPO##*/}\") {
    issues(first: 20, states: OPEN, filterBy: {issueType: \"Story\"}) {
      nodes { number title }
    }
  } }" --jq '.data.repository.issues.nodes[]? | "  - (in this repo) #\(.number) \(.title)"' 2>/dev/null || echo "")

# Cross-repo PRD epics from prdRepo, if configured.
PRD_REPO=$(sillok_config prdRepo)
prd_epics=""
if [[ -n "$PRD_REPO" ]]; then
  prd_epics=$(gh api graphql -H "X-GitHub-Api-Version: 2026-03-10" \
    -f query="{ repository(owner: \"${PRD_REPO%%/*}\", name: \"${PRD_REPO##*/}\") {
      issues(first: 20, states: OPEN, filterBy: {issueType: \"Epic\"}) {
        nodes { number title }
      }
    } }" --jq ".data.repository.issues.nodes[]? | \"  - (in $PRD_REPO) #\(.number) \(.title)\"" 2>/dev/null || echo "")
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
```

- [ ] **Step 3: Parse-check the script**

```bash
bash -n scripts/precompute-start.sh && echo "OK"
```

Expected: `OK`

- [ ] **Step 4: Commit**

```bash
git add scripts/precompute-start.sh
git commit -m "feat(precompute): list stories + cross-repo PRD epics (#14)"
```

---

## Task 8: Update commands/sillok-start.md — assignee, type, cross-repo, project, linked branch

**Files:**
- Modify: `commands/sillok-start.md`

This is the largest command file update. Many sections change.

- [ ] **Step 1: Read current sillok-start.md**

Familiarize with all 11 steps. The replacements below target specific named steps.

- [ ] **Step 2: Update the `description` frontmatter**

Change first line from current to:

```yaml
---
description: Bootstrap a new feature — create GH issue with Issue Type + self-assign + project status Todo + linked branch. Optional --parent N (same-repo) or owner/repo#N (cross-repo PRD epic).
---
```

- [ ] **Step 3: Update Step 1 (Parse args) to accept cross-repo --parent**

Replace the `--parent N` parsing with multi-form support:

```markdown
## Step 1: Parse args

Extract from the user's input:

- Optional positional `[prd-path]` — a markdown file path. Most starts have no PRD; that's expected.
- Optional flag `--parent <value>` — issue reference. Three forms accepted:
  - `--parent 42` — same-repo issue #42
  - `--parent myorg/prd#42` — cross-repo issue
  - `--parent https://github.com/myorg/prd/issues/42` — URL form, parsed to `myorg/prd#42`

Parse `--parent` into `parent_owner`, `parent_repo`, `parent_n`. If only a number is given, `parent_owner` = current repo owner and `parent_repo` = current repo name.
```

- [ ] **Step 4: Update Step 6 (Confirm with user) — drop "Stage label" line**

The stage label `todo` is no longer applied. Remove the line `- Stage label: \`todo\`` from the confirmation output.

- [ ] **Step 5: Update Step 7 (Create the issue)**

Replace with:

```markdown
## Step 7: Create the issue

Resolve type label (`<type>`) to Issue Type name via config:
- `feature` → use `types.defaults.feature` (default `Feature`)
- `bug` → use `Bug` (literal)
- `task` → use `Task` (literal)

Create the issue via REST so we can include `type` and `assignees` in one call:

```bash
issue_url=$(gh api -X POST \
  -H "X-GitHub-Api-Version: 2026-03-10" \
  "/repos/$REPO/issues" \
  -f title="<title>" \
  -f body="<body>" \
  -f type="<Issue-Type-name>" \
  -f "assignees[]=$(gh api user --jq .login)" \
  -f "labels[]=<priority>" \
  -f "labels[]=<area-if-any>" \
  --jq '.html_url')
```

Capture `<N>` by parsing the URL's last segment.
```

- [ ] **Step 6: Update Step 8 (Link as sub-issue if parent) to support cross-repo**

Replace with:

```markdown
## Step 8: Link as sub-issue if parent

If a parent was selected:

```bash
PARENT_ID=$(gh api graphql -f query="{ repository(owner: \"$parent_owner\", name: \"$parent_repo\") { issue(number: $parent_n) { id } } }" --jq '.data.repository.issue.id')
CHILD_ID=$(gh api graphql -f query="{ repository(owner: \"${REPO%%/*}\", name: \"${REPO##*/}\") { issue(number: $N) { id } } }" --jq '.data.repository.issue.id')
gh api graphql -f query="mutation { addSubIssue(input: { issueId: \"$PARENT_ID\", subIssueId: \"$CHILD_ID\" }) { issue { number } } }" >/dev/null
```

**Skip the epic-label verification step** when `parent_owner` differs from current repo owner — cross-repo parent labels are user-controlled.
```

- [ ] **Step 7: Update Step 9b (Determine base branch) for cross-repo**

Replace the parent-body parsing block with:

```markdown
## Step 9b: Determine base branch (parent integration awareness)

If parent is same-repo, check for integration branch as before. If cross-repo, **always** fall back to configured `baseBranch` (cross-repo PRD epics don't have integration branches).

```bash
if [[ -n "$parent_n" ]]; then
  if [[ "$parent_owner/$parent_repo" == "$REPO" ]]; then
    # Same repo: check for integration branch in parent body
    parent_body=$(gh issue view "$parent_n" --repo "$REPO" --json body --jq '.body')
    integration_branch=$(echo "$parent_body" \
      | awk '/^## Integration branch/{flag=1; next} /^## /{flag=0} flag && /^`/{gsub("`",""); print; exit}')
    if [[ -n "$integration_branch" ]]; then
      BASE_BRANCH="$integration_branch"
    else
      BASE_BRANCH=$(sillok_config baseBranch)
    fi
  else
    # Cross-repo: no integration branch concept
    BASE_BRANCH=$(sillok_config baseBranch)
  fi
else
  BASE_BRANCH=$(sillok_config baseBranch)
fi
```
```

- [ ] **Step 8: Add new Step 10b — push + link branch**

Insert after Step 10 (Create worktree):

```markdown
## Step 10b: Push branch + link to issue (Development panel)

Push the new branch so GitHub knows about it, then register the linked-branch relationship.

```bash
worktree_path=".worktrees/<slug>"
(cd "$worktree_path" && git push -u origin "<branch>")

# Resolve SHA of new branch tip
BRANCH_SHA=$(cd "$worktree_path" && git rev-parse HEAD)

# Look up GraphQL node IDs and create the linked branch
source "${CLAUDE_PLUGIN_ROOT}/scripts/lib/dev-link.sh"
ISSUE_NODE_ID=$(sillok_issue_node_id "$REPO" "$N")
sillok_link_branch "$ISSUE_NODE_ID" "<branch>" "$BRANCH_SHA"
```
```

- [ ] **Step 9: Add new Step 10c — project item add + status Todo**

Insert after Step 10b:

```markdown
## Step 10c: Add to project + set status Todo

Idempotent — works whether the auto-add workflow has already fired or not.

```bash
source "${CLAUDE_PLUGIN_ROOT}/scripts/lib/project.sh"
ITEM_ID=$(sillok_project_item_add "$issue_url")
sillok_project_status_set "$ITEM_ID" todo
```
```

- [ ] **Step 10: Update Step 11 (Output) with new fields**

Replace with:

```markdown
## Step 11: Output

Print:

- Issue URL: `<issue_url>`
- Branch: `<branch>`
- Worktree path: `.worktrees/<slug>`
- Project item: `<ITEM_ID>`
- Status: `Todo`
- Linked branch: ✓
- Handoff: "Next: `cd .worktrees/<slug>` then run `/sillok-design` to write the spec."
```

- [ ] **Step 11: Commit**

```bash
git add commands/sillok-start.md
git commit -m "feat(sillok-start): assignee + Issue Type + cross-repo parent + project + linked branch (#14)"
```

---

## Task 9: Update scripts/precompute-design.sh — cross-repo PRD recognition + project status

**Files:**
- Modify: `scripts/precompute-design.sh`

- [ ] **Step 1: Read current script**

Identify the issue metadata fetch block.

- [ ] **Step 2: After issue fetch, parse parent — same vs cross-repo**

Add a block that extracts the parent reference from issue body:

```bash
# Parse parent (could be same-repo "Parent: #N" or cross-repo "Parent: owner/repo#N")
parent_line=$(echo "$issue_body" | grep -m1 -E '^Parent:' || true)
parent_repo=""
parent_n=""
if [[ "$parent_line" =~ Parent:[[:space:]]+([^/]+/[^#]+)#([0-9]+) ]]; then
  parent_repo="${BASH_REMATCH[1]}"
  parent_n="${BASH_REMATCH[2]}"
elif [[ "$parent_line" =~ Parent:[[:space:]]+#([0-9]+) ]]; then
  parent_repo="$REPO"
  parent_n="${BASH_REMATCH[1]}"
fi
```

- [ ] **Step 3: Output parent + status info**

After the existing output, add:

```bash
if [[ -n "$parent_n" ]]; then
  echo
  echo "### Parent"
  if [[ "$parent_repo" == "$REPO" ]]; then
    echo "- Same-repo parent: #$parent_n"
  else
    echo "- Cross-repo parent: $parent_repo#$parent_n (PRD epic)"
  fi
fi

# Project status
echo
echo "### Project status"
source "${SCRIPT_DIR}/lib/project.sh" 2>/dev/null || true
if command -v sillok_project_item_for_issue >/dev/null 2>&1; then
  item_id=$(sillok_project_item_for_issue "https://github.com/$REPO/issues/$N")
  if [[ -n "$item_id" ]]; then
    status=$(sillok_project_status_get "$item_id" || echo "")
    echo "- Item ID: $item_id"
    echo "- Status: ${status:-unknown}"
  else
    echo "- (not in project — will be added at /sillok-design step)"
  fi
fi
```

- [ ] **Step 4: Parse-check**

```bash
bash -n scripts/precompute-design.sh && echo "OK"
```

Expected: `OK`

- [ ] **Step 5: Commit**

```bash
git add scripts/precompute-design.sh
git commit -m "feat(precompute): expose parent (cross-repo aware) + project status (#14)"
```

---

## Task 10: Update commands/sillok-design.md — cross-repo PRD fetch + status In Design

**Files:**
- Modify: `commands/sillok-design.md`

- [ ] **Step 1: Read current file**

Identify Step 4 (Invoke brainstorming) and Step 7 (Flip stage label).

- [ ] **Step 2: Update Step 4 — fetch cross-repo PRD body if parent is cross-repo**

Prepend to the existing brainstorming invocation:

```markdown
## Step 4: Invoke brainstorming

If precompute reported a cross-repo parent (`parent_repo != REPO`), fetch the PRD body:

```bash
PRD_BODY=$(gh issue view "$parent_n" --repo "$parent_repo" --json body --jq '.body')
```

Use the `superpowers:brainstorming` skill. Seed it with:

- Issue title: `<title>`
- Issue body: full body fetched in step 1
- **Cross-repo PRD body (if any):** `$PRD_BODY`
- Current state: stage, parent, slug
```

- [ ] **Step 3: Replace Step 7 (Flip stage label) with project status update**

Replace the entire Step 7:

```markdown
## Step 7: Set project status to In Design

After explicit user confirmation in step 6:

```bash
source "${CLAUDE_PLUGIN_ROOT}/scripts/lib/project.sh"
ITEM_ID=$(sillok_project_item_for_issue "https://github.com/$REPO/issues/$N")
if [[ -z "$ITEM_ID" ]]; then
  # Edge case: auto-add didn't fire and start didn't add. Recover.
  ITEM_ID=$(sillok_project_item_add "https://github.com/$REPO/issues/$N")
fi
sillok_project_status_set "$ITEM_ID" design
```

The old stage label flip (`todo → designed`) is removed — stage now lives in the project's Status field.
```

- [ ] **Step 4: Update Step 9 (Output) with new wording**

Change handoff line from "label `designed`" to "status `In Design`":

```markdown
- Spec path: `<SPEC_DIR>/<date>-<slug>.md`
- Issue URL with `In Design` status
- Issue body updated with full spec content inlined under `## Design`
- Handoff: "Next: `/sillok-execute` to write the plan and ship the work."
```

- [ ] **Step 5: Commit**

```bash
git add commands/sillok-design.md
git commit -m "feat(sillok-design): cross-repo PRD fetch + status In Design (#14)"
```

---

## Task 11: Update scripts/precompute-execute.sh — project status

**Files:**
- Modify: `scripts/precompute-execute.sh`

- [ ] **Step 1: Append project status section**

Add to the end of the script (after existing output):

```bash
# Project status
echo
echo "### Project status"
source "${SCRIPT_DIR}/lib/project.sh" 2>/dev/null || true
if command -v sillok_project_item_for_issue >/dev/null 2>&1; then
  item_id=$(sillok_project_item_for_issue "https://github.com/$REPO/issues/$N")
  if [[ -n "$item_id" ]]; then
    status=$(sillok_project_status_get "$item_id" || echo "")
    echo "- Item ID: $item_id"
    echo "- Status: ${status:-unknown}"
  else
    echo "- (not in project)"
  fi
fi
```

- [ ] **Step 2: Parse-check**

```bash
bash -n scripts/precompute-execute.sh && echo "OK"
```

Expected: `OK`

- [ ] **Step 3: Commit**

```bash
git add scripts/precompute-execute.sh
git commit -m "feat(precompute): expose project status for execute (#14)"
```

---

## Task 12: Update commands/sillok-execute.md — status In Progress

**Files:**
- Modify: `commands/sillok-execute.md`

- [ ] **Step 1: Find Step 4 (write the plan) — replace stage label flip**

Replace the line:

```
- Flip stage label: `gh issue edit <N> --remove-label designed --add-label in-progress`.
```

with:

```
- Set project status to `In Progress`:

  ```bash
  source "${CLAUDE_PLUGIN_ROOT}/scripts/lib/project.sh"
  ITEM_ID=$(sillok_project_item_for_issue "https://github.com/$REPO/issues/$N")
  sillok_project_status_set "$ITEM_ID" progress
  ```
```

- [ ] **Step 2: Update Step 2 pre-condition**

Replace the stage-label pre-condition (`designed` / `todo` / `in-progress` / `in-review` label checks) with project status checks:

```markdown
## Step 2: Pre-condition

Project status was extracted by precompute (step 1). Apply:

- `In Design` → proceed.
- `Todo` → ABORT with "Spec not yet designed. Run `/sillok-design`."
- `In Progress` → resume; some/all tasks may already be done.
- `In QA` → ABORT with "PR already opened. Run `/sillok-end` to finalize, or fix the status manually."
```

- [ ] **Step 3: Update Step 9 output line**

Change `- Stage label confirmed \`in-progress\`` to `- Project status confirmed \`In Progress\``.

- [ ] **Step 4: Commit**

```bash
git add commands/sillok-execute.md
git commit -m "feat(sillok-execute): project status In Progress (#14)"
```

---

## Task 13: Update scripts/precompute-end.sh — project status

**Files:**
- Modify: `scripts/precompute-end.sh`

- [ ] **Step 1: Append project status section**

Same pattern as Task 11. Add at end of script:

```bash
echo
echo "### Project status"
source "${SCRIPT_DIR}/lib/project.sh" 2>/dev/null || true
if command -v sillok_project_item_for_issue >/dev/null 2>&1; then
  item_id=$(sillok_project_item_for_issue "https://github.com/$REPO/issues/$N")
  if [[ -n "$item_id" ]]; then
    status=$(sillok_project_status_get "$item_id" || echo "")
    echo "- Item ID: $item_id"
    echo "- Status: ${status:-unknown}"
  fi
fi
```

- [ ] **Step 2: Parse-check**

```bash
bash -n scripts/precompute-end.sh && echo "OK"
```

Expected: `OK`

- [ ] **Step 3: Commit**

```bash
git add scripts/precompute-end.sh
git commit -m "feat(precompute): expose project status for end (#14)"
```

---

## Task 14: Update commands/sillok-end.md — status In QA

**Files:**
- Modify: `commands/sillok-end.md`

- [ ] **Step 1: Find the stage-label flip to `in-review` and replace**

Replace:

```bash
gh issue edit <N> --remove-label in-progress --add-label in-review
```

with:

```bash
source "${CLAUDE_PLUGIN_ROOT}/scripts/lib/project.sh"
ITEM_ID=$(sillok_project_item_for_issue "https://github.com/$REPO/issues/$N")
sillok_project_status_set "$ITEM_ID" review
```

- [ ] **Step 2: Update pre-condition checks if any**

Look for stage-label gates (`in-progress`, etc.) in Step 2 or equivalent. Replace label-based gates with project-status checks (`In Progress` expected).

- [ ] **Step 3: Update output line**

Change any `- Stage label: \`in-review\`` to `- Project status: \`In QA\``.

- [ ] **Step 4: Commit**

```bash
git add commands/sillok-end.md
git commit -m "feat(sillok-end): project status In QA (#14)"
```

---

## Task 15: Rename commands/sillok-epic.md → commands/sillok-story.md + content

**Files:**
- Delete: `commands/sillok-epic.md`
- Create: `commands/sillok-story.md`

- [ ] **Step 1: Git rename**

```bash
git mv commands/sillok-epic.md commands/sillok-story.md
```

- [ ] **Step 2: Global replace "epic" → "story" in the file content**

Edit `commands/sillok-story.md`:

- Frontmatter `description`: replace "epic" → "story" throughout the line.
- Body: every reference to `epic` (as a label name, command name, or section title) → `story`.
- Branch template references: `epic/issue-<N>` → `story/issue-<N>`.
- Issue Type to apply: `story` → use `Story` (via the new Issue Type API path).
- Add a new step (after issue creation): use REST `type=Story` field, just like sillok-start does.

Critical sections that need new content (replacing label-flip logic):

```markdown
4. Create the issue with Issue Type = Story:

```bash
issue_url=$(gh api -X POST \
  -H "X-GitHub-Api-Version: 2026-03-10" \
  "/repos/$REPO/issues" \
  -f title="<epic title>" \
  -f body="<body>" \
  -f type="Story" \
  -f "assignees[]=$(gh api user --jq .login)" \
  -f "labels[]=p3" \
  --jq '.html_url')
```

Capture `<N>`.
```

- [ ] **Step 3: Add Step (after worktree creation): push + linked branch + project add**

After the existing "Push the branch to origin" step, ensure:

```bash
BRANCH_SHA=$(cd "$worktree_path" && git rev-parse HEAD)
source "${CLAUDE_PLUGIN_ROOT}/scripts/lib/dev-link.sh"
ISSUE_NODE_ID=$(sillok_issue_node_id "$REPO" "$N")
sillok_link_branch "$ISSUE_NODE_ID" "$epic_branch" "$BRANCH_SHA"

source "${CLAUDE_PLUGIN_ROOT}/scripts/lib/project.sh"
ITEM_ID=$(sillok_project_item_add "$issue_url")
sillok_project_status_set "$ITEM_ID" todo
```

- [ ] **Step 4: Promotion mode update**

In the promotion (§3) block:
- Replace `gh issue edit "$N" --remove-label "$current_type" --add-label epic` with type PATCH:

```bash
source "${CLAUDE_PLUGIN_ROOT}/scripts/lib/issue-types.sh"
sillok_issue_type_set "$REPO" "$N" Story
```

- After branch rename + new push, re-link the branch:

```bash
source "${CLAUDE_PLUGIN_ROOT}/scripts/lib/dev-link.sh"
ISSUE_NODE_ID=$(sillok_issue_node_id "$REPO" "$N")
BRANCH_SHA=$(git rev-parse HEAD)
sillok_link_branch "$ISSUE_NODE_ID" "$epic_branch" "$BRANCH_SHA"
```

- [ ] **Step 5: Commit**

```bash
git add commands/sillok-story.md
git commit -m "feat(sillok-story): rename from sillok-epic + Story type + project + linked branch (#14)"
```

---

## Task 16: Update scripts/write-shim-commands.sh — rename in shim list

**Files:**
- Modify: `scripts/write-shim-commands.sh`

- [ ] **Step 1: Find the shim list**

Identify the array or list of canonical command names (likely `start`, `design`, `execute`, `end`, `epic`).

- [ ] **Step 2: Replace `epic` with `story`**

Change the entry from `sillok-epic` to `sillok-story` (and adjust any `epic` references in the shim body template if present).

- [ ] **Step 3: Parse-check**

```bash
bash -n scripts/write-shim-commands.sh && echo "OK"
```

Expected: `OK`

- [ ] **Step 4: Commit**

```bash
git add scripts/write-shim-commands.sh
git commit -m "feat(shims): rename sillok-epic → sillok-story (#14)"
```

---

## Task 17: Update commands/sillok-init.md — verify types/project, new label classes

**Files:**
- Modify: `commands/sillok-init.md`

- [ ] **Step 1: Add Step 2b — verify Issue Types exist**

Insert after Step 2 (Detect repo and base branch):

```markdown
## Step 2b: Verify org Issue Types

```bash
OWNER="${REPO%%/*}"
expected_types=("Epic" "Story" "Feature" "Task" "Bug")
existing_types=$(gh api -H "X-GitHub-Api-Version: 2026-03-10" "/orgs/$OWNER/issue-types" --jq '.[].name' 2>/dev/null || echo "")

missing=()
for t in "${expected_types[@]}"; do
  if ! echo "$existing_types" | grep -qx "$t"; then
    missing+=("$t")
  fi
done

if [[ ${#missing[@]} -gt 0 ]]; then
  echo "[sillok-init] Required org issue types missing: ${missing[*]}"
  echo "  Ask your org owner to run:"
  for t in "${missing[@]}"; do
    echo "    gh api -X POST -H 'X-GitHub-Api-Version: 2026-03-10' /orgs/$OWNER/issue-types -f name=$t"
  done
  echo "  Or via UI: https://github.com/organizations/$OWNER/settings/issue-types"
  TYPES_STATUS=missing
else
  TYPES_STATUS=ok
fi
```

- [ ] **Step 2: Add Step 9b — verify project + status options**

Insert after Step 9 (Bootstrap labels):

```markdown
## Step 9b: Verify project + Status field options

If `project.owner` and `project.number` are configured, verify the project exists and the Status field has the expected option names.

```bash
PROJ_OWNER=$(jq -r '.project.owner' "$CFG")
PROJ_NUM=$(jq -r '.project.number' "$CFG")
if [[ -n "$PROJ_OWNER" && "$PROJ_NUM" != "0" && "$PROJ_NUM" != "null" ]]; then
  expected_opts=("Todo" "In Design" "In Progress" "In QA" "Done")
  actual_opts=$(gh api graphql -f query="{ organization(login: \"$PROJ_OWNER\") { projectV2(number: $PROJ_NUM) { field(name: \"Status\") { ... on ProjectV2SingleSelectField { options { name } } } } } }" --jq '.data.organization.projectV2.field.options[].name' 2>/dev/null || echo "")
  
  proj_missing=()
  for opt in "${expected_opts[@]}"; do
    if ! echo "$actual_opts" | grep -qx "$opt"; then
      proj_missing+=("$opt")
    fi
  done
  
  if [[ ${#proj_missing[@]} -gt 0 ]]; then
    echo "[sillok-init] Project $PROJ_OWNER/projects/$PROJ_NUM Status field missing options: ${proj_missing[*]}"
    echo "  Add via UI: https://github.com/orgs/$PROJ_OWNER/projects/$PROJ_NUM/settings"
    PROJECT_STATUS=incomplete
  else
    PROJECT_STATUS=ok
  fi
else
  PROJECT_STATUS=unconfigured
  echo "[sillok-init] Cross-repo PRD: set 'project.owner' and 'project.number' in workflow.config.json to enable status transitions"
fi
```

- [ ] **Step 3: Update Step 11 (Print summary) to include new statuses**

In the summary block, add lines:

```
- Org Issue Types (Epic/Story/Feature/Task/Bug)            [<TYPES_STATUS>]
- Project + Status options                                  [<PROJECT_STATUS>]
```

And update the headline calculation to factor in these:

```bash
if [[ "$TYPES_STATUS" == "missing" || "$PROJECT_STATUS" == "incomplete" ]]; then
  HEADLINE="⚠️  sillok initialized (with warnings — see below)"
fi
```

- [ ] **Step 4: Update Step 6 (Write workflow.config.json) — drop labels.types and labels.stages, use new schema**

Update the `jq -n` invocation in Step 6 to write the new structure (matching `templates/workflow.config.json` from Task 2). Important changes:
- Remove `labels.types`, `labels.stages` from output
- Add `prdRepo: ""`, `project: {...}`, `types: {...}`, `labels.natures`
- Update `labels.defaults` to only have `priority`

- [ ] **Step 5: Commit**

```bash
git add commands/sillok-init.md
git commit -m "feat(sillok-init): verify Issue Types + project, new schema (#14)"
```

---

## Task 18: Update skills/gh-issue-management/SKILL.md — major rewrite

**Files:**
- Modify: `skills/gh-issue-management/SKILL.md`

- [ ] **Step 1: Read current file**

It documents the v1 label-based workflow.

- [ ] **Step 2: Rewrite the "Issue schema" section**

Replace:
- "Type (apply ONE)" label table → "Type (Issue Type)" section explaining the 5 types and how they're applied via REST.
- "Stage (transitions over lifecycle)" label table → "Stage (Projects v2 Status)" section listing the 5 statuses and which sillok command sets which.

Add a new "Nature labels (optional)" section listing the new label class.

- [ ] **Step 3: Add cross-repo sub-issue linking section**

Add a paragraph + GraphQL example showing parent in a different repo:

```bash
PARENT_ID=$(gh api graphql -f query='query { repository(owner:"myorg-prd", name:"prd-repo") { issue(number:42) { id } } }' --jq '.data.repository.issue.id')
CHILD_ID=$(gh api graphql -f query='query { repository(owner:"myorg-code", name:"frontend") { issue(number:101) { id } } }' --jq '.data.repository.issue.id')
gh api graphql -f query="mutation { addSubIssue(input: { issueId: \"$PARENT_ID\", subIssueId: \"$CHILD_ID\" }) { issue { number } } }"
```

Note: same-org cross-repo linking is supported natively.

- [ ] **Step 4: Update the "Type vs Structure relationship" section**

Replace `epic` references with `Story` (in-repo composite) and add a paragraph on `Epic` (cross-repo PRD parent).

- [ ] **Step 5: Add a "Linked branches (Development panel)" section**

Document `createLinkedBranch` GraphQL and that sillok handles it automatically via the `scripts/lib/dev-link.sh` helper.

- [ ] **Step 6: Update "Common mistakes" section**

- Remove the "Creating an issue without any stage label" mistake (stages are now project status).
- Add: "Manually flipping stage labels — they no longer exist in v2; update project status instead."

- [ ] **Step 7: Commit**

```bash
git add skills/gh-issue-management/SKILL.md
git commit -m "feat(skill): rewrite gh-issue-management for v2 (#14)"
```

---

## Task 19: Update templates/rules/gh-issue-conventions.md to match skill

**Files:**
- Modify: `templates/rules/gh-issue-conventions.md`

- [ ] **Step 1: Read current rule file**

It's the always-on imported rule layer.

- [ ] **Step 2: Apply parallel updates to skill rewrite**

Mirror the changes from Task 18. Specifically:
- Type → Issue Types
- Stage → project Status
- Add Nature labels
- Cross-repo sub-issue example
- Replace `epic` with `Story` (and explain `Epic` as cross-repo PRD)

The rule file is more concise than the skill — keep it shorter.

- [ ] **Step 3: Commit**

```bash
git add templates/rules/gh-issue-conventions.md
git commit -m "feat(rules): align gh-issue-conventions with v2 skill (#14)"
```

---

## Task 20: Create scripts/migrate-v1-to-v2.sh — bulk migration helper

**Files:**
- Create: `scripts/migrate-v1-to-v2.sh`

- [ ] **Step 1: Write the script header + dry-run mode**

```bash
#!/usr/bin/env bash
# sillok — migrate a repo from v1 (label-based types + stages) to v2
# (Issue Types + Projects v2 status).
#
# Usage:
#   bash scripts/migrate-v1-to-v2.sh <repo>           # report only
#   bash scripts/migrate-v1-to-v2.sh <repo> --apply   # execute changes
#
# Idempotent: re-running after a partial migration is safe.

set -euo pipefail

REPO="${1:-}"
APPLY="${2:-}"

if [[ -z "$REPO" ]]; then
  echo "Usage: $0 <owner/repo> [--apply]" >&2
  exit 1
fi

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "$SCRIPT_DIR/lib/config.sh"
source "$SCRIPT_DIR/lib/issue-types.sh"
source "$SCRIPT_DIR/lib/project.sh"

# Mapping: v1 label → v2 Issue Type name
declare -a TYPE_MAP=(
  "feature:Feature"
  "bug:Bug"
  "improvement:Feature"   # was a type label; now a nature label is preferred but issue itself becomes Feature type
  "infra:Task"            # infra issues map to Task; "infra" becomes a nature label
  "epic:Story"            # in-repo composite epics become Story
)

# Mapping: v1 stage label → v2 status key
declare -a STAGE_MAP=(
  "todo:todo"
  "designed:design"
  "in-progress:progress"
  "in-review:review"
)
```

- [ ] **Step 2: Add the per-issue migration logic**

Continue the script:

```bash
echo "Scanning open issues in $REPO..."
issues=$(gh issue list --repo "$REPO" --state all --limit 500 --json number,labels --jq '.[]')

count=0
while IFS= read -r line; do
  num=$(echo "$line" | jq -r '.number')
  labels=$(echo "$line" | jq -r '[.labels[].name] | join(",")')
  
  # Determine target type
  target_type=""
  for pair in "${TYPE_MAP[@]}"; do
    label="${pair%%:*}"
    type="${pair##*:}"
    if echo ",$labels," | grep -q ",$label,"; then
      target_type="$type"
      break
    fi
  done
  
  # Determine target status
  target_status=""
  for pair in "${STAGE_MAP[@]}"; do
    label="${pair%%:*}"
    key="${pair##*:}"
    if echo ",$labels," | grep -q ",$label,"; then
      target_status="$key"
      break
    fi
  done
  
  if [[ -z "$target_type" && -z "$target_status" ]]; then
    continue
  fi
  
  count=$((count + 1))
  echo "  #$num: type=${target_type:-keep} status=${target_status:-keep}"
  
  if [[ "$APPLY" == "--apply" ]]; then
    # Apply type
    if [[ -n "$target_type" ]]; then
      sillok_issue_type_set "$REPO" "$num" "$target_type" || echo "    [warn] type set failed for #$num"
    fi
    # Apply status
    if [[ -n "$target_status" ]]; then
      issue_url="https://github.com/$REPO/issues/$num"
      item_id=$(sillok_project_item_add "$issue_url") || continue
      sillok_project_status_set "$item_id" "$target_status" || echo "    [warn] status set failed for #$num"
    fi
    # Remove old type/stage labels
    for old in feature bug improvement infra epic todo designed in-progress in-review; do
      gh issue edit "$num" --repo "$REPO" --remove-label "$old" 2>/dev/null || true
    done
  fi
done <<< "$issues"

if [[ "$APPLY" != "--apply" ]]; then
  echo
  echo "DRY RUN. $count issues would be migrated. Re-run with --apply to execute."
else
  echo
  echo "Migration complete. $count issues processed."
fi
```

- [ ] **Step 3: Make executable + parse-check**

```bash
chmod +x scripts/migrate-v1-to-v2.sh
bash -n scripts/migrate-v1-to-v2.sh && echo "OK: parses"
```

Expected: `OK: parses`

- [ ] **Step 4: Commit**

```bash
git add scripts/migrate-v1-to-v2.sh
git commit -m "feat(migrate): add v1→v2 bulk migration script (#14)"
```

---

## Task 21: Update existing tests for new label/type model

**Files:**
- Modify: any existing `tests/*.test.sh` that asserts old label names

- [ ] **Step 1: Grep for old label references in tests**

```bash
grep -rln "epic\|in-review\|designed\|in-progress" tests/ 2>/dev/null || echo "no matches"
```

For each file that matches, examine the test and update assertions to match the v2 model (Story/Issue Types, project status).

- [ ] **Step 2: Update each matched test**

For each file:
- Replace assertions about label `epic` → assertion about Issue Type `Story`
- Replace assertions about stage labels (`designed`, `in-progress`, etc.) → remove or replace with project status assertion
- Update fixture configs (any temp `workflow.config.json` constructions) to use v2 schema

- [ ] **Step 3: Run full test suite**

```bash
for t in tests/*.test.sh; do echo "=== $(basename $t) ==="; bash "$t" 2>&1 | tail -3; done
```

Verify all pass.

- [ ] **Step 4: Commit**

```bash
git add tests/
git commit -m "test: update existing tests for v2 type/status model (#14)"
```

---

## Task 22: Create tests/cross-repo-parent.test.sh

**Files:**
- Create: `tests/cross-repo-parent.test.sh`

- [ ] **Step 1: Write the test**

```bash
#!/usr/bin/env bash
# Unit test for cross-repo --parent parsing logic.
# Tests the regex used in sillok-start (without actually invoking the command).
set -euo pipefail

# Inline the parsing logic for unit testing
parse_parent() {
  local parent_arg="$1"
  if [[ "$parent_arg" =~ ^https?://github\.com/([^/]+)/([^/]+)/issues/([0-9]+)$ ]]; then
    echo "URL ${BASH_REMATCH[1]} ${BASH_REMATCH[2]} ${BASH_REMATCH[3]}"
  elif [[ "$parent_arg" =~ ^([^/]+)/([^#]+)#([0-9]+)$ ]]; then
    echo "CROSS ${BASH_REMATCH[1]} ${BASH_REMATCH[2]} ${BASH_REMATCH[3]}"
  elif [[ "$parent_arg" =~ ^[0-9]+$ ]]; then
    echo "LOCAL $parent_arg"
  else
    echo "INVALID"
  fi
}

# Test cases
expected_outputs=(
  "42::LOCAL 42"
  "myorg/prd#42::CROSS myorg prd 42"
  "https://github.com/myorg/prd/issues/42::URL myorg prd 42"
  "garbage::INVALID"
)

fails=0
for tc in "${expected_outputs[@]}"; do
  input="${tc%%::*}"
  expected="${tc#*::}"
  actual=$(parse_parent "$input")
  if [[ "$actual" == "$expected" ]]; then
    echo "PASS: $input → $actual"
  else
    echo "FAIL: $input → expected '$expected' got '$actual'"
    fails=$((fails + 1))
  fi
done

if [[ $fails -gt 0 ]]; then
  exit 1
fi
echo "OK: all $(echo "${expected_outputs[@]}" | wc -w) cases passed"
```

- [ ] **Step 2: Run the test**

```bash
bash tests/cross-repo-parent.test.sh
```

Expected: All PASS, `OK: all 4 cases passed`

- [ ] **Step 3: Commit**

```bash
git add tests/cross-repo-parent.test.sh
git commit -m "test: cross-repo --parent parsing unit test (#14)"
```

---

## Task 23: Create tests/migrate-v1-to-v2.test.sh

**Files:**
- Create: `tests/migrate-v1-to-v2.test.sh`

- [ ] **Step 1: Write the test (dry-run only — no real GitHub calls)**

```bash
#!/usr/bin/env bash
# Smoke test for migrate-v1-to-v2.sh.
# Verifies the script parses, exits cleanly in dry-run mode, and
# rejects missing args.
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
SCRIPT="$SCRIPT_DIR/../scripts/migrate-v1-to-v2.sh"

if [[ ! -x "$SCRIPT" ]]; then
  echo "FAIL: $SCRIPT not executable"
  exit 1
fi

# Test 1: no args → usage error
if bash "$SCRIPT" 2>&1 | grep -q "Usage:"; then
  echo "PASS: missing args shows usage"
else
  echo "FAIL: missing args did not show usage"
  exit 1
fi

# Test 2: parse check
if bash -n "$SCRIPT"; then
  echo "PASS: script parses"
else
  echo "FAIL: script does not parse"
  exit 1
fi

echo "OK: 2/2 smoke checks passed"
```

- [ ] **Step 2: Run the test**

```bash
bash tests/migrate-v1-to-v2.test.sh
```

Expected: `OK: 2/2 smoke checks passed`

- [ ] **Step 3: Commit**

```bash
git add tests/migrate-v1-to-v2.test.sh
git commit -m "test: smoke test for migration script (#14)"
```

---

## Task 24: Update README.md — workflow examples + prerequisites

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Update Install section — add org prerequisites**

Add a "Prerequisites" subsection that lists:
- `gh` CLI authenticated
- `jq`
- An organization (Issue Types are org-only)
- Org owner adds the missing Issue Types (Epic, Story — Feature/Task/Bug usually exist)
- A Projects v2 board with Status field configured (Todo / In Design / In Progress / In QA / Done) + auto-add workflow + item-closed-to-Done workflow

- [ ] **Step 2: Update workflow diagram**

Replace the workflow block:

```
/sillok-start    # create GH issue + Issue Type + assignee + branch + worktree + project Todo
/sillok-design   # brainstorm + spec → project status In Design
/sillok-execute  # write plan + dispatch subagent execution → project status In Progress
/sillok-end      # open PR → project status In QA → (auto Done on merge)
```

- [ ] **Step 3: Update Epic flow section**

Rename to "Story flow" (in-repo composite, replacing the old "Epic flow"). All command references `/sillok-epic` → `/sillok-story`. Reference `Story` Issue Type.

Add a new section: "Cross-repo PRD flow" explaining how `prdRepo` config + `--parent owner/repo#N` works.

- [ ] **Step 4: Update Config section**

Add `prdRepo`, `project`, `types`, `labels.natures` entries. Remove `labels.types` and `labels.stages`.

- [ ] **Step 5: Update "Files in your project after `/sillok-init`" tree**

Reflect the shim rename (`sillok-story.md` instead of `sillok-epic.md`).

- [ ] **Step 6: Commit**

```bash
git add README.md
git commit -m "docs(readme): document v2 workflow + prerequisites (#14)"
```

---

## Task 25: Update CHANGELOG.md + version bump

**Files:**
- Modify: `CHANGELOG.md`
- Modify: `.claude-plugin/plugin.json`
- Modify: `.claude-plugin/marketplace.json`

- [ ] **Step 1: Add v2.0.0 CHANGELOG entry**

Prepend under `[Unreleased]` (or as a new `[2.0.0]` section if Unreleased is empty):

```markdown
## [2.0.0] — 2026-05-22

### Breaking
- **Type labels removed.** Categorical work types (`feature`, `bug`, `improvement`, `infra`, `epic`) are no longer labels. Issues use **GitHub Issue Types** (org-level), introduced in the 2026-03-10 API. Migration script: `bash scripts/migrate-v1-to-v2.sh <repo>` (re-runs idempotently).
- **Stage labels removed.** Lifecycle stage (`todo`, `designed`, `in-progress`, `in-review`) moved to **Projects v2 Status field**. The 5 expected status options: `Todo`, `In Design`, `In Progress`, `In QA`, `Done`.
- **`/sillok-epic` renamed to `/sillok-story`.** In-repo composite issues are now `Story` type, not `Epic`. `Epic` type is reserved for cross-repo PRD parents.
- **New required prerequisites:** an organization with Issue Types configured (admin sets up Epic + Story; Feature/Task/Bug auto-exist), and a Projects v2 board with the 5 Status options + auto-add and item-closed-to-Done workflows enabled.

### Added
- **Cross-repo PRD parent linking.** `--parent owner/repo#N` and full URL forms accepted by `/sillok-start`. Sub-issue API works across same-org repos. Open PRD epics auto-suggested when `prdRepo` config is set.
- **Auto-assignee.** `/sillok-start` and `/sillok-story` assign the gh-authenticated user (`@me`).
- **Linked branches (Development panel).** `/sillok-start` and `/sillok-story` push the new branch and register `createLinkedBranch` so the issue's Development panel populates from creation.
- **Nature label class.** `improvement`, `refactor`, `infra`, `docs`, `security`, `performance` — orthogonal to Issue Type.
- **Migration script.** `scripts/migrate-v1-to-v2.sh` for bulk re-labeling existing issues.

### Internal
- New helper libraries: `scripts/lib/issue-types.sh`, `scripts/lib/project.sh`, `scripts/lib/dev-link.sh`.
- Major rewrite of `skills/gh-issue-management/SKILL.md` and `templates/rules/gh-issue-conventions.md`.

### Migration (5-step procedure)
1. Update plugin: `/plugin update sillok`.
2. Org owner adds missing Issue Types (Epic, Story) via web UI or API.
3. Configure Projects v2 board with the 5 Status options + workflows.
4. Re-run `/sillok-init` in each project. Updates labels, verifies prerequisites.
5. Optionally bulk-migrate existing issues: `bash scripts/migrate-v1-to-v2.sh <repo> --apply`.
```

- [ ] **Step 2: Bump version in plugin.json**

```bash
jq '.version = "2.0.0"' .claude-plugin/plugin.json > /tmp/plugin.json && mv /tmp/plugin.json .claude-plugin/plugin.json
```

- [ ] **Step 3: Bump version in marketplace.json**

```bash
jq '.plugins[0].version = "2.0.0"' .claude-plugin/marketplace.json > /tmp/marketplace.json && mv /tmp/marketplace.json .claude-plugin/marketplace.json
```

- [ ] **Step 4: Verify both JSON files parse**

```bash
jq empty .claude-plugin/plugin.json && jq empty .claude-plugin/marketplace.json && echo "OK"
```

Expected: `OK`

- [ ] **Step 5: Commit**

```bash
git add CHANGELOG.md .claude-plugin/plugin.json .claude-plugin/marketplace.json
git commit -m "chore(release): v2.0.0 — Issue Types + Projects v2 + cross-repo PRD (#14)"
```

---

## Task 26: Final sanity check — full test suite + smoke test

**Files:** (no file changes — verification only)

- [ ] **Step 1: Run full test suite**

```bash
cd /Users/jihoopark/sillok/.worktrees/14-support-cross-repo-prd-epic-workflow
for t in tests/*.test.sh; do echo "=== $(basename $t) ==="; bash "$t" 2>&1 | tail -2; done
```

Expected: all tests pass (last line of each = `OK:` or equivalent).

- [ ] **Step 2: Smoke-test the helper libraries source cleanly**

```bash
bash -c 'export CLAUDE_PLUGIN_ROOT=$(pwd) && source scripts/lib/config.sh && source scripts/lib/issue-types.sh && source scripts/lib/project.sh && source scripts/lib/dev-link.sh && echo "all helpers source cleanly"'
```

Expected: `all helpers source cleanly`

- [ ] **Step 3: Smoke-test precompute scripts run without error**

```bash
export CLAUDE_PLUGIN_ROOT=$(pwd)
bash scripts/precompute-start.sh > /dev/null && echo "precompute-start OK"
bash scripts/precompute-design.sh > /dev/null && echo "precompute-design OK"
bash scripts/precompute-execute.sh > /dev/null && echo "precompute-execute OK"
bash scripts/precompute-end.sh > /dev/null && echo "precompute-end OK"
```

Each should exit 0 with the OK message.

- [ ] **Step 4: Verify version bump consistency**

```bash
grep -c '"version": "2.0.0"' .claude-plugin/plugin.json
grep -c '"version": "2.0.0"' .claude-plugin/marketplace.json
grep -c '## \[2.0.0\]' CHANGELOG.md
```

All should output `1`.

- [ ] **Step 5: Verify no stray references to old labels in scripts/commands**

```bash
grep -rn '"label" *: *"epic"' commands/ scripts/ skills/ 2>/dev/null || echo "no stray 'epic' label refs"
grep -rn 'remove-label *epic\|add-label *epic' commands/ scripts/ 2>/dev/null || echo "no stray epic label-flip refs"
grep -rn 'remove-label *designed\|add-label *designed' commands/ scripts/ 2>/dev/null || echo "no stray designed label-flip refs"
```

Expected: each grep outputs only "no stray ..." (or empty if `|| echo` did not fire).

- [ ] **Step 6: Final summary commit (optional empty commit to mark completion)**

Skip if no changes needed. Otherwise:

```bash
git commit --allow-empty -m "chore: v2 implementation complete (#14)"
```

- [ ] **Step 7: Hand off to /sillok-end**

After all checks pass, the branch is ready for PR. The orchestrator (sillok-execute) will invoke the whole-branch review next (Step 8 of sillok-execute), then the user runs `/sillok-end`.

---

## Self-Review (run after writing the full plan)

**Spec coverage check:**

- ✅ Config schema additions (Task 1, 2)
- ✅ Three new helper libs (Tasks 3, 4, 5)
- ✅ bootstrap-labels update (Task 6)
- ✅ All 5 commands updated (Tasks 8, 10, 12, 14, 15) + their precomputes (Tasks 7, 9, 11, 13)
- ✅ Init verification (Task 17)
- ✅ Skill + rule template (Tasks 18, 19)
- ✅ Migration script (Task 20)
- ✅ Tests (Tasks 21, 22, 23)
- ✅ Release docs + version (Tasks 24, 25)
- ✅ Final verification (Task 26)

**Out of scope (deferred to v3, per spec):**
- `/sillok-prd` command — not in this plan
- Skill-wrapper refactor (#15) — not in this plan
- Cross-repo `Closes #N` automation — not in this plan
- Projects v2 auto-add workflow auto-configuration — not in this plan

**Placeholder scan:** no "TBD", "TODO", or vague instructions found in plan body.

**Type consistency:**
- Issue Types: `Epic`, `Story`, `Feature`, `Task`, `Bug` — consistent across all tasks.
- Project statuses: `Todo`, `In Design`, `In Progress`, `In QA`, `Done` — consistent.
- Helper function names: `sillok_issue_type_id`, `sillok_issue_type_set`, `sillok_project_item_for_issue`, `sillok_project_item_add`, `sillok_project_status_set`, `sillok_link_branch`, `sillok_issue_node_id` — consistent across plan tasks 3-5 and consumer tasks 8, 10, 12, 14, 15.

---

## Execution Handoff

Plan complete and saved to `docs/superpowers/plans/2026-05-22-support-cross-repo-prd-epic-workflow.md`.

**Locked execution mode: Subagent-Driven** (per `/sillok-execute` Step 4 — sillok auto-selects option 1 without re-prompting).

Next: use `superpowers:subagent-driven-development` to dispatch implementer + spec-reviewer + code-quality-reviewer subagents per task.
