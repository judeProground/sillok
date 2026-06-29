#!/usr/bin/env bash
# Tests for scripts/write-shim-commands.sh
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$REPO_ROOT/scripts/write-shim-commands.sh"

fail() { echo "FAIL: $1" >&2; exit 1; }
pass() { echo "  ok: $1"; }

TMPDIR_PROJECT=$(mktemp -d)
trap 'rm -rf "$TMPDIR_PROJECT"' EXIT

echo "test: writes seven shim files into .claude/commands on fresh project"
bash "$SCRIPT" "$TMPDIR_PROJECT" >/dev/null
for cmd in start design execute end story add epic; do
  dest="$TMPDIR_PROJECT/.claude/commands/sillok-$cmd.md"
  [[ -f "$dest" ]] || fail "expected $dest to exist"
done
pass "seven shim files written"

echo "test: shim files contain the sillok-shim marker"
for cmd in start design execute end story add epic; do
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

echo "test: shim resolution is marketplace-agnostic (newest version wins across marketplaces)"
# The shim instructs Claude to run a one-liner that resolves the latest
# installed sillok version. Extract that exact command from a generated shim
# and execute it against a fake cache tree where the OLDER version lives in a
# marketplace whose name sorts LAST — a naive full-path `sort -V` would pick
# it; the version-segment sort must not.
TMP3=$(mktemp -d)
FAKE_HOME=$(mktemp -d)
mkdir -p "$FAKE_HOME/.claude/plugins/cache/zz-legacy-marketplace/sillok/3.0.0"
mkdir -p "$FAKE_HOME/.claude/plugins/cache/aa-marketplace/sillok/3.0.1"
mkdir -p "$FAKE_HOME/.claude/plugins/cache/aa-marketplace/other-plugin/9.9.9"
bash "$SCRIPT" "$TMP3" >/dev/null
# Pull the fenced bash block (the resolution one-liner) out of the shim.
resolve_cmd=$(awk '/^```bash$/{f=1;next} /^```$/{f=0} f' "$TMP3/.claude/commands/sillok-start.md")
[[ -n "$resolve_cmd" ]] || fail "could not extract resolution command from shim"
echo "$resolve_cmd" | grep -q 'cache/\*/sillok' || fail "resolution command is not marketplace-agnostic: $resolve_cmd"
resolved=$(HOME="$FAKE_HOME" bash -c "$resolve_cmd")
[[ "$resolved" == "$FAKE_HOME/.claude/plugins/cache/aa-marketplace/sillok/3.0.1/" ]] \
  || fail "expected newest version (3.0.1) to win regardless of marketplace name; got '$resolved'"
# Multi-digit patch must beat single-digit under sort -V.
mkdir -p "$FAKE_HOME/.claude/plugins/cache/zz-legacy-marketplace/sillok/3.0.10"
resolved=$(HOME="$FAKE_HOME" bash -c "$resolve_cmd")
[[ "$resolved" == "$FAKE_HOME/.claude/plugins/cache/zz-legacy-marketplace/sillok/3.0.10/" ]] \
  || fail "expected version sort (3.0.10 > 3.0.1); got '$resolved'"
# Empty cache: no output, no error.
EMPTY_HOME=$(mktemp -d)
resolved=$(HOME="$EMPTY_HOME" bash -c "$resolve_cmd" 2>&1) || fail "resolution command errored on empty cache"
[[ -z "$resolved" ]] || fail "expected empty output on empty cache; got '$resolved'"
rm -rf "$TMP3" "$FAKE_HOME" "$EMPTY_HOME"
pass "cross-marketplace resolution picks newest version; empty cache is silent"

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
