# Changelog

All notable changes to sillok are documented in this file. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/). This project adheres
to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [3.3.2] — 2026-06-24

### Fixed
- **`/sillok-story` promotion no longer renames with an empty branch (#51).** Step 1 lost its `branch=$(git branch --show-current …)` capture in the 3.x refactor wave, so §3 promotion ran `git branch -m "$branch" …` with an empty var — the old branch was never renamed, pushed, or deleted (promotion broke mid-rename). The capture is restored alongside `$REPO`/`$BASE_BRANCH`.
- **`/sillok-epic` re-sync no longer fails with HTTP 422 (#51).** Step 6 committed the PRD via a bare contents `PUT` with no `sha`, so re-syncing an already-committed PRD (an updated Notion/local source) 422'd; the existence handling was a non-runnable comment. It now fetches the existing blob sha and conditionally passes `-f sha=`, creating-or-updating.
- **`/sillok-start` & `/sillok-add` restore the `--label area:<name>` slot (#51).** The copyable `create-issue.sh` block had its area slot demoted to prose in the #36 dedup, so org-mode issues (type → REST, priority → board field) were created with zero labels. The visible slot is back in the block. `story` is intentionally excluded — Story/Epic parents carry no area/nature labels by convention.

### Added
- **`tests/skill-area-slot.test.sh` regression guard (#51).** Asserts the `start`/`add` create-issue.sh blocks keep a visible `--label "area:<name>"` slot, closing the root-cause test gap that let the area-label regression ship: no test asserted the skill prompt surface (only the script mechanics).

## [3.3.1] — 2026-06-18

### Refactored
- **`/sillok-epic` now creates its Epic via `scripts/create-issue.sh --plain` (#40).** Completes the #35 consolidation — epic was the one issue-creating skill still calling `gh api POST /issues` directly. `--plain` is a new bare-create mode that bypasses the helper's `orgMode` label/type fork: epic targets `epicRepo` (independent of the consumer's `orgMode`) and sets its Epic type via a non-fatal PATCH afterward, so it must not inherit consumer-mode labels.

### Fixed
- **`init/SKILL.md` intro prose corrected to the two-phase model (#40).** The auto-mode-contract paragraph still described the pre-#35 flat-step flow and named Step 8b as the tree emitter; phase1 emits the tree and Step 8b only reads it. Doc-only, no behavior change; the rewrite also drops a stray `MUST` on a procedural "every step must execute" line, which the emphasis-tiering rule #33 added reserves for irreversible-mutation gates.
- **`/sillok-init` stops on a phase1 hard failure (#40).** Added an explicit guard so a non-zero phase1 exit (missing `git`/`gh`/`jq` or a non-repo CWD) halts init and surfaces stderr instead of proceeding with empty status vars — matters most under auto-mode, where nothing else watches the stderr soft-contract.

## [3.3.0] — 2026-06-18

### Added
- **`/sillok-story` is now epic-aware.** It auto-suggests open Epics from `epicRepo` (same prompt shape as `/sillok-start` Step 4) and accepts `--parent <epicRepo#N>` to link the story as a cross-repo sub-issue via `addSubIssue`, completing the epic → story → feature hierarchy.
- **`scripts/precompute-story.sh`** — new precompute script for `/sillok-story`: derives branch-mode (new vs. promote) and emits the `### Open epics` block, following the skill → precompute-script pattern.
- **`scripts/lib/epics.sh`** — shared Open-epics discovery library (`sillok_open_epics_section`); the `### Open epics` block is now sourced from this shared lib by precompute-start, precompute-add, and precompute-story (no duplication).

### Documented
- **`/sillok-start`'s epicRepo auto-suggest** (present since 3.1.0) is now documented in `CLAUDE.md` and `CHANGELOG.md`. Previously the behavior shipped but was not mentioned in any doc.

## [3.2.0] — 2026-06-18

Behavior-preserving quality pass over the skills + scripts (story #31). No
user-facing workflow change.

### Changed
- **Skill bodies: dropped changelog framing, tiered emphasis, trimmed descriptions (#33).** `SKILL.md` files are always-loaded instructions, so they now state the current rule + durable reason instead of narrating edit history ("now / prior / an earlier version / removed") — across `verify-gate`, `execute`, `init`. Demoted the two procedural CAPS in `execute` Step 4; irreversible-mutation gates (no-auto-merge, link-before-push, failure-demotion, propose gate) stay loud. Trimmed the redundant eight-flow enumeration in `gh-issue-management`'s description. Documented both conventions ("emphasis tiering", "no changelog in bodies") in `plugins/sillok/CLAUDE.md`.

### Refactored
- **Extracted `init`'s deterministic bash into `scripts/init-bootstrap.sh` (#35).** `skills/init/SKILL.md` dropped 674 → 365 lines; the detect/config/rules/shims/labels/project/priority/dirs work now lives in a standalone **two-phase** script that prints a `KEY=value` status block the skill reads with a field-reader (the two interactive/LLM steps — empty-case URL prompt, area-label classification — stay in the skill). Matches the existing skill → precompute-script pattern.
- **Added `scripts/create-issue.sh` (#35).** Centralizes the `orgMode`-branched `gh api POST /issues` block that was duplicated across `/sillok-start`, `/sillok-add`, `/sillok-story`; reads `orgMode` from config itself and owns the API-version header.
- **Deduped the `## Integration branch` parse into `sillok_parent_integration_branch` (#35)** in `lib/config.sh`, shared by `/sillok-start` Step 9b and `/sillok-end` PR-base resolution.

### Fixed
- Three intended micro-improvements surfaced during the refactor (no change on default config): the empty `worktree.copyFiles` case writes `[]` instead of the latent `[""]`; `/sillok-story`'s user-mode priority label follows `labels.defaults.priority` instead of a hardcoded `p3`; `/sillok-init` re-run honors a pasted board URL instead of silently dropping it.

## [3.1.0] — 2026-06-17

### Added
- **`/sillok-epic` — validate a team PRD and create a light Epic in `epicRepo` for cross-repo parenting.** Reads a team PRD by path (`<category>/<project-name>/prd.md` in `epicRepo`), an interactive picker over discovered `*/prd.md`, or a Notion URL (when the Notion MCP is available), validates it against the team PRD convention (5 sections 배경/목표/실행/AI Agent Role/평가 + required frontmatter metadata + machine-parseable fields; required items block, recommended items warn), then creates a GitHub `Epic` issue in `epicRepo`. The Epic body is intentionally **light** — `## Summary` + `## Metadata` + `## PRD` (a link to the PRD path, plus the Notion source when synced), not the full PRD inline — and the command returns the `/sillok-start --parent <epicRepo>#<N>` line so sub-feature issues in other repos can parent to it.
- **Rewrote the stale Epic template** in `templates/rules/gh-issue-conventions.md` to the team PRD format: the light Epic body shape (`## Summary` / `## Metadata` — 피쳐목표·Main/Sub·Sprint·개발기간·담당자·상태·숫자·출시일·평가 예정일 / `## PRD` link) plus a note that the PRD lives at `<category>/<project-name>/prd.md` in `epicRepo` (a living doc) and the Epic links to it rather than embedding it. Consumer projects pick up the refreshed template on the next `/sillok-init` re-run.
- **Renamed `prdRepo` → `epicRepo`** (and `types.defaults.prd` → `types.defaults.epic`); PRDs are discovered generically at `<category>/<project-name>/prd.md` — no flat dir, no hard-coded category list. `/sillok-init` re-run migrates the legacy keys automatically (`scripts/migrate-config.sh`).

## [3.0.4] — 2026-06-17

### Fixed
- **`/sillok-end` now self-assigns the PR to its author.** `gh pr create` was missing `--assignee`, so PRs were created with no assignee even though the issue is self-assigned at `/sillok-start`. The create call now passes `--assignee "@me"`, mirroring the issue self-assign convention. Covers all modes (single-issue, umbrella, story-finalize) since Step 6 is the single create call.

## [3.0.3] — 2026-06-15

### Fixed
- **The `Priority` section in the `gh-issue-conventions` rule template is now org-mode aware (#20).** It previously documented priority only as `p1`–`p4` labels, contradicting the actual org-mode behavior where priority lives on the org-level **Priority issue field** projected onto the board (set by `/sillok-start` Step 10c via `sillok_issue_priority_set`, provisioned by `/sillok-init`) — org repos never get `p1`–`p4` labels (`bootstrap-labels.sh` skips them). The section now branches on `orgMode`, mirroring how the Type (REST) and Stage (Projects v2 field) sections document their mechanics: org repos get the issue-field table (`p1`–`p4` → `Urgent`/`High`/`Medium`/`Low` via `project.priorities`), user repos keep the `p1`–`p4` label list. Docs-only; consumer projects pick up the refreshed section on the next `/sillok-init` re-run (`refresh-rules.sh`).

## [3.0.2] — 2026-06-12

### Fixed
- **org-mode Priority now uses GitHub's org-level Issue Fields, not regular project fields (#17).** On real org boards the "Priority" column is an org Issue Field *projected* onto the board — through the old Projects v2 API it reads as a single-select with `options: []` and item values `null`, so the `updateProjectV2ItemFieldValue` mutation shipped in 3.0.0 (#66) could never set it (priority failed silently). sillok now discovers the field via `organization.issueFields` and sets values on the issue via `setIssueFieldValue` (no board item-id lookup needed).
  - **`/sillok-init` no longer misjudges a healthy projection as a broken field.** The previous Step 9c treated the empty-options reading as "not a real single-select" and prompted a rename/delete — which silently severs the projection. That gate is removed.
  - **`/sillok-init` provisions the org Priority issue field when absent** via `createIssueField` (options Urgent/High/Medium/Low, colors PINK/RED/YELLOW/GREEN) and projects it onto the board — org Priority issue fields cannot be created in the GitHub GUI (preview, API-only). Creation needs org-admin permission; without it the step warns and continues (non-fatal).
  - `project.priorityField` now names the **org issue field**, not a board field; `project.priorities` option names are unchanged (no schema migration). Re-run `/sillok-init` on org repos to create/verify the field.

## [3.0.1] — 2026-06-11

### Fixed
- **Consumer shims are now marketplace-name-agnostic.** The shim's version-resolution one-liner hardcoded a `cache/sillok/sillok/<version>/` path, so shims went blind once sillok was installed from a differently-named marketplace. Shims now glob `cache/*/sillok/*/` and sort by the **version segment** (a plain path sort would let the marketplace name dominate), so the latest installed version wins across marketplaces. **Re-run `/sillok-init` once after reinstalling** to refresh the shims in each consumer project.

### Changed
- Schema/manifest URLs point at the plugin's home: `plugin.json` homepage/repository and the config `$schema` / schema `$id` (`https://raw.githubusercontent.com/judeProground/sillok/main/schema/v1.json`). The `$schema` URL is used only for editor validation — runtime never fetches it.

## [3.0.0] — 2026-06-11

Major release: the skill-wrapper refactor (story #15) plus the backlog workflow (#33) and the org-mode Priority field (#66). Commands are now thin pointers; the substantive workflow lives in skills, with a new orchestrator, an automation mode, and a SessionStart hook. **No breaking changes for consumers** — all `/sillok-*` commands and existing shims keep working unchanged; the major bump reflects the architecture shift and the new auto-trigger surface.

> **Requires a recent Claude Code client** (developed and tested on 2.1.x). The plugin now relies on `${CLAUDE_PLUGIN_ROOT}` substitution inside SKILL.md content, the `user-invocable` skill frontmatter field, and automatic plugin-hook discovery (`hooks/hooks.json`). Upgrade Claude Code before upgrading sillok.

> **Upgrading consumer projects: re-run `/sillok-init` after updating.** It refreshes `.claude/sillok/rules/{sillok-workflow,pr-convention}.md` (which previously documented the dead `/sillok-epic` model), deep-merges the new config keys (`automation`, `project.statuses.backlog`, `project.priorityField`, `project.priorities`), and — **required for org-mode repos** — creates/maps the board's Priority field; until then, `/sillok-start` warns "priority not set" at the end of each run (non-fatal). The SessionStart hook itself ships with the plugin and needs no re-init; absent config keys fall back to safe template defaults, so skipping re-init degrades gracefully on user-mode repos. Re-init also installs the new `/sillok-add` shortcut shim — until then the namespaced `/sillok:sillok-add` works.

### Added (backlog workflow, #33)
- `/sillok-add` — lightweight backlog capture: issue + self-assign + board status `Backlog`, no branch/worktree/milestone.
- `/sillok-start <N>` adopt mode — pick up an existing issue with full environment setup, assignee/milestone backfill, and a soft gate on active statuses (board status and Priority are KEPT, never reset by adoption).
- `backlog` logical status in `project.statuses` (schema + template; existing consumer configs pick it up via per-key fallback or `/sillok-init` re-run).

### Added (org-mode Priority field, #66)
- Org repos manage priority on the board: `/sillok-start`/`/sillok-story` set the Projects v2 **Priority field** instead of `p1`–`p4` labels (hard switch, no dual-write; user repos keep labels unchanged). `bootstrap-labels.sh` skips p-labels in org mode.
- `/sillok-init` ensures the field: auto-creates a single-select `Priority` (Urgent/High/Medium/Low, p1→p4) when absent; when a board already has one with different option names, proposes the closest `project.priorities` mapping (one conditional question; auto-accepted in auto-mode). Neither sillok keys nor board options are renamed — the config mapping absorbs naming, mirroring `statuses`.
- `lib/project.sh`: shared single-select core for status + priority (the #47 guards, option-not-found guard, and malformed-id tripwire now protect both), `sillok_project_priority_field_ensure` (GraphQL `createProjectV2Field`), and colon-safe cache parsing for both the option and field caches.
- Deferred: migrating existing org `p*` labels into the field (`migrate-v1-to-v2.sh` untouched).

### Changed
- **All six commands refactored into skill packages (#15, #55–#58).** Each `commands/sillok-*.md` is now a ≤15-line version-stable pointer wrapper; the procedure bodies moved to `skills/{start,design,execute,end,story,init}/SKILL.md` with subfiles for bulky templates (`issue-body-template.md`, `story-mode.md`, `pr-body-templates.md`). Behavior equivalence was the migration bar — step-mapping diffs against the originals were reviewed per batch. Hard contracts, lint-enforced by three new tests: `${CLAUDE_PLUGIN_ROOT}` script invocations live in SKILL.md bodies only; wrappers never use `$ARGUMENTS`; each wrapper invokes its matching stage skill.
- **Stage skills carry deferral-marker descriptions** (`Internal sillok stage skill — enter via the /sillok-<stage> command or a sillok:workflow handoff`) and `user-invocable: false`, making the orchestrator the single auto-fire entry point.

### Added
- **`sillok:workflow` orchestrator skill (#55).** Owns the stage transition map (start → design → execute → end; story loop with a concrete sub-issue landed-check), reads the automation mode, and routes natural-language intent to the right stage. Propose mode confirms at chain entry and every stage boundary; failures always demote to propose mode.
- **`automation.fullAuto` config key.** Default `false` (absent == propose). When `true`, the chain runs without typed commands or mid-chain prompts — stage-internal confirmations are auto-resolved and every judgment is recorded in the issue's `## Key decisions`; the chain stops after PR creation and never merges; `end`'s dirty-tree/existing-PR prompts demote instead of bulldozing; verify-gate is never skipped.
- **SessionStart hook.** Injects a compact sillok context block (automation mode, branch ↔ issue) in sillok-configured projects. Hard contract: always exits 0, fully silent outside sillok projects and on any error, no network or `gh` calls. Ships with the plugin — no re-init needed.
- **Story integration branches are a sanctioned `--parent` start point**: `precompute-start.sh` no longer aborts on `story/issue-N-*` branches (emits a `STORY-BRANCH` proceed signal instead).

### Changed
- **Design stage has a single review gate (#64).** Key decisions are distilled BEFORE the spec confirmation and reviewed with it in one message — the separate key-decisions confirm loop is gone (recording afterwards is informational). The Language section gains a **Korean prose style contract** (complete sentences, no 개조식 noun endings, no idiom calques, backticked code tokens, 결정 → 이유 → 기각한 대안 order) so Korean specs stop reading like compressed logs.

### Fixed
- **Open Story/Epic suggestions were always empty on org repos (#41).** `precompute-start.sh` used the non-existent GraphQL `filterBy:{issueType}` argument and masked the rejection; both queries now use the Search API's `type:` qualifier (live-verified) and warn on stderr instead of failing silently. Guarded by a query-lint test.
- **Project status updates silently broke under zsh with multi-option boards (#65).** The option-cache loop re-declared `local` per iteration; zsh prints `name=value` on re-declaration, so from the second option onward values leaked into stdout and corrupted the GraphQL ids passed to `sillok_project_status_set`. Declaration hoisted; all four sourced libs audited (no other instances); hermetic 3-shell regression test added. Also fixed in passing: option-cache id parsing now splits on the LAST colon, so option names containing `:` resolve correctly.
- Consumer rule templates (`sillok-workflow.md`, `pr-convention.md`) modernized from the dead v1 `/sillok-epic` + `epic/issue-*` vocabulary to the story model; README's stale "zero-prompt init" and rank-threshold area-detection claims replaced with the actual at-most-two-questions hybrid flow.

## [2.4.1] — 2026-06-10

Patch release: four bug fixes found while dogfooding v2.4.0 (story #46).

> **Upgrading consumer projects: re-run `/sillok-init` after updating.** It refreshes `.claude/sillok/rules/gh-issue-conventions.md`, whose previous copy incorrectly claims dev-link branch linking is idempotent — it is create-only and must run **before** the first push. The stale rule is `@`-imported into your CLAUDE.md, so until refreshed it actively misinforms LLM sessions.

### Fixed
- **Linked branches were never created by `/sillok-start` or `/sillok-story` (#40).** GitHub's `createLinkedBranch` is create-only — once the branch exists on the remote it silently returns `null` — and sillok pushed before linking, so the Development panel stayed empty on every run while the helper swallowed the null as success. All three link sites now link **before** pushing (the promotion path additionally pre-pushes `HEAD` to the old branch name so the oid is reachable when local commits were never pushed), and `sillok_link_branch` warns loudly on null results, failed calls, and failed end-to-end verification (`linkedBranches(last: 50)`) — always non-fatal. Verified by a live API experiment. Stale "the helper is idempotent" claims in the `gh-issue-management` skill and the rule template are replaced with the create-only contract.
- **`config.sh` crashed with `unbound variable` when `CLAUDE_PLUGIN_ROOT` was unset (#45).** The env var is now optional: `config.sh` derives the plugin root from its own file location (cross-shell self-dir resolution; env var still wins when set). Bites direct script invocation and subshells; the normal command path was unaffected.
- **Lib sourcing still failed under zsh (#48) — completes the partial fix shipped in 2.4.0 (#37/#43).** The 2.4.0 idiom `${BASH_SOURCE[0]:-$0}` breaks under zsh sh-emulation (POSIX_ARGZERO resolves `$0` to `zsh`, so the lib dir becomes cwd and `config.sh` never loads) and trips nounset on zsh ≤ 5.8.1; the old compat test masked this by swallowing stderr and asserting only that functions were *defined*. All four libs now share an explicit shell-branch idiom (bash `${BASH_SOURCE[0]}`; zsh eval-deferred `${(%):-%x}`), and `tests/lib-zsh-compat.test.sh` asserts execution through the loaded chain under bash, zsh, and zsh sh-emulation with hermetic shells.
- **`sillok_project_status_set` could send malformed or empty-id mutations (#47).** Defensive hardening: empty `item_id` (the common case — issue not on the project board) and any id containing characters outside the GraphQL-id alphabet are refused loudly before any network call, instead of producing an opaque server-side error. Tripwire for resolver stdout pollution observed on a stale 1.2.x build; current resolvers are clean.

## [2.4.0] — 2026-06-09

### Added
- **`/sillok-init` auto-migrates config and rules on re-run (#34).** Re-running init now deep-merges new template keys into an existing `workflow.config.json` (preserving user values and arrays) via `scripts/migrate-config.sh`, and overwrites rule files from `templates/rules/` when their content differs via `scripts/refresh-rules.sh`. Previously a re-run left existing files untouched, so consumer projects could not pick up plugin upgrades without manual edits.

### Changed
- **Area-label detection reworked into a hybrid tree + LLM + confirm flow (#39).** Replaced the fixed layout-family scanner (`detect-slices.sh`) and rank-threshold filter (`pick-areas.sh`) with `scripts/project-tree.sh` — a deterministic directory-tree emitter (no fixed families, no depth cap) — plus LLM classification of vertical business areas vs. horizontal technical layers and a one-time confirmation before any `area:*` label is created (auto-accepted under auto-mode). Pruning combines a built-in junk set (incl. `target`, `__pycache__`, `venv`, `Pods`, and React Native's committed `android`/`ios`), all dot-dirs, and `.gitignore`-based exclusion via `git check-ignore` inside a git repo. This fixes detection on flat/backend layouts where features live under a singular `src/service/<feature>` or nested `src/service/v2/<feature>` and were previously labeled as layers (`area:controller`, `area:dto`, …).
- **`/sillok-end` no longer gates on plan-checkbox counts (#37).** Open `- [ ]` items in the plan file no longer block PR creation (subagent-driven execution doesn't tick them); the whole-branch verify gate covers completeness instead.

### Fixed
- **`/sillok-init` project auto-detection for projects owned by a different org than the repo (#35).** init now resolves a GitHub Project v2 even when it lives under a different owner than the repo; adds `scripts/parse-project-url.sh` and a single project-URL prompt as a fallback when auto-detection finds no board.
- **Library sourcing broke under zsh (#37).** `scripts/lib/*` sourcing is now zsh-safe, so commands work under both bash and zsh.

## [2.3.0] — 2026-05-28

### Fixed
- **`sillok_config_array` fallback broken when project config lacks an array key.** A `jq` empty result exited 0, triggering an early `return` that skipped the template default. Minimal consumer configs silently got empty arrays for `types.list`, `labels.natures`, etc. Now captures output and falls through when empty.
- **Projects v2 `EXCESSIVE_PAGINATION` error.** `sillok_project_item_for_issue` requested `items(first: 200)` (GraphQL caps `first` at 100). Rewritten to query from the issue side (`issue → projectItems`), so it works regardless of project size.
- **`SCRIPT_DIR` shadowing in lib modules.** `lib/project.sh`, `lib/issue-types.sh`, `lib/dev-link.sh` assigned `SCRIPT_DIR` at global scope, overwriting the caller's value — which broke `migrate-v1-to-v2.sh`'s sequential `source` chain. Renamed to module-scoped `_SILLOK_LIB_DIR`.
- **Worktree path with spaces.** The CWD-vs-worktree check in `precompute-{design,execute,end}.sh` parsed `git worktree list --porcelain` with `awk '{wt=$2}'`, truncating paths at the first space. Now strips the `worktree ` prefix to capture the full path.
- **Precompute abort on transient project-API failure.** `sillok_project_item_for_issue` calls in `precompute-{execute,end}.sh` lacked `|| echo ""`, so a network error aborted the whole precompute under `set -e`. Guarded.
- **Empty branch slug.** `slug-from-title.sh` emitted `<N>-` (trailing hyphen) for titles of only articles, punctuation, or non-ASCII characters. Now falls back to `issue-<N>`.
- **Non-English branch/worktree slugs.** Branch and worktree names are now kept ASCII/English even when the issue title is Korean (or any non-English language) — `/sillok-start` and `/sillok-story` translate the title to a concise English phrase for the slug, while the issue keeps its original-language title.
- **`worktree.copyFiles` flattened nested paths.** A configured `config/.env` was copied to the worktree root. Now preserves relative directory structure.
- **Spec match divergence.** `precompute-design.sh` used `head -1` (earliest) while `precompute-execute.sh` used `sort | tail -1` (latest) — they could resolve to different specs when one was rewritten on a later date. Both now pick the latest.
- **`migrate-v1-to-v2.sh` silent truncation.** Warns when the 500-issue fetch cap is hit so older issues aren't silently skipped.

### Added
- **Key Decisions section in issue body (#27)** — `/sillok-design` records key decisions inline.
- **Deviations and Review fixes sections in PR body (#29).**
- **`/sillok-design` support for Story issues (#30)** — umbrella story design mode.
- **Spec/plan files gitignored (#28)** — local working artifacts excluded; path references removed from issue/PR bodies (the issue body is the canonical record).

## [2.2.0] — 2026-05-27

### Added
- **Backend and single-family project support in area-label detection (#31).** `detect-slices.sh` now scans Go (`internal/`, `cmd/`, `pkg/`), Rust (`crates/`), and microservices (`services/`) layout families, plus a generic `src/` flat scan when no FSD subdirs exist (covers Python, Java, and other backend structures).
- **`pick-areas.sh` adaptive threshold.** When all candidates are rank 1 (single-family project), threshold drops to 1 so candidates are emitted instead of silently filtered. Multi-family projects retain the rank >= 2 cross-validation.

### Changed
- **CLAUDE.md** updated with v2 concepts (Issue Types, Projects v2, Development panel, lib/ modules).
- **README.md** prerequisites relaxed: personal repos supported via `orgMode: false`; added `language` and `orgMode` config docs; noted auto-detect project in `/sillok-init`.

## [2.1.0] — 2026-05-27

### Added
- **Language config for multilingual body generation (#19).** New `language` field in `workflow.config.json` (`auto`/`ko`/`en`). `auto` (default) matches the session language — Korean sessions produce Korean issue bodies, PR summaries, and specs. Section headers and structural markers stay English for parsing compatibility.

## [2.0.3] — 2026-05-27

### Fixed
- Removed legacy v1 stage label references from runtime files. Pipeline descriptions in `sillok-workflow.md` now show project status transitions (`Todo→In Design→In Progress→In QA`). Precompute script comments, command descriptions, and `gh-issue-management` skill updated accordingly.

## [2.0.0] — 2026-05-22

### Breaking
- **Type labels removed.** Categorical work types (`feature`, `bug`, `improvement`, `infra`, `epic`) are no longer labels. Issues use **GitHub Issue Types** (org-level), introduced in the 2026-03-10 API. Migration script: `bash scripts/migrate-v1-to-v2.sh <repo>` (re-runs idempotently).
- **Stage labels removed.** Lifecycle stage (`todo`, `designed`, `in-progress`, `in-review`) moved to **Projects v2 Status field**. The 5 expected status options: `Todo`, `In Design`, `In Progress`, `In QA`, `Done`.
- **`/sillok-epic` renamed to `/sillok-story`.** In-repo composite issues are now `Story` type, not `Epic`. `Epic` type is reserved for cross-repo PRD parents.
- **New required prerequisites:** an organization with Issue Types configured (admin sets up Epic + Story; Feature/Task/Bug auto-exist), and a Projects v2 board with the 5 Status options + auto-add and item-closed-to-Done workflows enabled.

### Added
- **Cross-repo PRD parent linking.** `--parent owner/repo#N` and full URL forms accepted by `/sillok-start`. Sub-issue API works across same-org repos. Open PRD epics auto-suggested when `epicRepo` config is set.
- **Auto-assignee.** `/sillok-start` and `/sillok-story` assign the gh-authenticated user (`@me`).
- **Linked branches (Development panel).** `/sillok-start` and `/sillok-story` push the new branch and register `createLinkedBranch` so the issue's Development panel populates from creation.
- **Nature label class.** `improvement`, `refactor`, `infra`, `docs`, `security`, `performance` — orthogonal to Issue Type.
- **Migration script.** `scripts/migrate-v1-to-v2.sh` for bulk re-labeling existing issues.

### Internal
- New helper libraries: `scripts/lib/issue-types.sh`, `scripts/lib/project.sh`, `scripts/lib/dev-link.sh`.
- Major rewrite of `skills/gh-issue-management/SKILL.md` and `templates/rules/gh-issue-conventions.md`.

### Migration (5-step procedure)
1. Update plugin: `/plugin update sillok`.
2. Org owner adds missing Issue Types (Epic, Story) via web UI or API.
3. Configure Projects v2 board with the 5 Status options + workflows.
4. Re-run `/sillok-init` in each project. Updates labels, verifies prerequisites.
5. Optionally bulk-migrate existing issues: `bash scripts/migrate-v1-to-v2.sh <repo> --apply`.

## [1.2.3] - 2026-05-20

### Fixed

- `/sillok-init` Step 3 no longer uses `eval` to import `detect-stack.sh` output. Values containing whitespace (e.g. `install=yarn install`) made the shell parse the line as a prefix-assignment followed by an `install` command — invoking BSD `/usr/bin/install` on macOS and running subsequent lines as standalone commands. Replaced with a `while IFS='=' read -r key val` loop. (#10, #12)
- `/sillok-init` Step 8b no longer inlines `awk -F'\t' '$2 >= 2 { print $1 }'`. Agent-readers of the markdown spec strip bare `$N` field references when they appear in code blocks, turning the filter into garbage and producing `area:4` GitHub labels in place of real names. The filter is now `scripts/pick-areas.sh`; the spec just pipes through it, so script internals are never read by the agent. (#11, #12)

## [1.2.2] - 2026-05-20

### Fixed

- `detect-stack` validates `lint`/`format`/`typecheck` against `package.json#scripts` for npm-family stacks (npm/yarn/pnpm/bun) instead of assuming conventional names. If the matching script doesn't exist, the field is left empty rather than producing a verify-gate command that fails at runtime. `typecheck` gains a `tsconfig.json` fallback to `npx tsc --noEmit` / `bunx tsc --noEmit`. (#7, #9)
- `worktree.copyFiles` detection no longer gets swallowed by `node_modules/` entries. Step 5 now pre-filters to candidate basenames via regex, excludes `node_modules`/`vendor`/`target`/`dist`/`build`/`out`/`coverage`/`.next`/`.turbo`/`.svelte-kit`/`.nuxt`/`.cache` prefixes, and uses a generous `head -200` safety bound instead of the old arbitrary `head -50`. Root-level `.env*`, `eas.json`, `google-services.json`, `GoogleService-Info.plist` and monorepo-nested variants are now correctly detected. (#8, #9)

## [1.2.1] - 2026-05-20

### Fixed

- `/sillok-init` no longer silently skips v1.2.0's new features when run via an auto-mode agent. (#5, #6)
  - Step 7b (shim install) is now marked REQUIRED with an explicit auto-mode contract in the init preamble; exit code is captured into `SHIM_STATUS`.
  - Step 8b no longer calls `AskUserQuestion` (which contradicted the init's "asks no questions" guarantee). Area labels are auto-picked non-interactively using `rank >= 2 AND top 15`. An existing non-empty `labels.areas` is preserved on re-init.
  - The final summary's headline (✅/⚠️/❌) is now computed from six sub-step status variables instead of always printing ✅. Each `Created:` line carries a `[status]` marker; a distinct area sub-summary is rendered per `AREA_STATUS` (auto-picked / none-detected / none-confident / skip-preserved / fail).

### Migration from 1.2.0

Re-run `/sillok-init` in any project initialized under v1.2.0. The new logic is idempotent: it will not overwrite `workflow.config.json`, will refresh shim files only if they carry the `sillok-shim: true` marker, and will preserve any non-empty `labels.areas` you already curated.

## [1.2.0] - 2026-05-20

### Added

- `/sillok-*` shortcut command shims. `/sillok-init` now writes pointer-only shim files to the project's `.claude/commands/sillok-{start,design,execute,end,epic}.md`, so users can type `/sillok-start` in place of the always-namespaced `/sillok:sillok-start`. Shims auto-resolve to the latest installed plugin version at runtime, so plugin upgrades require no re-init to refresh shim content. Idempotent: shims carrying the `sillok-shim: true` frontmatter marker are refreshed on re-init; any foreign file at the same path is preserved untouched. (#1, #3)
- Vertical-slice label detection. `/sillok-init` scans the project for domain folders across five layout families (FSD `src/{entities,features,widgets,pages,slices,modules}/<name>/`, `app/<name>/`, `modules/<name>/`, `packages/<name>/`, `apps/<name>/`), filters generic infrastructure names (`utils`, `components`, `hooks`, …), ranks candidates by how many families they appear in, and offers a multi-select prompt for opting into `area:<name>` GitHub labels. Selections persist to a new `labels.areas` field in `workflow.config.json`. (#2, #4)
- `scripts/detect-slices.sh` — bash 3.2-compatible scanner with 11 unit tests.
- `scripts/write-shim-commands.sh` — shim writer with 7 unit tests.
- `templates/command-shim.md.tmpl` — pointer-style shim template.
- `bootstrap-labels.sh --config <path>` — reads `labels.areas` and creates `area:<name>` labels with color `c9d4dd`.
- `schema/v1.json` — adds optional `labels.areas` array.

### Migration from 1.1.1

Re-run `/sillok-init` in any existing sillok project to pick up both features. The init is idempotent: it does not overwrite `workflow.config.json` or any scaffolded rule, only adds the new shim files under `.claude/commands/` and triggers the new slice-detection prompt.

## [1.1.1] - 2026-05-19

### Fixed

- Manifest version bump. v1.1.0 shipped with the correct file content but left `.claude-plugin/plugin.json` and `.claude-plugin/marketplace.json` reporting `"version": "1.0.0"`, which made `/plugin marketplace update` see no upgrade. This release bumps both manifest version fields so Claude Code recognizes the new release. No behavioral changes vs. 1.1.0.

## [1.1.0] - 2026-05-19

### Added

- Branch-prefix templating: `branchPrefix` now supports `{type}` and `{user}` placeholders. Default flipped from a username-based form to `"{type}/issue-"`, producing `feature/issue-42-add-x`, `bug/issue-67-fix-y`, etc.
- Integration-branch epics: every epic created with `/sillok-epic` now gets a real branch (`epic/issue-<N>-<slug>`) and a worktree. Sub-features cut from and PR back to the integration branch.
- Context-aware `/sillok-epic`: standalone creation on `main`/unrelated branches, plus in-place promotion of an existing feature/bug/improvement/infra branch into an epic (label flip, branch rename, body rewrite, optional work-in-progress extraction).
- `precompute-end.sh` recognizes a third mode (`epic-finalize`) when the current branch is the integration branch; the resulting PR base is the configured `baseBranch`, body contains `Closes #N` for the epic + each sub-feature, plus a `## Recommended merge` advisory.
- `sillok_branch_prefix_resolve` and `sillok_branch_prefix_regex` helpers in `scripts/lib/config.sh`.

### Changed

- `setup-feature-worktree.sh` accepts an optional third argument for the base branch (used when sub-features cut from an epic's integration branch).
- `/sillok-init` no longer derives a username-based prefix; the static template default `"{type}/issue-"` is used.
- `/sillok-end` resolves PR base dynamically: sub-features under an integration epic target the integration branch; epic-finalize PRs target the configured base branch.

### Migration from 1.0.0

Re-running `/sillok-init` is idempotent — it does NOT overwrite an existing `workflow.config.json`. To adopt the new default in an existing project, edit `.claude/sillok/workflow.config.json` and change `branchPrefix` to `"{type}/issue-"` (or keep your existing literal). Epics created under 1.0.0 (label-only, no branch) continue to work in tracking-only mode; they don't auto-acquire a branch.

## [1.0.0] - 2026-05-19

### Added

- Six slash commands: `sillok-init`, `sillok-start`, `sillok-design`, `sillok-execute`, `sillok-end`, `sillok-epic`.
- Three skills: `sillok:verify-gate`, `sillok:verify-spec-gate`, `sillok:gh-issue-management`.
- Zero-prompt project bootstrap via `/sillok-init`: detects repo, base branch, package manager, gitignored config files, and branch prefix automatically.
- Per-project configuration via `.claude/sillok/workflow.config.json` with JSON schema.
- Six scaffolded rule templates under `.claude/sillok/rules/`.
- Label bootstrap with a 14-label palette (5 types + 5 stages + 4 priorities).
