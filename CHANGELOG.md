# Changelog

All notable changes to sillok are documented in this file. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/). This project adheres
to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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
- **Cross-repo PRD parent linking.** `--parent owner/repo#N` and full URL forms accepted by `/sillok-start`. Sub-issue API works across same-org repos. Open PRD epics auto-suggested when `prdRepo` config is set.
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
