#!/usr/bin/env bash
# Regression tripwire for sillok_issue_priority_set (#17, was #66) — the org-mode
# priority write path. It now targets the org-level Priority *issue field* via
# setIssueFieldValue (not a board project field via updateProjectV2ItemFieldValue),
# so the resolved ids are issue node id + org field id + option id. The function
# must:
#   - refuse an empty issue url before any gh round-trip
#   - refuse an unmapped priority key before any gh round-trip
#   - fail-soft (rc 1, no mutation) when the org issue field is absent
#   - refuse to send setIssueFieldValue when any resolved id carries shell-noise
#     (#47 tripwire), and send exactly one mutation on clean ids.
#
# The two gh round-trips inside the real path (issue node id, org field resolve)
# are factored into stubbable functions (_sillok_issue_node_id,
# sillok_org_issue_field_resolve), so "no gh call before refusing" stays testable
# — the only un-stubbed `gh` is the final mutation.
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/.." && pwd)
export CLAUDE_PLUGIN_ROOT="$REPO_ROOT"

TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

fail() { echo "FAIL: $1" >&2; exit 1; }
pass() { echo "  ok: $1"; }

URL="https://github.com/o/r/issues/1"

# Minimal consumer project so config resolution finds priorityField + p1 name.
make_project() {
  local dir="$1"
  mkdir -p "$dir/.claude/sillok"
  cat > "$dir/.claude/sillok/workflow.config.json" <<'EOF'
{
  "project": {
    "priorityField": "Priority",
    "priorities": { "p1": "Urgent" }
  }
}
EOF
  git -C "$dir" init -q
}

# The guard's `case` glob must hold under zsh too (the libs are sourced from
# Claude Code's Bash tool, which isn't always bash) — run every case in both
# shells. Hermetic zsh per the house pattern: zsh -f (NO_RCS) skips ~/.zshenv.
run_shell() {
  local shell="$1" snippet="$2"
  case "$shell" in
    zsh) zsh -f -c "$snippet" ;;
    *)   "$shell" -c "$snippet" ;;
  esac
}

SHELLS=(bash)
if command -v zsh >/dev/null 2>&1; then
  SHELLS+=(zsh)
else
  echo "  note: zsh not found — skipping zsh assertions (macOS always has zsh; Linux CI may not)"
fi

for sh in "${SHELLS[@]}"; do

# --- case (a): contaminated option_id ------------------------------------
echo "test ($sh): contaminated option_id is refused before the mutation"
PROJ="$TMP_DIR/case-a-$sh"
make_project "$PROJ"
MARKER="$TMP_DIR/case-a-$sh.marker"
ERR="$TMP_DIR/case-a-$sh.err"
set +e
run_shell "$sh" "
  cd '$PROJ'
  source '$REPO_ROOT/scripts/lib/project.sh'
  _sillok_issue_node_id() { printf 'I_ok'; }
  sillok_org_issue_field_resolve() { printf 'IFSS_ok abc;rm'; }
  gh() { echo GH_CALLED >> '$MARKER'; return 9; }
  sillok_issue_priority_set '$URL' p1
" 2>"$ERR"
rc=$?
set -e
[[ $rc -eq 1 ]] || fail "$sh: expected rc 1 for contaminated option_id, got $rc (stderr: $(cat "$ERR"))"
grep -q "malformed" "$ERR" || fail "$sh: expected 'malformed' in stderr, got: $(cat "$ERR")"
[[ ! -f "$MARKER" ]] || fail "$sh: mutation gh was called despite contaminated option_id"
pass "$sh: contaminated option_id: rc 1, 'malformed' on stderr, no mutation"

# --- case (b): contaminated issue node id --------------------------------
echo "test ($sh): contaminated issue node id is refused before the mutation"
PROJ="$TMP_DIR/case-b-$sh"
make_project "$PROJ"
MARKER="$TMP_DIR/case-b-$sh.marker"
ERR="$TMP_DIR/case-b-$sh.err"
set +e
run_shell "$sh" "
  cd '$PROJ'
  source '$REPO_ROOT/scripts/lib/project.sh'
  _sillok_issue_node_id() { printf 'I bad'; }
  sillok_org_issue_field_resolve() { printf 'IFSS_ok OPT_ok'; }
  gh() { echo GH_CALLED >> '$MARKER'; return 9; }
  sillok_issue_priority_set '$URL' p1
" 2>"$ERR"
rc=$?
set -e
[[ $rc -eq 1 ]] || fail "$sh: expected rc 1 for contaminated issue id, got $rc (stderr: $(cat "$ERR"))"
grep -q "malformed" "$ERR" || fail "$sh: expected 'malformed' in stderr, got: $(cat "$ERR")"
[[ ! -f "$MARKER" ]] || fail "$sh: mutation gh was called despite contaminated issue id"
pass "$sh: contaminated issue id: rc 1, 'malformed' on stderr, no mutation"

# --- case (c): clean ids send exactly one setIssueFieldValue mutation -----
echo "test ($sh): clean ids send the mutation (gh called exactly once)"
PROJ="$TMP_DIR/case-c-$sh"
make_project "$PROJ"
MARKER="$TMP_DIR/case-c-$sh.marker"
ERR="$TMP_DIR/case-c-$sh.err"
set +e
run_shell "$sh" "
  cd '$PROJ'
  source '$REPO_ROOT/scripts/lib/project.sh'
  _sillok_issue_node_id() { printf 'I_ok'; }
  sillok_org_issue_field_resolve() { printf 'IFSS_ok OPT_ok'; }
  gh() { echo GH_CALLED >> '$MARKER'; return 0; }
  sillok_issue_priority_set '$URL' p1
" 2>"$ERR"
rc=$?
set -e
[[ $rc -eq 0 ]] || fail "$sh: expected rc 0 on happy path, got $rc (stderr: $(cat "$ERR"))"
[[ -f "$MARKER" ]] || fail "$sh: mutation gh was never called on happy path"
calls=$(wc -l < "$MARKER" | tr -d ' ')
[[ "$calls" == "1" ]] || fail "$sh: expected exactly 1 gh call, got $calls"
pass "$sh: clean ids: rc 0, mutation sent exactly once"

# --- case (d): empty issue url -------------------------------------------
# Hits the early guard at the top — before any resolver — so "no gh" holds
# even with real resolvers.
echo "test ($sh): empty issue url is refused before any gh call"
PROJ="$TMP_DIR/case-d-$sh"
make_project "$PROJ"
MARKER="$TMP_DIR/case-d-$sh.marker"
ERR="$TMP_DIR/case-d-$sh.err"
set +e
run_shell "$sh" "
  cd '$PROJ'
  source '$REPO_ROOT/scripts/lib/project.sh'
  _sillok_issue_node_id() { echo GH_CALLED >> '$MARKER'; printf 'I_ok'; }
  sillok_org_issue_field_resolve() { echo GH_CALLED >> '$MARKER'; printf 'IFSS_ok OPT_ok'; }
  gh() { echo GH_CALLED >> '$MARKER'; return 9; }
  sillok_issue_priority_set '' p1
" 2>"$ERR"
rc=$?
set -e
[[ $rc -eq 1 ]] || fail "$sh: expected rc 1 for empty issue url, got $rc (stderr: $(cat "$ERR"))"
grep -q "empty issue url" "$ERR" || fail "$sh: expected 'empty issue url' in stderr, got: $(cat "$ERR")"
[[ ! -f "$MARKER" ]] || fail "$sh: a resolver/gh ran despite empty issue url"
pass "$sh: empty issue url: rc 1, 'empty issue url' on stderr, nothing called"

# --- case (e): unmapped priority key -------------------------------------
echo "test ($sh): unmapped priority key is refused before any gh call"
PROJ="$TMP_DIR/case-e-$sh"
make_project "$PROJ"
MARKER="$TMP_DIR/case-e-$sh.marker"
ERR="$TMP_DIR/case-e-$sh.err"
set +e
run_shell "$sh" "
  cd '$PROJ'
  source '$REPO_ROOT/scripts/lib/project.sh'
  _sillok_issue_node_id() { echo GH_CALLED >> '$MARKER'; printf 'I_ok'; }
  sillok_org_issue_field_resolve() { echo GH_CALLED >> '$MARKER'; printf 'IFSS_ok OPT_ok'; }
  gh() { echo GH_CALLED >> '$MARKER'; return 9; }
  sillok_issue_priority_set '$URL' p9
" 2>"$ERR"
rc=$?
set -e
[[ $rc -eq 1 ]] || fail "$sh: expected rc 1 for unmapped priority key, got $rc (stderr: $(cat "$ERR"))"
grep -q "no project.priorities.p9 configured" "$ERR" || fail "$sh: expected 'no project.priorities.p9 configured' in stderr, got: $(cat "$ERR")"
[[ ! -f "$MARKER" ]] || fail "$sh: a resolver/gh ran despite unmapped key"
pass "$sh: unmapped priority key: rc 1, helpful stderr, nothing called"

# --- case (f): org issue field absent → fail-soft ------------------------
# resolve returns empty (field not found): the write must fail-soft with the
# re-init pointer and send no mutation.
echo "test ($sh): missing org issue field fails soft (no mutation)"
PROJ="$TMP_DIR/case-f-$sh"
make_project "$PROJ"
MARKER="$TMP_DIR/case-f-$sh.marker"
ERR="$TMP_DIR/case-f-$sh.err"
set +e
run_shell "$sh" "
  cd '$PROJ'
  source '$REPO_ROOT/scripts/lib/project.sh'
  _sillok_issue_node_id() { printf 'I_ok'; }
  sillok_org_issue_field_resolve() { printf ''; }
  gh() { echo GH_CALLED >> '$MARKER'; return 0; }
  sillok_issue_priority_set '$URL' p1
" 2>"$ERR"
rc=$?
set -e
[[ $rc -eq 1 ]] || fail "$sh: expected rc 1 for missing org field, got $rc (stderr: $(cat "$ERR"))"
grep -q "not found" "$ERR" || fail "$sh: expected 'not found' in stderr, got: $(cat "$ERR")"
grep -q "sillok-init" "$ERR" || fail "$sh: expected '/sillok-init' pointer in stderr, got: $(cat "$ERR")"
[[ ! -f "$MARKER" ]] || fail "$sh: mutation gh was called despite missing org field"
pass "$sh: missing org field: rc 1, re-init pointer, no mutation"

done

echo
echo "All project-priority-guard tests passed."
