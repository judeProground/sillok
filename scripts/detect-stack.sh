#!/usr/bin/env bash
# sillok — infer install / verify commands from lockfile presence.
#
# For npm-family stacks (npm/yarn/pnpm/bun), lint/format/typecheck are
# validated against package.json#scripts before emission: if the matching
# script name does not exist, the field is emitted as empty rather than
# guessed. This avoids producing config that fails at verify-gate time with
# "Command 'lint' not found." Typecheck has an extra fallback: if no
# `typecheck` script exists but a tsconfig.json is present, we emit
# `npx tsc --noEmit` (or `bunx tsc --noEmit` for bun).
#
# For non-npm stacks (bundler/go/cargo/poetry/pipenv), the commands are
# tool-conventional and emitted as-is — those ecosystems don't have a
# scripts-table to validate against in the same way.
#
# Outputs four lines, key=value, for install, lint, typecheck, format.
# Empty value means "not inferable".
#
# usage: detect-stack.sh [project_root]
set -euo pipefail

root="${1:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"

install=""
lint=""
typecheck=""
format=""

# resolve_script <runner-prefix> <script-name>
# Echoes "<runner-prefix> <script-name>" iff the script exists in
# <root>/package.json under the .scripts table, else empty string.
resolve_script() {
  local prefix="$1" name="$2"
  if [[ -f "$root/package.json" ]] && command -v jq >/dev/null 2>&1; then
    if jq -e --arg n "$name" '(.scripts // {}) | has($n)' "$root/package.json" >/dev/null 2>&1; then
      printf '%s %s' "$prefix" "$name"
      return
    fi
  fi
  printf ''
}

# resolve_tsc <exec-prefix>
# Echoes "<exec-prefix> tsc --noEmit" iff a tsconfig.json exists at root.
# Used as a typecheck fallback when no `typecheck` script is defined but
# the project is clearly TypeScript.
resolve_tsc() {
  local exec_prefix="$1"
  if [[ -f "$root/tsconfig.json" ]]; then
    printf '%s tsc --noEmit' "$exec_prefix"
  else
    printf ''
  fi
}

if   [[ -f "$root/pnpm-lock.yaml" ]]; then
  install="pnpm install"
  lint=$(resolve_script "pnpm" lint)
  format=$(resolve_script "pnpm" format)
  typecheck=$(resolve_script "pnpm" typecheck)
  [[ -z "$typecheck" ]] && typecheck=$(resolve_tsc "npx")
elif [[ -f "$root/yarn.lock" ]]; then
  install="yarn install"
  lint=$(resolve_script "yarn" lint)
  format=$(resolve_script "yarn" format)
  typecheck=$(resolve_script "yarn" typecheck)
  [[ -z "$typecheck" ]] && typecheck=$(resolve_tsc "npx")
elif [[ -f "$root/bun.lockb" || -f "$root/bun.lock" ]]; then
  install="bun install"
  lint=$(resolve_script "bun run" lint)
  format=$(resolve_script "bun run" format)
  typecheck=$(resolve_script "bun run" typecheck)
  [[ -z "$typecheck" ]] && typecheck=$(resolve_tsc "bunx")
elif [[ -f "$root/package-lock.json" ]]; then
  install="npm install"
  lint=$(resolve_script "npm run" lint)
  format=$(resolve_script "npm run" format)
  typecheck=$(resolve_script "npm run" typecheck)
  [[ -z "$typecheck" ]] && typecheck=$(resolve_tsc "npx")
elif [[ -f "$root/Gemfile.lock" ]]; then
  install="bundle install"
  lint="bundle exec rubocop"
  typecheck=""
  format="bundle exec rubocop -a"
elif [[ -f "$root/go.sum" ]]; then
  install="go mod download"
  lint="golangci-lint run"
  typecheck="go vet ./..."
  format="gofmt -w ."
elif [[ -f "$root/Cargo.lock" ]]; then
  install="cargo fetch"
  lint="cargo clippy --all-targets -- -D warnings"
  typecheck="cargo check"
  format="cargo fmt"
elif [[ -f "$root/poetry.lock" ]]; then
  install="poetry install"
  lint="poetry run ruff check ."
  typecheck="poetry run mypy ."
  format="poetry run ruff format ."
elif [[ -f "$root/Pipfile.lock" ]]; then
  install="pipenv install"
  lint="pipenv run ruff check ."
  typecheck="pipenv run mypy ."
  format="pipenv run ruff format ."
fi

echo "install=$install"
echo "lint=$lint"
echo "typecheck=$typecheck"
echo "format=$format"
