#!/usr/bin/env bash
# write-shim-commands.sh — install standalone-style shortcut commands so users can
# type `/sillok-start` etc. instead of the namespaced `/sillok:sillok-start`.
#
# Plugin slash commands are always namespaced by Claude Code; the only supported
# short form is via `.claude/commands/<name>.md` in the project. This script
# generates such shim files from `templates/command-shim.md.tmpl`.
#
# Each shim is a pointer (not a content copy): it instructs Claude at runtime to
# locate the latest installed sillok plugin version and follow the canonical
# command. That keeps shims version-agnostic — upgrading the plugin does not
# require re-running `/sillok:init`.
#
# usage: write-shim-commands.sh <project-root>
# env:   PLUGIN_ROOT (path to plugin root; defaults to dir-of-this-script/..)
#        SILLOK_SHIM_PROMPT_ON_CONFLICT=1  prompt before overwriting non-shim files
#                                          (default 0; skip silently and warn)
#
# Behaviour:
#   - Creates `<project-root>/.claude/commands/` if missing.
#   - For each shim target (start, add, design, execute, end, story, epic):
#       * If file is absent → write fresh shim.
#       * If file has `sillok-shim: true` in frontmatter → overwrite (idempotent refresh).
#       * If file exists without marker → skip with a warning unless prompted.
#   - Prints `+ <name>` on write, `· <name>` on skip, `· <name> (foreign — skipped)` on conflict.
#
# Exits non-zero only on missing template or invalid argument.
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: $0 <project-root>" >&2
  exit 1
fi

PROJECT_ROOT="$1"

if [[ ! -d "$PROJECT_ROOT" ]]; then
  echo "[write-shim-commands] project root does not exist: $PROJECT_ROOT" >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="${PLUGIN_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}"
TEMPLATE="$PLUGIN_ROOT/templates/command-shim.md.tmpl"

if [[ ! -f "$TEMPLATE" ]]; then
  echo "[write-shim-commands] template not found: $TEMPLATE" >&2
  exit 1
fi

# Shim targets — kept in sync with the user-facing canonical commands. We do
# NOT shim `sillok-init` itself (init runs once and is already typed in canonical
# form by definition).
SHIM_TARGETS=(start add design execute end story epic)

COMMANDS_DIR="$PROJECT_ROOT/.claude/commands"
mkdir -p "$COMMANDS_DIR"

written=0
refreshed=0
skipped_foreign=0

for cmd in "${SHIM_TARGETS[@]}"; do
  dest="$COMMANDS_DIR/sillok-$cmd.md"

  if [[ -f "$dest" ]]; then
    if grep -q '^sillok-shim: true$' "$dest"; then
      action="refresh"
    else
      action="skip-foreign"
    fi
  else
    action="write"
  fi

  case "$action" in
    skip-foreign)
      echo "  · sillok-$cmd (foreign — skipped; remove the file to let sillok manage it)"
      skipped_foreign=$((skipped_foreign + 1))
      continue
      ;;
    write|refresh)
      # Render template with placeholder substitution.
      sed "s/{{COMMAND}}/$cmd/g" "$TEMPLATE" > "$dest"
      if [[ "$action" == "write" ]]; then
        echo "  + sillok-$cmd"
        written=$((written + 1))
      else
        echo "  ~ sillok-$cmd (refreshed)"
        refreshed=$((refreshed + 1))
      fi
      ;;
  esac
done

echo
echo "Shim commands: $written written, $refreshed refreshed, $skipped_foreign foreign-skipped."
echo "Type \`/sillok-start\` (and siblings) as shortcuts for \`/sillok:sillok-start\`."
