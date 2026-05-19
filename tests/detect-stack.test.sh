#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$REPO_ROOT/scripts/detect-stack.sh"

fail() { echo "FAIL: $1" >&2; exit 1; }
pass() { echo "  ok: $1"; }

run_case() {
  local name="$1"
  local lockfile="$2"
  local expected_install="$3"
  echo "test: $name"
  tmp=$(mktemp -d)
  touch "$tmp/$lockfile"
  out=$("$SCRIPT" "$tmp")
  install_line=$(echo "$out" | grep '^install=' | cut -d= -f2-)
  [[ "$install_line" == "$expected_install" ]] || fail "expected install='$expected_install', got '$install_line'"
  pass "$lockfile → install=$expected_install"
  rm -rf "$tmp"
}

run_case "pnpm"      pnpm-lock.yaml    "pnpm install"
run_case "yarn"      yarn.lock         "yarn install"
run_case "bun"       bun.lockb         "bun install"
run_case "npm"       package-lock.json "npm install"
run_case "bundler"   Gemfile.lock      "bundle install"
run_case "go"        go.sum            "go mod download"
run_case "cargo"     Cargo.lock        "cargo fetch"
run_case "poetry"    poetry.lock       "poetry install"
run_case "pipenv"    Pipfile.lock      "pipenv install"

echo "test: unknown stack yields empty install"
tmp=$(mktemp -d)
out=$("$SCRIPT" "$tmp")
install_line=$(echo "$out" | grep '^install=' | cut -d= -f2-)
[[ "$install_line" == "" ]] || fail "expected empty install, got '$install_line'"
pass "unknown stack → empty install"
rm -rf "$tmp"

echo
echo "All detect-stack.sh tests passed."
