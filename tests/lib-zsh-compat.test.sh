#!/usr/bin/env bash
# Tests that the sourced libs load and run under BOTH bash and zsh.
# The three non-config libs historically used ${BASH_SOURCE[0]} (bash-only) for
# path resolution and BASH_REMATCH (bash-only) for URL parsing, which broke them
# under zsh. This guards against regressing either.
#
# Two zsh failure modes are covered (#45, #48):
#   - zsh <= 5.8.1 trips nounset on ${BASH_SOURCE[0]:-$0} (the unset array
#     subscript errors before the :- default applies).
#   - zsh in sh-emulation (POSIX_ARGZERO — how some hosts invoke "sh") sets
#     $0 to "zsh" instead of the sourced file, so a $0 fallback resolves the
#     lib dir to cwd and the transitive config.sh source silently breaks.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export CLAUDE_PLUGIN_ROOT="$REPO_ROOT"

fail() { echo "FAIL: $1" >&2; exit 1; }
pass() { echo "  ok: $1"; }

STDERR_FILE=$(mktemp)
WORKDIR=$(mktemp -d)
trap 'rm -f "$STDERR_FILE"; rm -rf "$WORKDIR"' EXIT

# Snippets run from a neutral cwd so a cwd-relative lib-dir fallback can never
# accidentally find config.sh and mask the bug. Shells are hermetic: zsh -f
# (NO_RCS) skips ~/.zshenv noise, and bash runs with BASH_ENV unset; the
# snippets set their own options, so behavior under test is unchanged.
run_in() {
  local shell="$1" snippet="$2"
  case "$shell" in
    zsh-sh) zsh -f -c "emulate sh; set -euo pipefail; export CLAUDE_PLUGIN_ROOT='$REPO_ROOT'; cd '$WORKDIR'; $snippet" ;;
    zsh)    zsh -f -c "set -euo pipefail; export CLAUDE_PLUGIN_ROOT='$REPO_ROOT'; cd '$WORKDIR'; $snippet" ;;
    *)      env -u BASH_ENV "$shell" -c "set -euo pipefail; export CLAUDE_PLUGIN_ROOT='$REPO_ROOT'; cd '$WORKDIR'; $snippet" ;;
  esac
}

# Asserts the lib sources WITHOUT stderr noise, defines its function, pulls in
# config.sh transitively, AND can actually execute a config read through the
# loaded chain. Definition alone is not enough: a failed transitive source
# still leaves the lib's functions defined but broken at call time.
check_lib() {
  local shell="$1" lib="$2" fn="$3"
  local snippet="source '$REPO_ROOT/scripts/lib/$lib'"
  snippet+="; command -v $fn >/dev/null"
  snippet+="; command -v sillok_config >/dev/null"
  snippet+="; sillok_config baseBranch >/dev/null"
  if ! run_in "$shell" "$snippet" 2>"$STDERR_FILE"; then
    fail "$shell: $lib failed to source, define $fn, or execute sillok_config — stderr: $(cat "$STDERR_FILE")"
  fi
  if [[ -s "$STDERR_FILE" ]]; then
    fail "$shell: $lib emitted stderr while sourcing/executing: $(cat "$STDERR_FILE")"
  fi
  pass "$shell: $lib sources cleanly, $fn defined, sillok_config executes"
}

SHELLS=(bash)
if command -v zsh >/dev/null 2>&1; then
  SHELLS+=(zsh zsh-sh) # zsh-sh = zsh in sh-emulation (POSIX_ARGZERO), the mode behind #48
else
  echo "  note: zsh not found — skipping zsh assertions (macOS always has zsh; Linux CI may not)"
fi

for sh in "${SHELLS[@]}"; do
  check_lib "$sh" config.sh      sillok_config
  check_lib "$sh" project.sh     sillok_project_item_for_issue
  check_lib "$sh" dev-link.sh    sillok_link_branch
  check_lib "$sh" issue-types.sh sillok_issue_type_set
done

for sh in "${SHELLS[@]}"; do
  snippet="source '$REPO_ROOT/scripts/lib/project.sh'; sillok_project_item_for_issue 'not-a-url'"
  if run_in "$sh" "$snippet" 2>/dev/null; then
    fail "$sh: expected non-zero from parse of malformed URL"
  fi
  pass "$sh: malformed URL rejected by parse guard"
done

# Option-cache loop must keep its stdout clean across MULTIPLE options (#65).
# zsh prints `name=value` when an existing variable is re-declared with
# local/typeset and no assignment, so a `local` declaration INSIDE the cache
# loop leaks `opt_name=...`/`opt_id=...` into the function's stdout from
# iteration 2 onward, corrupting command-substitution callers. Hermetic: gh is
# stubbed (no network), config lives in a throwaway git project.
STUB_BIN="$WORKDIR/stub-bin"
mkdir -p "$STUB_BIN"
cat > "$STUB_BIN/gh" <<'STUB'
#!/bin/sh
case "$1" in
  project) printf 'PVT_kwDOTEST001\n' ;;
  api)     printf 'Todo:aaa1\nIn Progress:1bb1\nP1: urgent:ddd1\nDone:ccc1\n' ;;
  *)       exit 1 ;;
esac
STUB
chmod +x "$STUB_BIN/gh"

PROJ_DIR="$WORKDIR/proj65"
mkdir -p "$PROJ_DIR/.claude/sillok"
git init -q "$PROJ_DIR"
cat > "$PROJ_DIR/.claude/sillok/workflow.config.json" <<'CFG'
{ "version": 1, "repo": "test/test", "baseBranch": "main", "branchPrefix": "{type}/issue-", "project": { "owner": "testorg", "number": 7 } }
CFG

for sh in "${SHELLS[@]}"; do
  snippet="export PATH='$STUB_BIN':\$PATH; cd '$PROJ_DIR'"
  snippet+="; source '$REPO_ROOT/scripts/lib/project.sh'"
  snippet+="; out=\$(sillok_project_option_id 'Status' 'In Progress')"
  snippet+="; [ \"\$out\" = '1bb1' ] || { echo \"polluted output: [\$out]\" >&2; exit 1; }"
  if ! run_in "$sh" "$snippet" 2>"$STDERR_FILE"; then
    fail "$sh: option-cache loop polluted its stdout (in-loop local re-declaration?) — $(cat "$STDERR_FILE")"
  fi
  pass "$sh: option-cache loop stdout clean across 4 options"
done

# Option NAMES may contain a colon ("P1: urgent"); ids never do. The cache
# parse must split each "<name>:<id>" line on the LAST colon — a first-colon
# split (${line#*:}) would yield " urgent:ddd1" instead of "ddd1" (#66).
for sh in "${SHELLS[@]}"; do
  snippet="export PATH='$STUB_BIN':\$PATH; cd '$PROJ_DIR'"
  snippet+="; source '$REPO_ROOT/scripts/lib/project.sh'"
  snippet+="; out=\$(sillok_project_option_id 'Status' 'P1: urgent')"
  snippet+="; [ \"\$out\" = 'ddd1' ] || { echo \"wrong id for colon-name option: [\$out]\" >&2; exit 1; }"
  if ! run_in "$sh" "$snippet" 2>"$STDERR_FILE"; then
    fail "$sh: option name containing ':' parsed to the wrong id — $(cat "$STDERR_FILE")"
  fi
  pass "$sh: option name containing ':' resolves to the correct id"
done

echo
echo "All lib-zsh-compat tests passed."
