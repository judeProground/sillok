#!/usr/bin/env bash
# Tests for scripts/parse-project-url.sh
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$REPO_ROOT/scripts/parse-project-url.sh"

fail() { echo "FAIL: $1" >&2; exit 1; }
pass() { echo "  ok: $1"; }

run_case() {
  local url="$1"; local expected="$2"
  local actual
  actual=$(bash "$SCRIPT" "$url" 2>/dev/null || true)
  [[ "$actual" == "$expected" ]] || fail "url='$url' expected='$expected' got='$actual'"
  pass "$url"
}

# Org project
run_case "https://github.com/orgs/acme/projects/3" \
$'owner=acme\nnumber=3'

# User project
run_case "https://github.com/users/jude/projects/12" \
$'owner=jude\nnumber=12'

# Tolerates trailing path segments (views, settings)
run_case "https://github.com/orgs/foo/projects/3/views/1" \
$'owner=foo\nnumber=3'

# Garbage → empty (no output)
run_case "not-a-url" ""
run_case "https://github.com/orgs/foo" ""
run_case "https://example.com/orgs/foo/projects/3" ""

echo "test: missing arg exits non-zero"
bash "$SCRIPT" 2>/dev/null && fail "expected non-zero exit with no args"
pass "no-arg invocation exits non-zero"

echo
echo "All parse-project-url.sh tests passed."
