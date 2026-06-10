#!/usr/bin/env bash
# sillok — SessionStart hook. Injects a compact sillok context block when the
# current project is sillok-configured; otherwise it is completely silent.
#
# HARD CONTRACT (this runs in EVERY session of EVERY consumer project):
#   - ALWAYS exits 0, no matter what.
#   - ZERO stdout/stderr when: CWD not a git repo, no workflow.config.json at
#     the git root, jq missing, malformed config, or any internal failure.
#   - NO network and NO `gh` calls — branch ↔ issue is derived locally.
#
# Deliberately NOT `set -euo pipefail`: every failure path must stay silent
# and exit 0, so guards are explicit instead. (config.sh sets -euo pipefail
# when sourced; we restore the permissive state right after — see below.)

sillok_session_context() {
  command -v git >/dev/null 2>&1 || return 1
  command -v jq >/dev/null 2>&1 || return 1

  local git_root
  git_root=$(git rev-parse --show-toplevel 2>/dev/null) || return 1
  [ -n "$git_root" ] || return 1

  local config="$git_root/.claude/sillok/workflow.config.json"
  [ -f "$config" ] || return 1
  jq -e . "$config" >/dev/null 2>&1 || return 1

  # Source the shared config lib relative to this script's own location
  # (standalone bash script — BASH_SOURCE is fine here). config.sh runs
  # `set -euo pipefail` in our shell when sourced; sourcing inside an `||`
  # guard suppresses errexit during the source itself, and we explicitly
  # restore the permissive state afterward to keep the exit-0 contract.
  local hook_dir
  hook_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd) || return 1
  local config_lib="$hook_dir/../scripts/lib/config.sh"
  [ -f "$config_lib" ] || return 1
  # shellcheck source=../scripts/lib/config.sh
  source "$config_lib" 2>/dev/null || return 1
  set +e +u +o pipefail

  # Automation mode — template-fallback semantics: absent key resolves to the
  # plugin template's false → propose mode. Anything but literal true = propose.
  local full_auto mode_line
  full_auto=$(sillok_config automation.fullAuto 2>/dev/null)
  if [ "$full_auto" = "true" ]; then
    mode_line="FULL-AUTO (chains stages without confirmation; stops after PR creation)"
  else
    mode_line="propose (confirm each stage before it runs)"
  fi

  # Branch ↔ issue, derived locally via the configured branch-prefix regex.
  # The {type} alternation injects a capture group BEFORE the issue number,
  # so walk BASH_REMATCH and take the first numeric capture (see
  # scripts/precompute-end.sh for the canonical loop).
  local branch branch_line prefix_regex issue cap
  branch=$(git branch --show-current 2>/dev/null)
  branch_line=""
  if [ -n "$branch" ]; then
    branch_line="- Branch: \`$branch\`"
    prefix_regex=$(sillok_branch_prefix_regex 2>/dev/null)
    if [ -n "$prefix_regex" ] && [[ "$branch" =~ ^${prefix_regex}([0-9]+)-(.+)$ ]]; then
      issue=""
      for cap in "${BASH_REMATCH[@]:1}"; do
        if [[ "$cap" =~ ^[0-9]+$ ]]; then
          issue="$cap"
          break
        fi
      done
      [ -n "$issue" ] && branch_line="- Branch: \`$branch\` → issue #$issue"
    fi
  fi

  echo "## sillok"
  echo
  echo "- sillok is active in this project (workflow.config.json found)."
  echo "- Automation mode: $mode_line"
  [ -n "$branch_line" ] && echo "$branch_line"
  echo "- Stage transitions (start → design → execute → end) are routed by the \`sillok:workflow\` skill."
  return 0
}

# Build the block in a subshell with stderr suppressed; print it only when
# everything succeeded. Any failure → no output. Always exit 0.
_sillok_hook_out=$(sillok_session_context 2>/dev/null)
_sillok_hook_rc=$?
if [ "$_sillok_hook_rc" -eq 0 ] && [ -n "$_sillok_hook_out" ]; then
  printf '%s\n' "$_sillok_hook_out"
fi
exit 0
