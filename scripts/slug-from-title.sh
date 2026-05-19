#!/usr/bin/env bash
# sillok — derive a worktree/branch slug from an issue title.
# Outputs `<N>-<title-slug>` where the title slug follows the rules in
# gh-issue-conventions.md (in .claude/sillok/rules/) (lowercase, articles stripped, non-alphanum runs to
# single hyphens, trimmed, ≤40 chars truncated at last hyphen).
#
# usage: slug-from-title.sh <issue_num> <title...>
#
# Examples:
#   $ ./slug-from-title.sh 79 "Add haptic feedback to record button"
#   79-add-haptic-feedback-to-record-button
#
#   $ ./slug-from-title.sh 102 "Implement comprehensive analytics dashboard for tracking user engagement"
#   102-implement-comprehensive-analytics
set -euo pipefail

if [[ $# -lt 2 ]]; then
  echo "usage: $0 <issue_num> <title...>" >&2
  exit 1
fi

n="$1"
shift
title="$*"

# 1. Lowercase + 2. non-alphanum runs → hyphens + 3. strip leading/trailing hyphens
slug=$(echo "$title" \
  | tr '[:upper:]' '[:lower:]' \
  | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//')

# 4. Strip articles (a, an, the) as hyphenated tokens — repeat until stable
prev=""
while [[ "$slug" != "$prev" ]]; do
  prev="$slug"
  slug=$(echo "$slug" | sed -E 's/(^|-)(a|an|the)(-|$)/\1\3/g; s/^-+//; s/-+$//; s/--+/-/g')
done

# 5. Truncate to ≤40 chars, snapping back to the last hyphen if possible
if [[ ${#slug} -gt 40 ]]; then
  slug="${slug:0:40}"
  if [[ "$slug" == *-* ]]; then
    slug="${slug%-*}"
  fi
fi

echo "${n}-${slug}"
