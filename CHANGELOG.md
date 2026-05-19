# Changelog

All notable changes to sillok are documented in this file. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/). This project adheres
to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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
