---
description: Push branch, create PR per pr-convention, flip stage label in-progress → in-review on the active sub-issue, update parent legacy checkbox if any. Does NOT auto-merge. Done note embedded in PR body Summary section.
---

You are running the `/sillok-end` slash command for the the configured GitHub repository.

## Step 1: Mode detection + state derivation

Run the precompute script. It outputs branch + mode + active issue meta + stage + plan path + plan task completion stats + existing PR + parent reference + dirty working tree + CWD check in one shot:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/precompute-end.sh
```

Read the markdown block. Show it back to the user as the current state summary.

**CWD mismatch handling:** if `⚠️  CWD MISMATCH` and `EXEC FIRST: cd ...`, run that `cd` BEFORE proceeding (same reason as `/sillok-design` step 1).

**Mode-specific handling:**

- **Single-issue mode**: precompute resolved `<N>`, `<slug>`, parent `<M>` (or none), plan path, task stats, existing PR.
- **Umbrella mode**: prompt user "Which sub-issue are you closing with this PR? Reply with the issue number." Active issue = that sub-issue. ALSO:
  - List other still-open sub-issues of the umbrella's parent epic: `gh issue list --repo "$REPO" --state open --search "in:body Parent: #<parent>"`. Add a `Closes #N` line per sub-issue in the PR body.
  - Include `Closes #<parent>` IF this PR is the LAST sub-issue going `in-review` (epic-completing).
- **Other branch**: ABORT.

## Step 2: Pre-conditions

All checks below were already performed by precompute (step 1). Apply the results:

1. **Stage label.** Must be `in-progress`. If `in-review` (PR likely exists, see check #5), redirect to update-only flow. Anything else → ABORT.
2. **Plan exists.** Required. precompute reported the path or `⚠️  No plan found` (ABORT in that case).
3. **Plan task completion.** precompute reported `X done / Y open`. If `Y > 0`: prompt "Plan has `<Y>` open task(s). Continue with PR? (y/N)". User can override (e.g., punting last cleanup task to a follow-up issue).
4. **Working tree.** precompute listed dirty files (if any). If dirty: prompt "Working tree has uncommitted changes (see above). Commit first / stash / abort? (commit / stash / abort)". Do NOT auto-stash silently — the user must see and decide.
5. **Existing PR.** precompute reported PR URL + state if any. If found: prompt "PR `<URL>` already exists. (a) Update body/labels only, (b) Skip and exit. Choice?".

## Step 3: Push branch

`git push origin <branch>`

If push fails (e.g., branch out of date with remote): inspect error, prompt for rebase (`git pull --rebase origin <branch>` then retry) or abort.

## Step 4: Invoke finishing-a-development-branch

Use the `superpowers:finishing-a-development-branch` skill for the merge/PR decision flow. The skill offers options. **For sillok, the answer is always "open a PR"** — auto-respond accordingly. Do not auto-merge.

## Step 5: Compute PR body

> `<SPEC_DIR>` and `<PLAN_DIR>` below resolve to the values of `docs.specs` and `docs.plans` in `.claude/sillok/workflow.config.json` (defaults `docs/superpowers/specs` and `docs/superpowers/plans`).

Construct the PR body per `pr-convention.md`. Use a heredoc:

```bash
PR_BODY=$(cat <<EOF
Closes #<N>
[Single-issue mode: only the line above]
[Umbrella mode: also one Closes line per still-open sub-issue, plus Closes #<parent> if epic-completing]

## Summary

<2-3 lines describing the work. THIS BECOMES THE SQUASH COMMIT MESSAGE WHEN MERGED, AND ALSO SERVES AS THE DONE-NOTE FOR THE CLOSED ISSUE. No separate post-merge comment needed.>

## Design

<SPEC_DIR>/<date>-<slug>.md

## Plan

<PLAN_DIR>/<date>-<slug>.md

## Test plan

- [ ] <manual test items derived from the spec's acceptance criteria>
EOF
)
```

The Summary section is critical:

- It is shown verbatim on the issue (auto-closed via Closes #N) — fulfilling the `Done note` requirement of `gh-issue-conventions.md`.
- It is the squash commit message when the user merges with `gh pr merge --squash` — making the project's `main` log readable.

Write 2–3 substantive sentences here, not a 1-line summary.

## Step 6: Create the PR

```bash
gh pr create \
  --base main \
  --head <branch> \
  --title "<active issue title> (#<N>)" \
  --body "$PR_BODY"
```

Capture the PR URL from output.

## Step 7: Flip stage label

**Single-issue mode:**

`gh issue edit <N> --remove-label in-progress --add-label in-review`

**Umbrella mode:** flip the **active sub-issue only**:

`gh issue edit <N> --remove-label in-progress --add-label in-review`

Do NOT flip the umbrella's parent label. The parent will close via `Closes #<parent>` when the user merges; its labels stay as-is.

Do NOT pre-create labels (`gh label create in-review` etc.). The standard label set is bootstrapped at repo setup. If the `gh issue edit --add-label` call fails because a label is missing, surface the gap to the user — don't silently create.

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
- Stage label flipped on `#<N>`: `in-progress → in-review`
- Issue body updated with PR link
- Parent checkbox updated (if legacy syntax present at `#<M>`)
- Handoff: "Done. Review the PR; merge when ready. The issue auto-closes on merge via `Closes #<N>` in the PR body."
