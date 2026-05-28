#!/usr/bin/env bash
# sillok — Development panel helpers.
# Wraps the createLinkedBranch GraphQL mutation so the issue's Development
# panel shows linked branches (not just PRs).
set -euo pipefail

_SILLOK_LIB_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=config.sh
source "$_SILLOK_LIB_DIR/config.sh"

# Get the GraphQL node ID for an issue.
# Usage: sillok_issue_node_id <repo> <issue-N>
sillok_issue_node_id() {
  local repo="$1"
  local issue_n="$2"
  local owner="${repo%%/*}"
  local name="${repo##*/}"
  gh api graphql -f query="{
    repository(owner: \"$owner\", name: \"$name\") {
      issue(number: $issue_n) { id }
    }
  }" --jq '.data.repository.issue.id'
}

# Get the repository GraphQL node ID.
# Usage: sillok_repo_node_id <repo>
sillok_repo_node_id() {
  local repo="$1"
  local owner="${repo%%/*}"
  local name="${repo##*/}"
  gh api graphql -f query="{
    repository(owner: \"$owner\", name: \"$name\") { id }
  }" --jq '.data.repository.id'
}

# Create a linked branch on an issue (Development panel).
# Usage: sillok_link_branch <issue-node-id> <branch-name> <commit-sha> [repo-node-id]
# Idempotent on re-call with same args (GitHub returns the existing link).
sillok_link_branch() {
  local issue_id="$1"

  local org_mode
  org_mode=$(sillok_config orgMode)
  if [[ "$org_mode" != "true" ]]; then
    # User repo: createLinkedBranch not available. Skip.
    # PRs will still auto-link via Closes #N.
    return 0
  fi

  local branch_name="$2"
  local oid="$3"
  local repo_id="${4:-}"

  local input="issueId: \"$issue_id\", name: \"$branch_name\", oid: \"$oid\""
  if [[ -n "$repo_id" ]]; then
    input="$input, repositoryId: \"$repo_id\""
  fi

  gh api graphql -f query="mutation {
    createLinkedBranch(input: { $input }) {
      linkedBranch { id ref { name } }
    }
  }" --jq '.data.createLinkedBranch.linkedBranch.id' 2>/dev/null || {
    # If the branch is already linked, GitHub returns an error; treat as idempotent
    echo "[sillok] linked branch creation returned non-zero (may already be linked); continuing" >&2
    return 0
  }
}
