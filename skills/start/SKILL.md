---
name: start
description: Internal sillok stage skill — enter via the /sillok-start command or a sillok:workflow handoff; for natural-language intent invoke sillok:workflow instead. Creates the GH issue (Issue Type + self-assign + project status Todo + linked branch) plus branch and worktree for a new work unit; optional --parent N (same-repo) or owner/repo#N (cross-repo PRD epic).
user-invocable: false
---

# Sillok Start

You are running the sillok `start` stage for the configured GitHub repository.

## Step 1: Parse args

Extract from the user's input:

- Optional positional `#N` or `N` (a bare issue number) — **adopt mode**: pick up existing issue `#N` instead of creating a new one. Mutually exclusive with `[prd-path]` and `--parent` (an adopted issue keeps its own parent relationship). See "Adopt mode" below.
- Optional positional `[prd-path]` — a markdown file path. Most starts have no PRD; that's expected.
- Optional flag `--parent <value>` — issue reference. Three forms accepted:
  - `--parent 42` — same-repo issue #42
  - `--parent myorg/prd#42` — cross-repo issue
  - `--parent https://github.com/myorg/prd/issues/42` — URL form, parsed to `myorg/prd#42`

Parse `--parent` into `parent_owner`, `parent_repo`, `parent_n`. If only a number is given, `parent_owner` = current repo owner and `parent_repo` = current repo name.

## Step 2: State derivation

Run the precompute script to derive current branch, open epics (for parent suggestion in step 4), and the current sprint milestone (for step 5) in one shot:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/precompute-start.sh
```

In adopt mode, pass the issue number as the first argument:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/precompute-start.sh <N>
```

The output then contains a `### Adopt` section — see "Adopt mode" below.

Read the markdown block it prints. Show it back to the user as the current state summary.

If the output contains `ABORT:` (you're already on a branch matching the configured `branchPrefix`), surface that line as a hard stop with: "You're already on `<branch>` for issue #<N>. Finish or stash current work before starting a new feature." Do not proceed.

If the output contains `STORY-BRANCH:` instead, you're on a story integration branch — that's the sanctioned starting point for the story loop. Proceed, treating `--parent <N>` (the story issue) as the default parent for Step 4.

Umbrella branches (`feature/<name>`) are OK as starting points — `/sillok-start` from any umbrella branch is supported, and the new sub-issue's branch will still be cut from `origin/<baseBranch>` (configured), not from the umbrella.

## Adopt mode (`/sillok-start #N`)

When the precompute output contains a `### Adopt` section, you are adopting an existing issue. The existing ABORT/STORY-BRANCH branch guard still applies first (you cannot adopt while on another issue's branch).

Read the verdict line:

- `ADOPT-ABORT:` → hard stop. Surface the reason. If the reason is a Story/Epic type, point the user at `/sillok-story`. If a branch already exists, point at its worktree.
- `ADOPT-WARN:` → the issue's board status is already past the capture stage (anything other than Backlog / Todo / not-on-board — e.g. In Design, In Progress, In QA, Done). Ask the user: "Issue #<N> is already '<status>'. Set up the environment anyway? The board status will be kept." Proceed only on explicit confirmation. This gate is ALWAYS interactive — full-auto never auto-resolves it.
- `ADOPT-OK:` → proceed directly.

Then:

1. **Skip Steps 3, 4, 6, 7, and 8 entirely** — the issue already exists; no PRD intake, no parent prompt, no creation call. The `### Adopt` block's metadata (title, type, labels, milestone, assignees, parent) is ground truth.
2. **Backfill** (each only when missing):
   - No assignee → self-assign: `gh issue edit <N> --repo "$REPO" --add-assignee @me`
   - No milestone → attach the current sprint milestone from the `### Sprint milestone` section (create it first via the Step 5 flow if it doesn't exist): `gh issue edit <N> --repo "$REPO" --milestone "<computed>"`
3. **Branch type** comes precomputed: read the Adopt block's `Branch type:` line as ground truth (the script lowercases the issue type and defaults unknown to `feature` — don't re-derive it).
4. Continue with **Step 9 (slug + branch)** using the issue's title — the non-ASCII translation rule applies as usual — then Step 9b (the Adopt block's `Parent:` line feeds the integration-branch lookup), Step 10, 10b, and 10c.
5. **Step 10c status nuance:** after `ADOPT-OK`, set status `todo` as usual (this is the Backlog → Todo promotion). After a confirmed `ADOPT-WARN`, do NOT touch the status — skip the `sillok_project_status_set` call and keep the board as-is.
6. In the Step 11 output, mark the issue line as `(adopted #N)`.

## Language

Read the `### Language` section from the precompute output (step 2).

- `auto` → write all generated content (issue body, commit summary) in the same language as the current conversation session.
- `ko` → write all generated content in Korean.
- `en` → write all generated content in English.

Section headers (`## Summary`, `## Design`, `Parent:` etc.) and GitHub API field names stay in English regardless of language setting — only prose content follows the language preference.

### Full-auto mode

ONLY when this stage was entered via a `sillok:workflow` handoff that is running a confirmed full-auto chain (`automation.fullAuto: true` alone is NOT sufficient — direct `/sillok-start` invocation keeps every gate interactive), the four confirmation gates below are auto-resolved per the workflow contract — do not prompt:

- Step 4 epic-fit question → answer `standalone` unless `--parent` was given.
- Step 5 missing sprint milestone → create it without asking.
- Step 6 issue-settings confirm loop → accept the proposed title/type/labels.
- Step 9 branch-name confirm → accept the derived branch name.
- Step 3 feature-description prompt (no-PRD path) → do not prompt; the description comes from the user's original intent utterance as interpreted (and confirmed) at chain entry by `sillok:workflow`. Never invent work.

Record each auto-resolved choice in the created issue (the settings land in the issue body; non-obvious calls go under `## Key decisions` per the workflow's decide+record rule).

## Step 3: PRD intake

Read `${CLAUDE_PLUGIN_ROOT}/skills/start/issue-body-template.md` and follow it to propose the issue title, body draft, and type label suggestion. It covers both intake branches (`[prd-path]` provided / no PRD path).

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
- Priority: `p3` (default)
- Parent: `#<M>` if any, else "standalone"
- Milestone: `<computed>` if captured, else "none"

Ask: "Create issue with these settings? (yes / edit). On `edit`, prompt for which field to change." Loop until confirmed.

## Step 7: Create the issue

Resolve type label (`<type>`) to Issue Type name via config:
- `feature` → use `types.defaults.feature` (default `Feature`)
- `bug` → use `Bug` (literal)
- `task` → use `Task` (literal)

Read orgMode from config (`sillok_config orgMode`). Branch the REST call:

**Org mode (`orgMode=true`):**

```bash
issue_url=$(gh api -X POST \
  -H "X-GitHub-Api-Version: 2026-03-10" \
  "/repos/$REPO/issues" \
  -f title="<title>" \
  -f body="<body>" \
  -f type="<Issue-Type-name>" \
  -f "assignees[]=$(gh api user --jq .login)" \
  -f "labels[]=<priority>" \
  -f "labels[]=<area-if-any>" \
  --jq '.html_url')
```

**User mode (`orgMode=false`):**

```bash
issue_url=$(gh api -X POST \
  -H "X-GitHub-Api-Version: 2026-03-10" \
  "/repos/$REPO/issues" \
  -f title="<title>" \
  -f body="<body>" \
  -f "assignees[]=$(gh api user --jq .login)" \
  -f "labels[]=<priority>" \
  -f "labels[]=<type-lowercased>" \
  -f "labels[]=<area-if-any>" \
  --jq '.html_url')
```

(Difference: org mode has `-f type=X`, user mode has `-f labels[]=x` instead.)

Capture `<N>` by parsing the URL's last segment.

## Step 8: Link as sub-issue if parent

If a parent was selected:

```bash
PARENT_ID=$(gh api graphql -f query="{ repository(owner: \"$parent_owner\", name: \"$parent_repo\") { issue(number: $parent_n) { id } } }" --jq '.data.repository.issue.id')
CHILD_ID=$(gh api graphql -f query="{ repository(owner: \"${REPO%%/*}\", name: \"${REPO##*/}\") { issue(number: $N) { id } } }" --jq '.data.repository.issue.id')
gh api graphql -f query="mutation { addSubIssue(input: { issueId: \"$PARENT_ID\", subIssueId: \"$CHILD_ID\" }) { issue { number } } }" >/dev/null
```

**Skip the epic-label verification step** when `parent_owner/parent_repo` differs from current repo — cross-repo parent labels are user-controlled and sillok cannot enforce them.

## Step 9: Compute slug and branch

Branch and worktree names are kept **ASCII/English regardless of the issue language** — the issue title/body may be Korean (or any language), but the branch stays English for clean URLs and broad tool compatibility.

**If the confirmed title is not already English** (contains Hangul/CJK/other non-ASCII letters), first translate it into a concise English phrase (3–6 words capturing the feature), then pass that English phrase — NOT the original title — to the slug script. The issue keeps its original-language title; only the slug argument is the English rendering.

```bash
# <slug-title> = the English phrase. For an already-English title, it IS the title.
# e.g. "녹음 버튼에 햅틱 피드백 추가" → "add haptic feedback to record button"
bash ${CLAUDE_PLUGIN_ROOT}/scripts/slug-from-title.sh <N> "<slug-title>"
```

The script outputs `<N>-<title-slug>` (e.g. `79-add-haptic-feedback-to-record-button`). The title-slug is lowercased, has articles (`a`/`an`/`the`) and non-alphanumeric runs collapsed to hyphens, and is truncated to ≤40 chars at the last hyphen. If the slug reduces to empty, the script falls back to `issue-<N>`. Capture the output as `<slug>`.

**Resolve the templated branch prefix** before constructing the final branch name:

```bash
source "${CLAUDE_PLUGIN_ROOT}/scripts/lib/config.sh"
# <type> is the confirmed type label from step 6 (e.g. "feature", "bug").
user_token=$(git config user.name | awk '{print tolower($1)}' | tr -cd '[:alnum:]')
RESOLVED_PREFIX=$(sillok_branch_prefix_resolve "<type>" "$user_token")
```

- **Branch:** `${RESOLVED_PREFIX}<slug>` — e.g. `feature/issue-42-add-volume-cap`, `bug/issue-67-fix-pause-timer`

Print the branch for user confirmation: "Branch will be `<branch>`. OK? (yes / change)". On `change`, prompt for replacement title-slug — re-run the script with the new title or accept a hand-typed slug.

## Step 9b: Determine base branch (parent integration awareness)

If parent is same-repo, check for integration branch as before. If cross-repo, always fall back to configured `baseBranch` (cross-repo PRD epics don't have integration branches).

```bash
if [[ -n "$parent_n" ]]; then
  if [[ "$parent_owner/$parent_repo" == "$REPO" ]]; then
    # Same repo: check for integration branch in parent body
    parent_body=$(gh issue view "$parent_n" --repo "$REPO" --json body --jq '.body')
    integration_branch=$(echo "$parent_body" \
      | awk '/^## Integration branch/{flag=1; next} /^## /{flag=0} flag && /^`/{gsub("`",""); print; exit}')
    if [[ -n "$integration_branch" ]]; then
      BASE_BRANCH="$integration_branch"
    else
      BASE_BRANCH=$(sillok_config baseBranch)
    fi
  else
    # Cross-repo: no integration branch concept
    BASE_BRANCH=$(sillok_config baseBranch)
  fi
else
  BASE_BRANCH=$(sillok_config baseBranch)
fi
```

## Step 10: Create worktree (always; no opt-out)

Run the worktree setup script from the project root:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/setup-feature-worktree.sh <slug> <branch> "$BASE_BRANCH"
```

The script:
1. Fetches `origin/$BASE_BRANCH` (resolved in step 9b — either the parent's integration branch or the configured base branch).
2. Creates `<worktreeDir>/<slug>` on `<branch>` based on `origin/$BASE_BRANCH`.
3. Copies the gitignored config files listed in `worktree.copyFiles` (configured).
4. Runs the configured `install` command inside the worktree (if set).

The `-b <branch> origin/main` form inside the script creates a new branch named `<branch>` based on the current `origin/main` HEAD, avoiding the bug where the worktree inherits commits from the calling branch.

Note: `git worktree` does NOT auto-symlink dependency directories (`node_modules`, `vendor`, etc.) — the `install` command run inside the script gets a fresh install for the new worktree.

## Step 10b: Link branch to issue (Development panel), THEN push

Order matters: `createLinkedBranch` is **create-only** — when the named branch already exists on the remote, the mutation silently returns `{linkedBranch: null}` (exit 0, no error) and the issue never gets the link. So the link MUST run before the branch exists on the remote, i.e. before the first push. Under `orgMode=false` the helper no-ops and the push creates the remote branch as before; under org mode the mutation itself creates the remote ref, so the subsequent push is a content no-op that just sets the upstream.

```bash
worktree_path=".worktrees/<slug>"

# Resolve SHA of new branch tip
BRANCH_SHA=$(cd "$worktree_path" && git rev-parse HEAD)

# Look up GraphQL node IDs and create the linked branch FIRST (create-only mutation)
source "${CLAUDE_PLUGIN_ROOT}/scripts/lib/dev-link.sh"
ISSUE_NODE_ID=$(sillok_issue_node_id "$REPO" "$N")
sillok_link_branch "$ISSUE_NODE_ID" "<branch>" "$BRANCH_SHA"

# THEN push — sets upstream; creates the remote branch when orgMode=false
(cd "$worktree_path" && git push -u origin "<branch>")
```

## Step 10c: Add to project + set status Todo

Idempotent — works whether the auto-add workflow has already fired or not.

```bash
source "${CLAUDE_PLUGIN_ROOT}/scripts/lib/project.sh"
ITEM_ID=$(sillok_project_item_add "$issue_url")
sillok_project_status_set "$ITEM_ID" todo
```

## Step 11: Output

Print:

- Issue URL: `<issue_url>`
- Branch: `<branch>`
- Worktree: `.worktrees/<slug>` — the next stage runs from there
- Project item: `<ITEM_ID>`
- Status: `Todo`
- Linked branch: ✓

## Handoff

Stage complete — cd into the printed worktree (`.worktrees/<slug>`), then invoke `sillok:workflow` to decide the next step.

## Integration

- **`sillok:workflow`** — stage orchestrator; decides what comes after this stage.
- **`sillok:design`** — next stage: brainstorm and write the spec for the issue created here.
- **`sillok:gh-issue-management`** — canonical issue title/body conventions and management flows (referenced by the issue proposal in Step 3).
