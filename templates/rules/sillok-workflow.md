# Sillok Workflow

GitHub-Issue-driven feature pipeline. Always use these slash commands instead of ad-hoc issue/branch/PR work — they enforce conventions defined in `gh-issue-conventions.md`, `pr-convention.md`, and `commit-conventions.md`.

## Pipeline (per feature)

```
/sillok-start   → creates GH issue + branch + worktree (cut from origin/main)
/sillok-design  → brainstorms + writes spec, pastes content into issue body, status Todo→In Design
/sillok-execute → writes plan, dispatches subagents per task with verify-gate, status In Design→In Progress
/sillok-end     → opens PR, status In Progress→In QA, done-note in PR body
                        → squash-merge auto-closes the issue via `Closes #N`
```

Project status (`Todo`/`In Design`/`In Progress`/`In QA`) is set by the commands — do not change by hand.

Stage transitions are owned by the `sillok:workflow` orchestrator skill: by default it proposes the next stage and waits for confirmation (propose mode). With `automation.fullAuto: true` in `workflow.config.json` it chains start → design → execute → end unprompted, stopping after PR creation — it never merges.

## Command invocation forms

Every sillok command can be invoked two ways:

| Form | Where it comes from | Notes |
|------|--------------------|-------|
| `/sillok-start` | `.claude/commands/sillok-*.md` shim (installed by `/sillok-init`) | Recommended for daily use. Resolves to the latest installed plugin version at runtime. |
| `/sillok:sillok-start` | Plugin command (namespaced by Claude Code) | Canonical form. Always works, even if shim files were deleted. |

The shim files carry a `sillok-shim: true` frontmatter marker so re-running `/sillok-init` can refresh them safely without clobbering your own custom commands. If you have your own command at the same name (no marker), sillok skips it.

## When to use which

| Situation | Command |
|-----------|---------|
| New idea (with or without PRD) | `/sillok-start` |
| Spec needs writing for the active issue | `/sillok-design` |
| Spec is locked, ready to implement | `/sillok-execute` |
| Implementation done, want a PR | `/sillok-end` |
| Work needs ≥2 sub-feature PRs in this repo | `/sillok-story` |

## Story vs feature

`/sillok-start` creates **work-unit** issues (`feature` / `bug` / `improvement` / `infra`) — single issue, single PR.

`/sillok-story` creates **parent tracking** issues — Issue Type `Story` (org mode) or a `story` label (user mode) — for in-repo composites spanning ≥2 sub-feature PRs. Stories have a different body shape (Integration branch / Key decisions / Architecture / Sub-issues / Context / Non-goals) and no code-level spec/plan of their own — `/sillok-design` in story mode fills Key decisions and Architecture; sub-issues run design/execute/end individually. Then for each sub-issue: `/sillok-start --parent <story-N>`.

See "Story template" in `gh-issue-conventions.md` for the body shape.

## Worktree note

Every `/sillok-start` creates `.worktrees/<N>-<slug>` and bases the branch on the configured `baseBranch` — or on the story integration branch when run with `--parent <N>` pointing at a story — even if invoked from another branch. After it returns, `cd .worktrees/<N>-<slug>` before running design/execute. Session-resume can silently reset cwd back to the main repo — design/execute precompute scripts detect this and surface the cd command.

## Don't bypass

- Don't `gh issue create` directly — use `/sillok-start` so labels, milestone, parent linking, and worktree all happen together.
- Don't manually change project status — let the commands do it.
- Don't open PRs via `gh pr create` — use `/sillok-end` so the body uses the convention and `Closes #N` auto-closes on merge.

## Story = integration branch

Every story gets a real branch (`story/issue-<N>-<slug>`) and a worktree, not just a tracking issue. Sub-features under a story cut from and PR back to the integration branch (squash-merged into it). The story itself merges to the configured `baseBranch` (usually `main`) with a **merge commit** — not a squash — so sub-feature commits remain visible in the base-branch history.

You can either start a story up front:

```bash
/sillok-story    # on main or any non-sillok branch → creates story from scratch
```

…or promote a feature that grew too big:

```bash
/sillok-start    # creates feature/issue-43-foo as usual
# ...halfway through, you realize the work needs sub-features
/sillok-story    # from inside feature/issue-43-foo → offers promotion
```

After promotion, `feature/issue-43-foo` becomes `story/issue-43-foo`, the GitHub Issue Type flips to `Story` (org mode; in user mode the `story` label stands in), the body is rewritten to the story template, and any work-in-progress in the worktree can optionally be split into its own sub-feature branch.
