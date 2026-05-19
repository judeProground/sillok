---
description: Create or promote-to an epic — always backed by a real integration branch and worktree. From a non-sillok branch creates a fresh epic; from inside a sillok feature/bug/improvement/infra branch offers promotion of the current issue.
---

You are running `/sillok-epic`.

An **epic** in sillok is a parent tracking issue PLUS a real integration branch (`epic/issue-<N>-<slug>`) PLUS a worktree. Sub-features under the epic cut from and PR back to this integration branch. The epic itself eventually PRs to the configured `baseBranch` (usually `main`) with a merge commit (NOT squash), so sub-feature commits remain visible in the base-branch history.

## Step 1: Detect context

Run:

```bash
source "${CLAUDE_PLUGIN_ROOT}/scripts/lib/config.sh"
REPO=$(sillok_config_required repo)
BASE_BRANCH=$(sillok_config_required baseBranch)
prefix_regex=$(sillok_branch_prefix_regex)
branch=$(git branch --show-current 2>/dev/null || echo "")
```

Decide branch context:

- If `$branch` matches `^epic/issue-([0-9]+)-`: ABORT — "You're already on an epic branch. To add a sub-feature, run `/sillok-start --parent <N>`."
- Else if `$branch` matches `$prefix_regex` and the captured type is one of `feature|bug|improvement|infra`: this is **promotion context** (§3). Extract `<N>` and `<slug>` by walking BASH_REMATCH (find first numeric, then next capture for slug, and remember the matched type token).
- Else: this is **standalone creation** (§2).

## Step 2: Standalone epic creation

Used when the user is on `main`, an unrelated branch, or a fresh worktree.

1. Prompt: "Epic title (verb-form imperative or short noun-phrase OK — epics are tracking issues, not single actions)."
2. Prompt for 1-line summary and a few lines of Context. Architecture and Non-goals are optional — leave blank if user has none.
3. Compose the epic body using the epic template from `.claude/sillok/rules/gh-issue-conventions.md`:

   ```markdown
   <1-line summary>

   ## Integration branch

   `epic/issue-<TBD>-<slug>`

   ## Architecture
   <optional>

   ## Sub-issues
   <empty — fills as /sillok-start --parent runs>

   ## Context
   <from prompt>

   ## Non-goals
   <optional>
   ```

4. Create the issue:

   ```bash
   gh issue create --repo "$REPO" \
     --title "<epic title>" \
     --label epic --label todo --label p3 \
     --body "<body>"
   ```

   Capture `<N>` from the URL output.

5. Compute slug:

   ```bash
   slug_full=$(bash "${CLAUDE_PLUGIN_ROOT}/scripts/slug-from-title.sh" "$N" "<title>")
   # Output is "<N>-<title-slug>"; strip the leading "<N>-" to get just the title slug
   slug_without_n="${slug_full#${N}-}"
   ```

6. Resolve epic branch name:

   ```bash
   user_token=$(git config user.name | awk '{print tolower($1)}' | tr -cd '[:alnum:]')
   resolved_epic_prefix=$(sillok_branch_prefix_resolve epic "$user_token")
   epic_branch="${resolved_epic_prefix}${N}-${slug_without_n}"
   ```

7. Update the issue body to replace the `<TBD>` placeholder in `## Integration branch` with the real branch name. Post the updated body back via `gh issue edit <N> -F -` (stdin heredoc).

8. Create the worktree (3rd arg = base branch is the configured `baseBranch`, not an integration branch):

   ```bash
   bash "${CLAUDE_PLUGIN_ROOT}/scripts/setup-feature-worktree.sh" \
     "${N}-${slug_without_n}" "$epic_branch" "$BASE_BRANCH"
   ```

9. Push the branch to origin (so sub-features can cut from it):

   ```bash
   worktree_path="<worktreeDir>/${N}-${slug_without_n}"   # use the path setup-feature-worktree printed
   (cd "$worktree_path" && git push -u origin "$epic_branch")
   ```

10. Print summary:

    ```
    ✅ Epic created
    
    Issue: <URL>
    Branch: <epic_branch>
    Worktree: <worktree_path>
    
    Next:
    - cd <worktree_path>
    - /sillok-start --parent <N>   to add a sub-feature
    ```

## Step 3: Promotion (current branch is a sillok feature/bug/improvement/infra)

Used when the user is in the middle of a non-epic work-unit branch that turned out bigger than expected.

1. Already extracted in Step 1: `<N>`, `<slug>`, `<matched_type>`.

2. Fetch the current issue:

   ```bash
   issue_json=$(gh issue view "$N" --repo "$REPO" --json title,labels,body)
   title=$(echo "$issue_json" | jq -r '.title')
   summary=$(echo "$issue_json" | jq -r '.body' | awk '/^## Summary/{flag=1; next} /^## /{if(flag)exit} flag')
   current_type=$(echo "$issue_json" | jq -r '[.labels[].name] | map(select(. == "feature" or . == "bug" or . == "improvement" or . == "infra")) | .[0] // ""')
   ```

   If `current_type` is empty: ABORT — "Issue #$N has no recognized type label; promote manually."

3. Check working-tree state:

   ```bash
   dirty=$(git status --porcelain 2>/dev/null)
   ```

   If non-empty, prompt: "Working tree has uncommitted changes. Stash them and (optionally) reapply on a new sub-feature branch? (y/n)". On `n`: ABORT with "Commit or stash manually before promoting."

4. Confirm promotion with user:

   ```
   Promote #$N (`$title`) from `$current_type` to `epic`?
   This will:
     • Change #$N's type label from $current_type to epic
     • Rename branch  $branch  →  epic/issue-$N-<slug>
     • Push the new branch and delete the old remote branch
     • Rewrite the issue body to the epic template (preserves Summary)
     • Insert ## Integration branch section
     ${dirty:+• Stash current changes and (optionally) move them into a new sub-feature}
   ```

   Prompt: "Proceed? (y/n)". On `n`: ABORT cleanly (no changes made yet).

5. On confirmation:

   a. **Stash if dirty:**
      ```bash
      stash_ref=""
      if [[ -n "$dirty" ]]; then
        git stash push -m "sillok-epic-promotion-${N}"
        stash_ref=$(git rev-parse stash@{0})
      fi
      ```

   b. **Flip the label:**
      ```bash
      gh issue edit "$N" --repo "$REPO" --remove-label "$current_type" --add-label epic
      ```

   c. **Resolve new epic branch name:**
      ```bash
      user_token=$(git config user.name | awk '{print tolower($1)}' | tr -cd '[:alnum:]')
      resolved_epic_prefix=$(sillok_branch_prefix_resolve epic "$user_token")
      epic_branch="${resolved_epic_prefix}${N}-${slug}"
      ```

   d. **Rename local branch:**
      ```bash
      git branch -m "$branch" "$epic_branch"
      ```

   e. **Push new + delete old on remote:**
      ```bash
      git push -u origin "$epic_branch"
      # Old branch may not exist on remote; ignore failure.
      git push origin --delete "$branch" 2>/dev/null || true
      ```

   f. **Rewrite issue body:**

      Build the new body from the epic template, preserving the original `$summary`. Use `gh issue edit -F -`:

      ```bash
      gh issue edit "$N" --repo "$REPO" -F - <<EOF
      $summary

      ## Integration branch

      \`$epic_branch\`

      ## Architecture

      (Promoted from $current_type — fill in architecture as sub-features emerge.)

      ## Sub-issues

      ## Context

      (Original context preserved from the $current_type issue; expand as needed.)

      ## Non-goals
      EOF
      ```

      The user can edit the body afterwards to flesh out Architecture / Context / Non-goals.

   g. **Handle the stash:**

      If `stash_ref` was set, prompt: "Move the stashed changes into a new sub-feature now? (y/n)"

      - On `y`: prompt for sub-feature title. Then run the `/sillok-start --parent $N` flow (create sub-issue, set BASE_BRANCH=$epic_branch, run setup-feature-worktree.sh). After the new worktree exists, apply the stash inside it:
        ```bash
        (cd "<new sub-feature worktree>" && git stash apply "$stash_ref" && git stash drop "$stash_ref")
        ```
      - On `n`: stash stays — print "Stash ref: $stash_ref. Run `git stash pop` here on the epic branch to recover, or move it manually later."

6. Print summary:

   ```
   ✅ Promoted #$N from $current_type to epic
   
   Branch renamed: $branch → $epic_branch
   Issue body: rewritten to epic template
   ${stash_handled:+Sub-feature created: <URL>}
   
   Next:
   - /sillok-start --parent $N  to add more sub-features
   ```

## Step 4: Abort conditions

ABORT cleanly (no side effects committed) if:

- Working tree is dirty and user declines to stash (Step 3.3 `n` path).
- Issue lacks a recognized type label (Step 3.2 fail).
- User declines confirmation at Step 3.4 (`n`).

For any partial failure mid-promotion (e.g. branch rename succeeded but push failed), surface the exact state and the command to recover manually. Do NOT attempt to auto-rollback complex states.
