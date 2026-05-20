#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$REPO_ROOT/scripts/detect-stack.sh"

fail() { echo "FAIL: $1" >&2; exit 1; }
pass() { echo "  ok: $1"; }

read_field() {
  local key="$1" out="$2"
  echo "$out" | grep "^${key}=" | cut -d= -f2-
}

run_case() {
  local name="$1"
  local lockfile="$2"
  local expected_install="$3"
  echo "test: $name"
  tmp=$(mktemp -d)
  touch "$tmp/$lockfile"
  out=$("$SCRIPT" "$tmp")
  install_line=$(read_field install "$out")
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
install_line=$(read_field install "$out")
[[ "$install_line" == "" ]] || fail "expected empty install, got '$install_line'"
pass "unknown stack → empty install"
rm -rf "$tmp"

# ---- npm-family scripts validation ----

echo "test: yarn project with no package.json → lint/format empty, typecheck empty"
tmp=$(mktemp -d)
touch "$tmp/yarn.lock"
out=$("$SCRIPT" "$tmp")
lint_line=$(read_field lint "$out")
format_line=$(read_field format "$out")
typecheck_line=$(read_field typecheck "$out")
[[ "$lint_line" == "" ]] || fail "expected empty lint, got '$lint_line'"
[[ "$format_line" == "" ]] || fail "expected empty format, got '$format_line'"
[[ "$typecheck_line" == "" ]] || fail "expected empty typecheck (no tsconfig), got '$typecheck_line'"
rm -rf "$tmp"
pass "yarn + no package.json → all empty"

echo "test: yarn project with package.json but no relevant scripts → lint/format empty"
tmp=$(mktemp -d)
touch "$tmp/yarn.lock"
echo '{"scripts":{"prepush":"some-command","check:all":"other"}}' > "$tmp/package.json"
out=$("$SCRIPT" "$tmp")
lint_line=$(read_field lint "$out")
format_line=$(read_field format "$out")
[[ "$lint_line" == "" ]] || fail "expected empty lint, got '$lint_line'"
[[ "$format_line" == "" ]] || fail "expected empty format, got '$format_line'"
rm -rf "$tmp"
pass "yarn + irrelevant scripts → lint/format empty"

echo "test: yarn project with lint+format scripts → both emit yarn <name>"
tmp=$(mktemp -d)
touch "$tmp/yarn.lock"
echo '{"scripts":{"lint":"eslint .","format":"prettier --check ."}}' > "$tmp/package.json"
out=$("$SCRIPT" "$tmp")
lint_line=$(read_field lint "$out")
format_line=$(read_field format "$out")
[[ "$lint_line" == "yarn lint" ]] || fail "expected 'yarn lint', got '$lint_line'"
[[ "$format_line" == "yarn format" ]] || fail "expected 'yarn format', got '$format_line'"
rm -rf "$tmp"
pass "yarn + lint/format scripts → emitted"

echo "test: yarn project with typecheck script → emits yarn typecheck (not tsc fallback)"
tmp=$(mktemp -d)
touch "$tmp/yarn.lock"
echo '{"scripts":{"typecheck":"tsc --noEmit"}}' > "$tmp/package.json"
touch "$tmp/tsconfig.json"
out=$("$SCRIPT" "$tmp")
typecheck_line=$(read_field typecheck "$out")
[[ "$typecheck_line" == "yarn typecheck" ]] || fail "expected 'yarn typecheck', got '$typecheck_line'"
rm -rf "$tmp"
pass "yarn + typecheck script → 'yarn typecheck'"

echo "test: yarn TypeScript project without typecheck script → falls back to npx tsc --noEmit"
tmp=$(mktemp -d)
touch "$tmp/yarn.lock"
echo '{"scripts":{}}' > "$tmp/package.json"
touch "$tmp/tsconfig.json"
out=$("$SCRIPT" "$tmp")
typecheck_line=$(read_field typecheck "$out")
[[ "$typecheck_line" == "npx tsc --noEmit" ]] || fail "expected 'npx tsc --noEmit', got '$typecheck_line'"
rm -rf "$tmp"
pass "yarn + tsconfig.json (no script) → npx tsc fallback"

echo "test: bun project with no typecheck script but tsconfig → bunx tsc --noEmit"
tmp=$(mktemp -d)
touch "$tmp/bun.lockb"
echo '{"scripts":{"lint":"eslint ."}}' > "$tmp/package.json"
touch "$tmp/tsconfig.json"
out=$("$SCRIPT" "$tmp")
typecheck_line=$(read_field typecheck "$out")
lint_line=$(read_field lint "$out")
[[ "$typecheck_line" == "bunx tsc --noEmit" ]] || fail "expected 'bunx tsc --noEmit', got '$typecheck_line'"
[[ "$lint_line" == "bun run lint" ]] || fail "expected 'bun run lint', got '$lint_line'"
rm -rf "$tmp"
pass "bun + tsconfig.json (no script) → bunx tsc fallback; bun run lint"

echo "test: npm project with lint script → 'npm run lint'"
tmp=$(mktemp -d)
touch "$tmp/package-lock.json"
echo '{"scripts":{"lint":"eslint ."}}' > "$tmp/package.json"
out=$("$SCRIPT" "$tmp")
lint_line=$(read_field lint "$out")
[[ "$lint_line" == "npm run lint" ]] || fail "expected 'npm run lint', got '$lint_line'"
rm -rf "$tmp"
pass "npm + lint script → 'npm run lint'"

echo "test: pnpm project without any of lint/format/typecheck scripts and no tsconfig → all empty"
tmp=$(mktemp -d)
touch "$tmp/pnpm-lock.yaml"
echo '{"scripts":{"build":"vite build"}}' > "$tmp/package.json"
out=$("$SCRIPT" "$tmp")
lint_line=$(read_field lint "$out")
format_line=$(read_field format "$out")
typecheck_line=$(read_field typecheck "$out")
[[ "$lint_line" == "" ]] || fail "expected empty lint, got '$lint_line'"
[[ "$format_line" == "" ]] || fail "expected empty format, got '$format_line'"
[[ "$typecheck_line" == "" ]] || fail "expected empty typecheck, got '$typecheck_line'"
rm -rf "$tmp"
pass "pnpm + no relevant scripts + no tsconfig → all empty"

echo "test: non-npm stack (go) is unaffected by validation"
tmp=$(mktemp -d)
touch "$tmp/go.sum"
out=$("$SCRIPT" "$tmp")
lint_line=$(read_field lint "$out")
typecheck_line=$(read_field typecheck "$out")
format_line=$(read_field format "$out")
[[ "$lint_line" == "golangci-lint run" ]] || fail "expected 'golangci-lint run', got '$lint_line'"
[[ "$typecheck_line" == "go vet ./..." ]] || fail "expected 'go vet ./...', got '$typecheck_line'"
[[ "$format_line" == "gofmt -w ." ]] || fail "expected 'gofmt -w .', got '$format_line'"
rm -rf "$tmp"
pass "go → tool-conventional commands unchanged"

echo
echo "All detect-stack.sh tests passed."
