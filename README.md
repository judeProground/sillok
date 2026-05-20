# Sillok

> **Sillok** (實錄, 실록) means "veritable records" — the authoritative chronicles of the Joseon Dynasty, registered with UNESCO Memory of the World. This Claude Code plugin applies the same idea to a codebase: every feature is brainstormed, recorded as a spec, chronicled through implementation, and sealed into `main` as the project's true record.

**Spec-driven feature development, tracked by GitHub issues.**

A GitHub issue is the canonical record of one feature. Its body holds the spec inline (so anyone can read it on GitHub without checking out the repo). A linked plan, a branch on a worktree, a series of commits, and finally a PR — every artifact threads back to that one issue. The issue label flips through `todo → designed → in-progress → in-review` as the work moves.

The plugin is built around five workflow commands plus one bootstrap command. They preserve a proven pipeline structure (issue creation, design brainstorming with spec inlining, plan generation with subagent-driven execution, end-of-plan whole-branch verification, PR creation) and connect them through a single per-project configuration file.

## Install

Requires Claude Code, `gh` CLI authenticated against your GitHub account, and `jq`.

```bash
/plugin marketplace add judeProground/sillok
/plugin install sillok@sillok
```

Then in any project:

```bash
cd /path/to/your-project
/sillok-init
```

`/sillok-init` is zero-prompt: it detects your repo, base branch, package manager (validating lint/format/typecheck against `package.json#scripts`), branch prefix, and gitignored config files automatically, writes `.claude/sillok/workflow.config.json`, scaffolds six rule files under `.claude/sillok/rules/`, installs shortcut shims under `.claude/commands/`, appends import lines to your `CLAUDE.md`, creates 14 default labels on the GitHub repo, and auto-picks vertical-slice candidates as `area:*` labels (top 15 by appearance across FSD/monorepo layouts). Edit the config file if anything detected wrong.

## Command invocation

After `/sillok-init`, every sillok command can be invoked two ways:

| Form | Source | Notes |
|------|--------|-------|
| `/sillok-start` | shim at `.claude/commands/sillok-start.md` | Recommended. Resolves the latest installed plugin version at runtime. |
| `/sillok:sillok-start` | plugin command (Claude Code namespaced form) | Canonical. Always works, even if shims were deleted. |

Shims carry a `sillok-shim: true` frontmatter marker; re-running `/sillok-init` refreshes them safely but leaves your own custom commands at the same path untouched.

## Workflow

```
/sillok-start    # create GH issue + branch + worktree (cut from base branch)
/sillok-design   # brainstorm + write spec → label `designed`
/sillok-execute  # write plan + dispatch subagent-driven execution → label `in-progress`
/sillok-end      # open PR (Closes #N) → label `in-review`
                 # squash-merge auto-closes the issue
```

For multi-PR work (an epic with sub-issues), sillok uses an **integration branch** model: every epic gets a real branch (`epic/issue-<N>-<slug>`) plus a worktree. Sub-features cut from and PR back to the integration branch; the epic itself merges to base with a merge commit (preserving sub-feature commits).

## Epic flow

```
/sillok-epic                          # on main → creates epic + integration branch + worktree
cd .worktrees/<epic-slug>
/sillok-start --parent <epic-N>       # sub-feature cuts from the epic branch
# ... work, PR sub-feature to epic ...
/sillok-start --parent <epic-N>       # another sub-feature
# ... when all sub-features are merged into the epic ...
cd .worktrees/<epic-slug>
/sillok-end                           # opens epic→main PR with merge-commit recommendation
```

**Promotion path** (starts as a normal feature, grows too big):

```
/sillok-start                         # feature/issue-43-foo
# ... halfway through realize it needs sub-features ...
/sillok-epic                          # detects feature context → offers promotion of #43
# After confirming: branch renames to epic/issue-43-foo, label flips, integration branch ready.
/sillok-start --parent 43             # add sub-feature(s)
```

## Config

`.claude/sillok/workflow.config.json` is the only file the plugin reads from your project. It records:

- `repo` — `owner/name` for the GitHub repo
- `baseBranch` — branch new feature branches are cut from
- `branchPrefix` — template, e.g. `{type}/issue-` (default), `{user}/issue-`, or a literal like `feat/`. `{type}` resolves to the issue's type label (`feature`/`bug`/`improvement`/`infra`/`epic`); `{user}` resolves to your git user name.
- `worktree.{enabled,dir,copyFiles}` — worktree behavior and what gitignored files to copy into new worktrees
- `install` — command run after a worktree is created (e.g. `pnpm install`)
- `verify.{lint,typecheck,format}` — commands the verify-gate runs (empty = skip that step)
- `docs.{specs,plans}` — where spec and plan files live
- `commit.coAuthor` — optional commit trailer
- `milestone.{naming,sprintWeeks,weekStart}` — sprint milestone convention
- `labels.{types,stages,priorities,areas,defaults}` — label taxonomy. `areas` is auto-populated from project layout during `/sillok-init` (rank ≥ 2 AND top 15); edit by hand or ask Claude to swap entries before re-running label bootstrap.

A JSON Schema (`schema/v1.json`) is referenced from the config via `$schema` so editors offer validation.

## Skills bundled

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
│       └── sillok-epic.md
├── docs/superpowers/
│   ├── specs/
│   └── plans/
└── CLAUDE.md  # @-import block appended
```

Everything sillok owns is under `.claude/sillok/` plus 5 shim files under `.claude/commands/sillok-*.md` (carrying `sillok-shim: true` frontmatter so re-init can refresh them without touching your own commands). Your own `.claude/rules/`, other `.claude/commands/`, etc. are not touched.

## License

MIT. See [LICENSE](./LICENSE).
