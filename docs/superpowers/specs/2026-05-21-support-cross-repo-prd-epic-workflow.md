# Cross-repo PRD epic workflow with Issue Types + Projects v2 (v2)

**Issue:** [#14](https://github.com/judeProground/sillok/issues/14)
**Status:** Designed (pivoted 2026-05-22 from labels-based to Issue Types + Projects v2)
**Authored:** 2026-05-21 (rev. 2026-05-22)

## Background

Sillok 1.x conflates several concerns into the label taxonomy:

- **Work type** (`feature`, `bug`, `improvement`, `infra`, `epic`) — categorical, mutually exclusive
- **Lifecycle stage** (`todo`, `designed`, `in-progress`, `in-review`) — sequential, sillok flips these as commands run
- **Priority** (`p1`–`p4`) — orthogonal scalar
- **Area** (`area:*`) — orthogonal categorical

The labels-only model works at single-repo solo scale but breaks down at the org-wide multi-repo scale this org actually operates at:

- Type labels must be bootstrapped per repo; drift is easy
- Stage labels are invisible at the project / planning layer
- No unified surface to view work across `progroundDev/*` repos
- PRDs live elsewhere (Notion / planning docs); no cross-link to code issues
- Mutual exclusivity of types is by convention, not enforced

GitHub now ships two features that match this scope better:

- **Issue Types** (org-level, GA): mutually-exclusive categorical metadata, defined once per org, applied per issue. API: `/orgs/{org}/issue-types`.
- **Projects v2**: unified multi-repo board with custom status field, auto-add workflows, and built-in "item closed → Done" automation.

Combined with the previously-locked cross-repo PRD direction, this lets sillok delegate each concern to its natural home.

## Goal

Restructure sillok v2 so each concern lives where it belongs:

| Concern | Where | Mechanism |
|---|---|---|
| Type (Epic, Story, Feature, Task, Bug) | **Issue Type** (org-level) | GitHub Issue Types REST API |
| Lifecycle stage (Todo / In Design / In Progress / In QA / Done) | **Projects v2 Status field** | Project item status update via GraphQL / REST |
| Priority (p1–p4) | Label | unchanged from v1 |
| Area (`area:*`) | Label | unchanged from v1 |
| Nature (improvement / refactor / infra / docs / security / performance) | Label (NEW) | new label class, ortho to type |
| Cross-repo PRD parent | Sub-issue API | unchanged from prior v2 design (cross-repo `--parent`) |

Out of band: the PRD repo's own conventions are user-controlled — sillok reads from but does not write to the PRD repo.

## Hierarchy

```
PRD repo (myorg/prd)         Code repos (myorg/{frontend,backend,...})
─────────────────────         ─────────────────────────────────────────
[Epic] PRD #42 ─────────────► [Story] Composite #15  (optional layer)
                              │           │
                              │           ├─ [Feature] #16
                              │           └─ [Task] #17
                              │
                              └─────────► [Feature] #18  (direct child, no Story)
```

`Epic`, `Story`, `Feature`, `Task`, `Bug` are GitHub Issue Types (mutually exclusive, org-defined). Hierarchy is conventional, not enforced by GitHub — sub-issue parent-child relationships do the actual linking.

- **Epic** = PRD; lives in PRD repo. Sillok never creates these (PM / planner does).
- **Story** = optional in-repo composite; has integration branch + worktree.
- **Feature / Task / Bug** = atomic work-unit issues, each shipping one PR.

## Locked design decisions

1. **Issue Type for "what is this work"** — 5 types: `Epic`, `Story`, `Feature`, `Task`, `Bug`.
2. **Projects v2 status field for "where is this in the lifecycle"** — 5 statuses: `Todo`, `In Design`, `In Progress`, `In QA`, `Done`.
3. **Labels for cross-cutting attributes**: priority, area, nature (improvement / refactor / infra / docs / security / performance).
4. **Stage labels removed entirely** (was: `todo`, `designed`, `in-progress`, `in-review`, `backlog`). Replaced by project status.
5. **Type labels removed entirely** (was: `feature`, `bug`, `improvement`, `infra`, `epic`). Replaced by Issue Types. `improvement` / `infra` survive as Nature labels.
6. **One-time org setup**: org owner adds `Epic` and `Story` Issue Types via API or web UI (other 3 types — `Feature`, `Task`, `Bug` — already exist in `progroundDev`).
7. **One-time project setup**: a Projects v2 board with a Status field configured with the 5 required option names (case-sensitive default; user-overridable via config).
8. **Auto-add workflow handles initial state**: when an issue is created, the project's auto-add workflow adds it as `Todo` (or the configured initial status). Sillok does not handle initial project add.
9. **Done is automated by project workflow**: project's built-in "item closed → Done" workflow handles the final transition. Sillok's `/sillok-end` opens a PR with `Closes #N`; on merge the issue closes; project flips status to `Done` automatically.
10. **Sillok-driven status updates**: `/sillok-design` → `In Design`, `/sillok-execute` → `In Progress`, `/sillok-end` → `In QA`. Three transitions only — start and done are workflow-driven.
11. **Cross-repo PRD** (unchanged from prior design): `prdRepo` config + `--parent owner/repo#N` syntax + cross-repo `addSubIssue` GraphQL mutation. Cross-repo `Closes #N` stays manual.
12. **`/sillok-epic` renamed to `/sillok-story`**: command body unchanged in shape, but the Type label flip becomes an Issue Type set, and the integration branch is now `story/issue-N-...`.

## Architecture overview

### Config schema (`schema/v1.json`, `templates/workflow.config.json`)

```jsonc
{
  "$schema": "...",
  "version": 1,

  "repo": "myorg/frontend",
  "baseBranch": "main",
  "branchPrefix": "{type}/issue-",          // {type} lowercased at substitution

  // NEW: cross-repo PRD reference
  "prdRepo": "myorg/prd",                   // optional. Empty = cross-repo PRD disabled.

  // NEW: Projects v2 integration
  "project": {
    "owner": "progroundDev",                // org owning the project (often same as code repo owner)
    "number": 3,                            // project number
    "statusField": "Status",                // status field name on the project (default "Status")
    "statuses": {
      "todo":     "Todo",
      "design":   "In Design",
      "progress": "In Progress",
      "review":   "In QA",
      "done":     "Done"
    }
  },

  // CHANGED: types removed (now Issue Types), stages removed (now project status)
  "types": {
    "list":     ["Epic", "Story", "Feature", "Task", "Bug"],
    "defaults": {
      "feature":   "Feature",
      "composite": "Story",
      "prd":       "Epic"
    }
  },

  "labels": {
    "priorities": ["p1", "p2", "p3", "p4"],
    "areas":      [],
    "natures":    ["improvement", "refactor", "infra", "docs", "security", "performance"],
    "defaults": {
      "priority": "p3"
    }
  },

  "worktree":  { "enabled": true, "dir": ".worktrees", "copyFiles": [] },
  "install":   "",
  "verify":    { "lint": "", "typecheck": "", "format": "" },
  "docs":      { "specs": "docs/superpowers/specs", "plans": "docs/superpowers/plans" },
  "commit":    { "coAuthor": "" },
  "milestone": { "naming": "YYYY-MM-Wn", "sprintWeeks": 2, "weekStart": "monday" }
}
```

- `project` is required for v2 to function (status updates need it).
- `types` is mostly informational at runtime — Issue Types are defined org-wide; this config tells sillok which names to use when applying.
- `prdRepo` is optional.

### One-time org-level setup (required before `/sillok-init`)

Org owner runs once:

```bash
# Add missing Issue Types (Epic and Story; Feature/Task/Bug already exist)
gh api -X POST -H "X-GitHub-Api-Version: 2026-03-10" \
  /orgs/progroundDev/issue-types \
  -f name=Epic -f color=purple -f description='Cross-repo PRD parent'

gh api -X POST -H "X-GitHub-Api-Version: 2026-03-10" \
  /orgs/progroundDev/issue-types \
  -f name=Story -f color=blue -f description='In-repo composite, has integration branch'
```

Plus, in the Project's Status field (web UI), ensure these option names exist: `Todo`, `In Design`, `In Progress`, `In QA`, `Done`. Plus enable the built-in "Auto-add to project" and "Item closed → Done" workflows.

Sillok detects missing types / statuses at `/sillok-init` and surfaces copy-paste fixes — does not attempt creation itself (member-level credentials cannot create types).

### Per-command behavior

#### `/sillok-init`

1. Verify org Issue Types: read `GET /orgs/{owner}/issue-types` and assert the 5 from config exist. If missing, surface copy-paste admin commands and abort.
2. Verify project: read project metadata; assert the configured Status field exists with the 5 configured option names. If missing, surface UI link + abort.
3. Verify auto-add workflow is enabled (best-effort — workflows API access is limited). If we can't verify, print a hint.
4. Bootstrap labels: `priorities`, `natures`, `areas`. No `types`, no `stages`.
5. Write config (idempotent — don't overwrite existing).
6. Shims + CLAUDE.md import + docs dirs — unchanged.
7. Summary: report which Issue Types, project, and labels were verified.

#### `/sillok-start`

1. Parse `--parent` (supports `N`, `owner/repo#N`, or full URL — same as prior design).
2. Build issue payload: title, body, labels (priority + nature + area as applicable), and **Issue Type** (via REST `type` field in `POST /repos/{owner}/{repo}/issues` — new in 2026-03-10 API).
3. Create issue. Capture `<N>`.
4. If parent, link as sub-issue via `addSubIssue` GraphQL (cross-repo capable).
5. **Auto-add workflow** picks up the new issue and adds it to the project with initial status (`Todo`). Sillok waits briefly and verifies the project item exists; if not, manually `gh project item-add` + set status to `Todo`.
6. Cut branch + worktree (unchanged).
7. Output: issue URL + branch + worktree path + **project item URL**.

#### `/sillok-design`

1. Precompute (state derivation) — unchanged in shape; also looks up project item ID for the current issue.
2. Pre-condition check: current project status should be `Todo`. If `In Design` already, allow continuation; otherwise warn.
3. If parent is cross-repo, fetch PRD body and seed brainstorming (unchanged from prior design).
4. Brainstorming → write spec to `docs/superpowers/specs/<date>-<slug>.md`.
5. User review loop (unchanged).
6. **Update project status: `Todo` → `In Design`** via GraphQL mutation `updateProjectV2ItemFieldValue`.
7. Paste spec inline into issue body (unchanged).

#### `/sillok-execute`

1. Precompute. Pre-condition: status `In Design`.
2. Write plan, dispatch superpowers subagents, run verify gate (unchanged).
3. **Update project status: `In Design` → `In Progress`** at the start of execution.

#### `/sillok-end`

1. Precompute. Pre-condition: status `In Progress`.
2. Open PR with `Closes #N` (unchanged).
3. **Update project status: `In Progress` → `In QA`**.
4. On merge: issue closes; project's built-in "item closed → Done" workflow flips status to `Done`. Sillok does not touch `Done`.

#### `/sillok-story` (renamed from `/sillok-epic`)

1. File rename: `commands/sillok-epic.md` → `commands/sillok-story.md`. Wording: "epic" → "story" throughout.
2. Issue Type applied: `Story`.
3. Integration branch: `story/issue-<N>-<slug>` (via `{type}/issue-` template with lowercase substitution).
4. Promotion mode: from a `feature/issue-N-...` branch, promote = update Issue Type to `Story` (`PATCH` on issue) + rename branch.

### Helper scripts

- **`scripts/lib/project.sh`** (NEW): wrappers for project item lookup, status get/set, field ID resolution. Functions:
  - `sillok_project_item_for_issue <issue-url>` → returns project item ID
  - `sillok_project_status_get <item-id>` → returns current status name
  - `sillok_project_status_set <item-id> <status-key>` → sets status (key in [todo, design, progress, review, done])
  - `sillok_project_field_id <field-name>` → returns field ID (cached)
  - `sillok_project_option_id <field-name> <option-name>` → returns option ID (cached)
- **`scripts/lib/issue-types.sh`** (NEW): wrappers for Issue Type API. Functions:
  - `sillok_issue_type_id <type-name>` → returns type ID (cached, org-level)
  - `sillok_issue_type_set <repo> <issue-N> <type-name>` → applies type
- **`scripts/precompute-*.sh`**: extend to look up project item + current status. Output includes a new `### Project status` section.
- **`scripts/bootstrap-labels.sh`**: bootstrap priorities + natures + areas only. No types, no stages.

### Label taxonomy after v2

| Category | Examples | Source |
|---|---|---|
| Priority | `p1`, `p2`, `p3`, `p4` | sillok bootstraps |
| Area | `area:auth`, `area:billing`, etc. | sillok detects + bootstraps |
| Nature | `improvement`, `refactor`, `infra`, `docs`, `security`, `performance` | sillok bootstraps (NEW class) |
| ~~Type~~ | ~~`feature`, `bug`, `epic`, ...~~ | **moved to Issue Types** |
| ~~Stage~~ | ~~`todo`, `designed`, ...~~ | **moved to project status** |

## Migration from sillok 1.x

1.x users have label-based types AND stages, no project setup, no Issue Types. v2 is a real migration, not a drop-in upgrade.

### Required user actions

1. **Update the plugin** to v2.0 via the marketplace.
2. **Org owner adds the two missing Issue Types** (Epic, Story) using the commands above.
3. **Owner creates / configures a Projects v2 board** with the required 5 Status field options + enables Auto-add + "item closed → Done" workflows.
4. **Re-run `/sillok-init`** in each project. It will:
   - Verify Issue Types and project (abort with copy-paste fix if missing).
   - Bootstrap new label classes (`natures`) and remove old ones (`types`, `stages`).
   - Write the updated config schema.
5. **Backfill existing issues** (optional but recommended) via the migration script (`scripts/migrate-v1-to-v2.sh`):
   - For each open issue: detect old type label → set new Issue Type → strip old type label.
   - For each open issue: detect old stage label → find project item → set status → strip old stage label.
   - Idempotent; safe to re-run.

The migration script is run by the user explicitly (`bash scripts/migrate-v1-to-v2.sh <repo>`), not by `/sillok-init`. Forcing migration in init would be too destructive.

### What breaks

- Any external automation that filters by `epic`, `feature`, etc. labels will need updating to filter by Issue Type instead.
- Any external automation that flips stage labels needs updating to use project status.
- The plugin install itself stays backward-discoverable (old `/sillok-epic` shim could redirect to `/sillok-story` for one release), but the underlying API surfaces have moved.

### What stays

- Branch prefix template (`{type}/issue-` still substitutes — values change from `feature/`, `bug/` to `feature/`, `story/`, `task/`, `bug/`)
- Sub-issue parent-child semantics
- `Closes #N` PR auto-close
- Spec / plan file conventions
- Worktree management
- `gh-issue-management` skill (substantially rewritten content)

## Verification plan

- **Issue Types**: integration test that `gh api /orgs/<org>/issue-types` returns the expected 5 types after admin setup.
- **Project**: integration test that the configured project number resolves and Status field has the expected 5 options.
- **Status transitions**: an end-to-end smoke test that creates a fixture issue, runs each sillok command, and asserts the project status advances correctly.
- **Cross-repo parent**: existing prior-design verification still applies — sub-issue link works across repos in the same org.
- **Migration script**: a fixture repo with v1-style labels → run migration → assert types + statuses are correctly set, old labels removed.
- **Backwards-compat**: with `prdRepo` empty + no project configured (legacy single-repo scenario), sillok should... actually no — v2 requires `project` config. Document this as a hard requirement.

Existing test suite (`tests/*.test.sh`) — substantial updates:

- Remove tests asserting `epic` / `feature` / etc. labels exist.
- Add tests for Issue Type read + apply.
- Add tests for project item lookup + status update.
- Add a `tests/migrate-v1-to-v2.test.sh` for the migration script.

## Out of scope (v3+)

Tracked in [#15](https://github.com/judeProground/sillok/issues/15) and / or future issues.

- **`/sillok-prd`** — PRD authoring command. Notion MCP fetch, local md, or copy-from-issue. Creates Epic-typed issue in `prdRepo` with linked md file. (Same v3 scope as before.)
- **v3 refactor — commands into skill wrappers** ([#15](https://github.com/judeProground/sillok/issues/15)). Now even more valuable: the helper libraries (`project.sh`, `issue-types.sh`) are skill-shaped logic that wants to be a proper skill package.
- **Cross-repo `Closes #N` automation**. Still fragile. Still manual.
- **Projects v2 auto-add workflow auto-configuration**. Requires Workflow API access that may not be in member role. Currently sillok only verifies presence; future could attempt creation if org grants the bot the right scope.
- **Custom org fields beyond status / priority**. The `issue-field-values` REST endpoint is shipping; future sillok could let users add e.g. `sprint`, `estimate`, `risk` org-level custom fields and assign them per-issue. Out of scope for v2 — labels handle priority and area for now.
- **Pure dogfood mode** (no org, no project). Sillok 2.x will require an org + project; solo-user workflows on User-owned repos are not a target. Such users can stay on 1.x or use the migration off-ramp.

## Changed files (full list)

| File | Change |
|---|---|
| `schema/v1.json` | Add `prdRepo`, `project.*`, `types.*`, `labels.natures`. Remove `labels.types`, `labels.stages` from defaults. Major schema bump still v1 (additive + clear deprecations). |
| `templates/workflow.config.json` | Reshape to new schema; `project` section required. |
| `templates/rules/gh-issue-conventions.md` | Major rewrite: Issue Types model, project status lifecycle, new label classes. |
| `commands/sillok-init.md` | Add type/project verification steps; remove stage/type label bootstrap; add migration-detection hint. |
| `commands/sillok-start.md` | Set Issue Type at creation; resolve project item; cross-repo `--parent` parsing. |
| `commands/sillok-design.md` | Status update to `In Design`; cross-repo PRD body fetch. |
| `commands/sillok-execute.md` | Status update to `In Progress` at start. |
| `commands/sillok-end.md` | Status update to `In QA` at PR open. |
| `commands/sillok-epic.md` → `commands/sillok-story.md` | File rename + Issue Type set to `Story` + integration branch prefix update. |
| `scripts/lib/project.sh` | NEW. Project item + status helpers. |
| `scripts/lib/issue-types.sh` | NEW. Issue Type helpers. |
| `scripts/precompute-*.sh` | Add project item + status to derived state output. |
| `scripts/bootstrap-labels.sh` | Drop types, drop stages. Add `natures`. |
| `scripts/write-shim-commands.sh` | Shim filename change (`sillok-epic.md` → `sillok-story.md`). |
| `scripts/migrate-v1-to-v2.sh` | NEW. Bulk migrate old labels → Issue Types + project statuses. |
| `skills/gh-issue-management/SKILL.md` | Major rewrite. Issue Type apply / lookup, project status, label classes. |
| `tests/*.test.sh` | Update label assertions; add type + project + migration tests. |
| `README.md` | Update workflow examples, prerequisites (org + project required). |
| `CHANGELOG.md` | v2.0.0 entry with breaking changes, migration 5-step procedure. |
| `.claude-plugin/{plugin.json,marketplace.json}` | Version bump to `2.0.0`. |

## Versioning

- **v2.0.0** — major bump.
- Breaking changes:
  - Type labels removed → Issue Types (org-level)
  - Stage labels removed → Project status
  - `/sillok-epic` renamed → `/sillok-story`
  - New requirement: Projects v2 board with prerequisite setup
  - New requirement: org-level Issue Types (Epic, Story added; Feature/Task/Bug must exist)
- Per repo release process (CLAUDE.md): bump in `.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json`, `CHANGELOG.md`.

## References

- Issue [#14](https://github.com/judeProground/sillok/issues/14) — this work
- Issue [#15](https://github.com/judeProground/sillok/issues/15) — v3 follow-up (skill-wrapper refactor)
- GitHub REST API — Issue Types: `/orgs/{org}/issue-types` (`X-GitHub-Api-Version: 2026-03-10`)
- GitHub REST API — Projects v2 items: `/orgs/{org}/projectsV2/{number}/items` (2026-03-10)
- GitHub REST API — Issue field values: `/repos/{owner}/{repo}/issues/{N}/issue-field-values` (2026-03-10 — kept in mind for future custom field support)
- GitHub Sub-issues API — same-org cross-repo linking confirmed supported
