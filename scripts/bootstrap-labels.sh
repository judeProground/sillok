#!/usr/bin/env bash
# sillok — create the default label set on a GitHub repo.
# Idempotent: existing labels are skipped (gh label create returns non-zero, masked with || true).
#
# usage: bootstrap-labels.sh <owner>/<name> [--config <path>]
#
# Without --config: creates the 6 nature labels, plus 4 priority labels and
# 4 type labels on user-mode repos (orgMode=false).
# With --config: additionally reads labels.areas from the given workflow.config.json
# and creates one area:<name> label per entry (color c9d4dd, muted blue-gray).
#
# Note: on org repos, categorical types (feature/bug/epic) are managed via GitHub Issue
# Types (see scripts/lib/issue-types.sh), stages (todo/.../in-review) via the Projects v2
# Status field, and priorities (p1–p4) via the Projects v2 Priority field (see
# scripts/lib/project.sh). None of these is a label class in org mode.
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "usage: $0 <owner>/<name> [--config <path>]" >&2
  exit 1
fi

REPO="$1"
shift
CONFIG=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --config)
      CONFIG="${2:-}"; shift 2 ;;
    *)
      echo "[bootstrap-labels] unknown arg: $1" >&2
      exit 1 ;;
  esac
done

create() {
  local name="$1" color="$2" description="$3"
  if gh label create "$name" --repo "$REPO" --color "$color" --description "$description" 2>/dev/null; then
    echo "  + $name"
  else
    echo "  · $name (already exists)"
  fi
}

SCRIPT_DIR_BL=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=lib/config.sh
source "$SCRIPT_DIR_BL/lib/config.sh" 2>/dev/null || true
ORG_MODE=$(sillok_config orgMode 2>/dev/null || echo "false")

echo "Bootstrapping labels on $REPO..."

# Natures — cross-cutting attributes orthogonal to Issue Type
create improvement  0e8a16 "Enhance existing functionality"
create refactor     0e8a16 "Restructure code without changing behavior"
create infra        0e8a16 "Tooling, CI, build, config — not user-facing"
create docs         0e8a16 "Documentation only"
create security     0e8a16 "Security-relevant change or finding"
create performance  0e8a16 "Performance-relevant change"

# Priority labels — only for user-mode repos (org repos track priority on the
# Projects v2 Priority field instead — see lib/project.sh, #66)
if [[ "$ORG_MODE" != "true" ]]; then
  create p1           FD3D00 "Urgent"
  create p2           FF8800 "High"
  create p3           CBCCD4 "Normal (default)"
  create p4           E6E6EB "Low"
else
  echo "  · p1–p4 skipped (org mode — priority lives on the project board)"
fi

# Type labels — only for user-mode repos (org repos use Issue Types instead)
if [[ "$ORG_MODE" != "true" ]]; then
  echo "  Type labels (user-repo fallback)..."
  create feature  0e8a16 "New user-facing functionality"
  create story    8B5CF6 "In-repo composite with integration branch"
  create bug      d73a4a "Broken behavior"
  create task     666666 "Generic work unit"
fi

# Areas (optional — driven by labels.areas in workflow.config.json)
if [[ -n "$CONFIG" ]]; then
  if [[ ! -f "$CONFIG" ]]; then
    echo "[bootstrap-labels] --config path not found: $CONFIG" >&2
    exit 1
  fi
  if ! command -v jq >/dev/null 2>&1; then
    echo "[bootstrap-labels] jq required to read area labels; skipping" >&2
  else
    # jq -r prints nothing for missing/null arrays, which is fine.
    areas=()
    while IFS= read -r area; do
      [[ -n "$area" ]] && areas+=("$area")
    done < <(jq -r '(.labels.areas // [])[]' "$CONFIG" 2>/dev/null)
    if [[ ${#areas[@]} -gt 0 ]]; then
      echo "Area labels from $CONFIG:"
      for area in "${areas[@]}"; do
        create "area:$area" "C9D4DD" "Vertical slice: $area"
      done
    fi
  fi
fi

echo "Done."
