#!/usr/bin/env bash
# sillok — precompute deterministic state for /sillok-epic (Epic creation from a PRD).
# Optional args: <source> [<target>]
#   <source> — a PRD path (a `.../prd.md` file or its containing dir), a Notion URL,
#              or empty (picker mode).
#   <target> — for a Notion source ONLY: the destination dir inside epicRepo
#              (e.g. `basic/my-feature`) under which the synced `prd.md` is committed.
# Emits: ### Source (mode), ### PRD repo, ### Candidate PRDs, ### Language.
#
# PRDs live at ANY path ending in `/prd.md` inside epicRepo (e.g.
# `<category>/<project>/prd.md`). There is no flat dir and no hard-coded category
# list — discovery is a generic tree walk, so the layout stays project-agnostic.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/config.sh
source "$SCRIPT_DIR/lib/config.sh"

# Tool check
need_missing=""
for cmd in git gh jq; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    need_missing="$need_missing $cmd"
  fi
done
if [[ -n "$need_missing" ]]; then
  echo "[precompute-epic] missing tools:$need_missing" >&2
  exit 1
fi

EPIC_REPO=$(sillok_config epicRepo)
if [[ -z "$EPIC_REPO" ]]; then
  echo "[precompute-epic] epicRepo not set" >&2
  exit 1
fi

# Classify source argument
SOURCE="${1:-}"
TARGET="${2:-}"
if [[ -z "$SOURCE" ]]; then
  mode="pick"
elif printf '%s' "$SOURCE" | grep -qE '^https?://.*notion'; then
  mode="notion"
else
  mode="path"
fi

echo "## precomputed state for /sillok-epic"
echo

echo "### Source"
echo "- mode: $mode"
if [[ -n "$SOURCE" ]]; then
  echo "- value: \`$SOURCE\`"
fi
if [[ "$mode" == "notion" && -n "$TARGET" ]]; then
  echo "- target: \`$TARGET\` (prd.md committed under this dir)"
fi

echo
echo "### PRD repo"
echo "- \`$EPIC_REPO\`"

echo
echo "### Candidate PRDs"
# A PRD is any blob whose path ends in `/prd.md` (or a top-level `prd.md`), at any
# depth. Generic tree walk — best-effort; an empty/unreachable repo yields none.
default_branch=$(gh api "repos/$EPIC_REPO" --jq '.default_branch' 2>/dev/null) || default_branch=""
candidates=""
if [[ -n "$default_branch" ]]; then
  candidates=$(gh api "repos/$EPIC_REPO/git/trees/$default_branch?recursive=1" \
    --jq '.tree[]? | select(.type=="blob" and ((.path|endswith("/prd.md")) or .path=="prd.md")) | "  - \(.path)"' 2>/dev/null) || candidates=""
fi
if [[ -n "$candidates" ]]; then
  printf '%s\n' "$candidates"
else
  echo "  - (none found — no \`*/prd.md\` in $EPIC_REPO yet)"
fi

echo
echo "### Language"
LANG_PREF=$(sillok_config language)
echo "- Config: \`${LANG_PREF:-auto}\`"

exit 0
