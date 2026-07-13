#!/usr/bin/env bash
# qa-merge.sh — merge a head branch into the configured QA/deploy branch.
#
# Called by /sillok-end (Step 6b) right after the PR is opened. When `qaBranch`
# is set in workflow.config.json, the team's post-end flow of merging work into
# a shared deploy branch (deploy/qa, deploy/qa/test, …) is done here via the
# GitHub server-side merge API — no local checkout, no temp worktree. The head
# branch is already pushed by /sillok-end Step 3, so it always exists on origin.
#
# Usage:
#   qa-merge.sh <repo> <head-branch> <issue-number>
#
# Contract: NON-FATAL. Every outcome (skipped / merged / conflict / failed)
# exits 0 so the caller's PR flow (status → In QA, issue body, output) is never
# blocked. The only non-zero exit is a usage error (missing args → exit 2).
#
# Output: one machine-readable `QA-MERGE: <outcome> ...` line on stdout, plus
# human-facing detail (conflict resolution steps) where useful.
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=lib/config.sh
source "$SCRIPT_DIR/lib/config.sh"

REPO="${1:-}"
HEAD="${2:-}"
N="${3:-}"

if [[ -z "$REPO" || -z "$HEAD" || -z "$N" ]]; then
  echo "usage: qa-merge.sh <repo> <head-branch> <issue-number>" >&2
  exit 2
fi

QA_BRANCH=$(sillok_config qaBranch)
if [[ -z "$QA_BRANCH" ]]; then
  echo "QA-MERGE: skipped (not configured)"
  exit 0
fi

# QA branch must already exist on origin — sillok does not provision deploy
# branches (that's infra setup). Absent → warn and skip.
if [[ -z "$(git ls-remote --heads origin "$QA_BRANCH" 2>/dev/null)" ]]; then
  echo "QA-MERGE: skipped (branch '$QA_BRANCH' not found on origin)"
  exit 0
fi

# Server-side merge. Capture stdout (JSON body on 201, empty on 204) and stderr
# (gh prints `... (HTTP 4xx)` on failure) separately.
out_file=$(mktemp)
err_file=$(mktemp)
trap 'rm -f "$out_file" "$err_file"' EXIT

set +e
gh api -X POST "/repos/$REPO/merges" \
  -f base="$QA_BRANCH" \
  -f head="$HEAD" \
  -f commit_message="Merge $HEAD into $QA_BRANCH (#$N)" \
  >"$out_file" 2>"$err_file"
rc=$?
set -e

if [[ $rc -eq 0 ]]; then
  sha=$(jq -r '.sha // empty' <"$out_file" 2>/dev/null || echo "")
  if [[ -n "$sha" ]]; then
    echo "QA-MERGE: merged $sha"
  else
    # 204 No Content — base already contains head.
    echo "QA-MERGE: already-up-to-date"
  fi
  exit 0
fi

# Failure: classify from gh's stderr.
err_line=$(head -1 "$err_file" 2>/dev/null || echo "")
if grep -q "HTTP 409" "$err_file" 2>/dev/null; then
  echo "QA-MERGE: conflict"
  echo "  '$HEAD' conflicts with '$QA_BRANCH'. Resolve manually:"
  echo "    git fetch origin"
  echo "    git checkout $QA_BRANCH && git pull"
  echo "    git merge $HEAD   # resolve conflicts"
  echo "    git push origin $QA_BRANCH"
else
  echo "QA-MERGE: failed (${err_line:-unknown error})"
fi
exit 0
