---
name: init
description: Internal sillok stage skill — enter via the /sillok-init command only (init sits outside the workflow chain and is never routed by sillok:workflow). Bootstraps a project for sillok; idempotent.
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

**Per-step script-contract reference is in `phase-reference.md`** (read on demand): what each phase1/phase2 step does (`Handled by phaseN → emits X`), the Step 11 summary output template + headline-icon table, and the Idempotency guarantees. This SKILL.md keeps only the action blocks — phase runs, the field reader, the Step 2a-2 URL prompt, the whole Step 8b classification, and the two HARD GATES.

## Run phase1 (Steps 1–8, deterministic)

```bash
INIT1=$(bash "${CLAUDE_PLUGIN_ROOT}/scripts/init-bootstrap.sh" phase1) || {
  echo "[sillok-init] phase1 failed — see stderr above. Stopping." >&2
  exit 1
}
```

**If phase1 exits non-zero, stop here** — do not run Step 8b or phase2. Step 1 hard-fails this way on a missing `git`/`gh`/`jq` or a non-repo CWD; surface phase1's stderr to the user (under auto-mode too, where nothing else is watching the stderr soft-contract) instead of proceeding with empty status vars.

Then parse `$INIT1` with the field reader above. phase1 covers Steps 1–8 (all relocated verbatim into the script) — see `phase-reference.md` for the per-step `Handled by phase1 → emits X` contract, including the `migrate-config.sh`/`refresh-rules.sh`/`CONFIG_STATUS=migrated` details (Steps 6–7). The two judgment steps inside that range stay in this skill:

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

## Steps 2b–8: handled by phase1 (reference)

Steps 2b (org Issue Types → `TYPES_STATUS`), 3 (stack/`detect-stack.sh` → `STACK` + `install`/`verify.*`), 4 (branch prefix → `BRANCH_PREFIX`), 5 (worktree copy files → `worktree.copyFiles`), 6 (`workflow.config.json` via `migrate-config.sh` → `CONFIG_STATUS=ok|migrated|fail`), 7 (rules via `refresh-rules.sh` → `RULES_STATUS`), 7b (shims via `write-shim-commands.sh` → `SHIM_STATUS`, REQUIRED), and 8 (`CLAUDE.md` imports → `CLAUDE_MD_STATUS`) all run inside phase1 — you do not act on them, you only parse their status keys. See `phase-reference.md` for each step's full `Handled by phase1 → emits X` contract.

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

phase2 re-reads `CFG`/config FRESH from disk (it depends on no phase1 shell vars) and covers Steps 9 (labels via `bootstrap-labels.sh` → `LABELS_STATUS`), 9b (project + Status options via `gh project field-list` → `PROJECT_STATUS`), 9c (org Priority issue field via `sillok_org_priority_field_ensure`, org mode only → `PRIORITY_STATUS`), and 10 (spec/plan dirs + `.gitignore`). You do not act on these — you only parse their status keys. See `phase-reference.md` for each step's full `Handled by phase2 → emits X` contract.

## Step 11: Print summary

Compose the summary from the phase1 + phase2 keys plus the skill-owned `AREA_STATUS`. **The headline-icon logic (`bash` block), the printed `Created:` template, the area-label sub-summary table, the "Not what you want?" guide, the warnings block, and the footer all live in `phase-reference.md` → "Step 11: Summary output"** — read it and reproduce the output verbatim. Nothing here is an action the agent computes beyond filling the status placeholders.

## Idempotency guarantees

Re-running `/sillok-init` is idempotent (all preserved by the two-phase script + in-skill 8b): rules/shim refresh, CLAUDE.md marker-guard + per-rule backfill, label `|| true` skip, config deep-merge via `migrate-config.sh`, `labels.areas` `skip-preserved` preservation, and Priority-field steady state. The full per-guarantee list is in `phase-reference.md` → "Idempotency guarantees".

## Integration

`init` is one-time project setup and sits OUTSIDE the workflow chain: it is always interactive (modulo the auto-mode contract above) and is never part of the start → design → execute → end chain — `sillok:workflow`'s transition map explicitly excludes it and never auto-runs it (a missing config means "suggest `/sillok-init`", nothing more). There is no stage handoff here; the Step 11 footer (`Next: /sillok-start ...`) is the only follow-up pointer.

- `sillok:workflow` — after init, natural-language workflow intent routes through the orchestrator; it activates only once `.claude/sillok/workflow.config.json` exists.
- `sillok:start` — the first chain stage a freshly initialized project runs.
- `sillok:gh-issue-management` — conventions backing the labels/types/project setup performed here.
