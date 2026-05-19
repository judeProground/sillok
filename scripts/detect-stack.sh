#!/usr/bin/env bash
# sillok — infer install / verify commands from lockfile presence.
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

if   [[ -f "$root/pnpm-lock.yaml" ]]; then
  install="pnpm install"
  lint="pnpm lint"
  typecheck="npx tsc --noEmit"
  format="pnpm format"
elif [[ -f "$root/yarn.lock" ]]; then
  install="yarn install"
  lint="yarn lint"
  typecheck="npx tsc --noEmit"
  format="yarn format"
elif [[ -f "$root/bun.lockb" || -f "$root/bun.lock" ]]; then
  install="bun install"
  lint="bun run lint"
  typecheck="bunx tsc --noEmit"
  format="bun run format"
elif [[ -f "$root/package-lock.json" ]]; then
  install="npm install"
  lint="npm run lint"
  typecheck="npx tsc --noEmit"
  format="npm run format"
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
