#!/usr/bin/env bash
# sillok — set up a fresh feature worktree.
# Creates `<worktreeDir>/<slug>` based on `origin/<baseBranch>`, copies the
# configured gitignored config files, and runs the configured install command.
#
# usage: setup-feature-worktree.sh <slug> <branch>
set -euo pipefail

if [[ $# -lt 2 || $# -gt 3 ]]; then
  echo "usage: $0 <slug> <branch> [base_branch]" >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/config.sh
source "$SCRIPT_DIR/lib/config.sh"

slug="$1"
branch="$2"
BASE_BRANCH_OVERRIDE="${3:-}"

if [[ -n "$BASE_BRANCH_OVERRIDE" ]]; then
  BASE_BRANCH="$BASE_BRANCH_OVERRIDE"
else
  BASE_BRANCH=$(sillok_config_required baseBranch)
fi
WORKTREE_DIR=$(sillok_config worktree.dir)
WORKTREE_DIR=${WORKTREE_DIR:-.worktrees}
INSTALL=$(sillok_config install)

worktree="$WORKTREE_DIR/$slug"

git fetch origin "$BASE_BRANCH"
git worktree add "$worktree" -b "$branch" "origin/$BASE_BRANCH"

# Copy configured gitignored files into the new worktree.
while IFS= read -r f; do
  [[ -z "$f" ]] && continue
  if [[ -f "$f" ]]; then
    cp "$f" "$worktree/"
  else
    echo "[setup-feature-worktree] WARN: '$f' not found in main worktree" >&2
  fi
done < <(sillok_config_array worktree.copyFiles)

if [[ -n "$INSTALL" ]]; then
  (cd "$worktree" && eval "$INSTALL")
else
  echo "[setup-feature-worktree] (install command not configured — skipping install step)"
fi

echo
echo "✅ worktree ready"
echo "   path:   $worktree"
echo "   branch: $branch"
