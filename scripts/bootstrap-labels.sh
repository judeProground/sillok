#!/usr/bin/env bash
# sillok — create the default label set on a GitHub repo.
# Idempotent: existing labels are skipped (gh label create returns non-zero, masked with || true).
#
# usage: bootstrap-labels.sh <owner>/<name>
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: $0 <owner>/<name>" >&2
  exit 1
fi

REPO="$1"

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

echo "Done."
