# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

This is **sillok** — a Claude Code plugin, not an application that uses one. The unit of shipping is a `.claude-plugin/plugin.json` manifest plus the slash commands, skills, scripts, schema, and rule templates that get installed into _other_ projects via `/plugin marketplace add judeProground/sillok`.

Concretely, the plugin is six slash commands under `commands/`, three skills under `skills/`, helper bash scripts under `scripts/`, a JSON config schema in `schema/v1.json`, and the rule + config templates copied into consumer projects by `/sillok-init` (under `templates/`).

Do **not** run `/sillok-init` inside this repo — it's for downstream projects, not for the plugin's own development.

## Common commands

```bash
# Run the full test suite (bash unit tests; no harness, just executable scripts)
for t in tests/*.test.sh; do echo "=== $(basename $t) ==="; bash "$t" 2>&1 | tail -2; done

# Run a single test
bash tests/pick-areas.test.sh

# Smoke-test a script end-to-end against a temp project (most tests do this internally)
# All scripts expect CLAUDE_PLUGIN_ROOT to point at the repo root:
export CLAUDE_PLUGIN_ROOT=$(pwd)
bash scripts/precompute-start.sh
```

There is no build step, lint command, or package manager — this is pure bash + markdown + JSON.

## Architecture

### Command → precompute-script → config-lib pattern

Each `commands/sillok-*.md` is a markdown prompt that Claude runs. The expensive deterministic state derivation (current branch, issue metadata, labels, plan task counts, CWD-vs-worktree drift, etc.) is delegated to a sibling `scripts/precompute-<command>.sh` script that prints a markdown block. The command then reads that block as ground truth and only handles the LLM-judgment portions (brainstorming, body composition, user confirmation).

Why: bash is much cheaper than LLM tool round-trips for state checks, and printing one markdown block avoids spending the conversation context on multi-step shell inspection. When adding a new code-path that needs git/gh state, add it to the matching `precompute-*.sh` rather than putting `gh issue view` inside the command markdown.

### Config resolution: project overrides plugin default

`scripts/lib/config.sh` is the single config reader. Every script sources it and calls `sillok_config <key>` / `sillok_config_array <key>` / `sillok_config_required <key>`. Precedence:

1. `<git-root>/.claude/sillok/workflow.config.json` (consumer project)
2. `${CLAUDE_PLUGIN_ROOT}/templates/workflow.config.json` (plugin fallback)

Inside this repo's own tests, `CLAUDE_PLUGIN_ROOT` is set to the repo root so the template acts as the default; test cases construct temp projects with their own `.claude/sillok/workflow.config.json` to exercise the override path (see `tests/config.test.sh`).

When adding a config key: update `schema/v1.json` AND `templates/workflow.config.json` together — the schema validates editor autocomplete, the template is the runtime default.

### Branch-prefix templating

`branchPrefix` is a template, not a literal. `sillok_branch_prefix_resolve <type> [user]` substitutes `{type}` and `{user}` placeholders to produce concrete prefixes (`feature/issue-`, `bug/issue-`, `story/issue-`, etc.). `sillok_branch_prefix_regex` builds the inverse — a regex with a `(feature|bug|...)` alternation, used by precompute scripts to parse branch names back into issue numbers.

When walking `BASH_REMATCH` after that regex: the `{type}` alternation injects a capture group BEFORE the issue number, so loop over `BASH_REMATCH[@]:1` and grab the first numeric capture as the issue number — don't hardcode indices. See the loop in `scripts/precompute-end.sh:46-65`.

### Story = integration branch

A story in sillok is a parent tracking issue PLUS a real `story/issue-<N>-<slug>` branch PLUS a worktree. Sub-features cut from and PR back to the integration branch; the story PR then merges to base with `--merge` (preserving sub-feature commits), not `--squash`. This is enforced across three commands:

- `/sillok-story` creates the integration branch + pushes it to origin.
- `/sillok-start --parent N` looks up the parent's `## Integration branch` body section and passes that branch as the 3rd arg to `setup-feature-worktree.sh`.
- `/sillok-end` detects story-finalize mode when the current branch matches `story/issue-<N>-<slug>` and switches PR base + body template accordingly.

If touching any of these, keep the three in sync — drift breaks the parent-child branch graph silently.

### Idempotency contract

`/sillok-init` and `scripts/bootstrap-labels.sh` are explicitly idempotent. Re-running must:

- Not overwrite an existing `workflow.config.json` (print "already exists — edit manually").
- Not duplicate the CLAUDE.md import block (grep for the marker line first).
- Not recreate existing rule files (skip with notice).
- Not error on `gh label create` when labels already exist (mask with `|| true`).

Preserve this when modifying init/bootstrap logic. Consumer projects re-run `/sillok-init` to upgrade.

### Command shortcut shims

Claude Code namespaces plugin commands (`/sillok:sillok-start`). Users prefer the shorter `/sillok-start` form, which requires standalone-style files at `<project>/.claude/commands/sillok-*.md`. `scripts/write-shim-commands.sh` writes 5 pointer-only shim files during `/sillok-init`; each shim resolves the latest installed plugin version at runtime (`ls -d ~/.claude/plugins/cache/sillok/sillok/*/ | sort -V | tail -1`) and delegates to the canonical command. So plugin upgrades require no re-init for shim freshness.

The `sillok-shim: true` frontmatter marker identifies sillok-managed shims for idempotent refresh. Foreign files at the same path (no marker) are preserved untouched — users can write their own custom command at `.claude/commands/sillok-start.md` and sillok will skip it.

### Area-label detection

`/sillok-init` Step 8b scans the project across five layout families (FSD `src/{entities,features,widgets,pages,slices,modules}/<name>/`, `app/<route>/`, `modules/<name>/`, `packages/<name>/`, `apps/<name>/`) and auto-picks slice candidates for `area:<name>` GitHub labels (filter: rank ≥ 2 AND top 15). Existing non-empty `labels.areas` in config is preserved on re-init.

Detection runs in `scripts/detect-slices.sh`; the rank-filter lives in `scripts/pick-areas.sh` (NOT inline awk in the spec). Reason: agent-readers of markdown specs strip bare `$1` / `$2` tokens in inline code blocks, corrupting any inline awk filter into `'... >= 2 { print }'`. Keep `$N`-using awk inside scripts that the agent calls, not reads. See #11 for the bug that surfaced this.

## Bash conventions

- **macOS bash 3.2 compatibility.** No `mapfile`, no `readarray`, no `${var,,}` lowercasing. Use the `while IFS= read -r line; do arr+=("$line"); done < <(cmd)` pattern instead. The example is at the top of `scripts/lib/config.sh`.
- All scripts use `set -euo pipefail`.
- All scripts that read config source `lib/config.sh` via `SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd); source "$SCRIPT_DIR/lib/config.sh"` (NOT relative to `${CLAUDE_PLUGIN_ROOT}` — scripts must work when invoked directly from tests).
- `.editorconfig`: 2-space indent, LF endings, trim trailing whitespace, final newline. Markdown files keep trailing whitespace (intentional for line breaks).

## Release process

Versions live in **three** places that must move together. Bumping git tag alone is not sufficient — Claude Code reads manifest versions to detect updates:

- `.claude-plugin/plugin.json` → `version`
- `.claude-plugin/marketplace.json` → `plugins[0].version`
- `CHANGELOG.md` → new entry under `[Unreleased]`

Grep for the old version string before each release: `grep -rn "$OLD_VERSION" .claude-plugin/ CHANGELOG.md`. After tag push, also run `gh release create v$NEW_VERSION` for marketplace discoverability.

## Skills bundled

- `sillok:verify-gate` — whole-branch verification (lint/typecheck/format → code-reviewer subagent → simplify). Required at end-of-plan in `/sillok-execute`.
- `sillok:verify-spec-gate` — spec-compliance reference (patterns.md, principles.md, smells.md as on-demand subfiles).
- `sillok:gh-issue-management` — canonical procedure for issue creation/triage/linking; substitutes `${REPO}` / `${OWNER}` / `${NAME}` from config at runtime.

Skills are loaded by Claude Code from the plugin's `skills/` directory automatically once the plugin is installed in a consumer project. The plugin itself does not invoke them; downstream `superpowers:*` skills and the slash commands do.
