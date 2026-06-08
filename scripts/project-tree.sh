#!/usr/bin/env bash
# project-tree.sh — emit the project's directory structure as a pruned, indented
# tree for area-label classification.
#
# Makes NO structural assumption about where feature slices live: it prints every
# directory (dirs only, files omitted), pruning build/tool junk and dot-dirs.
# There is intentionally NO depth cap — a fixed depth would reintroduce the bug
# class this replaces (deep slices like src/service/v2/<feature> getting missed).
# A line cap (LINE_CAP) is a pure resource backstop, not a structural limit; when
# exceeded the output ends with a "# … truncated (N more dirs)" marker so coverage
# is never silently bounded.
#
# Output: one directory per line, basename only, indented by (depth * 2) spaces
# where depth is relative to the project root. Empty output (no non-junk dirs) is
# a legitimate result (exit 0).
#
# usage: project-tree.sh <project-root>
# bash 3.2 compatible (no mapfile, no readarray).
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: $0 <project-root>" >&2
  exit 1
fi

ROOT="$1"
if [[ ! -d "$ROOT" ]]; then
  echo "[project-tree] project root does not exist: $ROOT" >&2
  exit 1
fi
ROOT="${ROOT%/}"

LINE_CAP=500

# Collect directory paths, pruning build/tool junk subtrees and any dot-dir.
# Junk = unambiguous build/tool artifacts (NOT business names — domain-vs-layer
# classification is the LLM's job, not this script's).
TALLY=$(mktemp)
trap 'rm -f "$TALLY"' EXIT

{ find "$ROOT" -mindepth 1 \
  \( -name node_modules -o -name dist -o -name build -o -name coverage \
     -o -name out -o -name vendor -o -name public -o -name '.*' \) -prune \
  -o -type d -print 2>/dev/null || true; } \
  | sort > "$TALLY"

if [[ ! -s "$TALLY" ]]; then
  exit 0
fi

total=$(wc -l < "$TALLY" | tr -d ' ')
count=0
while IFS= read -r path; do
  [[ -z "$path" ]] && continue
  count=$((count + 1))
  if [[ $count -gt $LINE_CAP ]]; then
    echo "# … truncated ($((total - LINE_CAP)) more dirs)"
    break
  fi
  off=$(( ${#ROOT} + 1 ))
  rel="${path:off}"
  depth=$(printf '%s' "$rel" | tr -cd '/' | wc -c | tr -d ' ')
  base="${rel##*/}"
  indent=""
  i=0
  while [[ $i -lt $depth ]]; do
    indent="$indent  "
    i=$((i + 1))
  done
  printf '%s%s\n' "$indent" "$base"
done < "$TALLY"
