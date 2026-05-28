---
description: Brainstorm and write the spec for the current issue. Saves spec to <SPEC_DIR>/, pastes the full spec content into the issue body, sets project status to In Design AFTER user reviews and confirms the spec content.
---

You are running the `/sillok-design` slash command for the sillok (`${REPO}`).

## Step 1: State derivation + mode detection

Run the precompute script to derive branch + mode + issue metadata + spec existence + CWD check in one shot:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/precompute-design.sh
```

Read the markdown block. Show it back to the user as the current state summary.

**CWD mismatch handling:** if the output contains `⚠️  CWD MISMATCH` and an `EXEC FIRST: cd ...` line, run that `cd` command BEFORE proceeding to step 2. Session resume (e.g., after `/rename`) silently resets cwd to the main repo, which makes file-relative operations (`<SPEC_DIR>/...`, `git add ...`) fail later with confusing errors. Don't skip this.

**Mode-specific handling:**

- **Single-issue mode**: precompute resolved `<N>`, `<slug>`, title, project status, and spec existence.
  - **Story check:** if the resolved issue is a `Story` (org repo: Issue Type is `Story`; user repo: carries the `story` label — both surface in precompute's Labels line, or check `gh api -H "X-GitHub-Api-Version: 2026-03-10" "/repos/$REPO/issues/$N" --jq '.type.name'`), this is a **story branch**. Prompt:

    ```
    Story #<N> detected. What would you like to design?

    (a) Design the story itself — brainstorm architecture, sub-issue breakdown, key decisions
    (b) Design a sub-issue — pick from open sub-issues below

    [list open sub-issues via gh api graphql subIssues, or "none yet"]
    ```

    - **(a)** → **Story-design mode** (see Step 4 story branch + Step 8 story branch). No spec file is created.
    - **(b)** → fetch the chosen sub-issue's metadata, derive its slug (`bash ${CLAUDE_PLUGIN_ROOT}/scripts/slug-from-title.sh <sub-N> "<sub-title>"`), and proceed as ordinary single-issue mode against that sub-issue.

  - Otherwise (Feature / Task / Bug): continue to step 2 as ordinary single-issue mode.
- **Umbrella mode** (`feature/<name>` branch, no resolvable `<N>`): fetch active sub-issues and prompt:
  - Map umbrella to its parent by asking the user: "Which parent does `<branch>` correspond to? Reply with the issue number."
  - `gh issue list --repo "$REPO" --state open --search "in:body Parent: #<parent>"` — list open sub-issues.
  - Prompt: "Which sub-issue are you designing? Reply with the issue number."
  - Re-run precompute conceptually for that `<N>` (or just fetch issue metadata directly), and derive slug = title-slug from `/sillok-start` step 9 (run `bash ${CLAUDE_PLUGIN_ROOT}/scripts/slug-from-title.sh <N> "<title>"`).
- **Other branch**: ABORT — workflow not applicable.

## Language

Read the `### Language` section from the precompute output (step 1).

- `auto` → write all generated content (spec, issue body) in the same language as the current conversation session.
- `ko` → write all generated content in Korean.
- `en` → write all generated content in English.

Section headers (`## Summary`, `## Design`, `Parent:` etc.) and GitHub API field names stay in English regardless of language setting — only prose content follows the language preference.

## Step 2: Pre-condition

Project status was extracted by precompute (step 1, `### Project status` section). Apply:

- `Todo` → proceed.
- `In Design` (continuing prior partial design work) → unusual but allowed; confirm intent with user.
- `In Progress` / `In QA` / `Done` → ABORT with "Issue is past design stage. Run `/sillok-execute` if In Progress, or fix the project status manually."

Spec existence was verified in step 1 — abort already handled there.

## Step 3: Spec path + pre-existing check

**Story-design mode skips this step** — stories do not get a spec file (the brainstorming output goes straight into the story body's `## Architecture` section). Jump to Step 4.

> `<SPEC_DIR>` below resolves to the value of `docs.specs` in `.claude/sillok/workflow.config.json` (default `docs/superpowers/specs`).

Spec existence was checked by precompute (step 1). Apply:

- **None found** → spec path is `<SPEC_DIR>/$(date +%Y-%m-%d)-<slug>.md` (date is today).
- **Found at `<found-path>`** → prompt user: "(a) continue editing, (b) overwrite, (c) cancel". Act per choice. If `continue`, use `<found-path>` as the spec path (don't re-date).

Do NOT pre-create labels — the standard label set is bootstrapped at repo setup. If a label is genuinely missing, surface the gap to the user; don't silently create.

## Step 4: Invoke brainstorming

**Story-design mode:** seed `superpowers:brainstorming` differently — the goal is architecture and decomposition, not a code-level spec:

- Story title + full body (Integration branch, Context, Non-goals)
- Cross-repo PRD body (if `prdRepo` configured)
- Framing: "This is a Story (composite tracking issue). Brainstorm the architecture (tech choices, data flow, component boundaries) and the sub-issue breakdown. No code-level spec — the output goes into the story body's Architecture and Sub-issues sections."

The brainstorming output is stored as `$architecture_content` (Architecture prose) and `$sub_issues_plan` (the planned breakdown) for Step 8. Then continue to Step 6 (review), Step 7 (status), Step 7.5 (key decisions). Skip the spec-file write in Step 5.

**Ordinary single-issue / sub-issue mode:** If precompute reported a cross-repo parent (`parent_repo != REPO`), fetch the PRD body:

```bash
PRD_BODY=$(gh issue view "$parent_n" --repo "$parent_repo" --json body --jq '.body')
```

Use the `superpowers:brainstorming` skill. Seed it with:

- Issue title: `<title>`
- Issue body: full body fetched in step 1
- **Cross-repo PRD body (if any):** `$PRD_BODY`
- Current state: project status, parent, slug

The brainstorming skill drives the discussion. Follow its instructions.

## Step 5: Save spec

When brainstorming concludes (the skill produces a coherent spec draft), write the result to the spec path computed in step 3.

**Story-design mode skips this step** — no spec file. The brainstorming output lives only in the story body (Step 8 story branch).

## Step 6: Review loop

Print: "Spec written to `<path>`. Review and tell me corrections, or say `looks good` / `lock` / `ship` to confirm."

Iterate:

- Apply user's corrections to the spec file (Edit tool, surgical).
- Re-print path after each correction round.
- Continue until user explicitly confirms.

The project status update in step 7 ONLY happens after explicit confirmation. Confirmation is required because the spec may still be wrong; the status change marks "I've seen and accepted this".

## Step 7: Set project status to In Design

After explicit user confirmation in step 6:

```bash
source "${CLAUDE_PLUGIN_ROOT}/scripts/lib/project.sh"
ITEM_ID=$(sillok_project_item_for_issue "https://github.com/$REPO/issues/$N")
if [[ -z "$ITEM_ID" ]]; then
  # Edge case: auto-add didn't fire and start didn't add. Recover.
  ITEM_ID=$(sillok_project_item_add "https://github.com/$REPO/issues/$N")
fi
sillok_project_status_set "$ITEM_ID" design
```

Stage is managed via the project's Status field — no label flipping.

## Step 7.5: Extract key decisions

After the spec is confirmed (step 6) and project status is set (step 7), extract key decisions from the brainstorming conversation and the spec content before updating the issue body.

A "key decision" is a choice where:
- 2+ viable options existed
- One was picked
- A future reader would ask "why not the other way?"

If no such choices exist (simple bug fix, mechanical change), produce an empty list — the `## Key decisions` section will still appear in the issue body, just with no bullets.

Draft 2-5 bullet points:

```
- **<What was decided>** — <Why. What was the alternative and why it wasn't picked. One sentence.>
```

Rules:
1. Extract from the brainstorming conversation context, not just the spec text. If the spec already existed (no brainstorming), extract from the spec content.
2. Use the same terms the user used. Do not elevate to abstract patterns or jargon.
3. Each bullet must be self-contained — readable without the full spec.
4. Prefer fewer strong bullets over many weak ones. 2 strong > 5 weak.
5. Implementation details are not decisions. "Used jq" is not a decision. "Labels instead of Issue Types for user repos — because the API silently fails" is a decision.

Present to the user separately from the spec review:

"Key decisions for the issue body — edit or confirm:"

Iterate until user confirms. Store as `$key_decisions` for step 8.

## Step 8: Update issue body — paste spec inline

The spec file is the **authoring artifact**. The issue body is **canonical** — anyone reading the issue on GitHub must see the full design without checking out the repo.

Read the locked spec file:

```bash
spec_content=$(cat <SPEC_DIR>/<date>-<slug>.md)
```

Reconstruct the issue body in the conventional section order (per `gh-issue-conventions.md`: Parent → Summary → **Key decisions** → PRD link → **Design (inline content)** → Plan link → PR link → Done note). Preserve the existing Parent / Summary / PRD link sections from the body fetched in step 1; insert `## Key decisions` from step 7.5; replace or insert the `## Design` section with the full spec content.

Post the new body via stdin (`-F -`) to avoid quoting headaches with backticks, dollar signs, and code blocks inside the spec:

```bash
gh issue edit <N> -F - <<EOF
[Parent: #M line if applicable]

## Summary

<preserved summary>

## Key decisions

$key_decisions

## PRD link

<preserved PRD link if applicable>

## Design

$spec_content
EOF
```

Drift policy: if the spec file and issue body diverge later, the file wins — re-run this step to re-paste. Don't hand-edit the GH issue body for design content.

### Step 8 (story-design mode): update story body

No spec file. Rebuild the story body using the Story template (per `gh-issue-conventions.md`), preserving the summary / Integration branch / Context / Non-goals from step 1, and inserting the brainstorming output:

```bash
gh issue edit <N> -F - <<EOF
<preserved 1-line summary>

## Integration branch

\`<preserved integration branch>\`

## Key decisions

$key_decisions

## Architecture

$architecture_content

## Sub-issues

$sub_issues_plan

## Context

<preserved context>

## Non-goals

<preserved non-goals>
EOF
```

`$sub_issues_plan` is a human-readable breakdown — each item becomes a real sub-issue later via `/sillok-start --parent <N>`. Do NOT auto-create sub-issues here.

## Step 9: Output

**Story-design mode:**

- Issue URL with status `In Design`
- Story body updated with Architecture + Sub-issues breakdown + Key decisions
- Handoff: "Next: `/sillok-start --parent <N>` to create each sub-issue from the breakdown."

**Ordinary single-issue / sub-issue mode:**

- Spec path: `<SPEC_DIR>/<date>-<slug>.md`
- Issue URL with status `In Design`
- Issue body updated with full spec content inlined under `## Design`
- Handoff: "Next: `/sillok-execute` to write the plan and ship the work."
