---
description: Brainstorm and write the spec for the current issue. Saves spec to <SPEC_DIR>/, pastes the full spec content into the issue body, flips stage label todo → designed AFTER user reviews and confirms the spec content.
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

- **Single-issue mode**: precompute resolved `<N>`, `<slug>`, title, stage, and spec existence. Continue to step 2.
- **Umbrella mode**: precompute can't resolve `<N>` alone (multiple sub-issues). Fetch active sub-issues and prompt:
  - Map umbrella to its parent epic by asking the user: "Which epic does `<branch>` correspond to? Reply with the issue number." Remember the mapping if useful, but never bake it into the plugin.
  - `gh issue list --repo "$REPO" --state open --search "in:body Parent: #<parent>"` — list open sub-issues.
  - Prompt: "Which sub-issue are you designing? Reply with the issue number."
  - Re-run precompute conceptually for that `<N>` (or just fetch issue metadata directly), and derive slug = title-slug from `/sillok-start` step 9 (run `bash ${CLAUDE_PLUGIN_ROOT}/scripts/slug-from-title.sh <N> "<title>"`).
- **Other branch**: ABORT — workflow not applicable.

## Step 2: Pre-condition

Stage was already extracted by precompute (step 1). Apply:

- `todo` → proceed.
- `in-progress` (continuing prior partial design work) → unusual but allowed; confirm intent with user.
- `designed` / `in-review` → ABORT with "Spec already exists. Run `/sillok-execute` instead, or change the stage label manually if you actually want to redesign."

If precompute reported a stage warning, surface it to the user before proceeding.

## Step 3: Spec path + pre-existing check

> `<SPEC_DIR>` below resolves to the value of `docs.specs` in `.claude/sillok/workflow.config.json` (default `docs/superpowers/specs`).

Spec existence was checked by precompute (step 1). Apply:

- **None found** → spec path is `<SPEC_DIR>/$(date +%Y-%m-%d)-<slug>.md` (date is today).
- **Found at `<found-path>`** → prompt user: "(a) continue editing, (b) overwrite, (c) cancel". Act per choice. If `continue`, use `<found-path>` as the spec path (don't re-date).

Do NOT pre-create labels (`gh label create designed` etc.) — the standard label set is bootstrapped at repo setup. If a label is genuinely missing, surface the gap to the user; don't silently create.

## Step 4: Invoke brainstorming

Use the `superpowers:brainstorming` skill. Seed it with:

- Issue title: `<title>`
- Issue body: full body fetched in step 1
- Current state: stage, parent, slug

The brainstorming skill drives the discussion. Follow its instructions.

## Step 5: Save spec

When brainstorming concludes (the skill produces a coherent spec draft), write the result to the spec path computed in step 3.

## Step 6: Review loop

Print: "Spec written to `<path>`. Review and tell me corrections, or say `looks good` / `lock` / `ship` to confirm."

Iterate:

- Apply user's corrections to the spec file (Edit tool, surgical).
- Re-print path after each correction round.
- Continue until user explicitly confirms.

The label flip in step 7 ONLY happens after explicit confirmation. Confirmation is required because the spec may still be wrong; the flip marks "I've seen and accepted this".

## Step 7: Flip stage label

After explicit user confirmation in step 6:

`gh issue edit <N> --remove-label todo --add-label designed`

(If the issue was at `in-progress` for a continuation, instead remove `in-progress` and re-add `designed` — i.e., move BACK to designed since spec is fresh.)

## Step 8: Update issue body — paste spec inline

The spec file is the **authoring artifact**. The issue body is **canonical** — anyone reading the issue on GitHub must see the full design without checking out the repo.

Read the locked spec file:

```bash
spec_content=$(cat <SPEC_DIR>/<date>-<slug>.md)
```

Reconstruct the issue body in the conventional section order (per `gh-issue-conventions.md`: Parent → Summary → PRD link → **Design (inline content)** → Plan link → PR link → Done note). Preserve the existing Parent / Summary / PRD link sections from the body fetched in step 1; replace or insert the `## Design` section with the full spec content.

Post the new body via stdin (`-F -`) to avoid quoting headaches with backticks, dollar signs, and code blocks inside the spec:

```bash
gh issue edit <N> -F - <<EOF
[Parent: #M line if applicable]

## Summary

<preserved summary>

## PRD link

<preserved PRD link if applicable>

## Design

$spec_content
EOF
```

Drift policy: if the spec file and issue body diverge later, the file wins — re-run this step to re-paste. Don't hand-edit the GH issue body for design content.

## Step 9: Output

Print:

- Spec path: `<SPEC_DIR>/<date>-<slug>.md`
- Issue URL with new label
- Issue body updated with full spec content inlined under `## Design`
- Handoff: "Next: `/sillok-execute` to write the plan and ship the work."
