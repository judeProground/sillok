---
description: Bootstrap a new feature — create GH issue (PRD optional), branch, worktree with env files copied. Optional --parent N flag links as sub-issue of an existing epic. Auto-suggests open epics if no parent specified.
---

You are running the `/sillok-start` slash command for the the configured GitHub repository.

## Step 1: Parse args

Extract from the user's input:

- Optional positional `[prd-path]` — a markdown file path. Most starts have no PRD; that's expected.
- Optional flag `--parent N` — issue number to link as parent (must be an `epic`).

## Step 2: State derivation

Run the precompute script to derive current branch, open epics (for parent suggestion in step 4), and the current sprint milestone (for step 5) in one shot:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/precompute-start.sh
```

Read the markdown block it prints. Show it back to the user as the current state summary.

If the output contains `ABORT:` (you're already on a branch matching the configured `branchPrefix`), surface that line as a hard stop with: "You're already on `<branch>` for issue #<N>. Finish or stash current work before starting a new feature." Do not proceed.

Umbrella branches (`feature/<name>`) are OK as starting points — `/sillok-start` from any umbrella branch is supported, and the new sub-issue's branch will still be cut from `origin/<baseBranch>` (configured), not from the umbrella.

## Step 3: PRD intake

**If `[prd-path]` provided:**

- Read the file with the Read tool.
- From the PRD content, propose:
  - Issue title (verb-form imperative; rewrite noun-phrases per `sillok:gh-issue-management` skill flow 1)
  - Issue body draft (Summary + scope from PRD)
  - Type label suggestion: default `feature`; `bug` if PRD says "fix"/"broken"; `infra` if tooling/CI keywords; `improvement` if "enhance"/"optimize" keywords

**If no PRD path:**

- Prompt user: "Describe the feature in 1–2 sentences. I'll draft the issue from there."
- Use the response to propose title + body + type.

## Step 4: Auto-suggest parent

Read the **Open epics** section from the precompute output (step 2). Display the list to the user.

Ask: "Does this fit under any of these epics? Reply with the issue number, or `standalone`."

If the precompute reported `(none — standalone unless --parent specified)`, default to standalone unless `--parent N` was provided in step 1.

If `--parent N` was provided in step 1, skip the prompt and use that.

## Step 5: Sprint milestone

Read the **Sprint milestone** section from the precompute output (step 2). It already shows the computed name (`YYYY-MM-Wn`) and whether the milestone exists in the repo.

If `Exists in repo: yes (number <M>)` — capture `<M>` for issue creation.

If `Exists in repo: no` — ask user: "Sprint milestone `<computed>` doesn't exist yet. Create it now? (y/N)". On yes, run:

```bash
gh api -X POST /repos/${REPO}/milestones -f title="<computed>" --jq '.number'
```

Capture the returned number for issue creation.

## Step 6: Confirm with user

Print:

- Title: `<title>`
- Type label: `<type>` (default `feature`)
- Stage label: `todo`
- Priority: `p3` (default)
- Parent: `#<M>` if any, else "standalone"
- Milestone: `<computed>` if captured, else "none"

Ask: "Create issue with these settings? (yes / edit). On `edit`, prompt for which field to change." Loop until confirmed.

## Step 7: Create the issue

Run:

`gh issue create --title "<title>" --label <type> --label todo --label p3 --milestone "<milestone>" --body "<body>"` (omit `--milestone` if no milestone captured)

Capture the new issue number `<N>` from the URL output (e.g., `https://github.com/${REPO}/issues/123` → `<N>=123`).

## Step 8: Link as sub-issue if parent

If a parent was selected in step 4 (or via `--parent`), use the GraphQL `addSubIssue` mutation per the `sillok:gh-issue-management` skill's Sub-issue linking section:

`PARENT_ID=$(gh api graphql -f query='query { repository(owner:"${OWNER}", name:"${NAME}") { issue(number:<M>) { id } } }' --jq '.data.repository.issue.id')`
`CHILD_ID=$(gh api graphql -f query='query { repository(owner:"${OWNER}", name:"${NAME}") { issue(number:<N>) { id } } }' --jq '.data.repository.issue.id')`
`gh api graphql -f query="mutation { addSubIssue(input: { issueId: \"$PARENT_ID\", subIssueId: \"$CHILD_ID\" }) { issue { number } subIssue { number } } }"`

Verify the parent has the `epic` label:

`gh issue view <M> --json labels --jq '.labels[].name'`

If `epic` is missing, surface: "Parent #<M> is missing the `epic` label. Per Type vs Structure rules in `gh-issue-conventions.md`, parents must be `epic`. Add it? (recommended; y/N)". On yes, `gh issue edit <M> --add-label epic`.

## Step 9: Compute slug and branch

Run the slug script with the new issue number and the confirmed title:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/slug-from-title.sh <N> "<title>"
```

The script outputs `<N>-<title-slug>` (e.g. `79-add-haptic-feedback-to-record-button`). The title-slug is lowercased, has articles (`a`/`an`/`the`) and non-alphanumeric runs collapsed to hyphens, and is truncated to ≤40 chars at the last hyphen. Capture the output as `<slug>`.

- **Branch:** `${BRANCH_PREFIX}<slug>`  (because `<slug>` already starts with the issue number, this resolves to `${BRANCH_PREFIX}<N>-<title-slug>` per the rule in `gh-issue-conventions.md`)

Print the branch for user confirmation: "Branch will be `<branch>`. OK? (yes / change)". On `change`, prompt for replacement title-slug — re-run the script with the new title or accept a hand-typed slug.

## Step 10: Create worktree (always; no opt-out)

Run the worktree setup script from the project root:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/setup-feature-worktree.sh <slug> <branch>
```

The script:
1. Fetches `origin/<baseBranch>` (configured).
2. Creates `<worktreeDir>/<slug>` on `<branch>` based on `origin/<baseBranch>` (NOT on the calling branch — even if invoked from an umbrella branch, the new feature branch starts fresh from base).
3. Copies the gitignored config files listed in `worktree.copyFiles` (configured).
4. Runs the configured `install` command inside the worktree (if set).

The `-b <branch> origin/main` form inside the script creates a new branch named `<branch>` based on the current `origin/main` HEAD, avoiding the bug where the worktree inherits commits from the calling branch.

Note: `git worktree` does NOT auto-symlink dependency directories (`node_modules`, `vendor`, etc.) — the `install` command run inside the script gets a fresh install for the new worktree.

## Step 11: Output

Print:

- Issue URL: `https://github.com/${REPO}/issues/<N>`
- Branch: `<branch>`
- Worktree path: `.worktrees/<slug>`
- Handoff: "Next: `cd .worktrees/<slug>` then run `/sillok-design` to write the spec."
