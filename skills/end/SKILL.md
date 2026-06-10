---
name: end
description: Internal sillok stage skill — enter via the /sillok-end command or a sillok:workflow handoff; for natural-language intent invoke sillok:workflow instead. Pushes the branch, creates the PR per pr-convention, sets project status to In QA on the active sub-issue, updates the parent legacy checkbox if any; never auto-merges (done note embedded in the PR body Summary section).
user-invocable: false
---

# Sillok End

You are running the sillok `end` stage for the configured GitHub repository.

## Step 1: Mode detection + state derivation

Run the precompute script. It outputs branch + mode + active issue meta + project status + plan path + existing PR + parent reference + dirty working tree + CWD check in one shot:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/precompute-end.sh
```

Read the markdown block. Show it back to the user as the current state summary.

**CWD mismatch handling:** if `⚠️  CWD MISMATCH` and `EXEC FIRST: cd ...`, run that `cd` BEFORE proceeding (same reason as the design stage step 1).

**Mode-specific handling:**

- **Single-issue mode**: precompute resolved `<N>`, `<slug>`, parent `<M>` (or none), plan path, existing PR.
- **Umbrella mode**: prompt user "Which sub-issue are you closing with this PR? Reply with the issue number." Active issue = that sub-issue. ALSO:
  - List other still-open sub-issues of the umbrella's parent story: `gh issue list --repo "$REPO" --state open --search "in:body Parent: #<parent>"`. Add a `Closes #N` line per sub-issue in the PR body.
  - Include `Closes #<parent>` IF this PR is the LAST sub-issue going to `In QA` (story-completing).
- **Other branch**: ABORT.

### Mode: story-finalize (precompute reported)

If precompute output contains `### Mode: story-finalize`, the current branch IS the integration branch for a story. Set `MODE=story-finalize` and use the story-finalize PR body (Step 5b below). The PR base is the configured `baseBranch`.

### Base-branch resolution

For non-story-finalize PRs, the PR base depends on whether the active issue has a parent story with an integration branch:

```bash
PR_BASE=$(sillok_config baseBranch)   # default = configured baseBranch (usually main)
if [[ "$MODE" == "single-issue" || "$MODE" == "umbrella" ]]; then
  # Only same-repo parents can supply an integration branch in this repo.
  # Cross-repo parents (PRD epics, `Parent: owner/repo#N`) intentionally fall
  # through to the configured baseBranch — they have no in-repo branch.
  parent_n=$(gh issue view "$N" --repo "$REPO" --json body --jq '.body' | grep -oE '^Parent: #[0-9]+' | head -1 | sed 's/Parent: #//')
  if [[ -n "$parent_n" ]]; then
    parent_body=$(gh issue view "$parent_n" --repo "$REPO" --json body --jq '.body')
    integration_branch=$(echo "$parent_body" \
      | awk '/^## Integration branch/{flag=1; next} /^## /{flag=0} flag && /^`/{gsub("`",""); print; exit}')
    if [[ -n "$integration_branch" ]]; then
      PR_BASE="$integration_branch"
    fi
  fi
fi
```

For story-finalize mode, `PR_BASE=$(sillok_config baseBranch)` directly — no parent lookup.

## Language

Read the `### Language` section from the precompute output (step 1).

- `auto` → write all generated content (PR body summary) in the same language as the current conversation session.
- `ko` → write all generated content in Korean.
- `en` → write all generated content in English.

Section headers (`## Summary`, `## Design`, `Closes #N` etc.) and GitHub API field names stay in English regardless of language setting — only prose content follows the language preference.

## Step 2: Pre-conditions

All checks below were already performed by precompute (step 1). Apply the results:

1. **Project status.** Must be `In Progress`. If `In QA` or `Done` (PR likely exists, see check #4), redirect to update-only flow. Anything else → ABORT.
2. **Plan exists.** Required. precompute reported the path or `⚠️  No plan found` (ABORT in that case).
3. **Working tree.** precompute listed dirty files (if any). If dirty: prompt "Working tree has uncommitted changes (see above). Commit first / stash / abort? (commit / stash / abort)". Do NOT auto-stash silently — the user must see and decide.
4. **Existing PR.** precompute reported PR URL + state if any. If found: prompt "PR `<URL>` already exists. (a) Update body/labels only, (b) Skip and exit. Choice?".

**Full-auto note:** under `sillok:workflow` full-auto, the dirty-tree (check 3) and existing-PR (check 4) prompts are failure-demotion events — stop the chain, report the state, and fall back to propose mode. Never auto-bulldoze past them (no silent stash, no silent PR overwrite).

## Step 3: Push branch

`git push origin <branch>`

If push fails (e.g., branch out of date with remote): inspect error, prompt for rebase (`git pull --rebase origin <branch>` then retry) or abort.

## Step 4: Invoke finishing-a-development-branch

Use the `superpowers:finishing-a-development-branch` skill for the merge/PR decision flow. The skill offers options. **For sillok, the answer is always "open a PR"** — auto-respond accordingly. Do not auto-merge.

## Step 5: Compute PR body

Construct the PR body per `pr-convention.md`. Read `${CLAUDE_PLUGIN_ROOT}/skills/end/pr-body-templates.md` and follow its **Feature PR body** section (the template plus the Summary-section requirements).

## Step 5b: Story-finalize PR body (only when MODE=story-finalize)

When the current branch is `story/issue-<N>-<slug>`, the PR body uses a different shape.

**Empty-story guard:** precompute reports sub-issues under `### Sub-issues` (from GitHub's native sub-issue link). If no sub-issues are listed, ABORT — do not open a PR with only `Closes #<story-N>`. Tell the user: "Empty story — no sub-features merged in. Either run /sillok-start --parent $N to add work, or close the story issue manually."

Otherwise, follow the **Story-finalize PR body** section of `${CLAUDE_PLUGIN_ROOT}/skills/end/pr-body-templates.md` (Closes-lines construction from the precompute sub-issue list, template, `--merge` recommendation, PR title).

## Step 6: Create the PR

```bash
gh pr create \
  --repo "$REPO" \
  --base "$PR_BASE" \
  --head <branch> \
  --title "<active issue title> (#<N>)" \
  --body "$PR_BODY"
```

Capture the PR URL from output.

## Step 7: Update project status

**Single-issue mode:**

```bash
source "${CLAUDE_PLUGIN_ROOT}/scripts/lib/project.sh"
ITEM_ID=$(sillok_project_item_for_issue "https://github.com/$REPO/issues/$N")
sillok_project_status_set "$ITEM_ID" review
```

**Umbrella mode:** update the **active sub-issue only**:

```bash
source "${CLAUDE_PLUGIN_ROOT}/scripts/lib/project.sh"
ITEM_ID=$(sillok_project_item_for_issue "https://github.com/$REPO/issues/$N")
sillok_project_status_set "$ITEM_ID" review
```

Do NOT update the umbrella's parent status. The parent will close via `Closes #<parent>` when the user merges; its status stays as-is.

## Step 8: Update active issue body

Fetch current body:

`gh issue view <N> --json body --jq '.body'`

Append `## PR link\n\n<PR URL>` in the conventional body-section position. Post back:

`gh issue edit <N> --body "<new-body>"`

## Step 9: Update parent legacy checkbox (if any)

If `Parent: #<M>` was found in step 1 AND the parent body contains a legacy task-list-syntax checkbox `- [ ] #<N>`:

- Fetch parent body: `gh issue view <M> --json body --jq '.body'`
- Replace `- [ ] #<N>` with `- [x] #<N>`.
- Post back: `gh issue edit <M> --body "<new-body>"`.

If no such line exists: do NOT add one. GitHub's native sub-issue panel renders the parent-child relationship from the GraphQL `addSubIssue` link automatically; manual checklists drift.

## Step 10: No auto-merge

Print PR URL. STOP. Do NOT run `gh pr merge`. The user reviews the PR (themselves or via reviewers) and merges manually via `gh pr merge --squash` or the GitHub UI.

## Step 11: Output

Print:

- PR URL: `<URL>`
- Project status on `#<N>`: `In QA`
- Issue body updated with PR link
- Parent checkbox updated (if legacy syntax present at `#<M>`)
- Handoff: "Done. Review the PR; merge when ready. The issue auto-closes on merge via `Closes #<N>` in the PR body."

## Handoff

Stage complete — invoke `sillok:workflow` to decide the next step.

## Integration

- `sillok:workflow` — orchestrator that routes between stages; invoke it at stage completion (after PR creation it never merges — the chain stops here)
- `superpowers:finishing-a-development-branch` — drives the merge/PR decision flow (step 4); sillok's answer is always "open a PR", never auto-merge
- `sillok:verify-gate` — must already have passed at end-of-plan in the execute stage before this stage runs
