#!/usr/bin/env bash
# project-tree.sh — emit the project's directory structure as a pruned, indented
# tree for area-label classification.
#
# Makes NO structural assumption about where feature slices live: it prints every
# directory (dirs only, files omitted), pruning: (a) a built-in set of build/tool
# and native-platform dirs that are never feature areas, (b) all dot-dirs, and
# (c) anything the project's .gitignore ignores, when run inside a git repo.
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

# Pass 1 — walk the tree, pruning during descent (so we never recurse into them) a
# built-in set of build/tool + native-platform dirs plus every dot-dir. None are
# business feature areas; domain-vs-layer judgment for everything else is the LLM's
# job, not this script's. The built-in set covers the heavy/common cases across
# ecosystems (JS, Python, Rust/JVM, native/RN) so the walk stays cheap — and so
# platform dirs that are *committed* (android/ios in React Native, which .gitignore
# won't list) are still excluded.
TALLY=$(mktemp)
trap 'rm -f "$TALLY"' EXIT

{ find "$ROOT" -mindepth 1 \
  \( -name node_modules -o -name dist -o -name build -o -name coverage \
     -o -name out -o -name vendor -o -name public \
     -o -name target -o -name __pycache__ -o -name venv \
     -o -name Pods -o -name android -o -name ios \
     -o -name '.*' \) -prune \
  -o -type d -print 2>/dev/null || true; } \
  | sort > "$TALLY"

# Pass 2 — inside a git repo, drop any directory the project's .gitignore ignores.
# This generalizes pruning to every language's build junk (Rust target/, .venv, a
# project's custom generated/ dir, …) without maintaining an exhaustive list.
# `git check-ignore` prints the IGNORED input paths; we keep the rest. No-op outside
# a git repo or when git is absent (e.g. a bare directory passed in tests).
if [[ -s "$TALLY" ]] && command -v git >/dev/null 2>&1 \
   && git -C "$ROOT" rev-parse --git-dir >/dev/null 2>&1; then
  IGN=$(mktemp)
  git -C "$ROOT" check-ignore --stdin < "$TALLY" > "$IGN" 2>/dev/null || true
  if [[ -s "$IGN" ]]; then
    KEPT=$(mktemp)
    grep -vxF -f "$IGN" "$TALLY" > "$KEPT" || true
    mv "$KEPT" "$TALLY"
  fi
  rm -f "$IGN"
fi

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
  # Strip the root prefix (quoted = literal, glob-safe; ROOT has no trailing slash).
  rel="${path#"$ROOT"/}"
  # depth = number of '/' separators in the relative path (pure bash, no subshell).
  slashes="${rel//[!\/]/}"
  depth=${#slashes}
  printf '%*s%s\n' "$((depth * 2))" '' "${rel##*/}"
done < "$TALLY"
