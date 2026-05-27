#!/usr/bin/env bash
# pick-areas.sh — auto-select area labels from detect-slices.sh output.
#
# Reads tab-separated `<name>\t<rank>` lines on stdin, emits names where
# rank >= threshold, capped at 15 entries.
#
# Threshold logic: when the max rank across all candidates is > 1 (multi-family
# project like FSD or monorepo), threshold = 2 (cross-family validation).
# When max rank == 1 (single-family project like a Python backend with only
# src/<name>/ dirs), threshold = 1 (emit all candidates — they're the only
# signal we have).
#
# Exists as a standalone script (rather than inline awk in sillok-init.md)
# because agent-readers of the markdown spec strip bare $1 / $2 tokens,
# turning the awk filter into garbage. Calling this script shields the
# logic from spec-side mangling.
#
# usage: detect-slices.sh <root> | pick-areas.sh
set -euo pipefail

awk -F'\t' '
  {
    names[NR] = $1
    ranks[NR] = $2
    if ($2 + 0 > max) max = $2 + 0
  }
  END {
    thresh = (max > 1) ? 2 : 1
    for (i = 1; i <= NR; i++)
      if (ranks[i] + 0 >= thresh) print names[i]
  }
' | head -n 15
