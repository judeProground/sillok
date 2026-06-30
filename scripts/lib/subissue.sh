#!/usr/bin/env bash
# sillok — sub-issue linking helper.
# Wraps the GraphQL addSubIssue mutation (the `gh` CLI has no native command for
# it) so the parent→child relationship is created identically from every stage.
# Same-repo and same-org cross-repo links use the same mutation.
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

# Link a child issue under a parent via the native sub-issue relationship.
# Resolves both node ids, then calls addSubIssue. Cross-repo (parent in a PRD
# repo, child in a code repo, same org) works with the same mutation.
# Usage: sillok_subissue_link <parent-owner> <parent-repo> <parent-N> \
#                             <child-owner> <child-repo> <child-N>
sillok_subissue_link() {
  local parent_owner="$1"
  local parent_repo="$2"
  local parent_n="$3"
  local child_owner="$4"
  local child_repo="$5"
  local child_n="$6"

  local PARENT_ID CHILD_ID
  PARENT_ID=$(gh api graphql -f query="{ repository(owner: \"$parent_owner\", name: \"$parent_repo\") { issue(number: $parent_n) { id } } }" --jq '.data.repository.issue.id')
  CHILD_ID=$(gh api graphql -f query="{ repository(owner: \"$child_owner\", name: \"$child_repo\") { issue(number: $child_n) { id } } }" --jq '.data.repository.issue.id')
  gh api graphql -f query="mutation { addSubIssue(input: { issueId: \"$PARENT_ID\", subIssueId: \"$CHILD_ID\" }) { issue { number } } }" >/dev/null
}
