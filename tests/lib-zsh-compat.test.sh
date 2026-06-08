#!/usr/bin/env bash
# Tests that the sourced libs load and run under BOTH bash and zsh.
# The three non-config libs historically used ${BASH_SOURCE[0]} (bash-only) for
# path resolution and BASH_REMATCH (bash-only) for URL parsing, which broke them
# under zsh. This guards against regressing either.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export CLAUDE_PLUGIN_ROOT="$REPO_ROOT"

fail() { echo "FAIL: $1" >&2; exit 1; }
pass() { echo "  ok: $1"; }

run_in() {
  local shell="$1" snippet="$2"
  "$shell" -c "set -euo pipefail; export CLAUDE_PLUGIN_ROOT='$REPO_ROOT'; $snippet"
}

check_lib() {
  local shell="$1" lib="$2" fn="$3"
  local snippet="source '$REPO_ROOT/scripts/lib/$lib'; command -v $fn >/dev/null"
  if run_in "$shell" "$snippet" 2>/dev/null; then
    pass "$shell: $lib sources, $fn defined"
  else
    fail "$shell: $lib failed to source or $fn missing"
  fi
}

SHELLS=(bash)
if command -v zsh >/dev/null 2>&1; then
  SHELLS+=(zsh)
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

echo
echo "All lib-zsh-compat tests passed."
