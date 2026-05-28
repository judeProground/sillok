#!/usr/bin/env bash
# sillok — migrate a repo from v1 (label-based types + stages) to v2
# (Issue Types + Projects v2 status).
#
# Usage:
#   bash scripts/migrate-v1-to-v2.sh <repo>           # report only (dry run)
#   bash scripts/migrate-v1-to-v2.sh <repo> --apply   # execute changes
#
# Idempotent: re-running after a partial migration is safe.

set -euo pipefail

REPO="${1:-}"
APPLY="${2:-}"

if [[ -z "$REPO" ]]; then
  echo "Usage: $0 <owner/repo> [--apply]" >&2
  exit 1
fi

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=lib/config.sh
source "$SCRIPT_DIR/lib/config.sh"
# shellcheck source=lib/issue-types.sh
source "$SCRIPT_DIR/lib/issue-types.sh"
# shellcheck source=lib/project.sh
source "$SCRIPT_DIR/lib/project.sh"

# Mapping: v1 label → v2 Issue Type name
# bash 3.2 has no associative arrays — use parallel arrays
TYPE_MAP_KEYS=("feature" "bug" "improvement" "infra" "epic")
TYPE_MAP_VALUES=("Feature" "Bug" "Feature" "Task" "Story")
# Note:
#   - `improvement` was a v1 type; in v2 the issue itself becomes Feature type
#     and gets a separate `improvement` nature label (added below)
#   - `infra` was a v1 type; in v2 the issue itself becomes Task type with
#     an `infra` nature label
#   - `epic` was the v1 in-repo composite; in v2 it becomes Story

# Mapping: v1 stage label → v2 status key (used by sillok_project_status_set)
STAGE_MAP_KEYS=("backlog" "todo" "designed" "in-progress" "in-review")
STAGE_MAP_VALUES=("todo" "todo" "design" "progress" "review")

# Helper: look up value by key in parallel arrays
lookup() {
  local target="$1"
  local -a keys=("${!2}")
  local -a values=("${!3}")
  local i
  for ((i=0; i<${#keys[@]}; i++)); do
    if [[ "${keys[$i]}" == "$target" ]]; then
      echo "${values[$i]}"
      return 0
    fi
  done
}

echo "Scanning open issues in $REPO..."

# Use --state all to also re-tag closed historical issues if user wants
issues=$(gh issue list --repo "$REPO" --state all --limit 500 --json number,labels)

# Warn on truncation: hitting the 500 cap means older issues weren't fetched.
if [[ "$(echo "$issues" | jq 'length')" -eq 500 ]]; then
  echo "[warn] 500-issue fetch limit reached — older issues may not be migrated." >&2
  echo "[warn] Re-run after closing/filtering, or migrate remaining issues manually." >&2
fi

count=0
while IFS= read -r line; do
  num=$(echo "$line" | jq -r '.number')
  labels=$(echo "$line" | jq -r '[.labels[].name] | join(",")')

  # Detect v1 type label
  v1_type=""
  for k in "${TYPE_MAP_KEYS[@]}"; do
    if echo ",$labels," | grep -q ",$k,"; then
      v1_type="$k"
      break
    fi
  done
  target_type=""
  if [[ -n "$v1_type" ]]; then
    target_type=$(lookup "$v1_type" TYPE_MAP_KEYS[@] TYPE_MAP_VALUES[@])
  fi

  # Detect v1 stage label
  v1_stage=""
  for k in "${STAGE_MAP_KEYS[@]}"; do
    if echo ",$labels," | grep -q ",$k,"; then
      v1_stage="$k"
      break
    fi
  done
  target_status=""
  if [[ -n "$v1_stage" ]]; then
    target_status=$(lookup "$v1_stage" STAGE_MAP_KEYS[@] STAGE_MAP_VALUES[@])
  fi

  # Detect nature labels to preserve (improvement / infra were v1 types,
  # become nature labels in v2)
  add_nature=""
  if [[ "$v1_type" == "improvement" ]]; then add_nature="improvement"; fi
  if [[ "$v1_type" == "infra" ]]; then add_nature="infra"; fi

  if [[ -z "$target_type" && -z "$target_status" ]]; then
    continue
  fi

  count=$((count + 1))
  echo "  #$num: type=${target_type:-keep} status=${target_status:-keep}${add_nature:+ nature=$add_nature}"

  if [[ "$APPLY" == "--apply" ]]; then
    if [[ -n "$target_type" ]]; then
      sillok_issue_type_set "$REPO" "$num" "$target_type" || echo "    [warn] type set failed for #$num" >&2
    fi
    if [[ -n "$target_status" ]]; then
      issue_url="https://github.com/$REPO/issues/$num"
      item_id=$(sillok_project_item_add "$issue_url") || { echo "    [warn] project add failed for #$num" >&2; continue; }
      sillok_project_status_set "$item_id" "$target_status" || echo "    [warn] status set failed for #$num" >&2
    fi
    if [[ -n "$add_nature" ]]; then
      gh issue edit "$num" --repo "$REPO" --add-label "$add_nature" 2>/dev/null || true
    fi
    # Strip old type + stage labels (idempotent)
    for old in feature bug improvement infra epic todo designed in-progress in-review backlog; do
      gh issue edit "$num" --repo "$REPO" --remove-label "$old" 2>/dev/null || true
    done
  fi
done < <(echo "$issues" | jq -c '.[]')

if [[ "$APPLY" != "--apply" ]]; then
  echo
  echo "DRY RUN. $count issues would be migrated. Re-run with --apply to execute."
else
  echo
  echo "Migration complete. $count issues processed."
fi
