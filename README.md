# Sillok

> **Sillok** (實錄, 실록) means "veritable records" — the authoritative chronicles of the Joseon Dynasty, registered with UNESCO Memory of the World. This Claude Code plugin applies the same idea to a codebase: every feature is brainstormed, recorded as a spec, chronicled through implementation, and sealed into `main` as the project's true record.

**Spec-driven feature development, tracked by GitHub issues.**

A GitHub issue is the canonical record of one feature. Its body holds the spec inline (so anyone can read it on GitHub without checking out the repo). A linked plan, a branch on a worktree, a series of commits, and finally a PR — every artifact threads back to that one issue. The issue's card on a Projects v2 board flips through `Todo → In Design → In Progress → In QA → Done` as the work moves.

The plugin is built around five workflow commands plus one bootstrap command. They preserve a proven pipeline structure (issue creation, design brainstorming with spec inlining, plan generation with subagent-driven execution, end-of-plan whole-branch verification, PR creation) and connect them through a single per-project configuration file.

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
  - a `Status` single-select field configured with exactly these five options: **Todo**, **In Design**, **In Progress**, **In QA**, **Done**.
  - the built-in workflows **"Auto-add to project"** and **"Item closed → Done"** enabled, so new issues land in Todo automatically and merged PRs close their issues into Done.

Then in any project:

```bash
cd /path/to/your-project
/sillok-init
```

`/sillok-init` is zero-prompt: it detects your repo, base branch, package manager (validating lint/format/typecheck against `package.json#scripts`), branch prefix, Projects v2 board (auto-detects from repo owner's project list), and gitignored config files automatically, writes `.claude/sillok/workflow.config.json`, scaffolds six rule files under `.claude/sillok/rules/`, installs shortcut shims under `.claude/commands/`, appends import lines to your `CLAUDE.md`, creates the 10 default labels on the GitHub repo (6 natures + 4 priorities — Issue Types and project Status replace the old `type:*`/`stage:*` labels), and auto-picks vertical-slice candidates as `area:*` labels (top 15 by appearance across FSD/monorepo layouts). Edit the config file if anything detected wrong.

## Command invocation

After `/sillok-init`, every sillok command can be invoked two ways:

| Form | Source | Notes |
|------|--------|-------|
| `/sillok-start` | shim at `.claude/commands/sillok-start.md` | Recommended. Resolves the latest installed plugin version at runtime. |
| `/sillok:sillok-start` | plugin command (Claude Code namespaced form) | Canonical. Always works, even if shims were deleted. |

Shims carry a `sillok-shim: true` frontmatter marker; re-running `/sillok-init` refreshes them safely but leaves your own custom commands at the same path untouched.

## Workflow

```
/sillok-start    # create GH issue + Issue Type + assignee + branch + worktree + project Todo
/sillok-design   # brainstorm + spec → project status In Design
/sillok-execute  # write plan + dispatch subagent execution → project status In Progress
/sillok-end      # open PR → project status In QA → (auto Done on merge)
```

State no longer lives in `stage:*` labels — it lives in the Projects v2 board's `Status` field. Issue Types (`Feature`, `Bug`, `Task`, `Story`, `Epic`) replace the old `type:*` labels. Sillok writes both: it sets the Issue Type on creation and moves the project card through the five `Status` options as the work advances.

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

For product work that spans multiple code repos, sillok supports a **cross-repo PRD** pattern. The PRD itself lives as an `Epic`-typed issue in a dedicated product/spec repo, configured via `prdRepo` in `workflow.config.json`. Code repos then attach sub-features to that remote PRD by passing the qualified reference:

```
# in any code repo configured with prdRepo
/sillok-start --parent owner/prd-repo#42   # cuts a sub-feature linked to the PRD
```

Cross-repo `Closes #N` syntax is not honored by GitHub, so PRD closure stays manual — a PM closes the PRD issue once all linked sub-features across repos have shipped. Sillok records the parent reference in the sub-feature's body and on the project board so the linkage is auditable, but it never tries to auto-close the PRD.

## Config

`.claude/sillok/workflow.config.json` is the only file the plugin reads from your project. It records:

- `repo` — `owner/name` for the GitHub repo
- `baseBranch` — branch new feature branches are cut from
- `branchPrefix` — template, e.g. `{type}/issue-` (default), `{user}/issue-`, or a literal like `feat/`. `{type}` resolves to the issue's Issue Type (`feature`/`bug`/`task`/`story`/`epic`); `{user}` resolves to your git user name.
- `language` — body generation language: `"auto"` (default, matches session language), `"ko"`, or `"en"`. Section headers stay English for parsing; prose follows the chosen language.
- `orgMode` — `true` for org repos (Issue Types + Projects v2 APIs), `false` (default) for personal repos (falls back to label-based type tracking).
- `prdRepo` — *optional.* `owner/name` of a separate repo where Epic-typed PRD issues live, for cross-repo PRD work. Leave empty if PRDs live in the same repo as code.
- `project.{owner, number, statusField, statuses}` — Projects v2 binding. `owner` is the org/user that owns the project, `number` is the project number from its URL, `statusField` is the single-select field name (default `Status`), and `statuses` maps sillok's five logical phases (`todo` / `design` / `progress` / `review` / `done`) to the option names on your board (defaults: `Todo`, `In Design`, `In Progress`, `In QA`, `Done`).
- `types.{list, defaults}` — Issue Type configuration. `list` is the Issue Types sillok expects to exist on the org (default: `["Epic", "Story", "Feature", "Task", "Bug"]`). `defaults` maps sillok roles (`feature`, `composite`, `prd`) to the Issue Type used when creating each (defaults: `Feature`, `Story`, `Epic`).
- `worktree.{enabled,dir,copyFiles}` — worktree behavior and what gitignored files to copy into new worktrees
- `install` — command run after a worktree is created (e.g. `pnpm install`)
- `verify.{lint,typecheck,format}` — commands the verify-gate runs (empty = skip that step)
- `docs.{specs,plans}` — where spec and plan files live
- `commit.coAuthor` — optional commit trailer
- `milestone.{naming,sprintWeeks,weekStart}` — sprint milestone convention
- `labels.{priorities,areas,natures,defaults}` — label taxonomy. `priorities` is the priority ladder (`p1`–`p4`). `natures` is the cross-cutting label class — orthogonal traits like `improvement`, `refactor`, `infra`, `docs`, `security`, `performance` — applied alongside an Issue Type. `areas` is auto-populated from project layout during `/sillok-init` (rank ≥ 2 AND top 15); edit by hand or ask Claude to swap entries before re-running label bootstrap.

A JSON Schema (`schema/v1.json`) is referenced from the config via `$schema` so editors offer validation.

## Skills bundled

- `sillok:workflow` — stage orchestrator (the auto-triggering entry point; reads `automation.fullAuto`)
- `sillok:start` / `sillok:design` / `sillok:execute` / `sillok:end` / `sillok:story` / `sillok:init` — per-stage skill bodies behind the commands above (not directly user-invocable)
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
│       ├── sillok-start.md       # shim (pointer-only, ~10 lines)
│       ├── sillok-design.md
│       ├── sillok-execute.md
│       ├── sillok-end.md
│       └── sillok-story.md
├── docs/superpowers/
│   ├── specs/
│   └── plans/
└── CLAUDE.md  # @-import block appended
```

Everything sillok owns is under `.claude/sillok/` plus 5 shim files under `.claude/commands/sillok-*.md` (carrying `sillok-shim: true` frontmatter so re-init can refresh them without touching your own commands). Your own `.claude/rules/`, other `.claude/commands/`, etc. are not touched.

## License

MIT. See [LICENSE](./LICENSE).
