#!/usr/bin/env bash
# Tests for scripts/lib/config.sh — CLAUDE_PLUGIN_ROOT unset fallback (#45).
# config.sh must not die with a nounset error when CLAUDE_PLUGIN_ROOT is
# not exported; it should derive the plugin root from its own file location.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

fail() { echo "FAIL: $1" >&2; exit 1; }
pass() { echo "  ok: $1"; }

TMP_PROJ=$(mktemp -d)
TMP_NOGIT=$(mktemp -d)
ERR_FILE=$(mktemp)
trap 'rm -rf "$TMP_PROJ" "$TMP_NOGIT" "$ERR_FILE"' EXIT

# Temp git project with its own config.
(
  cd "$TMP_PROJ"
  git init -q
  mkdir -p .claude/sillok
  printf '{"repo":"acme/x"}\n' > .claude/sillok/workflow.config.json
)

# Expected template value for the no-project-config case (don't hardcode).
TEMPLATE_BASE=$(jq -r '.baseBranch' "$REPO_ROOT/templates/workflow.config.json")
[[ -n "$TEMPLATE_BASE" && "$TEMPLATE_BASE" != "null" ]] \
  || fail "template baseBranch missing — test setup broken"

# Source config.sh in <shell> from <dir> with CLAUDE_PLUGIN_ROOT removed from
# the env, read <key>, and assert it equals <want> with no nounset death.
# bash says "unbound variable"; zsh says "parameter not set".
check_fallback() {
  local shell="$1" dir="$2" key="$3" want="$4" label="$5"
  local out
  out=$(env -u CLAUDE_PLUGIN_ROOT "$shell" -c "set -euo pipefail; cd '$dir'; source '$REPO_ROOT/scripts/lib/config.sh'; sillok_config $key" 2>"$ERR_FILE") \
    || { cat "$ERR_FILE" >&2; fail "$shell: sourcing died with CLAUDE_PLUGIN_ROOT unset ($label)"; }
  [[ "$out" == "$want" ]] || fail "$shell ($label): expected '$want', got '$out'"
  grep -Eq "unbound variable|parameter not set" "$ERR_FILE" \
    && fail "$shell ($label): stderr contains a nounset error"
  pass "$shell + $label: $key = $want, no nounset error"
}

SHELLS=(bash)
if command -v zsh >/dev/null 2>&1; then
  SHELLS+=(zsh)
else
  echo "  note: zsh not found — skipping zsh assertions (macOS always has zsh; Linux CI may not)"
fi

for sh in "${SHELLS[@]}"; do
  check_fallback "$sh" "$TMP_PROJ"  repo       "acme/x"        "project config"
  check_fallback "$sh" "$TMP_NOGIT" baseBranch "$TEMPLATE_BASE" "no project config (template via derived root)"
done

echo
echo "All config-root-fallback tests passed."
