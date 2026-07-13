# Sillok 실록

[![version](https://img.shields.io/badge/version-4.0.0-blue)](CHANGELOG.md)
[![license](https://img.shields.io/badge/license-MIT-green)](LICENSE)
[![Claude Code](https://img.shields.io/badge/Claude%20Code-plugin-8A2BE2)](https://docs.claude.com/en/docs/claude-code)

**A spec-driven feature workflow for Claude Code — every feature tracked from brainstorm to merge on a single GitHub issue.**

Sillok turns each feature into one auditable record. The GitHub issue holds the spec inline; a linked plan, a worktree branch, commits, and a PR all thread back to it; and the issue's Projects v2 card moves through `Todo → In Design → In Progress → In QA → Done` as the work advances. How a feature was designed and decided no longer lives only in a local session that disappears when you close the terminal.

```mermaid
flowchart LR
    add["/sillok-add"] -.->|Backlog| start["/sillok-start"]
    start -->|Todo| design["/sillok-design"]
    design -->|In Design| execute["/sillok-execute"]
    execute -->|In Progress| endpr["/sillok-end"]
    endpr -->|In QA| done(["merge → Done"])
```

## Why Sillok?

Building with an AI coding agent locally is fast — but the trail evaporates.

- **The process disappears; only code remains.** A local Claude Code session leaves a diff, but the reasoning behind it — why this approach, what was rejected, which trade-offs were made — is gone once the session ends. Under auto-accept, even the decisions you delegated leave no record.
- **Context is scattered.** Planning in Notion, issues in a tracker like Jira, code in git — three places, no single thread. Trackers often end up holding a ticket title and little else.
- **Everyone improvises a different workflow.** No shared structure means no shared record — and no clean substrate to later hand off to an agent.

Sillok makes the **GitHub issue the single source of truth** for a feature and wires the whole lifecycle around it:

- The issue connects commits, PR, milestone, board status, and release tag — one place for everything.
- Sub-issues and labels add finer structure: `Epic → Story → Feature → Task`.
- Skills and a SessionStart hook keep the issue in sync automatically and give every developer the same pipeline.
- Because the workflow is explicit and recorded, it becomes a natural substrate for agentic delegation — an agent can run the same pipeline a human does.

## Highlights

- **One issue = one feature's whole story** — spec inline, plan linked, branch/commits/PR threaded back, board status live.
- **Four-level hierarchy** — `Epic → Story → Feature → Task` via native GitHub sub-issue links (cross-repo capable).
- **GitHub-native, not label soup** — Issue Types + Projects v2 Status/Priority fields instead of `type:*` / `stage:*` labels.
- **Automatic linking & closing** — branches appear in the issue's Development panel; `Closes #N` auto-closes on merge.
- **Spec-driven by construction** — brainstorm → spec (pasted into the issue) → plan → subagent-driven build → whole-branch verify → PR.
- **Full-auto or propose mode** — chain the stages unprompted (it never merges), or confirm at each step.
- **No runtime dependencies** — pure bash + markdown + JSON; drops into any repo with one `/sillok-init`.

## Quick start

### Prerequisites

- Claude Code installed.
- `gh` CLI authenticated against your GitHub account.
- `jq` on your `PATH`.
- **A GitHub repo** — organization (recommended) or personal. Org repos get full Issue Types + Projects v2 (`orgMode: true`); personal repos fall back to label-based tracking (`orgMode: false`).
- **Org repos:** add the `Epic` and `Story` Issue Types (Organization → Settings → Issue Types); `Feature`, `Task`, and `Bug` usually exist already.
- **A Projects v2 board** (recommended) with a `Status` field carrying `Backlog`, `Todo`, `In Design`, `In Progress`, `In QA`, `Done`, and the built-in "Auto-add to project" + "Item closed → Done" workflows enabled.

### Install

```bash
/plugin marketplace add judeProground/sillok
/plugin install sillok@sillok
```

### Initialize

```bash
cd /path/to/your-project
/sillok-init
```

`/sillok-init` auto-detects your repo, base branch, package manager, Projects v2 board, and gitignored config files, then writes `.claude/sillok/workflow.config.json`, scaffolds the rule files, installs command shims, appends an import block to your `CLAUDE.md`, and proposes `area:*` labels from your directory tree. It asks at most two questions per run and is fully idempotent — re-run it any time to pick up plugin upgrades.

## Commands

| Command | What it does | Board status |
|---------|--------------|--------------|
| `/sillok-add` | Capture a backlog issue (no branch/worktree) | `Backlog` |
| `/sillok-start` | Create issue + Issue Type + assignee + linked branch + worktree | `Todo` |
| `/sillok-start <N>` | Adopt an existing issue (full setup) | `Backlog → Todo` |
| `/sillok-design` | Brainstorm + write the spec, paste it into the issue | `In Design` |
| `/sillok-execute` | Write the plan, run subagent-driven build + verify-gate | `In Progress` |
| `/sillok-end` | Open the PR (`Closes #N`), self-assign | `In QA` |
| `/sillok-story` | Create or promote a Story (integration branch + worktree) | — |
| `/sillok-epic` | Validate a team PRD and create a cross-repo Epic | — |
| `/sillok-prd` | Snapshot a completed PRD into the spec repo (record-only) | — |

Every command works two ways: the short `/sillok-start` shim (installed by `/sillok-init`) or the canonical namespaced `/sillok:sillok-start` — the shim resolves the latest installed version at runtime.

## Concepts

### Stories — multi-PR features

A **Story** is an in-repo composite: one parent issue (Type `Story`) plus a real integration branch and worktree. Sub-features cut from and PR back into the integration branch; the Story itself merges to the base branch with a merge commit, preserving each sub-feature's history.

```bash
/sillok-story                      # on main → create Story + integration branch + worktree
/sillok-start --parent <story-N>   # each sub-feature cuts from the story branch
# ...PR each sub-feature into the story, then:
/sillok-end                        # opens the story → main PR (merge-commit recommended)
```

Started something as a plain feature and it grew too big? Run `/sillok-story` from inside the feature branch to promote it — the Issue Type flips to `Story` and the branch is renamed.

### Cross-repo PRDs — epics

For product work spanning multiple repos, a PRD can live as an `Epic` issue in a dedicated spec repo (configured via `epicRepo`). Code repos then attach sub-features across repositories:

```bash
/sillok-start --parent owner/projects#42   # sub-feature linked to a cross-repo Epic
```

This completes the `Epic → Story → Feature` hierarchy across repositories. Cross-repo `Closes #N` isn't honored by GitHub, so PRD closure stays a deliberate manual step.

## In practice

- **You can reconstruct any feature later.** The issue carries the spec, the key decisions, the plan, and the PR — reading one issue tells the whole story with no archaeology across tools.
- **Decisions survive the session.** Even work run under full-auto records its judgment calls in the issue's `## Key decisions`, so "why did we do it this way?" has an answer.
- **Onboarding and handoff get easier.** A consistent pipeline means anyone — or any agent — can pick up where another left off, and the board status says exactly where a feature stands.
- **The board reflects reality on its own.** Because sillok sets status at each stage and GitHub closes issues on merge, the project board stops drifting from the code.
- **Less tool-switching.** Spec, tracking, and code share one GitHub thread instead of scattering across Notion, a tracker, and git.

## Configuration

`/sillok-init` writes `.claude/sillok/workflow.config.json` — the only file sillok reads from your project. Key fields:

| Field | Purpose |
|-------|---------|
| `repo`, `baseBranch` | Target repo and the branch features are cut from |
| `branchPrefix` | Branch template, e.g. `{type}/issue-` |
| `orgMode` | `true` for org repos (Issue Types + Projects v2), `false` for personal (label fallback) |
| `project.*` | Projects v2 binding — owner, number, Status/Priority field + option mappings |
| `types.*` | Issue Types sillok expects (`Epic` / `Story` / `Feature` / `Task` / `Bug`) |
| `epicRepo` | Optional separate repo where Epic/PRD issues live (cross-repo work) |
| `automation.fullAuto` | Chain stages unprompted (never merges); absent = propose mode |
| `worktree.*`, `install` | Worktree behavior + post-create install command |
| `verify.*` | lint / typecheck / format commands the verify-gate runs |
| `labels.*`, `milestone.*` | Label taxonomy (natures / areas / priorities) + sprint-milestone naming |
| `language` | Body-generation language: `auto` / `ko` / `en` |

A JSON Schema (`schema/v1.json`) is referenced via `$schema` so editors offer validation.

## How it works

- **Thin commands, skills do the work.** Each `/sillok-*` command is a ~15-line pointer; the real procedure lives in `skills/<stage>/SKILL.md`, and a `sillok:workflow` orchestrator owns the stage chain (propose mode by default; full-auto stops after PR creation and never merges).
- **Deterministic state in bash, judgment in the skill.** Expensive state derivation (current branch, issue metadata, plan task counts) runs in `precompute-*.sh` scripts that print one markdown block the skill reads as ground truth — cheaper and more reliable than LLM shell round-trips.
- **A SessionStart hook** injects a compact context block (automation mode, branch ↔ issue) into every session of a configured project — silent and network-free outside sillok projects.
- **Engineering maturity.** The plugin holds itself to the rigor it enforces. Skill prompts were reviewed against skill-writing best practices — single-sourced contracts, irreversible-mutation steps extracted into guarded helpers, progressive-disclosure subfiles, and command-surface guard tests. In v4.0.0 the always-mounted rule set was reclassified into on-trigger skills, cutting the context injected into every session by ~67% (≈8,000 → 2,650 tokens) with no workflow change.

## What gets installed

After `/sillok-init`, everything sillok owns lives under `.claude/sillok/` plus pointer shims under `.claude/commands/`:

```
your-project/
├── .claude/
│   ├── sillok/
│   │   ├── workflow.config.json
│   │   └── rules/            # workflow, commit, output-language (resident) + browse-only stubs
│   └── commands/
│       └── sillok-*.md       # shim commands (sillok-shim: true — refreshed by re-init)
├── docs/superpowers/
│   ├── specs/                # design specs
│   └── plans/                # implementation plans
└── CLAUDE.md                 # @-import block appended
```

Your own `.claude/rules/`, other commands, and files are left untouched.

## Roadmap

- **A GitHub repo as a team's single source of truth.** Beyond dev issues, grow a repo into the home for PRDs, ADRs, and cross-team documents — the durable knowledge base a team actually works from.
- **Automated doc authoring.** Extend sillok so the same spec-driven flow that produces feature issues also helps draft and maintain those PRDs and ADRs — capturing decisions as they're made, not reconstructed after the fact.
- **Agent-ready delegation.** With the workflow made explicit and recorded, hand an entire feature to an agent that runs the same pipeline — issue, spec, plan, PR — under the same guardrails a human follows.

## License

MIT — see [LICENSE](LICENSE).
