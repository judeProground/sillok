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
  check_lib "$sh" project.sh     sillok_priority_apply
  check_lib "$sh" dev-link.sh    sillok_link_branch
  check_lib "$sh" dev-link.sh    sillok_link_and_push
  check_lib "$sh" subissue.sh    sillok_subissue_link
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

# Same last-colon discipline for the FIELD cache: a first-colon split
# (awk -F:) truncates "P1: urgent" to "P1", never matches, and the ensure
# path would then create a duplicate field. The stub's api output doubles as
# a field list ("<name>:<id>" lines), so the same fixture exercises both the
# fresh-fetch lookup and the warm-cache lookup (two calls, second is cached).
for sh in "${SHELLS[@]}"; do
  snippet="export PATH='$STUB_BIN':\$PATH; cd '$PROJ_DIR'"
  snippet+="; source '$REPO_ROOT/scripts/lib/project.sh'"
  snippet+="; out=\$(sillok_project_field_id 'P1: urgent')"
  snippet+="; [ \"\$out\" = 'ddd1' ] || { echo \"wrong id for colon-name field (fresh fetch): [\$out]\" >&2; exit 1; }"
  snippet+="; sillok_project_field_id 'Todo' >/dev/null"  # warm the cache in THIS shell
  snippet+="; out=\$(sillok_project_field_id 'P1: urgent')"
  snippet+="; [ \"\$out\" = 'ddd1' ] || { echo \"wrong id for colon-name field (warm cache): [\$out]\" >&2; exit 1; }"
  if ! run_in "$sh" "$snippet" 2>"$STDERR_FILE"; then
    fail "$sh: field name containing ':' parsed to the wrong id — $(cat "$STDERR_FILE")"
  fi
  pass "$sh: field name containing ':' resolves to the correct id (fresh + cached)"
done

# org Issue Field resolver (#17) must load + run under every shell. It pipes
# `gh api graphql | jq` and parses the org issueFields JSON; the jq + parameter
# expansion (${2-} default, %% / #* splitting of "<field_id> <option_id>") must
# behave the same in bash and zsh. Hermetic: a gh stub returns fixed JSON for
# the graphql query.
IFSTUB="$WORKDIR/ifstub-bin"
mkdir -p "$IFSTUB"
cat > "$IFSTUB/gh" <<'STUB'
#!/bin/sh
# Any `gh api graphql ...` returns the org issueFields payload.
cat <<'JSON'
{"data":{"organization":{"issueFields":{"nodes":[
  {"__typename":"IssueFieldSingleSelect","id":"IFSS_x","name":"Priority","options":[
    {"id":"IFSSO_u","name":"Urgent"},
    {"id":"IFSSO_c","name":"P1: critical"}]},
  {"__typename":"IssueFieldDate","id":"IFD_d","name":"Target date"}
]}}}}
JSON
STUB
chmod +x "$IFSTUB/gh"

for sh in "${SHELLS[@]}"; do
  # (1) field + option found → "<field_id> <option_id>"
  snippet="export PATH='$IFSTUB':\$PATH; cd '$PROJ_DIR'"
  snippet+="; source '$REPO_ROOT/scripts/lib/project.sh'"
  snippet+="; out=\$(sillok_org_issue_field_resolve 'Priority' 'Urgent')"
  snippet+="; [ \"\${out%% *}\" = 'IFSS_x' ] || { echo \"wrong field id: [\$out]\" >&2; exit 1; }"
  snippet+="; [ \"\${out#* }\" = 'IFSSO_u' ] || { echo \"wrong option id: [\$out]\" >&2; exit 1; }"
  # (2) option name containing ':' resolves via jq exact match (no colon split)
  snippet+="; out=\$(sillok_org_issue_field_resolve 'Priority' 'P1: critical')"
  snippet+="; [ \"\${out#* }\" = 'IFSSO_c' ] || { echo \"wrong colon-option id: [\$out]\" >&2; exit 1; }"
  # (3) option absent → field id present, option part empty
  snippet+="; out=\$(sillok_org_issue_field_resolve 'Priority' 'Nope')"
  snippet+="; [ \"\${out%% *}\" = 'IFSS_x' ] && [ -z \"\${out#* }\" ] || { echo \"absent option not empty: [\$out]\" >&2; exit 1; }"
  # (4) field absent → empty output
  snippet+="; out=\$(sillok_org_issue_field_resolve 'Nonexistent' 'Urgent')"
  snippet+="; [ -z \"\$out\" ] || { echo \"absent field not empty: [\$out]\" >&2; exit 1; }"
  if ! run_in "$sh" "$snippet" 2>"$STDERR_FILE"; then
    fail "$sh: sillok_org_issue_field_resolve misbehaved — $(cat "$STDERR_FILE")"
  fi
  pass "$sh: org issue field resolver: found/colon-option/absent-option/absent-field all correct"
done

# sillok_parent_integration_branch (#35) reads the `## Integration branch`
# section from a parent issue body — shared by /sillok-start Step 9b and
# /sillok-end PR-base resolution. It lives in config.sh (the zsh-reachable lib),
# so it must define + run under every shell. The match runs inside awk, but the
# function body + command-substitution must behave identically. Hermetic: a gh
# stub returns a fixed issue body.
IBSTUB="$WORKDIR/ibstub-bin"
mkdir -p "$IBSTUB"
cat > "$IBSTUB/gh" <<'STUB'
#!/bin/sh
# `gh issue view <n> --repo <r> --json body --jq .body` → the issue body text.
printf '## Summary\n\nwhatever\n\n## Integration branch\n\n`story/issue-31-foo`\n\n## Context\n\nx\n'
STUB
chmod +x "$IBSTUB/gh"

for sh in "${SHELLS[@]}"; do
  snippet="export PATH='$IBSTUB':\$PATH; cd '$PROJ_DIR'"
  snippet+="; source '$REPO_ROOT/scripts/lib/config.sh'"
  snippet+="; command -v sillok_parent_integration_branch >/dev/null || { echo 'fn undefined' >&2; exit 1; }"
  snippet+="; out=\$(sillok_parent_integration_branch 31 'test/test')"
  snippet+="; [ \"\$out\" = 'story/issue-31-foo' ] || { echo \"wrong branch: [\$out]\" >&2; exit 1; }"
  if ! run_in "$sh" "$snippet" 2>"$STDERR_FILE"; then
    fail "$sh: sillok_parent_integration_branch misbehaved — $(cat "$STDERR_FILE")"
  fi
  pass "$sh: sillok_parent_integration_branch strips backticks + reads the section"
done

# epics.sh must load + run under every shell. sillok_open_epics_section prints
# "### Open epics" then a bullet list (or "(none)" when gh returns empty). The
# gh stub returns an empty JSON array for every call so the function exits 0 and
# emits the header. Hermetic: the stub + PROJ_DIR config (repo/orgMode/epicRepo)
# are set up above; the epicRepo key is absent so only the local-stories path
# runs — one gh issue list call, returning [].
EPICSTUB="$WORKDIR/epicstub-bin"
mkdir -p "$EPICSTUB"
cat > "$EPICSTUB/gh" <<'STUB'
#!/bin/sh
# Any `gh issue list` or `gh api graphql` call returns an empty JSON array.
printf '[]'
STUB
chmod +x "$EPICSTUB/gh"

for sh in "${SHELLS[@]}"; do
  snippet="export PATH='$EPICSTUB':\$PATH; cd '$PROJ_DIR'"
  snippet+="; source '$REPO_ROOT/scripts/lib/epics.sh'"
  snippet+="; command -v sillok_open_epics_section >/dev/null || { echo 'fn undefined' >&2; exit 1; }"
  snippet+="; out=\$(sillok_open_epics_section)"
  snippet+="; case \"\$out\" in '### Open epics'*) ;; *) echo \"unexpected output: [\$out]\" >&2; exit 1 ;; esac"
  if ! run_in "$sh" "$snippet" 2>"$STDERR_FILE"; then
    fail "$sh: sillok_open_epics_section failed — $(cat "$STDERR_FILE")"
  fi
  pass "$sh: epics.sh sources cleanly, sillok_open_epics_section prints ### Open epics"
done

echo
echo "All lib-zsh-compat tests passed."
