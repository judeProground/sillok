#!/usr/bin/env bash
# sillok — create the default label set on a GitHub repo.
# Idempotent: existing labels are skipped (gh label create returns non-zero, masked with || true).
#
# usage: bootstrap-labels.sh <owner>/<name> [--config <path>]
#
# Without --config: creates the 14 universal labels (5 types + 5 stages + 4 priorities).
# With --config: additionally reads labels.areas from the given workflow.config.json
# and creates one area:<name> label per entry (color c9d4dd, muted blue-gray).
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

echo "Bootstrapping labels on $REPO..."

# Types
create feature      FD3D00 "New functionality"
create bug          FF8800 "Something is broken"
create improvement  0AD6B4 "Enhance existing functionality"
create infra        BC52FE "Tooling, CI, config, refactor — not user-facing"
create epic         FF003C "Parent tracking issue with >=3 sub-issues"

# Stages
create backlog      E6E6EB "Raw idea, not yet prioritized"
create todo         CBCCD4 "Prioritized, ready to start"
create designed     AAACB7 "Spec written and accepted"
create in-progress  5D5DE8 "Plan exists, implementation underway"
create in-review    1F57FF "PR is open"

# Priorities
create p1           FD3D00 "Urgent"
create p2           FF8800 "High"
create p3           CBCCD4 "Normal (default)"
create p4           E6E6EB "Low"

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
