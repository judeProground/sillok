# Remove legacy stage label references from runtime files

v2 moved lifecycle stage from issue labels (`todo`, `designed`, `in-progress`, `in-review`) to the Projects v2 Status field (`Todo`, `In Design`, `In Progress`, `In QA`, `Done`). Several runtime files still reference the old label-based stage system.

## Scope

Every file below ships to consumer projects (via template copy or plugin install) or affects plugin self-hosting. Historical docs (`docs/`, `CHANGELOG.md`) are excluded — they describe what was true at the time.

## Changes

### 1. Self-hosting config (Critical)

**`.claude/sillok/workflow.config.json`** — migrate from v1 `labels` shape to v2.

Remove:
- `labels.types` array
- `labels.stages` array
- `labels.defaults.type`
- `labels.defaults.stage`

Add (match `templates/workflow.config.json`):
- `project` section with `statuses`
- `types` section with Issue Type list + defaults
- `labels.natures` array

### 2. Rule template (High — installed into consumer projects)

**`templates/rules/sillok-workflow.md`**

| Line(s) | Current | Target |
|---------|---------|--------|
| 9 | `label todo→designed` | `status Todo→In Design` |
| 10 | `label designed→in-progress` | `status In Design→In Progress` |
| 11 | `label in-progress→in-review` | `status In Progress→In QA` |
| 15 | `Stage labels (todo/designed/...) are flipped by the commands` | `Project status (Todo/In Design/...) is set by the commands` |
| 39 | type list without `refactor` | add `refactor` |
| 52 | `Don't manually flip stage labels` | `Don't manually change project status` |

### 3. Precompute script comments (Low — cosmetic)

| File | Line | Change |
|------|------|--------|
| `scripts/precompute-design.sh` | 4 | `current stage label` → `project status` |
| `scripts/precompute-execute.sh` | 3 | `stage` → `project status` |
| `scripts/precompute-end.sh` | 3 | `stage` → `project status` |

### 4. Command descriptions (Low — cosmetic)

| File | Line(s) | Change |
|------|---------|--------|
| `commands/sillok-execute.md` | 9, 21 | `stage` → `project status` |
| `commands/sillok-design.md` | 21, 48, 63, 97 | Remove stage label references; line 48 drop `designed` label example; line 97 remove historical migration note |
| `commands/sillok-end.md` | 9 | `stage` → `project status` |

## Non-goals

- Modifying `docs/superpowers/specs/` or `docs/superpowers/plans/` — historical artifacts
- Modifying `CHANGELOG.md` — historical record
- Modifying `scripts/migrate-v1-to-v2.sh` — correctly references old labels for migration purpose
- Adding `infra`/`refactor` back into branch prefix types — these are nature labels in v2, not Issue Types

## Decision record

**`infra` / `refactor` as branch types:** In v2, these are nature labels (orthogonal to Issue Type). Branch prefix `{type}` resolves from Issue Types only (`feature`, `story`, `bug`, `task`). Standalone infra/refactor work uses Issue Type `Feature`; sub-task infra/refactor work uses Issue Type `Task`. The nature label (`infra`, `refactor`) goes on as a separate label.
