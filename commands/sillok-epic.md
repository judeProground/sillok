---
description: Bootstrap a new epic — parent tracking issue spanning ≥3 sub-issues. Creates the issue with `epic` label and the epic body shape. Does NOT create a branch/worktree (epics are meta; sub-issues get their own via /sillok-start --parent N).
---

You are running the `/sillok-epic` slash command for the sillok (`${REPO}`).

Epic = parent tracking issue. Per `gh-issue-conventions.md` Type vs Structure rules: only `epic` may be a parent, and an epic must have sub-issues (a childless epic is a labeling mistake). Body shape differs from `feature` — see "Epic template" in `gh-issue-conventions.md`.

## Step 1: Parse args

Extract from the user's input:

- Optional positional `[prd-path]` — markdown PRD describing the umbrella scope.
- Optional flag `--priority pN` — defaults to `p3`.

## Step 2: State derivation

Reuse the workflow-start precompute for branch + sprint milestone (open epics list is irrelevant here — we're creating one):

```bash
bash .claude/scripts/precompute-workflow-start.sh
```

Read the output. The `Sprint milestone` section gives `<computed>` and existence. Branch state is informational only — epics don't require any particular branch context.

## Step 3: Topic intake

**If `[prd-path]` provided:**

- Read the file with the Read tool.
- Propose epic title (verb-form imperative or short noun-phrase like `Auth provider rollout` is OK for tracking issues — looser than work-unit titles since the epic itself isn't a single action).
- Draft a 1-line summary, plus Architecture / Context / Non-goals bullets from the PRD.

**If no PRD:**

- Prompt user: "Describe the epic in 2–3 sentences. What's the umbrella, what's it tracking, why now?"
- Use the response to draft the same fields.

## Step 4: Sub-issue list (recommended, optional)

Prompt: "List the planned sub-issue titles, one per line. Blank line / 'skip' to leave the list empty for now."

If user provides titles, render them as a checkbox stub WITHOUT issue numbers (issue numbers get filled in later when each sub-issue is created via `/sillok-start --parent <N>`):

```markdown
## Sub-issues

- [ ] (TBD) · <title 1>
- [ ] (TBD) · <title 2>
- [ ] (TBD) · <title 3>
```

When a sub-issue is later created with `--parent <N>`, the workflow does NOT auto-edit this list — GitHub renders the native sub-issue links separately. The checkbox list stays as the human-readable plan; update or delete it manually if it diverges (or just leave it, since GH's native panel is the source of truth).

## Step 5: Sprint milestone

Same as `/sillok-start` step 5 — read precompute output, capture milestone number if exists, otherwise prompt to create.

## Step 6: Confirm with user

Print:

- Title: `<title>`
- Type label: `epic` (forced — epics carry no work-type label like `feature`/`bug`)
- Stage label: **none** (epics are meta — they don't transition through `todo`/`designed`/`in-progress`/`in-review`. Closure is implicit when sub-issues are done.)
- Priority: `<priority>` (default `p3`)
- Milestone: `<computed>` if captured, else "none"
- Body preview: render the epic template (per `gh-issue-conventions.md` "Epic template" section) populated with title, summary, Architecture (if any), Sub-issues stub, Context, Non-goals.

Ask: "Create epic with these settings? (yes / edit). On `edit`, prompt for which field to change." Loop until confirmed.

## Step 7: Create the issue

```bash
gh issue create \
  --title "<title>" \
  --label epic \
  --label <priority> \
  --milestone "<milestone>" \
  --body "<body>"
```

(omit `--milestone` if no milestone captured)

Capture the new issue number `<N>` from the URL output.

## Step 8: Output

Print:

- Issue URL: `https://github.com/${REPO}/issues/<N>`
- Handoff:
  - "Next: `/sillok-start --parent <N>` for each sub-issue."
  - "If the epic needs its own umbrella branch (rare — only when sub-issues land on the umbrella before merging to main, like the harness rollout), create it manually: `git switch -c feature/<short-slug> origin/main && git push -u origin feature/<short-slug>`. Most epics don't need this."

## What this command does NOT do

- Does not create a branch or worktree (epics don't carry code).
- Does not invoke design/execute/end (those run per sub-issue).
- Does not auto-link sub-issues — that happens at `/sillok-start --parent <N>` time via the GraphQL `addSubIssue` mutation.
- Does not flip stage labels (epics don't have stages).
