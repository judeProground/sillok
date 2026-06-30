#!/usr/bin/env bash
# sillok — Development panel helpers.
# Wraps the createLinkedBranch GraphQL mutation so the issue's Development
# panel shows linked branches (not just PRs).
set -euo pipefail

# Resolve this file's directory under bash AND zsh (nounset-safe), so the
# plugin root can be derived when CLAUDE_PLUGIN_ROOT is not exported.
# zsh: ${(%):-%x} expands to the file currently being sourced; eval defers
# the zsh-only syntax so bash never parses it.
if [[ -n "${BASH_VERSION:-}" ]]; then
  _SILLOK_LIB_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
elif [[ -n "${ZSH_VERSION:-}" ]]; then
  eval '_SILLOK_LIB_DIR=$(cd "$(dirname "${(%):-%x}")" && pwd)'
else
  _SILLOK_LIB_DIR=$(cd "$(dirname "$0")" && pwd)
fi
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
# createLinkedBranch is CREATE-ONLY: if the branch already exists on the remote,
# the mutation returns {linkedBranch: null} with exit 0 and no link is made.
# Call this BEFORE the first push. Always returns 0 (linking is non-fatal).
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

  local linked_id
  linked_id=$(gh api graphql -f query="mutation {
    createLinkedBranch(input: { $input }) {
      linkedBranch { id ref { name } }
    }
  }" --jq '.data.createLinkedBranch.linkedBranch.id' 2>/dev/null) || {
    echo "[sillok] WARN: createLinkedBranch call failed — Development panel may lack the branch link for '$branch_name'" >&2
    return 0
  }

  if [[ -z "$linked_id" || "$linked_id" == "null" ]]; then
    echo "[sillok] WARN: linked branch NOT created for '$branch_name' — mutation returned null (the branch already exists on the remote; createLinkedBranch must run before the first push)" >&2
    return 0
  fi

  # End-to-end verification: a non-null mutation echo is not proof the link is
  # queryable. WARN (don't fail) when the branch is absent from the issue's
  # linkedBranches — linking is an enhancement, never a blocker.
  # `last: 50`: the just-created link is newest, so it is always within the
  # page regardless of total link count.
  local verified
  verified=$(gh api graphql -f query="{
    node(id: \"$issue_id\") {
      ... on Issue { linkedBranches(last: 50) { nodes { ref { name } } } }
    }
  }" --jq '.data.node.linkedBranches.nodes[].ref.name' 2>/dev/null | grep -Fx "$branch_name" || true)
  if [[ -z "$verified" ]]; then
    echo "[sillok] WARN: linked-branch verification failed for '$branch_name' — mutation returned an id but the link is not queryable on the issue" >&2
  fi
  return 0
}

# Resolve the issue node id, create the Development-panel link, THEN push — in
# that fixed order. createLinkedBranch is create-only (see sillok_link_branch),
# so the link MUST happen before the branch exists on the remote: baking the
# order into one function makes it impossible to reverse at a call site.
# The branch SHA and the push directory are caller-supplied so each site keeps
# its own pre/post steps (e.g. /sillok-story promotion's pre-push + delete-old).
# Usage: sillok_link_and_push <repo> <issue-N> <branch-name> <branch-sha> <push-dir>
sillok_link_and_push() {
  local repo="$1"
  local issue_n="$2"
  local branch_name="$3"
  local branch_sha="$4"
  local push_dir="$5"

  local issue_node_id
  issue_node_id=$(sillok_issue_node_id "$repo" "$issue_n")
  sillok_link_branch "$issue_node_id" "$branch_name" "$branch_sha"
  (cd "$push_dir" && git push -u origin "$branch_name")
}
