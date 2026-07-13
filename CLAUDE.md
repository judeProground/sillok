# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

This is **sillok** — a Claude Code plugin, not an application that uses one. The unit of shipping is a `.claude-plugin/plugin.json` manifest plus the slash commands, skills, scripts, schema, and rule templates that get installed into _other_ projects via `/plugin marketplace add judeProground/sillok`. The repo doubles as its own single-plugin marketplace: the root `.claude-plugin/marketplace.json` registers this plugin with `source: "./"`.

Concretely, the plugin is eight thin wrapper commands under `commands/` (pointer-only; each invokes its stage skill), fourteen skills under `skills/` — eight workflow skills (`workflow` orchestrator + `start`/`add`/`design`/`execute`/`end`/`story`/`init` stage skills), three standalone skills (`epic`, `prd`, `fable-orchestra`), and three reference skills (`verify-gate`, `verify-spec-gate`, `gh-issue-management`) — a SessionStart hook under `hooks/`, helper bash scripts under `scripts/`, a JSON config schema in `schema/v1.json`, and the rule + config templates copied into consumer projects by `/sillok-init` (under `templates/`).

Do **not** run `/sillok-init` inside this repo — it's for downstream projects, not for the plugin's own development.

When running sillok commands or `precompute-*.sh` from a **worktree** in this repo, copy the (gitignored) self-hosting config in first — `cp .claude/sillok/workflow.config.json <worktree>/.claude/sillok/` — otherwise `sillok_config` reads nothing and scripts abort with "required config key not set".

## Common commands

```bash
# Run the full test suite (bash unit tests; no harness, just executable scripts)
for t in tests/*.test.sh; do echo "=== $(basename $t) ==="; bash "$t" 2>&1 | tail -2; done

# Run a single test
bash tests/project-tree.test.sh

# Smoke-test a script end-to-end against a temp project (most tests do this internally)
# CLAUDE_PLUGIN_ROOT is optional since 2.4.1 (config.sh derives the plugin root
# from its own file location). The export below is a convention INSIDE
# tests/*.test.sh files only — during skill execution it is never needed:
# SKILL.md bodies get ${CLAUDE_PLUGIN_ROOT} substituted at load time, and all
# scripts self-derive their root. Do NOT cargo-cult this export into ad-hoc
# Bash calls.
export CLAUDE_PLUGIN_ROOT=$(pwd)
bash scripts/precompute-start.sh
```

There is no build step, lint command, or package manager — this is pure bash + markdown + JSON.

## Architecture

### Skill → precompute-script → config-lib pattern

Each `commands/sillok-*.md` is a ≤15-line pointer wrapper; the substantive body lives in `skills/<stage>/SKILL.md` (the markdown prompt Claude runs). The expensive deterministic state derivation (current branch, issue metadata, labels, plan task counts, CWD-vs-worktree drift, etc.) is delegated to a sibling `scripts/precompute-<stage>.sh` script that prints a markdown block. The skill then reads that block as ground truth and only handles the LLM-judgment portions (brainstorming, body composition, user confirmation).

Why: bash is much cheaper than LLM tool round-trips for state checks, and printing one markdown block avoids spending the conversation context on multi-step shell inspection. When adding a new code-path that needs git/gh state, add it to the matching `precompute-*.sh` rather than putting `gh issue view` inside the skill markdown.

Two hard contracts from the refactor (story #15): `${CLAUDE_PLUGIN_ROOT}` script invocations live in SKILL.md bodies ONLY (substitution is guaranteed for skill content; subfiles like `skills/end/pr-body-templates.md` are read raw, so they stay pure prose/templates), and wrappers never use `$ARGUMENTS` (consumer shims raw-read them) — argument pass-through is prose. Both are lint-enforced (see Testing).

Stage chaining is owned by the `sillok:workflow` orchestrator skill: stage skills end with a one-line handoff ("invoke `sillok:workflow` to decide the next step"), and only the orchestrator knows the transition map and reads the `automation` config (`automation.fullAuto: true` runs start → design → execute → end unprompted, stopping after PR creation; absent key == propose mode). `init`, `add`, and `epic` sit outside the chain and are never auto-routed. Stage skills carry `user-invocable: false` and deferral-marker descriptions ("Internal sillok stage skill — enter via the `/sillok-<stage>` command or a `sillok:workflow` handoff"); the workflow skill is the single auto-fire entry point ("Use when..." trigger description).

### SessionStart hook

`hooks/hooks.json` registers `hooks/session-start.sh`, which injects a compact sillok context block (automation mode, branch ↔ issue) into every session of a sillok-configured project. Hard contract (it runs in EVERY consumer session): always exits 0; zero stdout/stderr when the config is absent, the CWD is not a git repo, or anything errors; no network and no `gh` calls — branch ↔ issue is derived locally via `sillok_branch_prefix_regex`. Guarded by `tests/session-start-hook.test.sh`.

### Config resolution: project overrides plugin default

`scripts/lib/` is a shared library directory with five modules. Every script sources the ones it needs via `SCRIPT_DIR=$(cd …) && source "$SCRIPT_DIR/lib/<module>.sh"`.

- **`config.sh`** — config reader (`sillok_config <key>` / `sillok_config_array <key>` / `sillok_config_required <key>`)
- **`epics.sh`** — shared Open-epics discovery (`sillok_open_epics_section`); queries `epicRepo` for open Epic issues and emits the `### Open epics` markdown block consumed by precompute-start, precompute-add, and precompute-story
- **`issue-types.sh`** — wraps the GitHub REST API for org-level Issue Types (v2)
- **`project.sh`** — wraps GraphQL mutations for Projects v2 (add item, set status) and the org Priority issue field (resolve/set/ensure via `setIssueFieldValue`/`createIssueField`)
- **`dev-link.sh`** — wraps `createLinkedBranch` GraphQL so issues show linked branches in the Development panel

Config precedence:

1. `<git-root>/.claude/sillok/workflow.config.local.json` (per-user override, **gitignored** — `sillok-init` adds it to `.gitignore`)
2. `<git-root>/.claude/sillok/workflow.config.json` (consumer project, committed)
3. `${CLAUDE_PLUGIN_ROOT}/templates/workflow.config.json` (plugin fallback; when the env var is unset, config.sh derives the plugin root from its own file location — #45)

The **local override** (layer 1, added #78) is per-developer and never committed. It exists because `workflow.config.json` is team-shared, but a few keys are personal working-style preferences — `qaBranch` (opt out of `/sillok-end`'s QA auto-merge), `automation.fullAuto`, `language`. Semantics differ from the other layers **on purpose**: a key **present** in the local file wins *even when its value is `""`* (an empty string is a real override — "turn qaBranch off for me" — not "unset"), whereas the project/template layers treat `""` as unset and fall through. This present-wins path is **scalar-only** (`sillok_config`); `sillok_config_array` deliberately ignores the local layer, since the array keys (`labels.*`) are team structure, not personal preference.

Inside this repo's own tests, `CLAUDE_PLUGIN_ROOT` is set to the plugin root (the repo root, derived in each test as the parent of `tests/`) so the template acts as the default; test cases construct temp projects with their own `.claude/sillok/workflow.config.json` to exercise the override path (see `tests/config.test.sh`).

When adding a config key: update `schema/v1.json` AND `templates/workflow.config.json` together — the schema validates editor autocomplete, the template is the runtime default. The `epicRepo` key (added in 3.1.0; a separate PRD/epic repo, e.g. `acme/projects`) is where `/sillok-epic` reads team PRDs from — at `<category>/<project-name>/prd.md`, discovered generically via a tree walk (no flat dir, no hard-coded categories).

### Branch-prefix templating

`branchPrefix` is a template, not a literal. `sillok_branch_prefix_resolve <type> [user]` substitutes `{type}` and `{user}` placeholders to produce concrete prefixes (`feature/issue-`, `refactor/issue-`, `story/issue-`, etc.). `sillok_branch_prefix_regex` builds the inverse — a regex with a `(feature|bug|...|refactor|story)` alternation, used by precompute scripts to parse branch names back into issue numbers.

When walking `BASH_REMATCH` after that regex: the `{type}` alternation injects a capture group BEFORE the issue number, so loop over `BASH_REMATCH[@]:1` and grab the first numeric capture as the issue number — don't hardcode indices. See the loop in `scripts/precompute-end.sh:46-65`.

### Story = integration branch

A story in sillok is a parent tracking issue PLUS a real `story/issue-<N>-<slug>` branch PLUS a worktree. Sub-features cut from and PR back to the integration branch; the story PR then merges to base with `--merge` (preserving sub-feature commits), not `--squash`. This is enforced across three stages:

- `/sillok-story` creates the integration branch + pushes it to origin.
- `/sillok-start --parent N` looks up the parent's `## Integration branch` body section and passes that branch as the 3rd arg to `setup-feature-worktree.sh`.
- `/sillok-end` detects story-finalize mode when the current branch matches `story/issue-<N>-<slug>` and switches PR base + body template accordingly.

If touching any of these, keep the three in sync — drift breaks the parent-child branch graph silently.

### Idempotency contract

`/sillok-init` and `scripts/bootstrap-labels.sh` are explicitly idempotent. Re-running must:

- Deep-merge an existing `workflow.config.json` via `scripts/migrate-config.sh` (add missing template keys, preserve user values, arrays verbatim).
- Scaffold `.claude/sillok/workflow.config.local.json` (#80) only when absent — never clobber a developer's customized override. The scaffold is inert (per-user keys documented under an `__overridable` key config.sh never reads, as default-stating description strings rather than value blocks that could read as active settings — #82), so a fresh file changes nothing.
- Not duplicate the CLAUDE.md import block (grep for the marker line first).
- Refresh rule files from `templates/rules/` via `scripts/refresh-rules.sh` (overwrite when content differs).
- Not error on `gh label create` when labels already exist (mask with `|| true`).

Preserve this when modifying init/bootstrap logic. Consumer projects re-run `/sillok-init` to upgrade.

### Command shortcut shims

Claude Code namespaces plugin commands (`/sillok:sillok-start`). Users prefer the shorter `/sillok-start` form, which requires standalone-style files at `<project>/.claude/commands/sillok-*.md`. `scripts/write-shim-commands.sh` writes 7 pointer-only shim files during `/sillok-init`; each shim resolves the latest installed plugin version at runtime — marketplace-agnostically, sorting by the version segment so the marketplace name can't dominate (`ls -d ~/.claude/plugins/cache/*/sillok/*/ | awk -F/ '{print $(NF-1), $0}' | sort -V | tail -1 | cut -d' ' -f2-`) — and delegates to the canonical command. So plugin upgrades require no re-init for shim freshness, and reinstalling from a different marketplace keeps old shims working.

The `sillok-shim: true` frontmatter marker identifies sillok-managed shims for idempotent refresh. Foreign files at the same path (no marker) are preserved untouched — users can write their own custom command at `.claude/commands/sillok-start.md` and sillok will skip it.

### Area-label detection

`/sillok-init` Step 8b (in `skills/init/SKILL.md`) detects `area:<name>` GitHub labels with a **hybrid**: `scripts/project-tree.sh` deterministically emits the project's pruned directory tree, then the LLM running the skill classifies which dirs are **vertical business areas** (`auth`, `wallet`, `cash-withdrawal`) vs **horizontal technical layers** (`controller`, `dto`, `entity`, `guard`, …) and proposes the area list. GitHub labels are created only after a one-time confirmation (auto-accepted under auto-mode). Existing non-empty `labels.areas` is preserved on re-init.

Pruning in `project-tree.sh` is three layers: (a) a built-in name set of build/tool + native-platform dirs that are never feature areas (`node_modules`, `dist`, `build`, `target`, `__pycache__`, `venv`, `Pods`, and — crucially for React Native, since they're *committed* — `android`/`ios`); (b) all dot-dirs (`.git`, `.venv`, `.gradle`, …); and (c) when inside a git repo, anything `git check-ignore` reports as ignored by the project's `.gitignore` (generalizes to every language's build junk without an exhaustive list). Dirs only, NO depth cap, ~500-line backstop with a truncation marker.

Why hybrid: a fixed-path heuristic can't tell a business domain from a technical layer and breaks on unanticipated layouts (`src/service/` singular, `src/service/v2/` nesting). Structure-gathering is deterministic and belongs in bash; domain-vs-layer is judgment and belongs in the LLM skill. The classifier output is reviewed (confirm gate) and lands in a git-tracked, editable config, so LLM non-determinism is bounded. See #39 for the bug that surfaced this; the deleted `detect-slices.sh`/`pick-areas.sh` were the rank-threshold approach that this replaces.

### v2: Issue Types + Projects v2 + Development panel

v2.0 replaced label-based type/stage tracking with GitHub-native primitives:

- **Issue Types** — `lib/issue-types.sh` calls the org-level REST API (`/orgs/:org/issue-types`) to set type (Feature, Bug, Task, etc.) on issues instead of `type:*` labels.
- **Projects v2** — `lib/project.sh` uses GraphQL to add issues to a project board and set the Status single-select field, replacing `stage:*` labels.
- **Development panel linking** — `lib/dev-link.sh` calls `createLinkedBranch` so branches appear in the issue's Development section without waiting for a PR.
- **Priority (v3, org issue field)** — `lib/project.sh` sets priority via `setIssueFieldValue` on the *issue*, NOT `updateProjectV2ItemFieldValue` on the board item. On org boards "Priority" is an org **issue field** projected onto the board: through the Projects v2 API it reads as a single-select with `options: []` / item values `null`, so the board-item mutation silently no-ops (the #66 → #17 bug). It's discovered via `organization.issueFields` and, when absent, created by `/sillok-init` via `createIssueField` — org Priority issue fields are **API-only, not GUI-creatable**, and creation needs org-admin (non-fatal warn without it). `project.priorityField` names this org issue field; `project.priorities` maps `p1`–`p4` to its option names.
- **Migration** — `scripts/migrate-v1-to-v2.sh` converts an existing v1 repo (removes old labels, sets Issue Types, moves items to a project).

`orgMode` in config gates these features: when `false` (user repos), Issue Types and project mutations are skipped since they require org-level APIs.

## Script index

| Script | Purpose |
|--------|---------|
| `precompute-{start,design,execute,end}.sh` | State derivation for each stage skill |
| `precompute-add.sh` | Lightweight state derivation for /sillok-add (no branch guard, no milestone section) |
| `precompute-story.sh` | State derivation for /sillok-story: branch-mode classification (new vs. promote) + open epics from epicRepo |
| `precompute-epic.sh` | State derivation for /sillok-epic: resolves epicRepo, classifies the source (path/picker/notion), and discovers `*/prd.md` candidates in epicRepo via a tree walk |
| `prd-snapshot.sh` | Record-only Contents API upsert of a completed PRD markdown into epicRepo at `<prd.basePath>/<domain>/<name>/prd.md` (no PR — commits straight to epicRepo's default branch); composes/quotes frontmatter, preserving `epic`/`review_at` across updates. Used by /sillok-prd and gihoek's prd-creator |
| `init-bootstrap.sh` | Two-phase deterministic bootstrap for /sillok-init: `phase1` (Steps 1–8: detect repo/stack/copyFiles, write config, rules, shims, CLAUDE.md, emit project-tree) + `phase2` (Steps 9–10: labels, project + priority field, spec/plan dirs). Prints a `KEY=value` status block on stdout the skill reads with a field-reader (Step 8b area classification + URL prompt stay in the skill, between the phases) |
| `create-issue.sh` | Creates a GH issue, branching on `orgMode` (org: `-f type=` + board Priority; user: type/priority labels) + the API-version header; prints the issue URL. Shared by /sillok-start, /sillok-add, /sillok-story; /sillok-epic passes `--plain` (bare create — bypasses the orgMode fork since epicRepo is cross-repo and its Epic type is PATCHed non-fatally after) |
| `setup-feature-worktree.sh` | Creates worktree + branch for a new issue |
| `qa-merge.sh` | Server-side merge of the feature branch into the configured `qaBranch` (called by /sillok-end Step 6b); non-fatal — every outcome exits 0 so the PR flow is never blocked |
| `bootstrap-labels.sh` | Idempotent GitHub label creation |
| `project-tree.sh` | Emits a pruned directory tree (junk-removed, no depth cap) for area-label classification |
| `detect-stack.sh` | Detects project tech stack (language, framework) |
| `parse-project-url.sh` | Parse a GitHub Project v2 URL into owner+number (used by /sillok-init empty-case prompt) |
| `slug-from-title.sh` | Converts issue title → kebab-case branch slug |
| `write-shim-commands.sh` | Writes shortcut command shims during init |
| `migrate-v1-to-v2.sh` | Migrates a repo from v1 (label-based types/stages) to v2 (Issue Types + Projects v2) |
| `migrate-config.sh` | Deep-merges template defaults into an existing project config (preserves user values) on `/sillok-init` re-run |
| `refresh-rules.sh` | Overwrites project rule files from `templates/rules/` when content differs, on `/sillok-init` re-run |
| `lib/config.sh` | Shared config reader (sourced by all other scripts); also `sillok_branch_prefix_*` and `sillok_parent_integration_branch` (the parent-story `## Integration branch` parse shared by /sillok-start Step 9b and /sillok-end PR-base resolution) |
| `lib/epics.sh` | Shared Open-epics discovery (`sillok_open_epics_section`) — emits the `### Open epics` block used by precompute-start, precompute-add, and precompute-story |
| `lib/issue-types.sh` | GitHub Issue Types REST API helpers |
| `lib/project.sh` | Projects v2 GraphQL helpers (add item, set status) + org Priority issue field (resolve/set/ensure) |
| `lib/dev-link.sh` | Development panel branch linking via GraphQL |

## Testing

Tests live in `tests/*.test.sh`. Each test is a standalone bash script that creates a temp directory, exercises one script, and prints `pass`/`fail` lines. To add a new test: create `tests/<script-name>.test.sh`, define `pass()`/`fail()` helpers, and follow the existing pattern of setting up a temp project with `CLAUDE_PLUGIN_ROOT` pointing at the plugin root (the repo root).

Three lint tests enforce the skill-wrapper architecture: `command-wrapper-lint.test.sh` (every `commands/sillok-*.md` is a ≤15-line pointer wrapper — no `${CLAUDE_PLUGIN_ROOT}`, no `$ARGUMENTS`, no `## Step`), `skill-frontmatter.test.sh` (stage skills declare `name` + `user-invocable: false` + a deferral-marker description; among the workflow-chain skills, only `skills/workflow` gets "Use when..." trigger phrasing — the three reference skills keep theirs), and `skill-subfile-lint.test.sh` (`${CLAUDE_PLUGIN_ROOT}` is forbidden in skill subfiles — substitution only happens in SKILL.md bodies). Markdown skill bodies themselves are LLM-executed, so structural contracts are grep-anchored against `skills/<stage>/SKILL.md` (e.g. `sillok-init-detection.test.sh`, `sillok-init-migration.test.sh`).

## Bash conventions

- **macOS bash 3.2 compatibility.** No `mapfile`, no `readarray`, no `${var,,}` lowercasing. Use the `while IFS= read -r line; do arr+=("$line"); done < <(cmd)` pattern instead. The example is at the top of `scripts/lib/config.sh`.
- All scripts use `set -euo pipefail`.
- All scripts that read config source `lib/config.sh` via `SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd); source "$SCRIPT_DIR/lib/config.sh"` (NOT relative to `${CLAUDE_PLUGIN_ROOT}` — scripts must work when invoked directly from tests).
- **Sourced libs may run under zsh** (Claude Code's Bash tool isn't always bash). The 3 sourced libs (`project`/`dev-link`/`issue-types`.sh) and `config.sh` resolve their own directory via an explicit shell branch — bash `${BASH_SOURCE[0]}`, zsh eval-deferred `${(%):-%x}` — because with `${BASH_SOURCE[0]:-$0}` the `$0` fallback breaks under zsh sh-emulation (POSIX_ARGZERO resolves `$0` to `zsh`, so the lib dir becomes cwd), and zsh <= 5.8.1 additionally trips nounset on the unset array subscript before the `:-` default applies. Sourced libs also avoid `BASH_REMATCH` (empty in zsh — use parameter expansion). `tests/lib-zsh-compat.test.sh` guards this, asserting execution through the loaded chain, not just function definition. Standalone scripts (shebang) always run under bash, so bare `${BASH_SOURCE[0]}` is fine there.
- `.editorconfig`: 2-space indent, LF endings, trim trailing whitespace, final newline. Markdown files keep trailing whitespace (intentional for line breaks).

## Skill prose conventions

`SKILL.md` bodies are always-loaded instructions, so prose discipline is part of the contract:

- **Emphasis tiering.** Reserve the strongest markers (`HARD GATE`, `NEVER`, `MUST`) for **irreversible-mutation gates** — never auto-merge (`end` Step 10), link-before-push ordering (`start` Step 10b, the create-only `createLinkedBranch`), full-auto failure-demotion (`workflow`), and "no first gh/git mutation before the user confirms" (`workflow` propose gate). Ordinary procedural steps get plain imperative + a one-clause reason, not caps. When every step shouts, the genuinely irreversible ones stop standing out.
- **No changelog in skill bodies.** State the *current* rule and the durable reason for it; don't write "now / previously / an earlier version / this was removed". Git history and `CHANGELOG.md` hold the edit trail — a model executing the skill only needs the rule that applies today.

## Reviewing a behavior-preserving refactor

A "does it still work?" pass is necessary but not sufficient for a refactor PR — behavior preservation is the *start* of the review, not the verdict. After confirming behavior, run three more lenses (the #40 post-mortem: the #35 refactor shipped with stale intro prose and a half-adopted helper that a behavior-only review never thought to look for):

- **(a) self-consistency** — does the rewritten prose accurately describe its *own* new structure? `init/SKILL.md` moved to a two-phase bootstrap but its intro still described the old flat-step model and named the wrong step as the tree emitter.
- **(b) convention-compliance** — does it honor conventions added *recently, possibly in a sibling PR*? #33 added the emphasis-tiering rule (reserve `MUST`/`NEVER` for irreversible-mutation gates) but missed `init`'s intro, which still carried a `MUST` on a procedural "every step must execute" line; the separate #35 refactor didn't catch it either. PR-isolated reviews miss this — cross-check against the conventions in this file, especially Skill prose conventions.
- **(c) completeness** — is the change fully applied, not partial? When a refactor extracts a shared helper, confirm *every* call site adopts it — or document why one legitimately can't (`/sillok-epic` bypasses `create-issue.sh`'s orgMode fork via `--plain`, on purpose).

## Release process

Versions live in **three** places that must move together. Bumping git tag alone is not sufficient — Claude Code reads manifest versions to detect updates:

- `.claude-plugin/plugin.json` → `version`
- `.claude-plugin/marketplace.json` → the sillok entry's `version`
- `CHANGELOG.md` → new entry under `[Unreleased]`

Grep for the old version string before each release: `grep -rn "$OLD_VERSION" .claude-plugin/ CHANGELOG.md`.

## Skills bundled

Workflow skills (story #15 refactor):

- `sillok:workflow` — stage orchestrator; the only workflow-chain skill with a "Use when..." auto-trigger description (the three reference skills keep their "Use when/Use after" descriptions by design). Owns the transition map (start → design → execute → end; story loop), reads `automation.fullAuto` (propose mode by default; full-auto chains stages unprompted and stops after PR creation, never merging), and never routes `init`.
- `sillok:start` — create GH issue + Issue Type + assignee + linked branch + worktree + project status Todo (subfile: `issue-body-template.md`); `/sillok-start <N>` adopts an existing issue (full env setup + backfill, Backlog → Todo, soft gate on active statuses).
- `sillok:add` — backlog capture: issue + Issue Type + self-assign + status Backlog; NO branch/worktree/milestone. Outside the workflow chain (never auto-routed, no handoff); promotion path is `/sillok-start <N>` adopt mode.
- `sillok:design` — brainstorm + spec, paste spec into issue body, status In Design (subfile: `story-mode.md` for story-design).
- `sillok:execute` — write plan, subagent-driven execution, end-of-plan verify-gate, status In Progress.
- `sillok:end` — push, PR per its own templates, status In QA, parent legacy-checkbox update; never auto-merges (subfile: `pr-body-templates.md`).
- `sillok:story` — create or promote-to a story (parent issue + integration branch + worktree); auto-suggests open Epics from `epicRepo` and accepts `--parent <epicRepo#N>` to attach the story as a cross-repo sub-issue via `addSubIssue` (completing epic → story → feature).
- `sillok:init` — project bootstrap; idempotent; outside the workflow chain (always interactive, never auto-routed).
- `sillok:epic` — validate a team PRD and create a light Epic in `epicRepo` for cross-repo parenting; outside the workflow chain (never auto-routed by `sillok:workflow`, no stage handoff). Reads PRDs at `<category>/<project-name>/prd.md` in `epicRepo` (generic `*/prd.md` discovery, no flat dir / hard-coded categories); invoked via `/sillok-epic <path>/prd.md` or `/sillok-epic <notion-url> <category>/<project>`.
- `sillok:prd` — record a completed PRD markdown into `epicRepo` as a `prd.md` snapshot via `prd-snapshot.sh` (Contents API upsert, no PR — review happens in Notion, not a git PR); outside the workflow chain (never auto-routed by `sillok:workflow`, no stage handoff). Invoked via `/sillok-prd`; the permalink it outputs is for humans/records, while `/sillok-epic <basePath>/<domain>/<name>/prd.md` (the epicRepo path) is what feeds Epic creation.
- `sillok:fable-orchestra` — standalone, prompt-only skill (no scripts/subfiles) for the "Fable orchestrator" pattern: on a Fable main-loop session, keep Fable a thin orchestrator and delegate by `model × effort` (Sonnet workers for bulk coding + long-document drafting, Opus workers for hard/long reasoning), with a cost/intelligence/taste rankings table and quality-escalation permission. Not a routed stage (no stage handoff), but `sillok:workflow` Step 2b applies it at chain entry on a Fable session; outside sillok flows its trigger description auto-fires on dispatch intent.

The seven stage skills (`start`/`add`/`design`/`execute`/`end`/`story`/`init`) plus the `epic` and `prd` standalone skills carry `user-invocable: false` — entered via their `/sillok-*` command wrapper (and, for stage skills, a `sillok:workflow` handoff). The stage skills additionally lead their description with the "Internal sillok stage skill — enter via the `/sillok-<stage>` command or a `sillok:workflow` handoff" deferral marker, pointing entry at the wrappers and the orchestrator. `fable-orchestra` and the three reference skills omit `user-invocable: false`; `fable-orchestra` is invoked directly as `sillok:fable-orchestra`.

Reference skills:

- `sillok:verify-gate` — whole-branch verification (lint/typecheck/format → code-reviewer subagent → simplify). Required at end-of-plan in `/sillok-execute`.
- `sillok:verify-spec-gate` — spec-compliance reference (patterns.md, principles.md, smells.md as on-demand subfiles).
- `sillok:gh-issue-management` — canonical procedure for issue creation/triage/linking; substitutes `${REPO}` / `${OWNER}` / `${NAME}` from config at runtime.

Skills are loaded by Claude Code from the plugin's `skills/` directory automatically once the plugin is installed in a consumer project. The wrapper commands, the `sillok:workflow` orchestrator, and downstream `superpowers:*` skills invoke them.
