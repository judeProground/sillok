---
name: init
description: Internal sillok stage skill — enter via the /sillok-init command only (init sits outside the workflow chain and is never routed by sillok:workflow). Bootstraps a project for sillok — detects repo, base branch, package manager, gitignored config files, and branch prefix automatically; asks at most two questions per run (conditional: project URL when no board is detected; auto-detected area labels when candidates found), and nothing under auto-mode. Org-mode runs provision the org Priority issue field without asking (API-only; not GUI-creatable). Idempotent.
user-invocable: false
---

# Sillok Init

You are running sillok `init` to bootstrap the current project for sillok.

**Init takes no arguments and asks at most two questions per run**, drawn from two conditional ones — a project URL (only when auto-detection yields nothing — see Step 2a-2) and the auto-detected area labels (Step 8b, interactive runs only). Org-mode runs also provision the org Priority issue field (Step 9c) — but that step asks nothing: the field is created from config to match the fixed `project.priorities` option names. Under auto-mode it asks nothing at all. If detection of any field fails, the field is left empty in the generated config and a warning is printed; the user edits `.claude/sillok/workflow.config.json` afterward.

**Auto-mode contract:** all three orchestration calls run unconditionally — phase1 (Steps 1–8, deterministic, including the shim install at Step 7b), the in-skill area classification (Step 8b), and phase2 (Steps 9–10). Step 8b reads the directory tree that phase1 already emitted (it does not re-run `project-tree.sh`), then classifies and confirms; under auto-mode that confirmation auto-accepts the classified list (written to the git-tracked config), so it never blocks. Every step writes only to plugin-managed paths and carries idempotent safeguards documented in its own header.

## How this skill is structured

The deterministic, side-effecting work lives in `scripts/init-bootstrap.sh`, which runs in **two phases** and reports back through a printed `KEY=value` status block on stdout (the same channel `detect-stack.sh` / `precompute-*.sh` use). You orchestrate:

1. Run **phase1** (Steps 1–8 below, minus the two judgment steps) and parse its status block.
2. Run the in-skill **Step 2a-2 empty-case URL prompt** (only when `PROJ_NUM=0`).
3. Run the in-skill **Step 8b** area classification and persist `labels.areas`.
4. Run **phase2** (Steps 9, 9b, 9c, 10), which re-reads the now-final `labels.areas` from disk.
5. Compose the **Step 11** summary from the phase1 + phase2 keys plus the skill-owned `AREA_STATUS`.

**Reading the status block — field reader, NEVER `eval`.** Parse each phase's stdout one line at a time with a field reader; **do not** `eval` it (status values like `MERGE_SUMMARY`/`REFRESH_SUMMARY` contain spaces, so `eval` would mis-parse them — `detect-stack.sh`'s header documents the same hazard):

```bash
# parse phase1 output (already captured in $INIT1) into shell vars
while IFS='=' read -r key val; do
  case "$key" in
    REPO) REPO="$val" ;;
    BASE_BRANCH) BASE_BRANCH="$val" ;;
    ORG_MODE) ORG_MODE="$val" ;;
    OWNER_TYPE) OWNER_TYPE="$val" ;;
    STACK) STACK="$val" ;;
    PROJ_OWNER) PROJ_OWNER="$val" ;;
    PROJ_NUM) PROJ_NUM="$val" ;;
    PROJ_TOTAL) PROJ_TOTAL="$val" ;;
    BRANCH_PREFIX) BRANCH_PREFIX="$val" ;;
    CFG_PATH) CFG="$val" ;;
    PROJECT_ROOT) PROJECT_ROOT="$val" ;;
    CONFIG_STATUS) CONFIG_STATUS="$val" ;;
    RULES_STATUS) RULES_STATUS="$val" ;;
    SHIM_STATUS) SHIM_STATUS="$val" ;;
    CLAUDE_MD_STATUS) CLAUDE_MD_STATUS="$val" ;;
    TYPES_STATUS) TYPES_STATUS="$val" ;;
  esac
done <<EOF
$INIT1
EOF
```

The project tree for Step 8b is fenced between `### project-tree` and `### end-project-tree` sentinels in the phase1 output — extract it from there; do NOT re-run `project-tree.sh`.

**Hard ordering requirement:** Step 8b (below) must persist `labels.areas` to `CFG` **before** you invoke phase2 — phase2's `bootstrap-labels.sh` re-reads `labels.areas` from disk, so if the jq write hasn't happened the area labels silently won't be created.

## Run phase1 (Steps 1–8, deterministic)

```bash
INIT1=$(bash "${CLAUDE_PLUGIN_ROOT}/scripts/init-bootstrap.sh" phase1) || {
  echo "[sillok-init] phase1 failed — see stderr above. Stopping." >&2
  exit 1
}
```

**If phase1 exits non-zero, stop here** — do not run Step 8b or phase2. Step 1 hard-fails this way on a missing `git`/`gh`/`jq` or a non-repo CWD; surface phase1's stderr to the user (under auto-mode too, where nothing else is watching the stderr soft-contract) instead of proceeding with empty status vars.

Then parse `$INIT1` with the field reader above. phase1 covers, all relocated verbatim into the script:

## Step 1: Verify prerequisites

Handled by `init-bootstrap.sh phase1` — it hard-fails (non-zero exit) on missing `git`/`gh`/`jq` or when not inside a git repository. It also initializes the sub-step status variables (`CONFIG_STATUS`, `RULES_STATUS`, … default to `fail`) that the status block reports.

## Step 2: Detect repo and base branch

Handled by phase1 (`gh repo view`) → emits `REPO` and `BASE_BRANCH`. If `REPO` is empty, the user must fill `repo` in the generated config manually (surfaced in the Step 11 summary).

## Step 2a: Detect org mode

Handled by phase1 (`gh api /repos/$REPO` owner type) → emits `ORG_MODE` and `OWNER_TYPE`. User-owned repos print a label-fallback notice to stderr.

## Step 2a-2: Auto-detect project

The deterministic single/multi-project auto-detect arms (`gh project list`) run in phase1 and emit `PROJ_OWNER`, `PROJ_NUM` (`0` ⇒ empty-case), and `PROJ_TOTAL`. The **empty-case URL prompt stays here in the skill** — it is interactive and only fires when auto-detection found nothing:

**If `PROJ_NUM=0`** (no single auto-detected board), prompt once for a project URL (acceptable exception to zero-prompt — only fires when auto-detection yields nothing). First note the closed/hidden case driven by `PROJ_TOTAL`:

- If `PROJ_TOTAL` > 0: tell the user there are no OPEN projects under `$PROJ_OWNER` but `$PROJ_TOTAL` closed/hidden project(s) exist (they can list them with `gh project list --owner $PROJ_OWNER --closed`).
- Otherwise: tell the user no projects were found under `$PROJ_OWNER`.

Then ask the user to **paste its URL** (or skip). Use `AskUserQuestion`/`read` for the prompt. On a non-empty URL, parse it and, on a valid parse, write the board into `CFG` so phase2 verifies the right project:

```bash
if [[ "$PROJ_NUM" == "0" ]]; then
  # (prose above: print the closed/hidden vs none note using $PROJ_TOTAL, then prompt)
  read -r -p "If your board lives elsewhere, paste its URL (or press Enter to skip): " proj_url
  if [[ -n "$proj_url" ]]; then
    parsed=$(bash "${CLAUDE_PLUGIN_ROOT}/scripts/parse-project-url.sh" "$proj_url" 2>/dev/null || echo "")
    url_owner=$(echo "$parsed" | awk -F= '$1=="owner"{print $2}')
    url_number=$(echo "$parsed" | awk -F= '$1=="number"{print $2}')
    if [[ -n "$url_owner" && -n "$url_number" ]]; then
      PROJ_OWNER="$url_owner"
      PROJ_NUM="$url_number"
      tmp=$(mktemp)
      jq --arg o "$PROJ_OWNER" --argjson n "$PROJ_NUM" \
        '.project.owner = $o | .project.number = $n' "$CFG" > "$tmp" && mv "$tmp" "$CFG"
      echo "[sillok-init] Project set from URL: (#$PROJ_NUM, owner=$PROJ_OWNER)"
    else
      echo "[sillok-init] URL did not match a GitHub project — skipping project setup."
    fi
  fi
fi
```

## Step 2b: Verify org Issue Types

Handled by phase1 → emits `TYPES_STATUS` (`ok | missing | skip-user-repo`; user repos skip — Issue Types are org-only). A `missing` value triggers the ⚠️ warnings headline; `skip-user-repo` is informational (NOT a warning).

## Step 3: Detect package manager and verify commands

Handled by phase1 via `detect-stack.sh` (read with a `key=value` field reader, not `eval`, since values contain whitespace) → emits the single `STACK` label and writes `install`/`verify.*` into the config. Unknown stack ⇒ the user fills `verify.*` manually.

## Step 4: Branch prefix default

Handled by phase1 → emits `BRANCH_PREFIX` (default template `{type}/issue-`, which substitutes to `feature/issue-`, `bug/issue-`, etc. at branch-creation time). Users can override by editing `workflow.config.json`.

## Step 5: Detect worktree copy files

Handled by phase1 — finds gitignored per-worktree config files (`.env*`, `eas.json`, `google-services.json`, `GoogleService-Info.plist`) with the two-stage `grep`/`grep -v`/`head -200` filter (so `node_modules/**` doesn't drown out the root config), and writes them into `worktree.copyFiles`.

## Step 6: Write `workflow.config.json`

Handled by phase1. On an existing config it deep-merges missing template keys via `migrate-config.sh` (user values win, arrays verbatim) and reports `CONFIG_STATUS=migrated`; otherwise it writes a fresh config and reports `CONFIG_STATUS=ok`. `CONFIG_STATUS` values: `ok | migrated | fail`.

## Step 7: Scaffold rules

Handled by phase1 via `refresh-rules.sh` (overwrites project rule files from `templates/rules/` when content differs) → emits `RULES_STATUS`.

## Step 7b: Write command shortcut shims (REQUIRED)

Handled by phase1 via `write-shim-commands.sh` → emits `SHIM_STATUS`. This step is REQUIRED (the script writes the `.claude/commands/sillok-*.md` shims, respecting foreign files via the `sillok-shim: true` marker; it is idempotent). If `SHIM_STATUS=fail`, the Step 11 summary becomes ⚠️ with a follow-up command the user can copy.

## Step 8: Append `CLAUDE.md` imports

Handled by phase1 → emits `CLAUDE_MD_STATUS`. The append is guarded by the `## Sillok workflow rules` marker (`grep -q`), so a re-run never duplicates the import block.

## Step 8b: Auto-detect area labels (hybrid — tree → classify → confirm)

**This step STAYS in the skill — it is the LLM-judgment half.** phase1 already emitted the deterministic directory tree (between the `### project-tree` / `### end-project-tree` sentinels in `$INIT1`); you classify and persist. Detect vertical business feature areas for `area:<name>` GitHub labels.

1. **Skip if user already curated areas.** Re-running init on a project where
   `labels.areas` is already non-empty must NOT clobber the user's curation:

   ```bash
   EXISTING_AREAS=$(jq -r '(.labels.areas // [])[]' "$CFG" 2>/dev/null | wc -l | tr -d ' ')
   if [[ "$EXISTING_AREAS" -gt 0 ]]; then
     AREA_STATUS=skip-preserved
   fi
   ```

   When `skip-preserved`, **Step 8b is done — skip steps 2–6.**

2. **Read the directory tree (deterministic, already produced).** Extract the
   lines between the `### project-tree` and `### end-project-tree` sentinels in
   `$INIT1` into `$TREE`. Do NOT re-run `project-tree.sh`.

3. **No tree → no areas.**

   ```bash
   if [[ -z "$TREE" ]]; then
     AREA_STATUS=none-detected
     # leave labels.areas as []
   fi
   ```

   When `$TREE` is empty, **Step 8b is done — skip steps 4–6.** Otherwise continue:
   a non-empty tree always reaches step 6, which sets the final `AREA_STATUS`
   (`areas-confirmed` or `none-detected`) so it never stays at its `fail` default.

4. **Classify (LLM judgment — you do this, not a script).** Read `$TREE` and pick
   the **vertical business feature areas**, excluding horizontal technical layers:

   - **Include (vertical):** business/domain nouns — `auth`, `wallet`, `raffle`,
     `cash-withdrawal`, `abuse`, `notice`, `dashboard`, …
   - **Exclude (horizontal):** technical role/layer dirs — `controller`, `service`,
     `dto`, `entity`, `repository`, `dao`, `vo`, `guard`, `pipe`, `interceptor`,
     `filter`, `middleware`, `decorator`, `module`, `command`, `query`, `handler`,
     `common`, `shared`, `utils`, `helpers`, `config`, `constant`, `enum`, `type`,
     `model`, `models`, `api`, …
   - **Descend, don't label (wrappers):** grouping/version dirs — `src`, `app`,
     `apps`, `packages`, `modules`, `features`, `service`, `services`, `v1`, `v2`,
     … — are not areas themselves; treat their children as candidates.
     (`service`/`services` is dual-listed on purpose: descend into it when it holds
     business-named children like `service/wallet/`; treat it as an excluded leaf
     layer when it sits beside `controller`/`dto`. Judge by its children.)
   - Normalize each name to kebab-case (lowercase, `_`→`-`).
   - If no clear vertical slices exist, the list is empty (treat as `none-detected`).

5. **Confirm before creating (one-time gate).**

   - **Interactive (a human is driving this init):** present the proposed area list
     and ask the user to confirm or edit it (via `AskUserQuestion`). Use their
     final list as `$selected` (one name per line).
   - **Auto-mode (invoked by an automation agent, non-interactive):** skip the
     prompt and accept your proposed list as `$selected`. It is written to
     `labels.areas` (git-tracked, editable), so the user can adjust and re-bootstrap
     later. This preserves the auto-mode "never blocks" contract.
   - **No vertical areas found (either mode):** set `selected=""` (empty) and
     proceed — step 6 records `none-detected`.

6. **Persist to config.** `$selected` is the confirmed/auto-accepted area names,
   one per line (empty when none). This jq write MUST complete before phase2 runs.

   ```bash
   selected="${selected:-}"   # ensure defined even if classification was skipped
   if [[ -n "$selected" ]]; then
     selected_json=$(printf '%s\n' "$selected" | jq -R . | jq -s .)
     tmp=$(mktemp)
     jq --argjson areas "$selected_json" '.labels.areas = $areas' "$CFG" > "$tmp" && mv "$tmp" "$CFG"
     AREA_STATUS=areas-confirmed
     AREA_COUNT=$(printf '%s\n' "$selected" | wc -l | tr -d ' ')
   else
     AREA_STATUS=none-detected
   fi
   ```

7. **Surface the result in Step 11.**

`AREA_STATUS` is one of: `areas-confirmed`, `none-detected`, `skip-preserved`,
`fail`. Each maps to a distinct summary line (see Step 11). `AREA_STATUS` stays
**skill-owned** (you produced it) — it is not part of either phase's status block.

## Run phase2 (Steps 9, 9b, 9c, 10)

`labels.areas` is now final on disk, so run phase2 and parse its status block:

```bash
INIT2=$(bash "${CLAUDE_PLUGIN_ROOT}/scripts/init-bootstrap.sh" phase2)
while IFS='=' read -r key val; do
  case "$key" in
    LABELS_STATUS) LABELS_STATUS="$val" ;;
    PROJECT_STATUS) PROJECT_STATUS="$val" ;;
    PRIORITY_STATUS) PRIORITY_STATUS="$val" ;;
  esac
done <<EOF
$INIT2
EOF
```

phase2 re-reads `CFG`/config FRESH from disk (it depends on no phase1 shell vars) and covers:

## Step 9: Bootstrap labels

Handled by phase2 via `bootstrap-labels.sh "$REPO" --config "$CFG"` → emits `LABELS_STATUS` (`ok | skipped-no-repo | fail`). The `--config` flag picks up the now-final `labels.areas` and creates `area:<name>` labels (color `c9d4dd`); existing labels are skipped (`gh label create … || true`). If `REPO` is empty, the step is `skipped-no-repo` and the user runs `bootstrap-labels.sh` manually.

## Step 9b: Verify project + Status field options

Handled by phase2 via `gh project field-list` (owner-agnostic — works for user- and org-owned boards). It reads `project.owner`/`project.number` from `CFG`, compares the Status field's option names against the config's `project.statuses` values, and emits `PROJECT_STATUS` (`ok | incomplete | unconfigured`). Note: this verification does NOT issue a `gh api graphql` org query — it uses the CLI's `field-list`.

## Step 9c: Priority field (org mode only — ensure the org issue field)

Handled by phase2 (org mode only) → emits `PRIORITY_STATUS` (`ok | incomplete | skip-user-repo | unconfigured | fail`). It sources `lib/project.sh` and calls `sillok_org_priority_field_ensure` to discover/create the org Priority **issue field** (single-select from `project.priorities`, projected onto the board — API-only, not GUI-creatable), then verifies option coverage. User repos skip this entirely (`skip-user-repo`; p1–p4 labels are the priority record there). On steady-state re-init the step is `ok` without prompting or changing anything.

## Step 10: Ensure spec/plan dirs + gitignore

Handled by phase2 — `mkdir -p` the `docs.specs`/`docs.plans` dirs and append them to `.gitignore` if absent (they are local working artifacts; the issue body is the canonical record).

## Step 11: Print summary

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
      bash ${CLAUDE_PLUGIN_ROOT}/scripts/bootstrap-labels.sh <repo> --config <cfg-path>
  - Or just ask Claude in natural language, e.g.
      "remove area:foo and add area:bar from sillok config, then re-bootstrap labels"
```

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
- Skip CLAUDE.md import-block append if the `## Sillok workflow rules` marker is already present
- Skip label creation for labels that already exist (handled by `bootstrap-labels.sh` with `|| true`)
- Deep-merge `workflow.config.json` on re-run via `migrate-config.sh`: add missing template keys, preserve existing user values, keep arrays verbatim
- Preserve existing `labels.areas` array: if non-empty in the existing config, Step 8b reports `skip-preserved` and does NOT overwrite (user's curation wins over auto-pick)
- Priority field steady state asks nothing and changes nothing: when the field exists and every `project.priorities` value matches an option, Step 9c reports `ok` without prompting or writing (a once-confirmed `mapped` config matches on every later run)

## Integration

`init` is one-time project setup and sits OUTSIDE the workflow chain: it is always interactive (modulo the auto-mode contract above) and is never part of the start → design → execute → end chain — `sillok:workflow`'s transition map explicitly excludes it and never auto-runs it (a missing config means "suggest `/sillok-init`", nothing more). There is no stage handoff here; the Step 11 footer (`Next: /sillok-start ...`) is the only follow-up pointer.

- `sillok:workflow` — after init, natural-language workflow intent routes through the orchestrator; it activates only once `.claude/sillok/workflow.config.json` exists.
- `sillok:start` — the first chain stage a freshly initialized project runs.
- `sillok:gh-issue-management` — conventions backing the labels/types/project setup performed here.
