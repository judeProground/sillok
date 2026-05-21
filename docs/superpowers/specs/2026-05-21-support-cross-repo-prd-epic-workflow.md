# Support cross-repo PRD epic workflow (v2)

**Issue:** [#14](https://github.com/judeProground/sillok/issues/14)
**Status:** Designed
**Authored:** 2026-05-21

## Background

Sillok currently assumes a **single-repo model**: spec lives in the issue body of the same repo where code lives, and the optional `epic` parent is also in that repo (with its integration branch alongside the code). This works for solo projects and single-repo teams.

It does **not** fit large orgs where PRD authorship and code authorship live in separate repos:

- PRDs are authored by PMs / planners in a dedicated repo (e.g. `myorg/prd`)
- Frontend and backend code live in separate code repos (e.g. `myorg/frontend`, `myorg/backend`)
- A single PRD usually fans out into work items across multiple code repos

Today such teams cannot use sillok's parent-linking primitives (`/sillok-start --parent N`) because `--parent` accepts only a same-repo issue number.

## Goal

Support a cross-repo PRD workflow where:

- The **PRD** lives as an `epic`-labeled issue in a dedicated PRD repo, with the PRD content stored both inline in the issue body and as a markdown file in the same PRD repo
- **Code-repo feature issues** reference the PRD epic as a cross-repo parent via GitHub's native sub-issue API
- Each code repo continues to be sillok-managed at the same level of fidelity as today (label state machine, branch + worktree per feature, PR with `Closes #N`)

Out of band: the PRD repo's own conventions are user-controlled — sillok reads from but does not write to the PRD repo.

## Hierarchy

```
PRD repo (myorg/prd)         Code repo (myorg/frontend)
─────────────────────         ─────────────────────────
[epic] PRD #42 ─────────────► [story] Composite #15  (optional composite layer)
                              │           │
                              │           ├─ [feature] #16
                              │           └─ [feature] #17
                              │
                              └─────────► [feature] #18  (direct child of PRD, no composite)
```

- **Epic** = PRD, lives in PRD repo only. Sillok never creates these (user / PM does).
- **Story** = optional in-repo composite. New name for what v1 called `epic` (in-repo). Always has an integration branch + worktree, like v1's epic.
- **Feature / bug / improvement / infra** = work-unit issues, each ships one PR. Can be a direct child of either a Story or a cross-repo PRD epic.

## Locked design decisions (from brainstorm 2026-05-21)

1. **Hierarchy:** PRD epic → Story (composite, optional) → Feature.
2. **PRD persistence:** PRD stored as both an issue (in PRD repo) and a markdown file in the same PRD repo. Sillok reads the issue body for the cross-repo parent context; the md file is for the user's diff history and version control. Sillok does not enforce a path convention for the file.
3. **Cross-repo `Closes #N`:** Stays manual. The PRD epic in the PRD repo is closed by the user when all linked work ships; sillok does not attempt cross-repo auto-close because the GitHub behavior is fragile across org / permission boundaries.
4. **Projects v2 integration:** Out of scope. Users wire up multi-repo Project boards themselves.
5. **Label rename:** `epic` → `story` for the in-repo composite role. `epic` is reserved (semantically) for the cross-repo PRD layer.
6. **Command rename:** `/sillok-epic` → `/sillok-story` (file rename + body wording change). Behavior identical to v1's `/sillok-epic` — creates composite issue + integration branch + worktree.
7. **PRD integration depth:** "Light" — sillok adds a `prdRepo` config field and auto-suggests open PRD epics during `/sillok-start`. Sillok does not create / modify / close PRD issues. (A future `/sillok-prd` command for tighter PRD lifecycle handling is deferred to v3 — see *Out of scope*.)
8. **Issue Types:** Out of scope. GitHub's native Issue Types feature is org-only, requires admin setup the maintainer does not have, and lacks gh CLI support (`cli/cli#9696` still open). Sillok continues to use labels.

## Architecture overview

### Config schema additions (`schema/v1.json`, `templates/workflow.config.json`)

```jsonc
{
  "prdRepo": "myorg/prd",  // optional. Empty = cross-repo PRD features disabled.
  "labels": {
    "types": ["feature", "bug", "improvement", "infra", "story"]
    //                                                   ^^^^^ renamed from "epic"
  }
}
```

- `prdRepo` is **optional**. When empty (default), sillok behaves like v1 — `--parent N` accepts only same-repo issue numbers. When set, sillok enables cross-repo parent UX (auto-suggestion, validation).
- `/sillok-init` does **not** auto-detect `prdRepo` (it's an org convention, not derivable from code). Init leaves the field empty and prints a one-line hint in its Step 11 summary: *"Cross-repo PRD: set `prdRepo` in workflow.config.json if your team uses a dedicated PRD repo"*.

### Cross-repo `--parent` syntax

`/sillok-start` accepts three `--parent` forms:

| Form | Resolves to |
|---|---|
| `--parent 42` | Same-repo issue #42 (v1 behavior, unchanged) |
| `--parent myorg/prd#42` | Cross-repo issue #42 in `myorg/prd` |
| `--parent https://github.com/myorg/prd/issues/42` | Same as above (URL form) |

When `prdRepo` is configured, the `precompute-start.sh` "Open epics" section lists both in-repo stories and cross-repo PRD epics, prefixed with the repo:

```
### Open epics
- (in this repo)  #15  [story]  Add cart UI
- (in myorg/prd)  #42  [epic]   Mobile checkout v2
- (in myorg/prd)  #43  [epic]   Improve onboarding
```

Sub-issue linking uses the existing `addSubIssue` GraphQL mutation but with the parent ID fetched from the cross-repo `gh api graphql ... repository(owner: ..., name: ...)`. Same-org cross-repo sub-issue linking is supported by GitHub natively.

### Command-by-command changes

#### `/sillok-init`

- Step 6 (`workflow.config.json` writer) emits `prdRepo: ""` and uses `story` in `labels.types` (was `epic`).
- Step 9 (`bootstrap-labels.sh` invocation) creates the `story` label in the user's repo. The old `epic` label is **not** deleted by sillok — left in place so historical issues remain valid.
- Step 11 summary prints one extra line about `prdRepo` (only when the field is empty in the freshly written config).

#### `/sillok-start`

- Step 1 (Parse args) extends `--parent` parser to recognize `owner/repo#N` and URL forms in addition to bare integers.
- Step 4 (Auto-suggest parent) consumes the precompute output's new cross-repo entries when `prdRepo` is set.
- Step 8 (Sub-issue linking) branches: if the parent is cross-repo, the parent's GraphQL `node id` is fetched with the parent's owner/name; the child's id continues to use the local repo's owner/name. The `addSubIssue` mutation accepts both ids transparently.
- Step 8 (Parent label check) skips the `epic` label assertion for cross-repo parents — the PRD repo's label conventions are user-controlled and sillok cannot enforce them.
- Step 9b (Integration branch detection) skips the parent body parse for cross-repo parents (PRD epics never have a `## Integration branch` section) and falls back to the configured `baseBranch`.

#### `/sillok-design`

- Step 4 (Brainstorming seed) fetches the cross-repo PRD body when the issue's `Parent:` line references a cross-repo issue, and passes it to the brainstorming skill as additional context. Implementation: a single `gh issue view <N> --repo <parent-owner/parent-name> --json body` call.
- All other steps (write spec, paste into local issue body, flip label) are unchanged — the feature issue still lives in the code repo.

#### `/sillok-story` (renamed from `/sillok-epic`)

- File rename: `commands/sillok-epic.md` → `commands/sillok-story.md`.
- Body global replacement: "epic" → "story" throughout (where the word refers to the in-repo composite role, not the PRD-layer concept).
- Type label applied: `story` (was `epic`).
- Integration branch prefix unchanged in template — `{type}/issue-` resolves to `story/issue-N-...` automatically because `{type}` substitutes from the label name.
- Promotion-mode transition unchanged: from a `feature` / `bug` / etc. branch, the user runs `/sillok-story` to promote the current issue's type to `story` and rename its branch to `story/issue-N-...`.

#### `/sillok-execute`, `/sillok-end`

Unchanged. Both operate within the local repo:
- `/sillok-execute` reads the feature's spec from the local issue body, writes a plan, dispatches subagents.
- `/sillok-end` opens the PR; `Closes #N` closes the local feature issue. The cross-repo PRD epic stays open and is closed manually by the user.

### Shared helpers (`scripts/lib/config.sh`, no changes)

`sillok_config prdRepo` returns the configured value or empty string (via the existing config resolution chain). No new helper functions required.

### Bootstrap-labels script (`scripts/bootstrap-labels.sh`)

- Replace the hard-coded `epic` entry with `story`. Color stays the same hue or moves to a distinct one (suggestion: purple `8B5CF6`) — visual cue that the role differs from v1.
- The script remains idempotent (`|| true` masks "label already exists" errors).
- Pre-existing `epic` labels are left untouched. Migration is documented but not automated (see *Migration*).

### Shim writer (`scripts/write-shim-commands.sh`)

Generates `.claude/commands/sillok-story.md` (was `sillok-epic.md`). The shim writer already enumerates the canonical command names; this change is one line in the array.

### Skill updates (`skills/gh-issue-management/SKILL.md`)

- Replace `epic` type-label entry with `story`. Reword the description: "Composite in-repo issue (≥2 sub-issues) with integration branch."
- Add a separate paragraph under **Type vs Structure** explaining the cross-repo PRD layer:
  > A cross-repo `epic` parent lives in the org's PRD repo and is referenced from code-repo issues via `--parent owner/repo#N`. Sillok does not enforce conventions on the PRD repo.
- Add a cross-repo sub-issue linking example showing the parent query against a different `owner`/`name`.

### Rule template updates (`templates/rules/gh-issue-conventions.md`)

Same content updates as the skill above. The rule file is the always-on imported source-of-truth; keep it consistent with the skill.

## Migration (existing sillok 1.x users)

For users upgrading from 1.x to 2.0:

1. **Update the plugin** via the marketplace (`/plugin update sillok`).
2. **Re-run `/sillok-init`** in each existing project. Init is idempotent — it will not overwrite the existing `workflow.config.json`, but its Step 9 (`bootstrap-labels.sh`) will idempotently create the `story` label in the repo.
3. **Manually add `story` to `labels.types`** in `workflow.config.json` (add `"story"`, optionally remove `"epic"`). Without this step, init's label-list awareness drifts from what v2 commands hardcode. Init does not auto-edit existing configs by design.
4. **(Optional) Re-tag historical `epic`-labeled issues** with a one-liner:
   ```bash
   gh issue list --repo <repo> --label epic --state all --json number --jq '.[].number' | \
     xargs -I{} gh issue edit {} --remove-label epic --add-label story
   ```

Steps 1–3 are required for v2 commands (`/sillok-story` and `/sillok-start --parent <N>` linking to an in-repo composite) to work. Step 4 is optional cleanup — sillok does not auto-relabel because doing so per-issue without consent is too destructive for a tool.

**Why v2 doesn't read the type-label name from config:** the renamed `/sillok-story` command applies `--label story` directly. Making the label name fully data-driven (read from config at runtime) would touch every command and is larger surface than v2 needs. v3's command-to-skill refactor ([#15](https://github.com/judeProground/sillok/issues/15)) is a natural place to revisit this.

CHANGELOG will surface this 4-step procedure verbatim.

## Verification plan

- **Schema test:** validate that a config with `prdRepo` set passes `jq` schema check.
- **Parser test:** `precompute-start.sh` correctly distinguishes `--parent 42` vs `--parent owner/repo#42` vs URL form.
- **Cross-repo GraphQL test:** sub-issue link works when parent is in a different repo (same org). Use a fixture: two dummy repos under the same test org.
- **Backwards-compat test:** with `prdRepo` empty, sillok 2.0 behaves identically to v1 for same-repo workflows.
- **Migration smoke test:** an existing 1.x project re-running `/sillok-init` does not destabilize — no overwritten config, `story` label appended, `epic` label preserved.

Existing test suite (`tests/*.test.sh`) updates:
- Update any test asserting the `epic` label name to assert either label depending on config.
- Add a new `tests/cross-repo-parent.test.sh` exercising the `--parent owner/repo#N` parsing path.

## Out of scope (v3+)

Tracked in [#15](https://github.com/judeProground/sillok/issues/15) and / or future issues.

- **`/sillok-prd`** — a new command for PRD lifecycle:
  - Input modes: `--from notion <url>` (via Notion MCP), `--from file <path>` (local md), `--from issue <owner/repo#N>` (copy from existing issue), interactive.
  - Operation: write PRD as `prd/<slug>.md` to `prdRepo`, create `epic` issue there with summary + link.
  - Currently the PM / planner creates the PRD by hand; v3 brings PRD authoring into the sillok-driven flow for engineers who lead the PRD as well.
- **v3 refactor — commands into skill wrappers** ([#15](https://github.com/judeProground/sillok/issues/15)). Each command file collapses to ~10 lines and the procedural body moves into a sibling skill. Blocked by v2 to avoid combining two large-surface changes.
- **GitHub Issue Types migration.** Conceptually a better fit for cross-repo work (org-wide consistency, mutually-exclusive types) but blocked on three things: gh CLI native support (`cli/cli#9696` still open), the maintainer's org-admin authority, and dogfooding feasibility on `judeProground/sillok` (User account, not Org).
- **Cross-repo `Closes #N` automation.** GitHub's behavior is fragile across org / permission boundaries; we explicitly keep this manual.
- **Projects v2 auto-registration.** Users own their multi-repo board setup.

## Changed files (full list)

| File | Change |
|---|---|
| `schema/v1.json` | Add optional `prdRepo` field with `owner/repo` pattern; update `labels.types` default to include `story` |
| `templates/workflow.config.json` | Add `"prdRepo": ""`, rename `"epic"` → `"story"` in `labels.types` |
| `templates/rules/gh-issue-conventions.md` | Label rename, cross-repo conventions paragraph |
| `commands/sillok-init.md` | Step 11 hint about `prdRepo` |
| `commands/sillok-start.md` | `--parent` cross-repo parsing, Step 4 / 8 / 9b branching for cross-repo |
| `commands/sillok-design.md` | Step 4 cross-repo PRD body fetch |
| `commands/sillok-epic.md` → `commands/sillok-story.md` | File rename + body wording change |
| `scripts/precompute-start.sh` | `prdRepo` open-epic enumeration |
| `scripts/precompute-design.sh` | Cross-repo parent recognition for design context |
| `scripts/bootstrap-labels.sh` | `story` instead of `epic`; preserve old `epic` label |
| `scripts/write-shim-commands.sh` | Shim filename change |
| `skills/gh-issue-management/SKILL.md` | Label rename, cross-repo sub-issue example |
| `tests/*.test.sh` | Update label assertions; add cross-repo parent test |
| `README.md` | Update workflow examples for cross-repo case |
| `CHANGELOG.md` | v2.0.0 entry with breaking changes (label / command rename) and migration tip |
| `.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json` | Version bump to `2.0.0` |

## Versioning

- **v2.0.0** — major bump (breaking: `epic` label → `story` label, `/sillok-epic` command → `/sillok-story` command).
- Migration is one shell one-liner per repo, documented in CHANGELOG.
- Per the repo's release process (CLAUDE.md), version bumps must update all three places: `.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json`, `CHANGELOG.md`.

## References

- Issue [#14](https://github.com/judeProground/sillok/issues/14) — this work
- Issue [#15](https://github.com/judeProground/sillok/issues/15) — v3 follow-up (skill-wrapper refactor)
- `cli/cli#9696` — gh CLI native Issue Types support (open, blocks v3 Issue Types migration)
- GitHub Sub-issues API ([docs](https://docs.github.com/en/issues/tracking-your-work-with-issues/using-issues/adding-sub-issues)) — same-org cross-repo linking confirmed supported
