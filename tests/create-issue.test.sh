#!/usr/bin/env bash
# Tests scripts/create-issue.sh: the orgMode fork, label/type construction, the
# stdout contract (html_url only), and that empty labels are never emitted.
# Hermetic: gh is stubbed (no network); config lives in a throwaway git project.
set -euo pipefail

PLUGIN_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT"
SCRIPT="$PLUGIN_ROOT/scripts/create-issue.sh"

fail() { echo "FAIL: $1" >&2; exit 1; }
pass() { echo "  ok: $1"; }

WORKDIR=$(mktemp -d)
export ARGS_LOG="$WORKDIR/args.log"
trap 'rm -rf "$WORKDIR"' EXIT

# gh stub: `gh api user` → a login; `gh api -X POST …` → record argv + print URL.
STUB="$WORKDIR/bin"
mkdir -p "$STUB"
cat > "$STUB/gh" <<'STUB'
#!/bin/sh
if [ "$1" = "api" ] && [ "$2" = "user" ]; then echo "tester"; exit 0; fi
if [ "$1" = "api" ]; then
  : > "$ARGS_LOG"
  for a in "$@"; do printf '%s\n' "$a" >> "$ARGS_LOG"; done
  echo "https://github.com/o/r/issues/123"
  exit 0
fi
exit 1
STUB
chmod +x "$STUB/gh"

make_project() {
  local org="$1"
  local dir="$WORKDIR/proj-$org"
  mkdir -p "$dir/.claude/sillok"
  git init -q "$dir"
  cat > "$dir/.claude/sillok/workflow.config.json" <<CFG
{ "version": 1, "repo": "o/r", "baseBranch": "main", "branchPrefix": "{type}/issue-",
  "orgMode": $org, "labels": { "defaults": { "priority": "p3" } } }
CFG
  echo "$dir"
}

run() { ( cd "$1"; shift; PATH="$STUB:$PATH" bash "$SCRIPT" "$@" ); }
log_has() { grep -qxF "$1" "$ARGS_LOG"; }

# ── org mode: type field, NO priority label ──────────────────────────────────
ORGDIR=$(make_project true)
OUT=$(run "$ORGDIR" --repo o/r --title "Add thing" --body "b" \
  --type-name Feature --type-label feature --priority p2 --label "area:wallet")
[ "$OUT" = "https://github.com/o/r/issues/123" ] || fail "org: stdout not the html_url: [$OUT]"
pass "org: stdout is exactly the html_url"
log_has "type=Feature"      || fail "org: missing -f type=Feature"
pass "org: sets Issue Type via -f type="
log_has "labels[]=p2" && fail "org: must NOT add a priority label (board field owns it)"
log_has "labels[]=feature" && fail "org: must NOT add a type label in org mode"
pass "org: no priority/type labels"
log_has "labels[]=area:wallet" || fail "org: missing extra --label area:wallet"
pass "org: extra label appended"
log_has "assignees[]=tester" || fail "org: default assignee not the gh user"
pass "org: defaults assignee to authenticated user"
log_has "X-GitHub-Api-Version: 2026-03-10" || fail "org: missing X-GitHub-Api-Version header"
pass "org: always sends the X-GitHub-Api-Version header"

# ── user mode: type + priority labels, NO type field ─────────────────────────
USERDIR=$(make_project false)
OUT=$(run "$USERDIR" --repo o/r --title "Fix thing" --body "b" \
  --type-name Bug --type-label bug --priority p1 --label "area:auth")
log_has "labels[]=bug" || fail "user: missing -f labels[]=bug"
log_has "labels[]=p1"  || fail "user: missing -f labels[]=p1"
pass "user: adds type + priority labels"
grep -q '^type=' "$ARGS_LOG" && fail "user: must NOT send a type field"
pass "user: no type field in user mode"
log_has "labels[]=area:auth" || fail "user: missing extra label"
pass "user: extra label appended"

# ── user mode: priority defaults from labels.defaults.priority ───────────────
run "$USERDIR" --repo o/r --title "T" --body "b" --type-name Task --type-label task >/dev/null
log_has "labels[]=p3" || fail "user: priority did not default to labels.defaults.priority (p3)"
pass "user: priority defaults to config labels.defaults.priority"

# ── never emit a bare labels[]= for an empty --label ─────────────────────────
run "$USERDIR" --repo o/r --title "T" --body "b" --type-name Task --type-label task --label "" >/dev/null
grep -qxF 'labels[]=' "$ARGS_LOG" && fail "empty --label produced a bare labels[]= (would 422)"
pass "empty --label is skipped, no bare labels[]="

# ── body via stdin (--body-file -) survives multi-line ───────────────────────
printf '## Summary\n\nline one\nline two\n' | run "$USERDIR" --repo o/r --title "T" \
  --type-name Task --type-label task --body-file - >/dev/null
grep -q 'line two' "$ARGS_LOG" || fail "--body-file - did not pass multi-line body through"
pass "--body-file - reads multi-line body from stdin"

# ── --plain: bare create, no orgMode fork (no type field, no priority label) ──
# In a USER config a normal create stamps type+priority labels; --plain must not.
run "$USERDIR" --repo o/r --title "Epic" --body "b" \
  --type-name Epic --type-label feature --priority p1 --plain >/dev/null
grep -q '^type=' "$ARGS_LOG" && fail "plain: must NOT send a type field"
log_has "labels[]=feature" && fail "plain: must NOT add a type label"
log_has "labels[]=p1"      && fail "plain: must NOT add a priority label"
grep -qxF 'labels[]=' "$ARGS_LOG" && fail "plain: emitted a bare labels[]="
pass "plain: no type field, no priority/type labels (user config)"
log_has "assignees[]=tester"                 || fail "plain: default assignee not the gh user"
log_has "X-GitHub-Api-Version: 2026-03-10"   || fail "plain: missing version header"
pass "plain: still sends assignee + version header"
# In an ORG config too — --plain ignores orgMode entirely.
run "$ORGDIR" --repo o/r --title "Epic" --body "b" --type-name Epic --plain >/dev/null
grep -q '^type=' "$ARGS_LOG" && fail "plain(org): must NOT send a type field even in org config"
pass "plain: bypasses the org fork too (no type field in org config)"
# --plain composes with --body-file - (the /sillok-epic call shape).
printf '## Summary\n\nepic body\n' | run "$ORGDIR" --repo o/r --title "Epic" --plain --body-file - >/dev/null
grep -q 'epic body' "$ARGS_LOG" || fail "plain: --body-file - did not pass body through"
pass "plain: composes with --body-file - (the /sillok-epic call shape)"
# --plain still requires a body — the HAVE_BODY guard fires for it too.
if run "$ORGDIR" --repo o/r --title "Epic" --plain >/dev/null 2>&1; then
  fail "plain: missing body should still exit non-zero"
fi
pass "plain: missing --body/--body-file still exits non-zero"

# ── missing required args fail fast ──────────────────────────────────────────
if run "$USERDIR" --repo o/r --type-name Task --type-label task --body b >/dev/null 2>&1; then
  fail "missing --title should exit non-zero"
fi
pass "missing --title exits non-zero"

echo
echo "All create-issue tests passed."
