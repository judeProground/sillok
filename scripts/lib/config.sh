#!/usr/bin/env bash
# sillok — workflow.config.json reader.
# Resolves config values with this precedence:
#   1. project's .claude/sillok/workflow.config.json (relative to git repo root)
#   2. plugin's templates/workflow.config.json (default fallback)
#
# Usage:
#   source "${CLAUDE_PLUGIN_ROOT}/scripts/lib/config.sh"
#   REPO=$(sillok_config repo)
#   LINT=$(sillok_config verify.lint)
#   # bash 3.2-compatible array read (macOS-friendly):
#   COPY_FILES=()
#   while IFS= read -r line; do COPY_FILES+=("$line"); done < <(sillok_config_array worktree.copyFiles)
set -euo pipefail

_sillok_project_config() {
  local root
  root=$(git rev-parse --show-toplevel 2>/dev/null || echo "")
  if [[ -n "$root" && -f "$root/.claude/sillok/workflow.config.json" ]]; then
    echo "$root/.claude/sillok/workflow.config.json"
  fi
}

_sillok_default_config() {
  echo "${CLAUDE_PLUGIN_ROOT}/templates/workflow.config.json"
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
  local project default
  project=$(_sillok_project_config)
  default=$(_sillok_default_config)

  if [[ -n "$project" ]]; then
    jq -r --arg k "$key" 'getpath($k | split(".")) // [] | .[]' "$project" 2>/dev/null && return 0
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
  types_alt=$(sillok_config_array labels.types | tr '\n' '|' | sed 's/|$//')
  if [[ -z "$types_alt" ]]; then
    types_alt="feature|bug|improvement|infra|epic"
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
