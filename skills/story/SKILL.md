---
name: story
description: Internal sillok stage skill — enter via the /sillok-story command or a sillok:workflow handoff; for natural-language intent invoke sillok:workflow instead. Creates or promotes-to a story (parent tracking issue + integration branch + worktree).
user-invocable: false
---

# Sillok Story

You are running the sillok `story` stage.

A **story** in sillok is a parent tracking issue PLUS a real integration branch (`story/issue-<N>-<slug>`) PLUS a worktree. Sub-features under the story cut from and PR back to this integration branch. The story itself eventually PRs to the configured `baseBranch` (usually `main`) with a merge commit (NOT squash), so sub-feature commits remain visible in the base-branch history.

## Input contract

The user may pass:

- No arguments — standalone creation or promotion is auto-detected.
- `--parent <value>` — attach to an existing Epic or story in a parent repo. Three forms accepted:
  - `--parent 42` — same-repo issue #42
  - `--parent myorg/projects#42` — cross-repo issue
  - `--parent https://github.com/myorg/projects/issues/42` — URL form, parsed to `myorg/projects#42`

Parse `--parent` into `parent_owner`, `parent_repo`, `parent_n`. When only a number is given, `parent_owner` = current repo owner and `parent_repo` = current repo name.

## Language

Read the `### Language` section from the precompute output and apply the `output-language.md` rule (`.claude/sillok/rules/output-language.md`) to all generated content (issue body).

## Step 1: Detect context

Run the precompute script to derive current branch context, open epics, and language setting:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/precompute-story.sh
```

Then source the config helpers and capture the values the later steps reference (`$REPO`, `$BASE_BRANCH`, the current `$branch`, and the `sillok_*` shell functions used in §2/§3):

```bash
source "${CLAUDE_PLUGIN_ROOT}/scripts/lib/config.sh"
REPO=$(sillok_config_required repo)
BASE_BRANCH=$(sillok_config_required baseBranch)
branch=$(git branch --show-current 2>/dev/null || echo "")   # current branch; §3 promotion renames this
```

Read the markdown block it prints. Branch on the `### Mode` section:

- If the Mode line is `ABORT:` — hard stop. Surface the printed reason to the user. Do not proceed.
- If the Mode line is `promotion` — read the printed Issue # and Slug; proceed to §3 (Promotion).
- If the Mode line is `standalone` — proceed to §2 (Standalone creation).

## Step 2: Standalone story creation

Used when the user is on `main`, an unrelated branch, or a fresh worktree.

1. Prompt: "Story title (verb-form imperative or short noun-phrase OK — stories are tracking issues, not single actions)."
2. Prompt for 1-line summary and a few lines of Context. Architecture and Non-goals are optional — leave blank if user has none.
3. Compose the story body. Read `${CLAUDE_PLUGIN_ROOT}/skills/story/body-templates.md` and follow its **Standalone story body** section (the skeleton plus the empty-section notes).

4. Create the issue via the shared helper — type `Story` (org mode) / `story` label (user mode), default `p3` priority:

   ```bash
   issue_url=$(bash ${CLAUDE_PLUGIN_ROOT}/scripts/create-issue.sh \
     --repo "$REPO" \
     --title "<story title>" \
     --type-name Story --type-label story \
     --body-file - <<'BODY'
<body>
BODY
   )
   ```

   The script reads `orgMode` from config: org mode sets `-f type=Story` and no priority label (priority lands on the board's Priority field in step 10); user mode applies the `story` + default `p3` labels. (Omit `--priority` → defaults to `labels.defaults.priority`.)

   Capture `<N>` from the URL (`${issue_url##*/}`).

5. Epic-suggest — attach the story under an Epic parent (runs BEFORE creating the integration branch):

   If `--parent` was given in the input, use `parent_owner`, `parent_repo`, `parent_n` directly — skip the prompt.

   Otherwise, display the **Open epics** section from the precompute output and ask:
   "Does this story belong under an epic? Reply with the issue number, or `standalone`."

   If the precompute reported `(none — standalone unless --parent specified)`, default to standalone unless `--parent` was given.

   On a chosen `#M` or `owner/repo#M`:
   - Parse into `parent_owner`, `parent_repo`, `parent_n`.
   - Resolve node IDs and call `addSubIssue` (see "Epic link step" below).
   - Add a `Parent: owner/repo#M` line at the top of the story body (per `sillok:gh-issue-management` body-template order), then update the issue body via `gh issue edit <N> --repo "$REPO" -F -`.

6. Compute slug. Branch/worktree names stay ASCII/English even when the story title is Korean (or any non-English language). **If `<title>` is not already English**, translate it into a concise English phrase (3–6 words) first and pass THAT — not the original title — as the slug argument. The issue keeps its original-language title.

   ```bash
   # <slug-title> = English phrase (== title if already English).
   # e.g. "결제 모듈 리팩터링" → "refactor payment module"
   slug_full=$(bash "${CLAUDE_PLUGIN_ROOT}/scripts/slug-from-title.sh" "$N" "<slug-title>")
   # Output is "<N>-<title-slug>"; strip the leading "<N>-" to get just the title slug
   slug_without_n="${slug_full#${N}-}"
   ```

7. Resolve story branch name:

   ```bash
   user_token=$(git config user.name | awk '{print tolower($1)}' | tr -cd '[:alnum:]')
   resolved_story_prefix=$(sillok_branch_prefix_resolve story "$user_token")
   story_branch="${resolved_story_prefix}${N}-${slug_without_n}"
   ```

8. Update the issue body to replace the `<TBD>` placeholder in `## Integration branch` with the real branch name. Post the updated body back via `gh issue edit <N> -F -` (stdin heredoc).

9. Create the worktree (3rd arg = base branch is the configured `baseBranch`, not an integration branch):

   ```bash
   bash "${CLAUDE_PLUGIN_ROOT}/scripts/setup-feature-worktree.sh" \
     "${N}-${slug_without_n}" "$story_branch" "$BASE_BRANCH"
   ```

10. Link the branch into the Development panel and push, in that fixed create-only order (`sillok_link_and_push` bakes it in — the link must precede the push or `createLinkedBranch` silently no-ops; see `sillok:gh-issue-management` → "Linked branches"). Under org mode the mutation creates the remote ref and the push sets the upstream; under `orgMode=false` the link no-ops and the push creates the branch (so sub-features can cut from it):

    ```bash
    worktree_path="<worktreeDir>/${N}-${slug_without_n}"   # use the path setup-feature-worktree printed
    BRANCH_SHA=$(cd "$worktree_path" && git rev-parse HEAD)

    # HARD GATE: link-before-push (create-only) — enforced inside sillok_link_and_push.
    source "${CLAUDE_PLUGIN_ROOT}/scripts/lib/dev-link.sh"
    sillok_link_and_push "$REPO" "$N" "$story_branch" "$BRANCH_SHA" "$worktree_path"
    ```

11. Add the issue to the project board with Status=Todo, then set priority:

    ```bash
    source "${CLAUDE_PLUGIN_ROOT}/scripts/lib/project.sh"
    ITEM_ID=$(sillok_project_item_add "$issue_url")
    sillok_project_status_set "$ITEM_ID" todo

    # Priority — org-guarded + NON-FATAL inside sillok_priority_apply (org mode
    # sets the org Priority issue field; user mode is a no-op since the p3 label
    # from step 4 is the record). Default key from labels.defaults.priority.
    sillok_priority_apply "$issue_url" "$(sillok_config labels.defaults.priority)"
    ```

    Priority failure is NON-FATAL: the story issue, branch, and worktree exist either way (the helper warns and continues). See `sillok:gh-issue-management` → "Priority" for the storage model.

12. Print summary:

    ```
    ✅ Story created

    Issue: <URL>
    Branch: <story_branch>
    Worktree: <worktree_path> — the next stage runs from there
    Sub-features: added via the start stage with --parent <N> (orchestrator-routed)
    ```

## Step 3: Promotion (current branch is a sillok feature/bug/improvement/infra)

Used when the user is in the middle of a non-story work-unit branch that turned out bigger than expected.

1. Already extracted from precompute output (Step 1): `<N>`, `<slug>`.

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

3. Check for existing parent. Look up the promoted issue's current parent via GraphQL, or a `Parent:` line in its body:

   ```bash
   existing_parent=$(gh api graphql \
     -f query="{ repository(owner: \"${REPO%%/*}\", name: \"${REPO##*/}\") { issue(number: $N) { parent { number repository { nameWithOwner } } } } }" \
     --jq '.data.repository.issue.parent | if . then "\(.repository.nameWithOwner)#\(.number)" else "" end' \
     2>/dev/null || echo "")
   ```

   If `existing_parent` is non-empty, preserve it — note it to the user ("이 이슈는 이미 `$existing_parent`의 하위 이슈입니다. 기존 부모 관계를 보존합니다.") and skip the epic-suggest prompt for promotion. Set `parent_owner`, `parent_repo`, `parent_n` from the preserved reference.

   If `existing_parent` is empty and `--parent` was not given, run the same epic-suggest step as §2 (display the **Open epics** section from the precompute output and ask the user). If `--parent` was given, use it.

4. Check working-tree state:

   ```bash
   dirty=$(git status --porcelain 2>/dev/null)
   ```

   If non-empty, prompt: "Working tree has uncommitted changes. Stash them and (optionally) reapply on a new sub-feature branch? (y/n)". On `n`: ABORT with "Commit or stash manually before promoting."

5. Confirm promotion with user:

   ```
   Promote #$N (`$title`) from `$current_issue_type` to `Story`?
   This will:
     • Change #$N's Issue Type from $current_issue_type to Story
     • Rename branch  $branch  →  story/issue-$N-<slug>
     • Re-link the new branch into the issue's Development panel
     • Push the new branch and delete the old remote branch
     • Rewrite the issue body to the story template (preserves Summary)
     • Insert ## Integration branch section
     ${dirty:+• Stash current changes and (optionally) move them into a new sub-feature}
   ```

   Prompt: "Proceed? (y/n)". On `n`: ABORT cleanly (no changes made yet).

6. On confirmation:

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

   e. **Pre-push the oid to the OLD branch, then re-link + push the story branch:** `createLinkedBranch` is create-only AND needs the oid to already exist on the remote; mid-work promotion typically has unpushed local commits, so first push HEAD to the OLD branch name to make the oid reachable without creating the story ref. `sillok_link_and_push` then links (creating the story ref at that oid) and pushes — the push is a content no-op here that just sets the upstream (see `sillok:gh-issue-management` → "Linked branches" for the create-only rule).

      ```bash
      # Pre-push HEAD to the OLD branch name so the oid exists remotely without
      # creating the story ref. Plain fast-forward push — typically succeeds
      # because the rename kept history; if the user rewrote history it fails
      # silently and linking degrades to a WARN. The old branch gets deleted
      # in 6f anyway.
      git push origin "HEAD:refs/heads/$branch" 2>/dev/null || true

      # HARD GATE: link-before-push (create-only) — enforced inside sillok_link_and_push.
      source "${CLAUDE_PLUGIN_ROOT}/scripts/lib/dev-link.sh"
      BRANCH_SHA=$(git rev-parse HEAD)
      sillok_link_and_push "$REPO" "$N" "$story_branch" "$BRANCH_SHA" .
      ```

      (The issue was already added to the project when it was first created as `$current_issue_type` via `/sillok-start` — no project-add needed here.)

   f. **Delete old on remote** (the story branch was pushed in 6e via `sillok_link_and_push`):
      ```bash
      # Delete the old remote branch (created/updated by 6e's pre-push);
      # ignore failure if it's absent (e.g. the pre-push itself failed).
      git push origin --delete "$branch" 2>/dev/null || true
      ```

   g. **Link as sub-issue if parent was selected in step 3:**

      If `parent_n` is set (either preserved from the existing parent or newly chosen), run the epic link step (see "Epic link step" below) — unless `existing_parent` was non-empty (the GraphQL relationship already exists; skip the mutation to avoid duplication).

   h. **Rewrite issue body:**

      Read `${CLAUDE_PLUGIN_ROOT}/skills/story/body-templates.md` and follow its **Promotion body rewrite** section (the `gh issue edit ... -F -` heredoc, preserving `$summary` and including the `Parent:` line when a parent was selected or preserved).

   i. **Handle the stash:**

      If `stash_ref` was set, prompt: "Move the stashed changes into a new sub-feature now? (y/n)"

      - On `y`: prompt for sub-feature title. Then run the `/sillok-start --parent $N` flow (create sub-issue, set BASE_BRANCH=$story_branch, run setup-feature-worktree.sh). After the new worktree exists, apply the stash inside it:
        ```bash
        (cd "<new sub-feature worktree>" && git stash apply "$stash_ref" && git stash drop "$stash_ref")
        ```
      - On `n`: stash stays — print "Stash ref: $stash_ref. Run `git stash pop` here on the story branch to recover, or move it manually later."

7. Print summary:

   ```
   ✅ Promoted #$N from $current_issue_type to Story

   Branch renamed: $branch → $story_branch
   Issue body: rewritten to story template
   ${stash_handled:+Sub-feature created: <URL>}
   Sub-features: added via the start stage with --parent $N (orchestrator-routed)
   ```

## Epic link step

When a parent is selected (in §2 or §3), link the story under it via the shared helper (resolves both node ids + calls `addSubIssue`; see `sillok:gh-issue-management` → "Sub-issue linking" for the canonical mutation):

```bash
source "${CLAUDE_PLUGIN_ROOT}/scripts/lib/subissue.sh"
sillok_subissue_link "$parent_owner" "$parent_repo" "$parent_n" "${REPO%%/*}" "${REPO##*/}" "$N"
```

Skip any epic-label verification when `parent_owner/parent_repo` differs from the current repo — cross-repo parent labels are user-controlled and sillok cannot enforce them.

## Full-auto behavior

When this stage runs inside a confirmed full-auto chain (`sillok:workflow` handoff with `automation.fullAuto: true`), the following gates are auto-resolved without prompting:

- Epic-fit question (§2 step 5 and §3 step 3) → auto-answer `standalone` unless `--parent` was given.
- Story title and summary prompts → use the user's original intent utterance as interpreted at chain entry.
- Story body confirm → accept as-is.

## Step 4: Abort conditions

ABORT cleanly (no side effects committed) if:

- Working tree is dirty and user declines to stash (Step 3.4 `n` path).
- Issue has no Issue Type, or its Issue Type is `Story` / `Epic` (Step 3.2 fail).
- User declines confirmation at Step 3.5 (`n`).
- Precompute Mode is `ABORT:`.

For any partial failure mid-promotion (e.g. branch rename succeeded but push failed), surface the exact state and the command to recover manually. Do NOT attempt to auto-rollback complex states.

## Handoff

Stage complete — on either success path (Step 2.12 standalone or Step 3.7 promotion), cd into the printed worktree first for standalone creation (promotion stays on the renamed branch in place), then invoke `sillok:workflow` to decide the next step.

## Integration

- **`sillok:workflow`** — stage orchestrator; decides what comes after this stage.
- **`sillok:start`** — next stage: run with `--parent <N>` to add a sub-feature under the story.
- **`sillok:gh-issue-management`** — canonical issue title/body conventions and management flows.
