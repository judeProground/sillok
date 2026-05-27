---
description: Write the plan from the spec, dispatch subagent-driven execution, and run a final whole-branch review at the end. Per-task reviews are delegated to superpowers; only the end-of-plan review is mandatory. Sets project status to In Progress when plan saved. Auto-answers writing-plans handoff with subagent-driven (no re-prompt).
---

You are running the `/sillok-execute` slash command for the sillok.

## Step 1: State derivation + mode detection

Run the precompute script. It outputs branch + mode + issue metadata + project status + spec existence + plan existence + CWD check in one shot:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/precompute-execute.sh
```

Read the markdown block. Show it back to the user as the current state summary.

**CWD mismatch handling:** if the output contains `⚠️  CWD MISMATCH` and an `EXEC FIRST: cd ...` line, run that `cd` command BEFORE proceeding. Same reason as `/sillok-design` step 1 — session resume silently resets cwd, breaking file-relative operations.

**Mode-specific handling:**

- **Single-issue mode**: precompute resolved everything (issue, slug, project status, spec path, plan path).
- **Umbrella mode**: prompt user for which sub-issue to execute (mapping required), then proceed as single-issue against that issue number.
- **Other branch**: ABORT.

**Spec is required.** If precompute reports "Spec: none", ABORT with "No spec at `<SPEC_DIR>/*-<slug>.md`. Run `/sillok-design` first."

If multiple spec matches (rare; only if user redesigned with a new date), the precompute picks the most recent — that's the correct behavior.

## Step 2: Pre-condition

Project status was extracted by precompute (step 1). Apply:

- `In Design` → proceed.
- `Todo` → ABORT with "Spec not yet designed. Run `/sillok-design`."
- `In Progress` → resume; some/all tasks may already be done.
- `In QA` → ABORT with "PR already opened. Run `/sillok-end` to finalize, or fix the status manually."

Spec existence was verified in step 1 — abort already handled there.

## Step 3: Plan path

> `<SPEC_DIR>` and `<PLAN_DIR>` below resolve to the values of `docs.specs` and `docs.plans` in `.claude/sillok/workflow.config.json` (defaults `docs/superpowers/specs` and `docs/superpowers/plans`).

`<PLAN_DIR>/$(date +%Y-%m-%d)-<slug>.md`. Date is today (the plan is created/written now). Note: spec date may be earlier.

Check if plan exists:

`ls <PLAN_DIR>/*-<slug>.md 2>/dev/null`

If found, capture the most recent path. Skip step 4 (plan already written; this is a resume).

## Step 4: If plan doesn't exist — write the plan

Invoke the `superpowers:writing-plans` skill with the spec path as input.

**CRITICAL: when writing-plans completes its execution-mode handoff and asks the user "1. Subagent-Driven (recommended) 2. Inline Execution. Which?":**

**AUTO-RESPOND `subagent-driven` (option 1).** Do NOT prompt the user. Sillok locks in subagent-driven execution as the canonical mode; re-prompting per feature is friction.

After the plan is written and writing-plans hands off to subagent-driven-development:

- The plan file is at `<PLAN_DIR>/<today-date>-<slug>.md`.
- Update issue body to add `## Plan\n\nPlan written.` marker (fetch body, mutate, post back). The plan file is a local working artifact, not committed.
- Set project status to `In Progress`:

  ```bash
  source "${CLAUDE_PLUGIN_ROOT}/scripts/lib/project.sh"
  ITEM_ID=$(sillok_project_item_for_issue "https://github.com/$REPO/issues/$N")
  sillok_project_status_set "$ITEM_ID" progress
  ```

## Step 5: If plan exists — resume

Skip step 4 (plan already written; this is a resume).

## Step 6: Invoke subagent-driven execution

Use the `superpowers:subagent-driven-development` skill with the plan path. The skill dispatches an implementer subagent per task and runs spec-compliance + code-quality reviews after each.

## Step 7: Per-task execution — delegated to superpowers

Per-task implementation reviews (spec compliance + code quality) are owned by `superpowers:subagent-driven-development`. That skill's protocol already dispatches:

1. Implementer subagent (writes the code, commits)
2. Spec reviewer subagent (verifies spec compliance)
3. Code quality reviewer subagent (catches issues)

Do NOT layer extra mandatory gates per task on top. The skill itself decides when reviews can be batched or skipped (e.g., trivial mechanical refactors after a precedent task passed) — trust its judgment.

**Optional `sillok:verify-gate` per task:** an earlier version of this command required `sillok:verify-gate` between every task. That has been moved to step 8 (end-of-plan whole-branch) because it was disproportionate for trivial features. Per-task invocation is allowed when a task introduces a new lint/tsc surface or you genuinely doubt the change, but no longer required.

## Step 8: Final whole-branch review — REQUIRED

After all plan tasks are marked complete in TodoWrite, run the whole-branch verification before handing off to `/sillok-end`. Do NOT skip this step even for trivial features — whole-branch reviewers regularly catch things per-task reviews miss (consumers in `pages/` / `widgets/` outside the spec's audit zone, cross-task interactions, drift from the spec's invariants).

1. **Dispatch a final code-reviewer subagent** for the whole-feature diff (`<base-sha>..HEAD`) using the `superpowers:requesting-code-review` template. Reviewer scope is the full diff, not the most recent task.
   - If issues found, dispatch a fix subagent (do NOT modify in main context). Re-review until clean.

2. **Invoke the `sillok:verify-gate` skill on the whole-feature diff:**
   - Tier 1 auto-fixes mechanical issues (lint/tsc/format).
   - Tier 2 runs `simplify` once over the aggregate diff — much cheaper than per-task.
   - Apply blockers via fix subagent. Re-run until clean.

## Step 9: All tasks done

Print summary:

- Number of commits landed: `git rev-list --count <base-sha>..HEAD`
- Files changed: `git diff --stat <base-sha> HEAD`
- Final whole-branch review state: clean / had-blockers (note iteration count if multiple)
- Project status confirmed `In Progress`
- Issue body updated with Plan marker

Handoff: "Next: `/sillok-end` to push the branch and open the PR."
