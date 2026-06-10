#!/usr/bin/env bash
# Tests for scripts/lib/config.sh — CLAUDE_PLUGIN_ROOT unset fallback (#45).
# config.sh must not die with "unbound variable" when CLAUDE_PLUGIN_ROOT is
# not exported; it should derive the plugin root from its own file location.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

fail() { echo "FAIL: $1" >&2; exit 1; }
pass() { echo "  ok: $1"; }

TMP_PROJ=$(mktemp -d)
TMP_NOGIT=$(mktemp -d)
trap 'rm -rf "$TMP_PROJ" "$TMP_NOGIT"' EXIT

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

ERR_FILE=$(mktemp)

echo "test: bash, env removed, project config present"
out=$(env -u CLAUDE_PLUGIN_ROOT bash -c "set -euo pipefail; cd '$TMP_PROJ'; source '$REPO_ROOT/scripts/lib/config.sh'; sillok_config repo" 2>"$ERR_FILE") \
  || { cat "$ERR_FILE" >&2; fail "bash sourcing died with CLAUDE_PLUGIN_ROOT unset"; }
[[ "$out" == "acme/x" ]] || fail "expected 'acme/x', got '$out'"
grep -q "unbound variable" "$ERR_FILE" && fail "stderr contains 'unbound variable'"
pass "bash + project config: repo = acme/x, no unbound variable"

echo "test: bash, env removed, NO project config (non-git dir) — template fallback via derived root"
out=$(env -u CLAUDE_PLUGIN_ROOT bash -c "set -euo pipefail; cd '$TMP_NOGIT'; source '$REPO_ROOT/scripts/lib/config.sh'; sillok_config baseBranch" 2>"$ERR_FILE") \
  || { cat "$ERR_FILE" >&2; fail "bash sourcing died without project config"; }
[[ "$out" == "$TEMPLATE_BASE" ]] || fail "expected '$TEMPLATE_BASE' from template, got '$out'"
grep -q "unbound variable" "$ERR_FILE" && fail "stderr contains 'unbound variable'"
pass "bash + no project config: baseBranch = $TEMPLATE_BASE (template via derived root)"

if command -v zsh >/dev/null 2>&1; then
  echo "test: zsh, env removed, project config present"
  out=$(env -u CLAUDE_PLUGIN_ROOT zsh -c "set -euo pipefail; cd '$TMP_PROJ'; source '$REPO_ROOT/scripts/lib/config.sh'; sillok_config repo" 2>"$ERR_FILE") \
    || { cat "$ERR_FILE" >&2; fail "zsh sourcing died with CLAUDE_PLUGIN_ROOT unset"; }
  [[ "$out" == "acme/x" ]] || fail "zsh: expected 'acme/x', got '$out'"
  grep -q "unbound variable" "$ERR_FILE" && fail "zsh stderr contains 'unbound variable'"
  pass "zsh + project config: repo = acme/x, no unbound variable"

  echo "test: zsh, env removed, NO project config — template fallback via derived root"
  out=$(env -u CLAUDE_PLUGIN_ROOT zsh -c "set -euo pipefail; cd '$TMP_NOGIT'; source '$REPO_ROOT/scripts/lib/config.sh'; sillok_config baseBranch" 2>"$ERR_FILE") \
    || { cat "$ERR_FILE" >&2; fail "zsh sourcing died without project config"; }
  [[ "$out" == "$TEMPLATE_BASE" ]] || fail "zsh: expected '$TEMPLATE_BASE' from template, got '$out'"
  grep -q "unbound variable" "$ERR_FILE" && fail "zsh stderr contains 'unbound variable'"
  pass "zsh + no project config: baseBranch = $TEMPLATE_BASE (template via derived root)"
else
  echo "note: zsh not found on PATH — skipping zsh fallback cases."
fi

rm -f "$ERR_FILE"

echo
echo "All config-root-fallback tests passed."
