#!/usr/bin/env bash
# pick-areas.sh — auto-select area labels from detect-slices.sh output.
#
# Reads tab-separated `<name>\t<rank>` lines on stdin, emits names where
# rank >= 2 (excludes single-family candidates as low-confidence noise),
# capped at 15 entries (avoid drowning the GitHub repo in noisy labels).
#
# Exists as a standalone script (rather than inline awk in sillok-init.md)
# because agent-readers of the markdown spec strip bare $1 / $2 tokens,
# turning the awk filter into garbage. Calling this script shields the
# logic from spec-side mangling.
#
# usage: detect-slices.sh <root> | pick-areas.sh
set -euo pipefail

awk -F'\t' '$2 >= 2 { print $1 }' | head -n 15
