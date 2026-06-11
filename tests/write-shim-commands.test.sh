#!/usr/bin/env bash
# Tests for scripts/write-shim-commands.sh
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$REPO_ROOT/scripts/write-shim-commands.sh"

fail() { echo "FAIL: $1" >&2; exit 1; }
pass() { echo "  ok: $1"; }

TMPDIR_PROJECT=$(mktemp -d)
trap 'rm -rf "$TMPDIR_PROJECT"' EXIT

echo "test: writes six shim files into .claude/commands on fresh project"
bash "$SCRIPT" "$TMPDIR_PROJECT" >/dev/null
for cmd in start design execute end story add; do
  dest="$TMPDIR_PROJECT/.claude/commands/sillok-$cmd.md"
  [[ -f "$dest" ]] || fail "expected $dest to exist"
done
pass "six shim files written"

echo "test: shim files contain the sillok-shim marker"
for cmd in start design execute end story add; do
  dest="$TMPDIR_PROJECT/.claude/commands/sillok-$cmd.md"
  grep -q '^sillok-shim: true$' "$dest" || fail "missing marker in $dest"
done
pass "all shims carry sillok-shim: true marker"

echo "test: shim template placeholder is substituted"
grep -q 'sillok-start' "$TMPDIR_PROJECT/.claude/commands/sillok-start.md" || fail "no sillok-start reference"
grep -q '{{COMMAND}}' "$TMPDIR_PROJECT/.claude/commands/sillok-start.md" && fail "raw placeholder leaked"
pass "placeholder substitution worked, no raw {{COMMAND}} left"

echo "test: re-running silently refreshes managed shims"
output=$(bash "$SCRIPT" "$TMPDIR_PROJECT")
echo "$output" | grep -q 'refreshed' || fail "expected refresh count in summary; got: $output"
pass "second run refreshes managed shims"

echo "test: foreign file (no marker) is skipped, not clobbered"
TMP2=$(mktemp -d)
mkdir -p "$TMP2/.claude/commands"
cat > "$TMP2/.claude/commands/sillok-start.md" <<'EOF'
---
description: A user's own custom sillok-start command.
---

This is my hand-written command, do not touch.
EOF
bash "$SCRIPT" "$TMP2" >/dev/null
contents=$(cat "$TMP2/.claude/commands/sillok-start.md")
echo "$contents" | grep -q 'hand-written' || fail "foreign file was overwritten"
echo "$contents" | grep -q 'sillok-shim: true' && fail "foreign file gained shim marker"
# Other shims (design/execute/end/story) should still be written.
[[ -f "$TMP2/.claude/commands/sillok-design.md" ]] || fail "expected sillok-design.md to be written despite foreign sillok-start.md"
rm -rf "$TMP2"
pass "foreign sillok-start.md preserved; siblings still written"

echo "test: script exits non-zero on missing project root"
if bash "$SCRIPT" /this/path/does/not/exist 2>/dev/null; then
  fail "expected non-zero exit for missing project root"
fi
pass "missing project root exits non-zero"

echo "test: script exits non-zero with no arguments"
if bash "$SCRIPT" 2>/dev/null; then
  fail "expected non-zero exit with no args"
fi
pass "no-arg invocation exits non-zero"

echo
echo "All write-shim-commands.sh tests passed."
