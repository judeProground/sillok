# Changelog

All notable changes to sillok are documented in this file. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/). This project adheres
to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.0.0] - 2026-05-19

### Added

- Six slash commands: `sillok-init`, `sillok-start`, `sillok-design`, `sillok-execute`, `sillok-end`, `sillok-epic`.
- Three skills: `sillok:verify-gate`, `sillok:verify-spec-gate`, `sillok:gh-issue-management`.
- Zero-prompt project bootstrap via `/sillok-init`: detects repo, base branch, package manager, gitignored config files, and branch prefix automatically.
- Per-project configuration via `.claude/sillok/workflow.config.json` with JSON schema.
- Six scaffolded rule templates under `.claude/sillok/rules/`.
- Label bootstrap with a 14-label palette (5 types + 5 stages + 4 priorities).
