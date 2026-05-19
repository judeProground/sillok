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
