#!/usr/bin/env bash
# migrate-config.sh — deep-merge template defaults into an existing project
# workflow.config.json, preserving all user values. Adds keys present in the
# template but missing in the project; never deletes or overwrites existing
# keys; arrays are kept verbatim from the project (NOT unioned with template).
#
# Mechanism: jq's `*` recursively merges two objects with the right operand
# winning, and replaces arrays wholesale with the right operand — exactly the
# semantics we want when the project config is the right operand.
#
# Mutates <project-config> in place, atomically (temp file + mv), and ONLY when
# the merge actually changes something (so a no-op preserves the user's exact
# file formatting). Prints a one-line summary of added top-level keys to stdout,
# or nothing if no keys were added. On error, leaves <project-config> unchanged
# and exits non-zero.
#
# usage: migrate-config.sh <project-config> <template-config>
set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "[sillok-init] migrate-config: usage: $0 <project-config> <template-config>" >&2
  exit 1
fi

project="$1"
template="$2"

if [[ ! -f "$project" ]]; then
  echo "[sillok-init] migrate-config: $project not found" >&2
  exit 1
fi
if [[ ! -f "$template" ]]; then
  echo "[sillok-init] migrate-config: template missing at $template" >&2
  exit 1
fi

if ! jq empty "$project" 2>/dev/null; then
  echo "[sillok-init] Config: workflow.config.json is invalid JSON — fix manually, then re-run /sillok-init" >&2
  exit 1
fi
if ! jq empty "$template" 2>/dev/null; then
  echo "[sillok-init] migrate-config: template is invalid JSON at $template" >&2
  exit 1
fi

# Deep-merge: template * project (project wins; arrays replaced wholesale).
# Explicit failure check — a bare `x=$(cmd)` assignment does not trip set -e.
if ! merged=$(jq -s '.[0] * .[1]' "$template" "$project"); then
  echo "[sillok-init] migrate-config: merge failed (jq error)" >&2
  exit 1
fi

# No-op guard: if the merge is semantically identical to the current project
# config, leave the file untouched (preserve user formatting) and print nothing.
if [[ "$(printf '%s' "$merged" | jq -S .)" == "$(jq -S . "$project")" ]]; then
  exit 0
fi

# Summary: top-level keys present in template but absent from project, sorted.
if ! added=$(jq -rs '(.[0] | keys) - (.[1] | keys) | sort | join(", ")' "$template" "$project"); then
  echo "[sillok-init] migrate-config: summary computation failed (jq error)" >&2
  exit 1
fi

# Write atomically on the same filesystem as the target.
tmp=$(mktemp "${project}.tmp.XXXXXX")
trap 'rm -f "$tmp"' EXIT
printf '%s\n' "$merged" > "$tmp"
mv "$tmp" "$project"
trap - EXIT

if [[ -n "$added" ]]; then
  echo "[sillok-init] Config: added $added"
fi
