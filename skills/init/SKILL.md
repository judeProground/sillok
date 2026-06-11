---
name: init
description: Internal sillok stage skill — enter via the /sillok-init command only (init sits outside the workflow chain and is never routed by sillok:workflow). Bootstraps a project for sillok — detects repo, base branch, package manager, gitignored config files, and branch prefix automatically; asks at most two questions per run (conditional: project URL when no board is detected; auto-detected area labels when candidates found; Priority-field option mapping only when an existing board field mismatches the config), and nothing under auto-mode. Idempotent.
user-invocable: false
---

# Sillok Init

You are running sillok `init` to bootstrap the current project for sillok.

**Init takes no arguments and asks at most two questions per run**, drawn from three conditional ones — a project URL (only when auto-detection yields nothing — see Step 2a-2), the auto-detected area labels (Step 8b, interactive runs only), and the Priority-field option mapping (Step 9c, org mode, ONLY when an existing board field's options genuinely mismatch the config — a fresh or matching board asks nothing). Under auto-mode it asks nothing. If detection of any field fails, the field is left empty in the generated config and a warning is printed; the user edits `.claude/sillok/workflow.config.json` afterward.

**Auto-mode contract:** every step below MUST execute. Do not skip Step 7b (shim install) or Step 8b (area detection) even when invoked by an auto-mode agent. Step 7b is deterministic. Step 8b emits a deterministic tree (`project-tree.sh`), then classifies and confirms; under auto-mode the confirmation auto-accepts the classified list (written to the git-tracked config), so it never blocks. Both write only to plugin-managed paths and have idempotent safeguards documented in their own headers.

## Step 1: Verify prerequisites

Run silently:

```bash
need_missing=""
for cmd in git gh jq; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    need_missing="$need_missing $cmd"
  fi
done
if [[ -n "$need_missing" ]]; then
  echo "[sillok-init] missing tools:$need_missing"
  echo "[sillok-init] install them and re-run /sillok-init"
  exit 1
fi

if ! git rev-parse --show-toplevel >/dev/null 2>&1; then
  echo "[sillok-init] not inside a git repository — cd into the project root first"
  exit 1
fi

# Initialize sub-step status variables consumed by the Step 11 summary.
# Each step below sets its own; defaulting to "fail" makes any skipped step
# visible in the final status icon rather than silently masquerading as ok.
CONFIG_STATUS=fail
RULES_STATUS=fail
SHIM_STATUS=fail
CLAUDE_MD_STATUS=fail
AREA_STATUS=fail
LABELS_STATUS=fail
TYPES_STATUS=fail
PROJECT_STATUS=fail
PRIORITY_STATUS=fail
ORG_MODE=false
```

## Step 2: Detect repo and base branch

```bash
REPO=$(gh repo view --json owner,name --jq '"\(.owner.login)/\(.name)"' 2>/dev/null || echo "")
BASE_BRANCH=$(gh repo view --json defaultBranchRef --jq '.defaultBranchRef.name' 2>/dev/null || echo "main")
```

If `REPO` is empty, set a warning flag (printed at end). The user will need to fill `repo` in the generated config manually.

## Step 2a: Detect org mode

```bash
OWNER_TYPE=$(gh api "/repos/$REPO" --jq '.owner.type' 2>/dev/null || echo "User")
if [[ "$OWNER_TYPE" == "Organization" ]]; then
  ORG_MODE=true
else
  ORG_MODE=false
  echo "[sillok-init] ⚠️  User-owned repo detected. Issue Types and linked branches unavailable — using label fallback mode."
fi
```

## Step 2a-2: Auto-detect project

```bash
PROJ_OWNER="${REPO%%/*}"
PROJ_NUM=0
PROJ_TITLE=""

# Try listing projects for the repo owner (works for both org and user)
proj_json=$(gh project list --owner "$PROJ_OWNER" --format json 2>/dev/null || echo '{"projects":[],"totalCount":0}')
proj_count=$(echo "$proj_json" | jq '.projects | length')
proj_total=$(echo "$proj_json" | jq '.totalCount // 0')

if [[ "$proj_count" == "1" ]]; then
  PROJ_NUM=$(echo "$proj_json" | jq -r '.projects[0].number')
  PROJ_TITLE=$(echo "$proj_json" | jq -r '.projects[0].title')
  echo "[sillok-init] Auto-detected project: $PROJ_TITLE (#$PROJ_NUM)"
elif [[ "$proj_count" -gt 1 ]]; then
  echo "[sillok-init] Multiple projects found for $PROJ_OWNER:"
  echo "$proj_json" | jq -r '.projects[] | "  \(.number)) \(.title)"'
  echo "[sillok-init] Set project.owner and project.number in workflow.config.json manually."
else
  # Empty-case: 0 open projects under the repo owner. Note closed/hidden, then
  # prompt once for a project URL (acceptable exception to zero-prompt — only
  # fires when auto-detection yields nothing).
  if [[ "$proj_total" -gt 0 ]]; then
    echo "[sillok-init] No OPEN projects under $PROJ_OWNER (but $proj_total closed/hidden project(s) exist — list with 'gh project list --owner $PROJ_OWNER --closed')."
  else
    echo "[sillok-init] No projects found under $PROJ_OWNER."
  fi
  read -r -p "If your board lives elsewhere, paste its URL (or press Enter to skip): " proj_url
  if [[ -n "$proj_url" ]]; then
    parsed=$(bash "${CLAUDE_PLUGIN_ROOT}/scripts/parse-project-url.sh" "$proj_url" 2>/dev/null || echo "")
    url_owner=$(echo "$parsed" | awk -F= '$1=="owner"{print $2}')
    url_number=$(echo "$parsed" | awk -F= '$1=="number"{print $2}')
    if [[ -n "$url_owner" && -n "$url_number" ]]; then
      PROJ_OWNER="$url_owner"
      PROJ_NUM="$url_number"
      PROJ_TITLE=$(gh project view "$PROJ_NUM" --owner "$PROJ_OWNER" --format json --jq '.title' 2>/dev/null || echo "(unknown)")
      echo "[sillok-init] Project set from URL: $PROJ_TITLE (#$PROJ_NUM, owner=$PROJ_OWNER)"
    else
      echo "[sillok-init] URL did not match a GitHub project — skipping project setup."
    fi
  fi
fi
```

## Step 2b: Verify org Issue Types

If `$ORG_MODE` is `false`, skip this step entirely (Issue Types are org-only):

```bash
if [[ "$ORG_MODE" != "true" ]]; then
  TYPES_STATUS=skip-user-repo
else
  OWNER="${REPO%%/*}"
  expected_types=("Epic" "Story" "Feature" "Task" "Bug")
  existing_types=$(gh api -H "X-GitHub-Api-Version: 2026-03-10" "/orgs/$OWNER/issue-types" --jq '.[].name' 2>/dev/null || echo "")

  missing=()
  for t in "${expected_types[@]}"; do
    if ! echo "$existing_types" | grep -qx "$t"; then
      missing+=("$t")
    fi
  done

  if [[ ${#missing[@]} -gt 0 ]]; then
    echo "[sillok-init] Required org issue types missing: ${missing[*]}"
    echo "  Ask your org owner to run:"
    for t in "${missing[@]}"; do
      echo "    gh api -X POST -H 'X-GitHub-Api-Version: 2026-03-10' /orgs/$OWNER/issue-types -f name=$t"
    done
    echo "  Or via UI: https://github.com/organizations/$OWNER/settings/issue-types"
    TYPES_STATUS=missing
  else
    TYPES_STATUS=ok
  fi
fi
```

`TYPES_STATUS` is initialized to `fail` in Step 1 and surfaces in the Step 11 summary. A `missing` value triggers the ⚠️ warnings headline. `skip-user-repo` is informational (NOT a warning).

## Step 3: Detect package manager and verify commands

`detect-stack.sh` emits one `key=value` line per field. The values often contain whitespace (e.g. `install=yarn install`, `typecheck=npx tsc --noEmit`), so `eval` is unsafe — the shell would parse `install=yarn install` as a prefix-assignment followed by an `install` command. Use an explicit field reader instead:

```bash
PROJECT_ROOT=$(git rev-parse --show-toplevel)
install=""; lint=""; typecheck=""; format=""
while IFS='=' read -r key val; do
  case "$key" in
    install)   install="$val" ;;
    lint)      lint="$val" ;;
    typecheck) typecheck="$val" ;;
    format)    format="$val" ;;
  esac
done < <(bash "${CLAUDE_PLUGIN_ROOT}/scripts/detect-stack.sh" "$PROJECT_ROOT")
```

If `install` is empty, set a warning flag noting "unknown stack — fill verify.* manually".

## Step 4: Branch prefix default

```bash
# The default template uses {type}/issue-, which substitutes to feature/issue-,
# bug/issue-, epic/issue-, etc. at branch-creation time. Users can override to
# any literal or templated string by editing workflow.config.json.
BRANCH_PREFIX="{type}/issue-"
```

## Step 5: Detect worktree copy files

Find gitignored files that match common per-worktree config patterns. The pipeline pre-filters with `grep` so dependency-cache entries like `node_modules/**/*` don't crowd out the actual config files; the case-filter inside the loop then acts as a final defence-in-depth check.

```bash
COPY_FILES=()
while IFS= read -r f; do
  case "$f" in
    *.env|*.env.local|*.env.production|.env|.env.*) COPY_FILES+=("$f") ;;
    *eas.json|eas.json) COPY_FILES+=("$f") ;;
    *google-services.json|google-services.json) COPY_FILES+=("$f") ;;
    *GoogleService-Info.plist|GoogleService-Info.plist) COPY_FILES+=("$f") ;;
  esac
done < <(cd "$PROJECT_ROOT" && git ls-files --others --ignored --exclude-standard 2>/dev/null \
  | grep -E '(^|/)(\.env(\..*)?|eas\.json|google-services\.json|GoogleService-Info\.plist)$' \
  | grep -vE '^(node_modules|vendor|target|dist|build|out|coverage|\.next|\.turbo|\.svelte-kit|\.nuxt|\.cache)/' \
  | head -200)
```

Two-stage filter rationale:

1. **First `grep`** narrows the gitignored-file list to candidates that *might* be per-worktree config. Without this, `git ls-files --others --ignored` is dominated by `node_modules/` (typically tens of thousands of entries), drowning out the root-level config we care about.
2. **Second `grep -v`** excludes matches that happen to live inside dependency caches or build outputs (e.g. a third-party package shipping its own `.env.example` under `node_modules/foo/.env.example`). Those files are owned by the dependency, not the project, and copying them into a new worktree is wrong (worktrees reinstall dependencies anyway).
3. **`head -200`** is a safety bound for absurdly large match sets — well above any realistic per-project config count.

The case-filter inside the loop remains as a final defence-in-depth check.

## Step 6: Write `workflow.config.json`

```bash
mkdir -p "$PROJECT_ROOT/.claude/sillok"
CFG="$PROJECT_ROOT/.claude/sillok/workflow.config.json"

MERGE_SUMMARY=""

# Existing config — deep-merge in any missing template keys (user values win).
if [[ -f "$CFG" ]]; then
  if MERGE_SUMMARY=$(bash "${CLAUDE_PLUGIN_ROOT}/scripts/migrate-config.sh" \
      "$CFG" "${CLAUDE_PLUGIN_ROOT}/templates/workflow.config.json"); then
    if [[ -n "$MERGE_SUMMARY" ]]; then
      echo "$MERGE_SUMMARY"
      CONFIG_STATUS=migrated
    else
      CONFIG_STATUS=ok
    fi
  else
    CONFIG_STATUS=fail
  fi
else
  CONFIG_STATUS=ok
  # Build copyFiles JSON array
  copyfiles_json=$(printf '%s\n' "${COPY_FILES[@]}" | jq -R . | jq -s .)

  jq -n \
    --arg repo "$REPO" \
    --arg baseBranch "$BASE_BRANCH" \
    --arg branchPrefix "$BRANCH_PREFIX" \
    --argjson copyFiles "$copyfiles_json" \
    --arg install "$install" \
    --arg lint "$lint" \
    --arg typecheck "$typecheck" \
    --arg format "$format" \
    --argjson orgMode "$ORG_MODE" \
    --arg projOwner "$PROJ_OWNER" \
    --argjson projNum "$PROJ_NUM" \
    '{
      "$schema": "https://raw.githubusercontent.com/judeProground/sillok/main/schema/v1.json",
      "version": 1,
      "repo": $repo,
      "baseBranch": $baseBranch,
      "branchPrefix": $branchPrefix,
      "prdRepo": "",
      "orgMode": $orgMode,
      "project": {
        "owner": $projOwner,
        "number": $projNum,
        "statusField": "Status",
        "statuses": {
          "todo": "Todo",
          "design": "In Design",
          "progress": "In Progress",
          "review": "In QA",
          "done": "Done"
        },
        "priorityField": "Priority",
        "priorities": {
          "p1": "Urgent",
          "p2": "High",
          "p3": "Medium",
          "p4": "Low"
        }
      },
      "types": {
        "list": ["Epic", "Story", "Feature", "Task", "Bug"],
        "defaults": {
          "feature": "Feature",
          "composite": "Story",
          "prd": "Epic"
        }
      },
      "worktree": { "enabled": true, "dir": ".worktrees", "copyFiles": $copyFiles },
      "install": $install,
      "verify": { "lint": $lint, "typecheck": $typecheck, "format": $format },
      "docs": { "specs": "docs/superpowers/specs", "plans": "docs/superpowers/plans" },
      "commit": { "coAuthor": "" },
      "milestone": { "naming": "YYYY-MM-Wn", "sprintWeeks": 2, "weekStart": "monday" },
      "labels": {
        "priorities": ["p1", "p2", "p3", "p4"],
        "areas": [],
        "natures": ["improvement", "refactor", "infra", "docs", "security", "performance"],
        "defaults": { "priority": "p3" }
      }
    }' > "$CFG"
fi
```

## Step 7: Scaffold rules

```bash
RULES_DIR="$PROJECT_ROOT/.claude/sillok/rules"
if REFRESH_SUMMARY=$(bash "${CLAUDE_PLUGIN_ROOT}/scripts/refresh-rules.sh" \
    "$RULES_DIR" "${CLAUDE_PLUGIN_ROOT}/templates/rules"); then
  RULES_STATUS=ok
  [[ -n "$REFRESH_SUMMARY" ]] && echo "$REFRESH_SUMMARY"
else
  RULES_STATUS=fail
fi
```

## Step 7b: Write command shortcut shims (REQUIRED)

This step is REQUIRED. Do not skip even when operating in auto-mode. The script only writes to `.claude/commands/sillok-*.md` files (6 specific filenames), respects existing foreign files via the `sillok-shim: true` marker, and is fully idempotent. Skipping it leaves the plugin's `/sillok-*` shortcuts inactive — a silent regression for the user.

Plugin slash commands are namespaced by Claude Code (`/sillok:sillok-start` etc.). The shims under `.claude/commands/` are the only supported mechanism for the shorter `/sillok-start` form.

```bash
if bash "${CLAUDE_PLUGIN_ROOT}/scripts/write-shim-commands.sh" "$PROJECT_ROOT"; then
  SHIM_STATUS=ok
else
  SHIM_STATUS=fail
fi
```

`SHIM_STATUS` feeds the final-summary status calculation in Step 11. If `fail`, the summary becomes ⚠️ with a follow-up command the user can copy.

## Step 8: Append `CLAUDE.md` imports

```bash
CLAUDE_MD="$PROJECT_ROOT/CLAUDE.md"
SNIPPET="${CLAUDE_PLUGIN_ROOT}/templates/claude-md-snippet.md"
CLAUDE_MD_STATUS=ok
if [[ ! -f "$CLAUDE_MD" ]]; then
  if ! { echo "# CLAUDE.md" > "$CLAUDE_MD" && echo >> "$CLAUDE_MD"; }; then
    CLAUDE_MD_STATUS=fail
  fi
fi
# Only append the import section if the marker line is not already there.
if [[ "$CLAUDE_MD_STATUS" == "ok" ]] && ! grep -q "## Sillok workflow rules" "$CLAUDE_MD"; then
  if ! { echo >> "$CLAUDE_MD" && cat "$SNIPPET" >> "$CLAUDE_MD"; }; then
    CLAUDE_MD_STATUS=fail
  fi
fi
```

## Step 8b: Auto-detect area labels (hybrid — tree → classify → confirm)

Detect vertical business feature areas for `area:<name>` GitHub labels. The
deterministic part (emit the project's directory structure) is done by
`project-tree.sh`; the judgment part (which dirs are business domains vs. technical
layers) is done by **you**, the LLM running this skill; GitHub labels are created
only after a one-time confirmation.

1. **Skip if user already curated areas.** Re-running init on a project where
   `labels.areas` is already non-empty must NOT clobber the user's curation:

   ```bash
   EXISTING_AREAS=$(jq -r '(.labels.areas // [])[]' "$CFG" 2>/dev/null | wc -l | tr -d ' ')
   if [[ "$EXISTING_AREAS" -gt 0 ]]; then
     AREA_STATUS=skip-preserved
   fi
   ```

   When `skip-preserved`, **Step 8b is done — skip steps 2–6.**

2. **Emit the directory tree (deterministic).**

   ```bash
   TREE=$(bash "${CLAUDE_PLUGIN_ROOT}/scripts/project-tree.sh" "$PROJECT_ROOT" 2>/dev/null || true)
   ```

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
   one per line (empty when none).

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
`fail`. Each maps to a distinct summary line (see Step 11).

## Step 9: Bootstrap labels

```bash
if [[ -n "$REPO" ]]; then
  if bash "${CLAUDE_PLUGIN_ROOT}/scripts/bootstrap-labels.sh" "$REPO" --config "$CFG"; then
    LABELS_STATUS=ok
  else
    LABELS_STATUS=fail
  fi
else
  LABELS_STATUS=skipped-no-repo
fi
```

The `--config` flag picks up `labels.areas` from the config (empty by default) and creates corresponding `area:<name>` labels with color `c9d4dd` (muted blue-gray).

If `$REPO` is empty (detection failed), skip with a warning that the user must run `bash ${CLAUDE_PLUGIN_ROOT}/scripts/bootstrap-labels.sh <owner>/<repo> --config <path-to-config>` manually.

## Step 9b: Verify project + Status field options

If `project.owner` and `project.number` are configured, verify the project exists and the Status field has the expected option names.

```bash
PROJ_OWNER=$(jq -r '.project.owner' "$CFG")
PROJ_NUM=$(jq -r '.project.number' "$CFG")
if [[ -n "$PROJ_OWNER" && "$PROJ_NUM" != "0" && "$PROJ_NUM" != "null" ]]; then
  # Expected options come from the config's project.statuses VALUES (all six,
  # including Backlog — #33), not a hardcoded list: the config is the contract
  # the stage skills resolve against, so re-init must verify exactly what they
  # will use.
  expected_opts=()
  while IFS= read -r opt; do expected_opts+=("$opt"); done \
    < <(jq -r '.project.statuses // {} | .[]' "$CFG")
  # gh project field-list is owner-agnostic (works for both user- and org-owned boards)
  actual_opts=$(gh project field-list "$PROJ_NUM" --owner "$PROJ_OWNER" --format json \
    --jq '.fields[] | select(.name=="Status") | .options[].name' 2>/dev/null || echo "")

  proj_missing=()
  for opt in "${expected_opts[@]}"; do
    if ! echo "$actual_opts" | grep -qx "$opt"; then
      proj_missing+=("$opt")
    fi
  done

  if [[ ${#proj_missing[@]} -gt 0 ]]; then
    echo "[sillok-init] Project $PROJ_OWNER/projects/$PROJ_NUM Status field missing options: ${proj_missing[*]}"
    echo "  Add via UI: https://github.com/orgs/$PROJ_OWNER/projects/$PROJ_NUM/settings (or /users/$PROJ_OWNER/projects/$PROJ_NUM/settings for a user board)"
    PROJECT_STATUS=incomplete
  else
    PROJECT_STATUS=ok
  fi
else
  PROJECT_STATUS=unconfigured
  echo "[sillok-init] Cross-repo PRD: set 'project.owner' and 'project.number' in workflow.config.json to enable status transitions"
fi
```

`PROJECT_STATUS` is initialized to `fail` in Step 1. Values: `ok` (project verified), `incomplete` (Status field missing options), `unconfigured` (project not yet set in config — informational, not a warning).

## Step 9c: Priority field (org mode only — ensure + option mapping)

On org repos, priority lives on the board's Priority single-select field (`project.priorityField`), not on `p1`–`p4` labels — the same native-primitive split as type→Issue Type and stage→Status. User repos keep the labels, so this whole step is skipped there.

1. **Gate + read the board's options for the configured field:**

   ```bash
   if [[ "$ORG_MODE" != "true" ]]; then
     PRIORITY_STATUS=skip-user-repo
   elif [[ -z "$PROJ_OWNER" || "$PROJ_NUM" == "0" || "$PROJ_NUM" == "null" ]]; then
     PRIORITY_STATUS=unconfigured
   else
     PRIORITY_FIELD=$(jq -r '.project.priorityField // "Priority"' "$CFG")
     pri_fields_json=$(gh project field-list "$PROJ_NUM" --owner "$PROJ_OWNER" --format json 2>/dev/null || echo '{"fields":[]}')
     pri_field_exists=$(echo "$pri_fields_json" | jq -r --arg f "$PRIORITY_FIELD" '[.fields[] | select(.name==$f)] | length')
     pri_field_type=$(echo "$pri_fields_json" | jq -r --arg f "$PRIORITY_FIELD" '.fields[] | select(.name==$f) | .type // ""')
     actual_pri_opts=$(echo "$pri_fields_json" | jq -r --arg f "$PRIORITY_FIELD" '.fields[] | select(.name==$f) | .options[]?.name')
   fi
   ```

   When `PRIORITY_STATUS` was set to `skip-user-repo` or `unconfigured`, **Step 9c is done — skip steps 2–4.**

2. **Field absent → auto-create, no question** (user-confirmed decision on #66; same resolution level as the Status detection in Step 9b, auto-accepted under auto-mode). `sillok_project_priority_field_ensure` creates the single-select via `createProjectV2Field` with options from `project.priorities` in p1→p4 order and prints one stderr notice:

   ```bash
   if [[ "$pri_field_exists" == "0" ]]; then
     source "${CLAUDE_PLUGIN_ROOT}/scripts/lib/project.sh"
     if sillok_project_priority_field_ensure; then
       PRIORITY_STATUS=created
     else
       PRIORITY_STATUS=fail
     fi
   fi
   ```

   When the field was absent, **Step 9c is done — skip steps 3–4.**

3. **Field exists → verify it's actually a single-select with options, then compare against the config mapping.** A name match alone is not enough — a text/number field named "Priority", or a single-select with zero options, can never hold a priority (`gh project field-list` exposes `.type`; require `ProjectV2SingleSelectField`):

   ```bash
   if [[ "$pri_field_type" != "ProjectV2SingleSelectField" || -z "$actual_pri_opts" ]]; then
     PRIORITY_STATUS=fail
     echo "[sillok-init] field '$PRIORITY_FIELD' exists but is not a single-select (or has no options) — rename/delete it or point project.priorityField elsewhere"
   fi
   ```

   When this gate fails, **Step 9c is done — skip step 4.** (`sillok_project_priority_field_ensure` itself stays a simple name check — this init gate is where field type and options are verified.)

   Otherwise compare the board's options against the config mapping values. Zero non-empty mapped values is a `fail`, not `ok` — an all-empty mapping can never set any priority:

   ```bash
   pri_mismatch=0
   pri_mapped=0
   for key in p1 p2 p3 p4; do
     want=$(jq -r ".project.priorities.$key // \"\"" "$CFG")
     if [[ -n "$want" ]]; then
       pri_mapped=$((pri_mapped + 1))
       if ! echo "$actual_pri_opts" | grep -qxF "$want"; then
         pri_mismatch=1
       fi
     fi
   done
   if [[ "$pri_mapped" == "0" ]]; then
     PRIORITY_STATUS=fail
     echo "[sillok-init] project.priorities maps no option names — fill in p1–p4 in workflow.config.json (the schema requires all four)"
   elif [[ "$pri_mismatch" == "0" ]]; then
     PRIORITY_STATUS=ok
   fi
   ```

   All four mapped names present → `ok`; zero mapped names → `fail`; **in either case Step 9c is done — skip step 4.** On `ok` nothing is asked and nothing changes (idempotent re-init).

4. **Genuine mismatch → propose the closest p1→p4 mapping (LLM judgment — you do this), confirm, persist.** Read `$actual_pri_opts` and map the board's options to sillok keys ordered most→least urgent (e.g. `P0/P1/P2` → p1=P0, p2=P1, p3=P2, p4=P2 — with fewer than four options the lowest keys share the least-urgent option; with more than four, pick the four clearest urgency levels).

   - **Interactive:** present the proposed mapping and ask the user to confirm or edit it (via `AskUserQuestion`). This is the Priority-mapping question from the at-most-two budget — it fires ONLY on genuine mismatch. If two questions were already asked this run, do not ask a third: accept the proposal silently (it lands in the git-tracked config, freely editable afterward).
   - **Auto-mode:** accept the proposed mapping without prompting.

   Persist the confirmed mapping (board option names stay untouched — the config absorbs naming differences, mirroring the `statuses` mapping philosophy):

   ```bash
   tmp=$(mktemp)
   jq --arg p1 "<p1-option>" --arg p2 "<p2-option>" --arg p3 "<p3-option>" --arg p4 "<p4-option>" \
     '.project.priorities = { "p1": $p1, "p2": $p2, "p3": $p3, "p4": $p4 }' "$CFG" > "$tmp" && mv "$tmp" "$CFG"
   PRIORITY_STATUS=mapped
   ```

`PRIORITY_STATUS` is one of: `ok`, `created`, `mapped`, `skip-user-repo`, `unconfigured`, `fail`. Only `fail` is a warning; `skip-user-repo` and `unconfigured` are informational.

## Step 10: Ensure spec/plan dirs + gitignore

```bash
SPEC_DIR=$(jq -r '.docs.specs' "$CFG")
PLAN_DIR=$(jq -r '.docs.plans' "$CFG")
mkdir -p "$PROJECT_ROOT/$SPEC_DIR" "$PROJECT_ROOT/$PLAN_DIR"
```

Spec and plan files are local working artifacts (the issue body is the canonical record). Add them to `.gitignore` if not already present:

```bash
GITIGNORE="$PROJECT_ROOT/.gitignore"
for entry in "$SPEC_DIR/" "$PLAN_DIR/"; do
  if ! grep -qxF "$entry" "$GITIGNORE" 2>/dev/null; then
    echo "$entry" >> "$GITIGNORE"
  fi
done
```

## Step 11: Print summary

Compute the headline status icon from sub-step outcomes:

```bash
# Inputs (set by earlier steps):
#   CONFIG_STATUS   = ok | migrated | fail          (Step 6)
#   RULES_STATUS    = ok | fail                    (Step 7)
#   SHIM_STATUS     = ok | fail                    (Step 7b)
#   CLAUDE_MD_STATUS= ok | fail                    (Step 8)
#   AREA_STATUS     = areas-confirmed | none-detected | skip-preserved | fail   (Step 8b)
#   LABELS_STATUS   = ok | skipped-no-repo | fail  (Step 9)
#   TYPES_STATUS    = ok | missing | skip-user-repo | fail   (Step 2b)
#   PROJECT_STATUS  = ok | incomplete | unconfigured | fail   (Step 9b)
#   PRIORITY_STATUS = ok | created | mapped | skip-user-repo | unconfigured | fail   (Step 9c)

# Critical steps — must all succeed for ✅
if [[ "$CONFIG_STATUS" == "fail" || "$RULES_STATUS" == "fail" || "$CLAUDE_MD_STATUS" == "fail" || "$LABELS_STATUS" == "fail" ]]; then
  HEADLINE="❌ sillok init FAILED"
elif [[ "$TYPES_STATUS" == "missing" || "$PROJECT_STATUS" == "incomplete" ]]; then
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
- Priority field on the board (org mode)               [<PRIORITY_STATUS>]
  - `skip-user-repo` → "📋 User-owned repo — board Priority field skipped (p1–p4 labels are the priority record)."
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

Re-running `/sillok-init` must:
- Refresh rule files from the plugin's `templates/rules/` (overwrite when content differs; local edits are not preserved — recover from git if needed)
- Refresh shim command files that carry `sillok-shim: true` (so a plugin upgrade can update the shim format); leave foreign `.claude/commands/sillok-*.md` files untouched
- Skip CLAUDE.md import-block append if the marker is already present
- Skip label creation for labels that already exist (handled by `bootstrap-labels.sh` with `|| true`)
- Deep-merge `workflow.config.json` on re-run: add missing template keys, preserve existing user values, keep arrays verbatim
- Preserve existing `labels.areas` array: if non-empty in the existing config, Step 8b reports `skip-preserved` and does NOT overwrite (user's curation wins over auto-pick)
- Priority field steady state asks nothing and changes nothing: when the board field exists and every `project.priorities` value matches an option, Step 9c reports `ok` without prompting or writing (a once-confirmed `mapped` config matches on every later run)

## Integration

`init` is one-time project setup and sits OUTSIDE the workflow chain: it is always interactive (modulo the auto-mode contract above) and is never part of the start → design → execute → end chain — `sillok:workflow`'s transition map explicitly excludes it and never auto-runs it (a missing config means "suggest `/sillok-init`", nothing more). There is no stage handoff here; the Step 11 footer (`Next: /sillok-start ...`) is the only follow-up pointer.

- `sillok:workflow` — after init, natural-language workflow intent routes through the orchestrator; it activates only once `.claude/sillok/workflow.config.json` exists.
- `sillok:start` — the first chain stage a freshly initialized project runs.
- `sillok:gh-issue-management` — conventions backing the labels/types/project setup performed here.
