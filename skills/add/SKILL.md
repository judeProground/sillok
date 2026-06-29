---
name: add
description: Internal sillok stage skill — enter via the /sillok-add command; for natural-language intent invoke sillok:workflow instead. Captures a backlog issue (Issue Type + self-assign + project status Backlog) with NO branch, worktree, or milestone; pick it up later with /sillok-start <N>.
user-invocable: false
---

# Sillok Add

You are running the sillok `add` stage: lightweight backlog capture for the configured GitHub repository. This command creates an issue and parks it in Backlog — no branch, no worktree, no milestone. The work environment comes later, when the issue is adopted via `/sillok-start <N>`.

`add` sits OUTSIDE the workflow chain (like `init`): `sillok:workflow` never routes to it, and it never hands off to a next stage. It is safe to run from ANY branch, including mid-feature — capturing a discovery must not disturb the current work.

## Step 1: Parse args

The user's input is the idea description — free-form, one line or several. Optional `--parent <N>` (same-repo) or `--parent owner/repo#N` (cross-repo) links the new issue under an epic/story.

If no description was given, prompt: "Describe the idea in 1–2 sentences. I'll draft the backlog issue from there."

## Step 2: State derivation

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/precompute-add.sh
```

Read the markdown block (open epics for the parent suggestion, language preference). There is deliberately no branch guard and no sprint-milestone section.

## Language

Same contract as `sillok:start`: `auto` → conversation language, `ko` → Korean, `en` → English. Section headers and GitHub field names stay English.

## Step 3: Propose issue settings

From the description, propose in one block:

- Title (verb-form imperative, per `sillok:gh-issue-management` flow 1)
- Type: `feature` (default) / `bug` / `task`
- Priority: `p3` default
- Area labels if obvious from the description
- Parent: suggest from the Open epics list, or standalone

Ask once: "Create backlog issue with these settings? (yes / edit)". Loop on `edit` until confirmed. Under a confirmed full-auto chain, auto-accept the proposal.

## Step 4: Create the issue

Compose the body per `${CLAUDE_PLUGIN_ROOT}/skills/start/issue-body-template.md` (no-PRD branch). Resolve type and orgMode exactly as `sillok:start` Step 7, with TWO differences: self-assign stays, but NO milestone is attached (backlog items are not sprint-committed — the milestone is backfilled at adopt time).

Create the issue via the shared helper (same as `sillok:start` Step 7) — NO milestone:

```bash
issue_url=$(bash ${CLAUDE_PLUGIN_ROOT}/scripts/create-issue.sh \
  --repo "$REPO" \
  --title "<title>" \
  --type-name "<Issue-Type-name>" --type-label "<type-lowercased>" \
  --priority "<priority>" \
  --label "area:<name>" \
  --body-file - <<'BODY'
<body>
BODY
)
```

The script reads `orgMode` from config: org mode sets `-f type=` and no priority label (priority lands on the board's Priority field in Step 6); user mode applies the `<type-lowercased>` + `<priority>` labels. The block includes an `--label area:<name>` slot — replace `<name>` with the matching `area:*` label (see `labels.areas` in config), or delete that line when no area applies.

Capture `<N>` from the URL's last segment.

## Step 5: Link as sub-issue if parent

Same GraphQL `addSubIssue` mutation as `sillok:start` Step 8 (skip label verification for cross-repo parents).

## Step 6: Board — add + status Backlog + priority (fail-soft)

```bash
source "${CLAUDE_PLUGIN_ROOT}/scripts/lib/project.sh"
ITEM_ID=$(sillok_project_item_add "$issue_url") || ITEM_ID=""
if [[ -n "$ITEM_ID" ]]; then
  sillok_project_status_set "$ITEM_ID" backlog \
    || echo "[sillok] could not set Backlog status — the issue is created and on the board; add a 'Backlog' option to the board's Status field to enable backlog parking"

  # Org mode only: priority lives on the org-level Priority *issue field* (set
  # on the issue itself, then projected onto the board — no p-label was applied
  # in Step 4). <priority-key> = the confirmed priority from Step 3 (default:
  # p3). User mode skips this — the p-label from Step 4 is the priority record
  # there.
  if [[ "$(sillok_config orgMode)" == "true" ]]; then
    sillok_issue_priority_set "$issue_url" "<priority-key>" \
      || echo "[sillok] priority not set — re-run /sillok-init to create the org Priority issue field" >&2
  fi
fi
```

Status and priority failures are NON-FATAL: the issue exists either way — surface the warning and continue (a board whose org never had a Priority issue field provisioned has nothing to set until `/sillok-init` is re-run, which creates it). Never roll back issue creation over a board error. Recording priority here matters because adopt mode (`/sillok-start <N>`) KEEPs whatever priority the issue already has — backlog capture is the only point where it gets set.

## Step 7: Output

- Issue URL
- Status: `Backlog` (or the fail-soft warning)
- Reminder: "Pick it up later with `/sillok-start <N>` — that's when the branch, worktree, milestone, and Todo status arrive."

No handoff. Do NOT invoke `sillok:workflow` — capture is not a stage transition; the user returns to whatever they were doing.

## Integration

- `sillok:start` — adopt mode (`/sillok-start <N>`) is the promotion path out of the backlog created here.
- `sillok:gh-issue-management` — title/body conventions and the triage/mid-session-discovery flows.
