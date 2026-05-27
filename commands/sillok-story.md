---
description: Create or promote-to a story — always backed by a real integration branch and worktree. From a non-sillok branch creates a fresh story; from inside a sillok feature/bug/improvement/infra branch offers promotion of the current issue. A story is an in-repo composite (parent tracking issue + integration branch + worktree) typed `Story` on GitHub.
---

You are running `/sillok-story`.

A **story** in sillok is a parent tracking issue PLUS a real integration branch (`story/issue-<N>-<slug>`) PLUS a worktree. Sub-features under the story cut from and PR back to this integration branch. The story itself eventually PRs to the configured `baseBranch` (usually `main`) with a merge commit (NOT squash), so sub-feature commits remain visible in the base-branch history.

## Language

Read the `language` value from config (`sillok_config language`).

- `auto` → write all generated content (issue body) in the same language as the current conversation session.
- `ko` → write all generated content in Korean.
- `en` → write all generated content in English.

Section headers (`## Summary`, `## Integration branch`, etc.) and GitHub API field names stay in English regardless of language setting — only prose content follows the language preference.

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

- If `$branch` matches `^story/issue-([0-9]+)-`: ABORT — "You're already on a story branch. To add a sub-feature, run `/sillok-start --parent <N>`."
- Else if `$branch` matches `$prefix_regex` and the captured type is one of `feature|bug|improvement|infra`: this is **promotion context** (§3). Extract `<N>` and `<slug>` by walking BASH_REMATCH (find first numeric, then next capture for slug, and remember the matched type token).
- Else: this is **standalone creation** (§2).

## Step 2: Standalone story creation

Used when the user is on `main`, an unrelated branch, or a fresh worktree.

1. Prompt: "Story title (verb-form imperative or short noun-phrase OK — stories are tracking issues, not single actions)."
2. Prompt for 1-line summary and a few lines of Context. Architecture and Non-goals are optional — leave blank if user has none.
3. Compose the story body using the story template from `.claude/sillok/rules/gh-issue-conventions.md`:

   ```markdown
   <1-line summary>

   ## Integration branch

   `story/issue-<TBD>-<slug>`

   ## Architecture
   <optional>

   ## Sub-issues
   <empty — fills as /sillok-start --parent runs>

   ## Context
   <from prompt>

   ## Non-goals
   <optional>
   ```

4. Create the issue. Read orgMode from config (`sillok_config orgMode`). Branch the REST call:

   **Org mode (`orgMode=true`):**

   ```bash
   issue_url=$(gh api -X POST \
     -H "X-GitHub-Api-Version: 2026-03-10" \
     "/repos/$REPO/issues" \
     -f title="<story title>" \
     -f body="<body>" \
     -f type="Story" \
     -f "assignees[]=$(gh api user --jq .login)" \
     -f "labels[]=p3" \
     --jq '.html_url')
   ```

   **User mode (`orgMode=false`):**

   ```bash
   issue_url=$(gh api -X POST \
     -H "X-GitHub-Api-Version: 2026-03-10" \
     "/repos/$REPO/issues" \
     -f title="<story title>" \
     -f body="<body>" \
     -f "assignees[]=$(gh api user --jq .login)" \
     -f "labels[]=p3" \
     -f "labels[]=story" \
     --jq '.html_url')
   ```

   (Difference: org mode has `-f type=Story`, user mode has `-f labels[]=story` instead.)

   Capture `<N>` from the URL (`${issue_url##*/}`).

5. Compute slug:

   ```bash
   slug_full=$(bash "${CLAUDE_PLUGIN_ROOT}/scripts/slug-from-title.sh" "$N" "<title>")
   # Output is "<N>-<title-slug>"; strip the leading "<N>-" to get just the title slug
   slug_without_n="${slug_full#${N}-}"
   ```

6. Resolve story branch name:

   ```bash
   user_token=$(git config user.name | awk '{print tolower($1)}' | tr -cd '[:alnum:]')
   resolved_story_prefix=$(sillok_branch_prefix_resolve story "$user_token")
   story_branch="${resolved_story_prefix}${N}-${slug_without_n}"
   ```

7. Update the issue body to replace the `<TBD>` placeholder in `## Integration branch` with the real branch name. Post the updated body back via `gh issue edit <N> -F -` (stdin heredoc).

8. Create the worktree (3rd arg = base branch is the configured `baseBranch`, not an integration branch):

   ```bash
   bash "${CLAUDE_PLUGIN_ROOT}/scripts/setup-feature-worktree.sh" \
     "${N}-${slug_without_n}" "$story_branch" "$BASE_BRANCH"
   ```

9. Push the branch to origin (so sub-features can cut from it):

   ```bash
   worktree_path="<worktreeDir>/${N}-${slug_without_n}"   # use the path setup-feature-worktree printed
   (cd "$worktree_path" && git push -u origin "$story_branch")
   ```

10. Link the branch into the issue's Development panel and add the issue to the project board with Status=Todo:

    ```bash
    # Linked branch — populate Development panel
    BRANCH_SHA=$(cd "$worktree_path" && git rev-parse HEAD)
    source "${CLAUDE_PLUGIN_ROOT}/scripts/lib/dev-link.sh"
    ISSUE_NODE_ID=$(sillok_issue_node_id "$REPO" "$N")
    sillok_link_branch "$ISSUE_NODE_ID" "$story_branch" "$BRANCH_SHA"

    # Project add + status Todo
    source "${CLAUDE_PLUGIN_ROOT}/scripts/lib/project.sh"
    ITEM_ID=$(sillok_project_item_add "$issue_url")
    sillok_project_status_set "$ITEM_ID" todo
    ```

11. Print summary:

    ```
    ✅ Story created

    Issue: <URL>
    Branch: <story_branch>
    Worktree: <worktree_path>

    Next:
    - cd <worktree_path>
    - /sillok-start --parent <N>   to add a sub-feature
    ```

## Step 3: Promotion (current branch is a sillok feature/bug/improvement/infra)

Used when the user is in the middle of a non-story work-unit branch that turned out bigger than expected.

1. Already extracted in Step 1: `<N>`, `<slug>`, `<matched_type>`.

2. Fetch the current issue:

   ```bash
   issue_json=$(gh issue view "$N" --repo "$REPO" --json title,labels,body)
   title=$(echo "$issue_json" | jq -r '.title')
   summary=$(echo "$issue_json" | jq -r '.body' | awk '/^## Summary/{flag=1; next} /^## /{if(flag)exit} flag')
   # v2: type lives in the .type field, not labels
   current_issue_type=$(gh api -H "X-GitHub-Api-Version: 2026-03-10" \
     "/repos/$REPO/issues/$N" --jq '.type.name // ""')
   ```

   If `current_issue_type` is empty OR equals `Story` or `Epic`: ABORT — "Issue #$N has type \`$current_issue_type\` — only Feature/Task/Bug issues can be promoted to Story."

3. Check working-tree state:

   ```bash
   dirty=$(git status --porcelain 2>/dev/null)
   ```

   If non-empty, prompt: "Working tree has uncommitted changes. Stash them and (optionally) reapply on a new sub-feature branch? (y/n)". On `n`: ABORT with "Commit or stash manually before promoting."

4. Confirm promotion with user:

   ```
   Promote #$N (`$title`) from `$current_issue_type` to `Story`?
   This will:
     • Change #$N's Issue Type from $current_issue_type to Story
     • Rename branch  $branch  →  story/issue-$N-<slug>
     • Push the new branch and delete the old remote branch
     • Re-link the new branch into the issue's Development panel
     • Rewrite the issue body to the story template (preserves Summary)
     • Insert ## Integration branch section
     ${dirty:+• Stash current changes and (optionally) move them into a new sub-feature}
   ```

   Prompt: "Proceed? (y/n)". On `n`: ABORT cleanly (no changes made yet).

5. On confirmation:

   a. **Stash if dirty:**
      ```bash
      stash_ref=""
      if [[ -n "$dirty" ]]; then
        git stash push -m "sillok-story-promotion-${N}"
        stash_ref=$(git rev-parse stash@{0})
      fi
      ```

   b. **Set the GitHub issue type to Story:**
      ```bash
      source "${CLAUDE_PLUGIN_ROOT}/scripts/lib/issue-types.sh"
      sillok_issue_type_set "$REPO" "$N" Story
      ```

   c. **Resolve new story branch name:**
      ```bash
      user_token=$(git config user.name | awk '{print tolower($1)}' | tr -cd '[:alnum:]')
      resolved_story_prefix=$(sillok_branch_prefix_resolve story "$user_token")
      story_branch="${resolved_story_prefix}${N}-${slug}"
      ```

   d. **Rename local branch:**
      ```bash
      git branch -m "$branch" "$story_branch"
      ```

   e. **Push new + delete old on remote:**
      ```bash
      git push -u origin "$story_branch"
      # Old branch may not exist on remote; ignore failure.
      git push origin --delete "$branch" 2>/dev/null || true
      ```

   f. **Re-link branch into the issue's Development panel:**
      ```bash
      source "${CLAUDE_PLUGIN_ROOT}/scripts/lib/dev-link.sh"
      ISSUE_NODE_ID=$(sillok_issue_node_id "$REPO" "$N")
      BRANCH_SHA=$(git rev-parse HEAD)
      sillok_link_branch "$ISSUE_NODE_ID" "$story_branch" "$BRANCH_SHA"
      ```

      (The issue was already added to the project when it was first created as `$current_issue_type` via `/sillok-start` — no project-add needed here.)

   g. **Rewrite issue body:**

      Build the new body from the story template, preserving the original `$summary`. Use `gh issue edit -F -`:

      ```bash
      gh issue edit "$N" --repo "$REPO" -F - <<EOF
      $summary

      ## Integration branch

      \`$story_branch\`

      ## Architecture

      (Promoted from $current_issue_type — fill in architecture as sub-features emerge.)

      ## Sub-issues

      ## Context

      (Original context preserved from the $current_issue_type issue; expand as needed.)

      ## Non-goals
      EOF
      ```

      The user can edit the body afterwards to flesh out Architecture / Context / Non-goals.

   h. **Handle the stash:**

      If `stash_ref` was set, prompt: "Move the stashed changes into a new sub-feature now? (y/n)"

      - On `y`: prompt for sub-feature title. Then run the `/sillok-start --parent $N` flow (create sub-issue, set BASE_BRANCH=$story_branch, run setup-feature-worktree.sh). After the new worktree exists, apply the stash inside it:
        ```bash
        (cd "<new sub-feature worktree>" && git stash apply "$stash_ref" && git stash drop "$stash_ref")
        ```
      - On `n`: stash stays — print "Stash ref: $stash_ref. Run `git stash pop` here on the story branch to recover, or move it manually later."

6. Print summary:

   ```
   ✅ Promoted #$N from $current_issue_type to Story

   Branch renamed: $branch → $story_branch
   Issue body: rewritten to story template
   ${stash_handled:+Sub-feature created: <URL>}

   Next:
   - /sillok-start --parent $N  to add more sub-features
   ```

## Step 4: Abort conditions

ABORT cleanly (no side effects committed) if:

- Working tree is dirty and user declines to stash (Step 3.3 `n` path).
- Issue has no Issue Type, or its Issue Type is `Story` / `Epic` (Step 3.2 fail).
- User declines confirmation at Step 3.4 (`n`).

For any partial failure mid-promotion (e.g. branch rename succeeded but push failed), surface the exact state and the command to recover manually. Do NOT attempt to auto-rollback complex states.
