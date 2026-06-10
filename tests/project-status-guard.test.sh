#!/usr/bin/env bash
# Regression tripwire for #47: sillok_project_status_set must refuse to send
# the updateProjectV2ItemFieldValue mutation when any resolved id (item_id,
# project_id, field_id, option_id) contains non-id characters — the symptom
# of a resolver leaking debug text to stdout (e.g. `opt_name=…` lines riding
# along with the option id), which produces a malformed GraphQL document.
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/.." && pwd)
export CLAUDE_PLUGIN_ROOT="$REPO_ROOT"

TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

fail() { echo "FAIL: $1" >&2; exit 1; }
pass() { echo "  ok: $1"; }

# Build a minimal consumer project so config resolution finds statusField
# and the todo status name.
make_project() {
  local dir="$1"
  mkdir -p "$dir/.claude/sillok"
  cat > "$dir/.claude/sillok/workflow.config.json" <<'EOF'
{
  "project": {
    "statusField": "Status",
    "statuses": { "todo": "Todo" }
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

# --- case (a): contaminated option_id -----------------------------------
echo "test ($sh): contaminated option_id is refused before any gh call"
PROJ="$TMP_DIR/case-a-$sh"
make_project "$PROJ"
MARKER="$TMP_DIR/case-a-$sh.marker"
ERR="$TMP_DIR/case-a-$sh.err"
set +e
run_shell "$sh" "
  cd '$PROJ'
  source '$REPO_ROOT/scripts/lib/project.sh'
  sillok_project_id() { printf 'PVT_ok'; }
  sillok_project_field_id() { printf 'PVTSSF_ok'; }
  sillok_project_option_id() { printf 'abc123\nopt_name=Todo\nopt_id=xyz'; }
  gh() { echo GH_CALLED >> '$MARKER'; return 9; }
  sillok_project_status_set 'PVTI_item' todo
" 2>"$ERR"
rc=$?
set -e
[[ $rc -eq 1 ]] || fail "$sh: expected rc 1 for contaminated option_id, got $rc (stderr: $(cat "$ERR"))"
grep -q "malformed" "$ERR" || fail "$sh: expected 'malformed' in stderr, got: $(cat "$ERR")"
[[ ! -f "$MARKER" ]] || fail "$sh: gh was called despite contaminated option_id"
pass "$sh: contaminated option_id: rc 1, 'malformed' on stderr, gh never called"

# --- case (b): contaminated item_id (caller-supplied) --------------------
echo "test ($sh): contaminated item_id is refused before any gh call"
PROJ="$TMP_DIR/case-b-$sh"
make_project "$PROJ"
MARKER="$TMP_DIR/case-b-$sh.marker"
ERR="$TMP_DIR/case-b-$sh.err"
set +e
run_shell "$sh" "
  cd '$PROJ'
  source '$REPO_ROOT/scripts/lib/project.sh'
  sillok_project_id() { printf 'PVT_ok'; }
  sillok_project_field_id() { printf 'PVTSSF_ok'; }
  sillok_project_option_id() { printf 'abc123'; }
  gh() { echo GH_CALLED >> '$MARKER'; return 9; }
  sillok_project_status_set 'PVTI x y' todo
" 2>"$ERR"
rc=$?
set -e
[[ $rc -eq 1 ]] || fail "$sh: expected rc 1 for contaminated item_id, got $rc (stderr: $(cat "$ERR"))"
grep -q "malformed" "$ERR" || fail "$sh: expected 'malformed' in stderr, got: $(cat "$ERR")"
[[ ! -f "$MARKER" ]] || fail "$sh: gh was called despite contaminated item_id"
pass "$sh: contaminated item_id: rc 1, 'malformed' on stderr, gh never called"

# --- case (c): clean ids pass through and gh is called once --------------
echo "test ($sh): clean ids send the mutation (gh called exactly once)"
PROJ="$TMP_DIR/case-c-$sh"
make_project "$PROJ"
MARKER="$TMP_DIR/case-c-$sh.marker"
ERR="$TMP_DIR/case-c-$sh.err"
set +e
run_shell "$sh" "
  cd '$PROJ'
  source '$REPO_ROOT/scripts/lib/project.sh'
  sillok_project_id() { printf 'PVT_ok'; }
  sillok_project_field_id() { printf 'PVTSSF_ok'; }
  sillok_project_option_id() { printf 'abc123'; }
  gh() { echo GH_CALLED >> '$MARKER'; return 0; }
  sillok_project_status_set 'PVTI_item' todo
" 2>"$ERR"
rc=$?
set -e
[[ $rc -eq 0 ]] || fail "$sh: expected rc 0 on happy path, got $rc (stderr: $(cat "$ERR"))"
[[ -f "$MARKER" ]] || fail "$sh: gh was never called on happy path"
calls=$(wc -l < "$MARKER" | tr -d ' ')
[[ "$calls" == "1" ]] || fail "$sh: expected exactly 1 gh call, got $calls"
pass "$sh: clean ids: rc 0, gh called exactly once"

# --- case (d): empty item_id (issue not on board) ------------------------
# Hits the early guard at the top of sillok_project_status_set — before the
# resolvers run, so "before any gh call" holds even with real resolvers.
echo "test ($sh): empty item_id is refused before any gh call"
PROJ="$TMP_DIR/case-d-$sh"
make_project "$PROJ"
MARKER="$TMP_DIR/case-d-$sh.marker"
ERR="$TMP_DIR/case-d-$sh.err"
set +e
run_shell "$sh" "
  cd '$PROJ'
  source '$REPO_ROOT/scripts/lib/project.sh'
  sillok_project_id() { printf 'PVT_ok'; }
  sillok_project_field_id() { printf 'PVTSSF_ok'; }
  sillok_project_option_id() { printf 'abc123'; }
  gh() { echo GH_CALLED >> '$MARKER'; return 9; }
  sillok_project_status_set '' todo
" 2>"$ERR"
rc=$?
set -e
[[ $rc -eq 1 ]] || fail "$sh: expected rc 1 for empty item_id, got $rc (stderr: $(cat "$ERR"))"
grep -q "empty project item id" "$ERR" || fail "$sh: expected 'empty project item id' in stderr, got: $(cat "$ERR")"
[[ ! -f "$MARKER" ]] || fail "$sh: gh was called despite empty item_id"
pass "$sh: empty item_id: rc 1, 'empty project item id' on stderr, gh never called"

done

echo
echo "All project-status-guard tests passed."
