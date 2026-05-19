# Sillok Workflow

GitHub-Issue-driven feature pipeline. Always use these slash commands instead of ad-hoc issue/branch/PR work — they enforce conventions defined in `gh-issue-conventions.md`, `pr-convention.md`, and `commit-conventions.md`.

## Pipeline (per feature)

```
/sillok-start   → creates GH issue + branch + worktree (cut from origin/main)
/sillok-design  → brainstorms + writes spec, pastes content into issue body, label todo→designed
/sillok-execute → writes plan, dispatches subagents per task with verify-gate, label designed→in-progress
/sillok-end     → opens PR, label in-progress→in-review, done-note in PR body
                        → squash-merge auto-closes the issue via `Closes #N`
```

Stage labels (`todo`/`designed`/`in-progress`/`in-review`) are flipped by the commands — do not edit by hand.

## When to use which

| Situation | Command |
|-----------|---------|
| New idea (with or without PRD) | `/sillok-start` |
| Spec needs writing for the active issue | `/sillok-design` |
| Spec is locked, ready to implement | `/sillok-execute` |
| Implementation done, want a PR | `/sillok-end` |

## Epic vs feature

`/sillok-start` creates **work-unit** issues (`feature` / `bug` / `improvement` / `infra`) — single issue, single PR.

`/sillok-epic` creates **parent tracking** issues (label `epic`, ≥3 sub-issues spanning multiple PRs). Epics have a different body shape (Architecture / Sub-issues / Context / Non-goals) and no design/execute/end phase — sub-issues run those individually. Then for each sub-issue: `/sillok-start --parent <epic-N>`.

See "Epic template" in `gh-issue-conventions.md` for the body shape; the canonical epic example is the canonical example.

## Worktree note

Every `/sillok-start` creates `.worktrees/<N>-<slug>` and bases the branch on `origin/main`, even if invoked from an umbrella branch. After it returns, `cd .worktrees/<N>-<slug>` before running design/execute. Session-resume can silently reset cwd back to the main repo — design/execute precompute scripts detect this and surface the cd command.

## Don't bypass

- Don't `gh issue create` directly — use `/sillok-start` so labels, milestone, parent linking, and worktree all happen together.
- Don't manually flip stage labels — let the commands do it.
- Don't open PRs via `gh pr create` — use `/sillok-end` so the body uses the convention and `Closes #N` auto-closes on merge.
