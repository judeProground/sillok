# Changelog

All notable changes to sillok are documented in this file. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/). This project adheres
to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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
