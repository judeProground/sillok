#!/usr/bin/env bash
# refresh-rules.sh — copy sillok rule templates into a project's rules dir,
# overwriting any whose content differs. Adds missing files, updates changed
# files, skips identical files. Never deletes. Prints a one-line summary of
# refreshed (added or updated) files, sorted, or nothing if all were current.
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
