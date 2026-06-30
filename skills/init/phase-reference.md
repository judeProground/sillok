# Init phase reference

On-demand reference for `/sillok-init`. The SKILL.md body owns the action blocks (phase1/phase2 runs, the field-reader, the Step 2a-2 URL prompt, the whole Step 8b classification, and the two HARD GATES). This file documents what each script phase does per step, the Step 11 summary output, and the idempotency guarantees — none of it is an action block the agent re-runs, so it lives here behind a pointer.

## What each phase1 step does (Steps 1–8, deterministic)

phase1 covers, all relocated verbatim into `scripts/init-bootstrap.sh`:

### Step 1: Verify prerequisites

Handled by `init-bootstrap.sh phase1` — it hard-fails (non-zero exit) on missing `git`/`gh`/`jq` or when not inside a git repository. It also initializes the sub-step status variables (`CONFIG_STATUS`, `RULES_STATUS`, … default to `fail`) that the status block reports.

### Step 2: Detect repo and base branch

Handled by phase1 (`gh repo view`) → emits `REPO` and `BASE_BRANCH`. If `REPO` is empty, the user must fill `repo` in the generated config manually (surfaced in the Step 11 summary).

### Step 2a: Detect org mode

Handled by phase1 (`gh api /repos/$REPO` owner type) → emits `ORG_MODE` and `OWNER_TYPE`. User-owned repos print a label-fallback notice to stderr.

### Step 2a-2: Auto-detect project (deterministic arms)

The deterministic single/multi-project auto-detect arms (`gh project list`) run in phase1 and emit `PROJ_OWNER`, `PROJ_NUM` (`0` ⇒ empty-case), and `PROJ_TOTAL`. The **empty-case URL prompt stays in SKILL.md** — it is interactive and only fires when auto-detection found nothing.

### Step 2b: Verify org Issue Types

Handled by phase1 → emits `TYPES_STATUS` (`ok | missing | skip-user-repo`; user repos skip — Issue Types are org-only). A `missing` value triggers the ⚠️ warnings headline; `skip-user-repo` is informational (NOT a warning).

### Step 3: Detect package manager and verify commands

Handled by phase1 via `detect-stack.sh` (read with a `key=value` field reader, not `eval`, since values contain whitespace) → emits the single `STACK` label and writes `install`/`verify.*` into the config. Unknown stack ⇒ the user fills `verify.*` manually.

### Step 4: Branch prefix default

Handled by phase1 → emits `BRANCH_PREFIX` (default template `{type}/issue-`, which substitutes to `feature/issue-`, `bug/issue-`, etc. at branch-creation time). Users can override by editing `workflow.config.json`.

### Step 5: Detect worktree copy files

Handled by phase1 — finds gitignored per-worktree config files (`.env*`, `eas.json`, `google-services.json`, `GoogleService-Info.plist`) with the two-stage `grep`/`grep -v`/`head -200` filter (so `node_modules/**` doesn't drown out the root config), and writes them into `worktree.copyFiles`.

### Step 6: Write `workflow.config.json`

Handled by phase1. On an existing config it deep-merges missing template keys via `migrate-config.sh` (user values win, arrays verbatim) and reports `CONFIG_STATUS=migrated`; otherwise it writes a fresh config and reports `CONFIG_STATUS=ok`. `CONFIG_STATUS` values: `ok | migrated | fail`.

### Step 7: Scaffold rules

Handled by phase1 via `refresh-rules.sh` (overwrites project rule files from `templates/rules/` when content differs) → emits `RULES_STATUS`.

### Step 7b: Write command shortcut shims (REQUIRED)

Handled by phase1 via `write-shim-commands.sh` → emits `SHIM_STATUS`. This step is REQUIRED (the script writes the `.claude/commands/sillok-*.md` shims, respecting foreign files via the `sillok-shim: true` marker; it is idempotent). If `SHIM_STATUS=fail`, the Step 11 summary becomes ⚠️ with a follow-up command the user can copy.

### Step 8: Append `CLAUDE.md` imports

Handled by phase1 → emits `CLAUDE_MD_STATUS`. The append is guarded by the `## Sillok workflow rules` marker (`grep -q`), so a re-run never duplicates the import block. When the marker is already present, phase1 still backfills any `@.claude/sillok/rules/*.md` import line from the snippet that is missing from `CLAUDE.md` (idempotent line-level `grep -Fxq`), so new rules reach existing consumers on re-init.

## What each phase2 step does (Steps 9, 9b, 9c, 10)

phase2 re-reads `CFG`/config FRESH from disk (it depends on no phase1 shell vars) and covers:

### Step 9: Bootstrap labels

Handled by phase2 via `bootstrap-labels.sh "$REPO" --config "$CFG"` → emits `LABELS_STATUS` (`ok | skipped-no-repo | fail`). The `--config` flag picks up the now-final `labels.areas` and creates `area:<name>` labels (color `c9d4dd`); existing labels are skipped (`gh label create … || true`). If `REPO` is empty, the step is `skipped-no-repo` and the user runs `bootstrap-labels.sh` manually.

### Step 9b: Verify project + Status field options

Handled by phase2 via `gh project field-list` (owner-agnostic — works for user- and org-owned boards). It reads `project.owner`/`project.number` from `CFG`, compares the Status field's option names against the config's `project.statuses` values, and emits `PROJECT_STATUS` (`ok | incomplete | unconfigured`). Note: this verification does NOT issue a `gh api graphql` org query — it uses the CLI's `field-list`.

### Step 9c: Priority field (org mode only — ensure the org issue field)

Handled by phase2 (org mode only) → emits `PRIORITY_STATUS` (`ok | incomplete | skip-user-repo | unconfigured | fail`). It sources `lib/project.sh` and calls `sillok_org_priority_field_ensure` to discover/create the org Priority **issue field** (single-select from `project.priorities`, projected onto the board — API-only, not GUI-creatable), then verifies option coverage. User repos skip this entirely (`skip-user-repo`; p1–p4 labels are the priority record there). On steady-state re-init the step is `ok` without prompting or changing anything.

### Step 10: Ensure spec/plan dirs + gitignore

Handled by phase2 — `mkdir -p` the `docs.specs`/`docs.plans` dirs and append them to `.gitignore` if absent (they are local working artifacts; the issue body is the canonical record).

## Step 11: Summary output

Compute the headline status icon from sub-step outcomes (phase1 + phase2 keys + the skill-owned `AREA_STATUS`):

```bash
# Inputs:
#   CONFIG_STATUS   = ok | migrated | fail          (Step 6, phase1)
#   RULES_STATUS    = ok | fail                    (Step 7, phase1)
#   SHIM_STATUS     = ok | fail                    (Step 7b, phase1)
#   CLAUDE_MD_STATUS= ok | fail                    (Step 8, phase1)
#   AREA_STATUS     = areas-confirmed | none-detected | skip-preserved | fail   (Step 8b, in-skill)
#   LABELS_STATUS   = ok | skipped-no-repo | fail  (Step 9, phase2)
#   TYPES_STATUS    = ok | missing | skip-user-repo | fail   (Step 2b, phase1)
#   PROJECT_STATUS  = ok | incomplete | unconfigured | fail   (Step 9b, phase2)
#   PRIORITY_STATUS = ok | incomplete | skip-user-repo | unconfigured | fail   (Step 9c, phase2)

# Critical steps — must all succeed for ✅
if [[ "$CONFIG_STATUS" == "fail" || "$RULES_STATUS" == "fail" || "$CLAUDE_MD_STATUS" == "fail" || "$LABELS_STATUS" == "fail" ]]; then
  HEADLINE="❌ sillok init FAILED"
elif [[ "$TYPES_STATUS" == "missing" || "$PROJECT_STATUS" == "incomplete" || "$PRIORITY_STATUS" == "incomplete" ]]; then
  HEADLINE="⚠️  sillok initialized (with warnings — see below)"
elif [[ "$SHIM_STATUS" == "fail" || "$AREA_STATUS" == "fail" || "$PRIORITY_STATUS" == "fail" ]]; then
  HEADLINE="⚠️  sillok initialized (with warnings — see below)"
else
  HEADLINE="✅ sillok initialized"
fi
```

Print:

```
<HEADLINE>

Repo:          <REPO or "(detect failed, edit manually)">
Base branch:   <BASE_BRANCH>
Branch prefix: <BRANCH_PREFIX>
Stack:         <one of pnpm/yarn/npm/bun/bundler/go/cargo/poetry/pipenv or "unknown">
Org mode:      <ORG_MODE> (<OWNER_TYPE>)                     [detected]

Created:
- .claude/sillok/workflow.config.json                  [<CONFIG_STATUS>]
- .claude/sillok/rules/* (refreshed on re-run)         [<RULES_STATUS>]
- .claude/commands/sillok-{start,add,design,execute,end,story}.md  [<SHIM_STATUS>]
- CLAUDE.md (appended Sillok import block)             [<CLAUDE_MD_STATUS>]
- <SPEC_DIR>/ and <PLAN_DIR>/ (ensured)
- Labels on <REPO>                                     [<LABELS_STATUS>]
- Org Issue Types (Epic/Story/Feature/Task/Bug)        [<TYPES_STATUS>]
  - `skip-user-repo` → "📋 User-owned repo — Issue Types skipped (using label fallback)."
- Project + Status options                             [<PROJECT_STATUS>]
- Org Priority issue field (org mode)                  [<PRIORITY_STATUS>]
  - `skip-user-repo` → "📋 User-owned repo — org Priority issue field skipped (p1–p4 labels are the priority record)."
```

**Area-label sub-summary** (always printed when relevant):

| `AREA_STATUS` | Output |
|---|---|
| `areas-confirmed` | `📊 Area labels confirmed: area:<n1>, area:<n2>, …` followed by the "Not what you want?" guide below. |
| `none-detected` | `📊 No vertical feature areas detected — no area labels created.` |
| `skip-preserved` | `📊 labels.areas already curated ($EXISTING_AREAS entries) — detection skipped to preserve user edits.` |
| `fail` | `📊 Area detection FAILED — re-run manually: bash <plugin>/scripts/project-tree.sh "$PROJECT_ROOT"` |

The "Not what you want?" guide (for `areas-confirmed` only):

```
Not what you want?
  - Edit `labels.areas` in .claude/sillok/workflow.config.json, then re-run:
      bash <plugin>/scripts/bootstrap-labels.sh <repo> --config <cfg-path>
  - Or just ask Claude in natural language, e.g.
      "remove area:foo and add area:bar from sillok config, then re-bootstrap labels"
```

(`<plugin>` is the installed plugin root — the same path the plugin-root-substituted run blocks in SKILL.md resolve to.)

**Warnings block** (only when `SHIM_STATUS == fail` or `LABELS_STATUS == skipped-no-repo`):

```
⚠️  Warnings / follow-ups:
- <issue> — <copy-pasteable fix command>
```

**Footer:**

```
Next: /sillok-start to create your first feature.
```

## Idempotency guarantees

Re-running `/sillok-init` must (all preserved by the two-phase script + in-skill 8b):
- Refresh rule files from the plugin's `templates/rules/` via `refresh-rules.sh` (overwrite when content differs; local edits are not preserved — recover from git if needed)
- Refresh shim command files that carry `sillok-shim: true` (so a plugin upgrade can update the shim format); leave foreign `.claude/commands/sillok-*.md` files untouched
- Skip the full CLAUDE.md import-block append if the `## Sillok workflow rules` marker is already present, but backfill any individual `@.claude/sillok/rules/*.md` import line missing from the file (so new rules reach existing consumers on re-init)
- Skip label creation for labels that already exist (handled by `bootstrap-labels.sh` with `|| true`)
- Deep-merge `workflow.config.json` on re-run via `migrate-config.sh`: add missing template keys, preserve existing user values, keep arrays verbatim
- Preserve existing `labels.areas` array: if non-empty in the existing config, Step 8b reports `skip-preserved` and does NOT overwrite (user's curation wins over auto-pick)
- Priority field steady state asks nothing and changes nothing: when the field exists and every `project.priorities` value matches an option, Step 9c reports `ok` without prompting or writing (a once-confirmed `mapped` config matches on every later run)
