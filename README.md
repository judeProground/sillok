# Sillok

> **Sillok** — spec-driven feature development for Claude Code. Every feature is brainstormed, written up as a spec, tracked through implementation on a GitHub issue, and merged into `main` as the project's record.

**Spec-driven feature development, tracked by GitHub issues.**

A GitHub issue is the canonical record of one feature. Its body holds the spec inline (so anyone can read it on GitHub without checking out the repo). A linked plan, a branch on a worktree, a series of commits, and finally a PR — every artifact threads back to that one issue. The issue's card on a Projects v2 board flips through `Todo → In Design → In Progress → In QA → Done` as the work moves.

The plugin is built around six workflow commands — `/sillok-add` for backlog capture and the `start`/`design`/`execute`/`end`/`story` feature pipeline — plus one bootstrap command (`/sillok-init`). They preserve a proven pipeline structure (issue creation, design brainstorming with spec inlining, plan generation with subagent-driven execution, end-of-plan whole-branch verification, PR creation) and connect them through a single per-project configuration file.

**Architecture:** each command is a thin pointer wrapper over a per-stage skill (`skills/<stage>/SKILL.md` holds the actual procedure), and a `sillok:workflow` orchestrator skill owns the stage chain — it proposes the next stage by default, or runs the whole start → design → execute → end chain unprompted (stopping after PR creation, never merging) when `automation.fullAuto: true` is set in `workflow.config.json`. A SessionStart hook injects a small sillok context block in configured projects.

## Install

```bash
/plugin marketplace add judeProground/sillok
/plugin install sillok@sillok
```

### Prerequisites

- Claude Code installed.
- `gh` CLI authenticated against your GitHub account.
- `jq` available on `PATH`.
- **Organization repo (recommended) or personal repo.** Org repos get full Issue Types + Projects v2 integration (`orgMode: true`). Personal repos work too — sillok falls back to label-based type tracking when `orgMode: false` (the default).
- **Org repos only: add missing Issue Types.** Sillok v2 uses `Epic`, `Story`, `Feature`, `Task`, and `Bug` as Issue Types. `Feature`, `Task`, and `Bug` usually exist by default; an org owner must add `Epic` and `Story` from the org-level **Issue Types** settings (Organization → Settings → Issue Types).
- **A Projects v2 board** (optional for personal repos, recommended for orgs) with:
  - a `Status` single-select field configured with these six options: **Backlog**, **Todo**, **In Design**, **In Progress**, **In QA**, **Done**. (`Backlog` is used by `/sillok-add`; a board without it still works — sillok warns and skips the backlog parking.)
  - the built-in workflows **"Auto-add to project"** and **"Item closed → Done"** enabled. Point auto-add's default status at **Backlog** (recommended) so manually-filed issues land in the backlog; sillok commands set their own status explicitly (`/sillok-add` → Backlog, `/sillok-start` → Todo).

Then in any project:

```bash
cd /path/to/your-project
/sillok-init
```

`/sillok-init` asks at most two questions per run, drawn from three conditional ones (a Projects v2 URL when no board is auto-detected; a one-time confirmation of proposed `area:*` labels when candidates are found; on org repos, the board's Priority-field option mapping — only when an existing field's options genuinely mismatch the config): it detects your repo, base branch, package manager (validating lint/format/typecheck against `package.json#scripts`), branch prefix, Projects v2 board (auto-detects from repo owner's project list), and gitignored config files automatically, writes `.claude/sillok/workflow.config.json`, scaffolds six rule files under `.claude/sillok/rules/`, installs shortcut shims under `.claude/commands/`, appends import lines to your `CLAUDE.md`, creates the default labels on the GitHub repo (6 natures always; the 4 `p1`–`p4` priority labels on user-mode repos only — org repos track priority on the board's Priority field; Issue Types and project Status replace the old `type:*`/`stage:*` labels), and proposes `area:*` labels by classifying the project's pruned directory tree (`scripts/project-tree.sh`) into vertical business areas vs horizontal technical layers — labels are created only after you confirm, and the list stays editable in the config afterwards. Edit the config file if anything detected wrong.

## Command invocation

After `/sillok-init`, every sillok command can be invoked two ways:

| Form | Source | Notes |
|------|--------|-------|
| `/sillok-start` | shim at `.claude/commands/sillok-start.md` | Recommended. Resolves the latest installed plugin version at runtime. |
| `/sillok:sillok-start` | plugin command (Claude Code namespaced form) | Canonical. Always works, even if shims were deleted. |

Shims carry a `sillok-shim: true` frontmatter marker; re-running `/sillok-init` refreshes them safely but leaves your own custom commands at the same path untouched.

## Workflow

```
/sillok-add      # capture a backlog issue — no branch/worktree; status Backlog
/sillok-start    # create GH issue + Issue Type + assignee + branch + worktree + project Todo
/sillok-start 41 # ADOPT existing issue #41 — full env setup, Backlog → Todo
/sillok-design   # brainstorm + spec → project status In Design
/sillok-execute  # write plan + dispatch subagent execution → project status In Progress
/sillok-end      # open PR → project status In QA → (auto Done on merge)
```

State no longer lives in `stage:*` labels — it lives in the Projects v2 board's `Status` field. Issue Types (`Feature`, `Bug`, `Task`, `Story`, `Epic`) replace the old `type:*` labels. Sillok writes both: it sets the Issue Type on creation and moves the project card through the six `Status` options as the work advances.

For multi-PR work (a composite within one repo), sillok uses an **integration branch** model: every Story gets a real branch (`story/issue-<N>-<slug>`) plus a worktree. Sub-features cut from and PR back to the integration branch; the Story itself merges to base with a merge commit (preserving sub-feature commits).

## Story flow

A **Story** is sillok's in-repo composite: one parent issue (Issue Type `Story`) plus a real integration branch and worktree, with sub-features PR'd into it.

```
/sillok-story                          # on main → creates Story + integration branch + worktree
cd .worktrees/<story-slug>
/sillok-start --parent <story-N>       # sub-feature cuts from the story branch
# ... work, PR sub-feature to story ...
/sillok-start --parent <story-N>       # another sub-feature
# ... when all sub-features are merged into the story ...
cd .worktrees/<story-slug>
/sillok-end                            # opens story→main PR with merge-commit recommendation
```

**Promotion path** (starts as a normal feature, grows too big):

```
/sillok-start                          # feature/issue-43-foo
# ... halfway through realize it needs sub-features ...
/sillok-story                          # detects feature context → offers promotion of #43
# After confirming: branch renames to story/issue-43-foo, Issue Type flips to Story, integration branch ready.
/sillok-start --parent 43              # add sub-feature(s)
```

## Cross-repo PRD flow

For product work that spans multiple code repos, sillok supports a **cross-repo PRD** pattern. The PRD itself lives as an `Epic`-typed issue in a dedicated product/spec repo, configured via `epicRepo` in `workflow.config.json`. Code repos then attach sub-features to that remote PRD by passing the qualified reference:

```
# in any code repo configured with epicRepo
/sillok-start --parent owner/projects#42   # cuts a sub-feature linked to the PRD
```

Cross-repo `Closes #N` syntax is not honored by GitHub, so PRD closure stays manual — a PM closes the PRD issue once all linked sub-features across repos have shipped. Sillok records the parent reference in the sub-feature's body and on the project board so the linkage is auditable, but it never tries to auto-close the PRD.

## Config

`.claude/sillok/workflow.config.json` is the only file the plugin reads from your project. It records:

- `repo` — `owner/name` for the GitHub repo
- `baseBranch` — branch new feature branches are cut from
- `branchPrefix` — template, e.g. `{type}/issue-` (default), `{user}/issue-`, or a literal like `feat/`. `{type}` resolves to the issue's Issue Type (`feature`/`bug`/`task`/`story`/`epic`); `{user}` resolves to your git user name.
- `language` — body generation language: `"auto"` (default, matches session language), `"ko"`, or `"en"`. Section headers stay English for parsing; prose follows the chosen language.
- `orgMode` — `true` for org repos (Issue Types + Projects v2 APIs), `false` (default) for personal repos (falls back to label-based type tracking).
- `automation.{fullAuto}` — boolean, default `false`. When `true`, the `sillok:workflow` orchestrator chains start → design → execute → end without per-stage confirmation, stopping after PR creation (it never merges). An absent key means propose mode.
- `epicRepo` — *optional.* `owner/name` of a separate repo where Epic-typed PRD issues live, for cross-repo PRD work. Leave empty if PRDs live in the same repo as code.
- `project.{owner, number, statusField, statuses, priorityField, priorities}` — Projects v2 binding. `owner` is the org/user that owns the project, `number` is the project number from its URL, `statusField` is the single-select field name (default `Status`), and `statuses` maps sillok's six logical phases (`backlog` / `todo` / `design` / `progress` / `review` / `done`) to the option names on your board (defaults: `Backlog`, `Todo`, `In Design`, `In Progress`, `In QA`, `Done`). On org repos, priority is set via the board's Priority single-select: `priorityField` is its field name (default `Priority`), and `priorities` maps `p1`–`p4` to its option names (defaults: `Urgent`, `High`, `Medium`, `Low`); `/sillok-init` auto-creates the field when absent. User repos keep the `p1`–`p4` labels instead.
- `types.{list, defaults}` — Issue Type configuration. `list` is the Issue Types sillok expects to exist on the org (default: `["Epic", "Story", "Feature", "Task", "Bug"]`). `defaults` maps sillok roles (`feature`, `composite`, `epic`) to the Issue Type used when creating each (defaults: `Feature`, `Story`, `Epic`).
- `worktree.{enabled,dir,copyFiles}` — worktree behavior and what gitignored files to copy into new worktrees
- `install` — command run after a worktree is created (e.g. `pnpm install`)
- `verify.{lint,typecheck,format}` — commands the verify-gate runs (empty = skip that step)
- `docs.{specs,plans}` — where spec and plan files live
- `commit.coAuthor` — optional commit trailer
- `milestone.{naming,sprintWeeks,weekStart}` — sprint milestone convention
- `labels.{priorities,areas,natures,defaults}` — label taxonomy. `priorities` is the priority ladder (`p1`–`p4`) — applied as labels on user-mode repos only; org repos record priority on the board's Priority field instead. `natures` is the cross-cutting label class — orthogonal traits like `improvement`, `refactor`, `infra`, `docs`, `security`, `performance` — applied alongside an Issue Type. `areas` is proposed during `/sillok-init` by an LLM classification of the project's pruned directory tree (`scripts/project-tree.sh`) — vertical business areas (e.g. `auth`, `wallet`) vs horizontal technical layers (e.g. `controller`, `dto`), confirmed once before labels are created; edit by hand or ask Claude to swap entries before re-running label bootstrap.

A JSON Schema (`schema/v1.json`) is referenced from the config via `$schema` so editors offer validation.

## Skills bundled

- `sillok:workflow` — stage orchestrator (the auto-triggering entry point; reads `automation.fullAuto`)
- `sillok:start` / `sillok:add` / `sillok:design` / `sillok:execute` / `sillok:end` / `sillok:story` / `sillok:init` — per-stage skill bodies behind the commands above (not directly user-invocable)
- `sillok:verify-gate` — whole-branch verification (lint/typecheck/format auto-fix → code review)
- `sillok:verify-spec-gate` — spec compliance reference (patterns, principles, smells)
- `sillok:gh-issue-management` — canonical GitHub-issue procedure

## Files in your project after `/sillok-init`

```
your-project/
├── .claude/
│   ├── sillok/
│   │   ├── workflow.config.json
│   │   └── rules/
│   │       ├── sillok-workflow.md
│   │       ├── gh-issue-conventions.md
│   │       ├── pr-convention.md
│   │       ├── commit-conventions.md
│   │       ├── worktree-setup.md
│   │       └── spec-driven-development.md
│   └── commands/
│       ├── sillok-add.md         # shim (pointer-only, ~10 lines)
│       ├── sillok-start.md
│       ├── sillok-design.md
│       ├── sillok-execute.md
│       ├── sillok-end.md
│       └── sillok-story.md
├── docs/superpowers/
│   ├── specs/
│   └── plans/
└── CLAUDE.md  # @-import block appended
```

Everything sillok owns is under `.claude/sillok/` plus 6 shim files under `.claude/commands/sillok-*.md` (carrying `sillok-shim: true` frontmatter so re-init can refresh them without touching your own commands). Your own `.claude/rules/`, other `.claude/commands/`, etc. are not touched.

## License

MIT. See [LICENSE](./LICENSE).
