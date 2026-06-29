#!/usr/bin/env bash
# sillok — workflow.config.json reader.
# Resolves config values with this precedence:
#   1. project's .claude/sillok/workflow.config.json (relative to git repo root)
#   2. plugin's templates/workflow.config.json (default fallback)
#
# Usage:
#   SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
#   source "$SCRIPT_DIR/lib/config.sh"
#   REPO=$(sillok_config repo)
#   # CLAUDE_PLUGIN_ROOT is optional — when unset, the plugin root is
#   # derived from this file's own location.
#   LINT=$(sillok_config verify.lint)
#   # bash 3.2-compatible array read (macOS-friendly):
#   COPY_FILES=()
#   while IFS= read -r line; do COPY_FILES+=("$line"); done < <(sillok_config_array worktree.copyFiles)
set -euo pipefail

# Resolve this file's directory under bash AND zsh (nounset-safe), so the
# plugin root can be derived when CLAUDE_PLUGIN_ROOT is not exported.
# zsh: ${(%):-%x} expands to the file currently being sourced; eval defers
# the zsh-only syntax so bash never parses it.
if [[ -n "${BASH_VERSION:-}" ]]; then
  _SILLOK_CONFIG_LIB_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
elif [[ -n "${ZSH_VERSION:-}" ]]; then
  eval '_SILLOK_CONFIG_LIB_DIR=$(cd "$(dirname "${(%):-%x}")" && pwd)'
else
  _SILLOK_CONFIG_LIB_DIR=$(cd "$(dirname "$0")" && pwd)
fi
_SILLOK_PLUGIN_ROOT_FALLBACK=$(cd "$_SILLOK_CONFIG_LIB_DIR/../.." && pwd)

_sillok_project_config() {
  local root
  root=$(git rev-parse --show-toplevel 2>/dev/null || echo "")
  if [[ -n "$root" && -f "$root/.claude/sillok/workflow.config.json" ]]; then
    echo "$root/.claude/sillok/workflow.config.json"
  fi
}

_sillok_default_config() {
  echo "${CLAUDE_PLUGIN_ROOT:-$_SILLOK_PLUGIN_ROOT_FALLBACK}/templates/workflow.config.json"
}

sillok_config() {
  local key="$1"
  local project default value
  project=$(_sillok_project_config)
  default=$(_sillok_default_config)

  if [[ -n "$project" ]]; then
    value=$(jq -r --arg k "$key" 'getpath($k | split("."))' "$project" 2>/dev/null || echo "null")
    if [[ "$value" != "null" && "$value" != "" ]]; then
      echo "$value"
      return 0
    fi
  fi

  if [[ -f "$default" ]]; then
    value=$(jq -r --arg k "$key" 'getpath($k | split("."))' "$default" 2>/dev/null || echo "null")
    if [[ "$value" != "null" ]]; then
      echo "$value"
      return 0
    fi
  fi

  echo ""
}

sillok_config_array() {
  local key="$1"
  local project default output
  project=$(_sillok_project_config)
  default=$(_sillok_default_config)

  if [[ -n "$project" ]]; then
    output=$(jq -r --arg k "$key" 'getpath($k | split(".")) // [] | .[]' "$project" 2>/dev/null) || true
    if [[ -n "$output" ]]; then
      printf '%s\n' "$output"
      return 0
    fi
  fi
  if [[ -f "$default" ]]; then
    jq -r --arg k "$key" 'getpath($k | split(".")) // [] | .[]' "$default"
  fi
}

sillok_config_required() {
  local key="$1"
  local value
  value=$(sillok_config "$key")
  if [[ -z "$value" ]]; then
    echo "[sillok] required config key not set: $key" >&2
    echo "[sillok] edit .claude/sillok/workflow.config.json" >&2
    return 1
  fi
  echo "$value"
}

# Build a regex that matches any branch produced by the configured template.
# Substitutes {type} with an alternation of labels.types values, and {user}
# with .+ (any non-empty run). Escapes regex metacharacters in literal parts.
sillok_branch_prefix_regex() {
  local template
  template=$(sillok_config branchPrefix)
  [[ -z "$template" ]] && { echo ""; return 1; }

  # Escape regex metacharacters EXCEPT { and } (placeholders).
  local escaped
  escaped=$(printf '%s' "$template" | sed -e 's/[][\.^$*+?()|]/\\&/g')

  # Build the {type} alternation from labels.types.
  local types_alt
  # v2: types live in types.list (Title-cased Issue Type names).
  # Branch prefixes use lowercase forms (story, feature, bug, task).
  # We lowercase the list here. Filter out "Epic" — PRDs live in the PRD
  # repo and don't have code branches, so an epic/* branch shouldn't match.
  types_alt=$(sillok_config_array types.list \
    | grep -v '^Epic$' \
    | tr '[:upper:]' '[:lower:]' \
    | tr '\n' '|' | sed 's/|$//')
  if [[ -z "$types_alt" ]]; then
    types_alt="feature|story|bug|task"
  fi

  local result="$escaped"
  result=${result//\{type\}/($types_alt)}
  result=${result//\{user\}/.+}
  printf '%s' "$result"
}

# Resolve a concrete branch prefix for a specific type + user.
sillok_branch_prefix_resolve() {
  local type="$1"
  local user="${2:-}"
  local template
  template=$(sillok_config branchPrefix)
  local result="$template"
  result=${result//\{type\}/$type}
  result=${result//\{user\}/$user}
  printf '%s' "$result"
}

# Read the integration branch named under the `## Integration branch` heading
# in a parent issue's body. Prints the branch name (backticks stripped) or
# empty. The caller must gate same-repo-only before calling — cross-repo PRD
# epics have no in-repo integration branch. Shared by /sillok-start (Step 9b)
# and /sillok-end (PR base resolution) so the parse lives in one place.
# zsh-safe: the match runs inside awk (no BASH_REMATCH / [[ =~ ]]).
sillok_parent_integration_branch() {
  local n="$1" repo="${2:-$(sillok_config repo)}" body
  body=$(gh issue view "$n" --repo "$repo" --json body --jq '.body' 2>/dev/null || echo "")
  printf '%s' "$body" \
    | awk '/^## Integration branch/{flag=1; next} /^## /{flag=0} flag && /^`/{gsub("`",""); print; exit}'
}
