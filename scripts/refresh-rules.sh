#!/usr/bin/env bash
# refresh-rules.sh — copy sillok rule templates into a project's rules dir,
# overwriting any whose content differs. Adds missing files, updates changed
# files, skips identical files. Never deletes. Prints a one-line summary of
# refreshed (added or updated) files, sorted, or nothing if all were current.
#
# This script stays "never deletes" on purpose: to retire a rule file
# upstream, leave a 1-line pointer stub in templates/rules/ (instead of
# removing the file outright) so refresh overwrites the consumer's stale copy
# with the stub rather than orphaning it. Deleting the corresponding
# `- @.claude/sillok/rules/<file>.md` import line from a consumer's CLAUDE.md
# is a separate concern, handled by init-bootstrap.sh's phase1 Step 8
# removal pass (reconcile = backfill + remove-dead), not by this script.
#
# usage: refresh-rules.sh <dest-rules-dir> <src-rules-dir>
set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "[sillok-init] refresh-rules: usage: $0 <dest-rules-dir> <src-rules-dir>" >&2
  exit 1
fi

dest_dir="$1"
src_dir="$2"

mkdir -p "$dest_dir"

refreshed=()
for src in "$src_dir"/*.md; do
  # When no .md files exist the glob stays literal; skip it.
  [[ -e "$src" ]] || continue
  name=$(basename "$src")
  dest="$dest_dir/$name"
  if [[ ! -f "$dest" ]] || ! cmp -s "$src" "$dest"; then
    cp "$src" "$dest"
    refreshed+=("$name")
  fi
done

if [[ ${#refreshed[@]} -gt 0 ]]; then
  sorted=$(printf '%s\n' "${refreshed[@]}" | sort | tr '\n' ' ' | sed 's/ $//')
  echo "[sillok-init] Refreshed: $sorted (prior contents are in your git history if needed)"
fi
