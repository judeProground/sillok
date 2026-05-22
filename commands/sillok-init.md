---
description: Bootstrap a project for sillok. Zero-prompt — detects repo, base branch, package manager, gitignored config files, and branch prefix automatically. Idempotent.
---

You are running `/sillok-init` to bootstrap the current project for sillok.

**This command takes no arguments and asks no questions.** If detection of any field fails, the field is left empty in the generated config and a warning is printed; the user edits `.claude/sillok/workflow.config.json` afterward.

**Auto-mode contract:** every step below MUST execute. Do not skip Step 7b (shim install) or Step 8b (area auto-pick) even when invoked by an auto-mode agent — both are deterministic, write only to plugin-managed paths, and have idempotent safeguards documented in their own headers.

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
```

## Step 2: Detect repo and base branch

```bash
REPO=$(gh repo view --json owner,name --jq '"\(.owner.login)/\(.name)"' 2>/dev/null || echo "")
BASE_BRANCH=$(gh repo view --json defaultBranchRef --jq '.defaultBranchRef.name' 2>/dev/null || echo "main")
```

If `REPO` is empty, set a warning flag (printed at end). The user will need to fill `repo` in the generated config manually.

## Step 2b: Verify org Issue Types

```bash
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
```

`TYPES_STATUS` is initialized to `fail` in Step 1 and surfaces in the Step 11 summary. A `missing` value triggers the ⚠️ warnings headline.

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

# If config already exists, do NOT overwrite — print notice and skip this step.
if [[ -f "$CFG" ]]; then
  echo "[sillok-init] $CFG already exists — leaving as-is. Edit manually to update."
  CONFIG_STATUS=preserved
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
    '{
      "$schema": "https://raw.githubusercontent.com/judeProground/sillok/main/schema/v1.json",
      "version": 1,
      "repo": $repo,
      "baseBranch": $baseBranch,
      "branchPrefix": $branchPrefix,
      "prdRepo": "",
      "project": {
        "owner": "",
        "number": 0,
        "statusField": "Status",
        "statuses": {
          "todo": "Todo",
          "design": "In Design",
          "progress": "In Progress",
          "review": "In QA",
          "done": "Done"
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
if mkdir -p "$PROJECT_ROOT/.claude/sillok/rules"; then
  SKIPPED_RULES=()
  RULES_STATUS=ok
  for src in "${CLAUDE_PLUGIN_ROOT}/templates/rules/"*.md; do
    name=$(basename "$src")
    dest="$PROJECT_ROOT/.claude/sillok/rules/$name"
    if [[ -f "$dest" ]]; then
      SKIPPED_RULES+=("$name")
    else
      if ! cp "$src" "$dest"; then
        RULES_STATUS=fail
      fi
    fi
  done
else
  RULES_STATUS=fail
fi
```

## Step 7b: Write command shortcut shims (REQUIRED)

This step is REQUIRED. Do not skip even when operating in auto-mode. The script only writes to `.claude/commands/sillok-*.md` files (5 specific filenames), respects existing foreign files via the `sillok-shim: true` marker, and is fully idempotent. Skipping it leaves the plugin's `/sillok-*` shortcuts inactive — a silent regression for the user.

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

## Step 8b: Auto-pick area labels

Scan the project for vertical-slice candidates and auto-select a conservative subset for `area:<name>` GitHub labels. This step is **non-interactive** (no `AskUserQuestion` call) so the init preamble's "asks no questions" guarantee holds. The user can adjust the selection afterward by editing `labels.areas` in `workflow.config.json` or by asking Claude to do it in natural language.

1. **Skip if user already curated areas.** Re-running init on a project where `labels.areas` is already non-empty should NOT clobber the user's curation:

   ```bash
   EXISTING_AREAS=$(jq -r '(.labels.areas // [])[]' "$CFG" 2>/dev/null | wc -l | tr -d ' ')
   if [[ "$EXISTING_AREAS" -gt 0 ]]; then
     AREA_STATUS=skip-preserved
     # leave $CFG untouched; report in summary
   else
     ...continue to step 2...
   fi
   ```

2. **Detect candidates.**

   ```bash
   CANDIDATES=$(bash "${CLAUDE_PLUGIN_ROOT}/scripts/detect-slices.sh" "$PROJECT_ROOT" 2>/dev/null || true)
   ```

3. **No candidates → silent ok.**

   ```bash
   if [[ -z "$CANDIDATES" ]]; then
     AREA_STATUS=none-detected
     # leave labels.areas as []
   fi
   ```

4. **Auto-pick with two filters:**

   - **Rank ≥ 2.** A candidate must appear in at least 2 layout families. Names that appear only once are excluded as low-confidence noise.
   - **Top 15.** Cap the resulting list so a sprawling project doesn't generate 50+ noisy labels.

   The filter lives in `scripts/pick-areas.sh` (not inline awk) because agent-readers of this markdown spec strip bare `$N` field references when they appear in code blocks, corrupting an inline `awk` filter.

   ```bash
   selected=$(printf '%s\n' "$CANDIDATES" | bash "${CLAUDE_PLUGIN_ROOT}/scripts/pick-areas.sh")
   ```

5. **Persist to config.**

   ```bash
   if [[ -n "$selected" ]]; then
     selected_json=$(printf '%s\n' $selected | jq -R . | jq -s .)
     tmp=$(mktemp)
     jq --argjson areas "$selected_json" '.labels.areas = $areas' "$CFG" > "$tmp" && mv "$tmp" "$CFG"
     AREA_STATUS=auto-picked
     AREA_COUNT=$(printf '%s\n' $selected | wc -l | tr -d ' ')
   else
     AREA_STATUS=none-confident   # candidates existed but all rank 1
   fi
   ```

6. **Surface the result in Step 11** with the names listed and a follow-up guide on how to adjust.

`AREA_STATUS` is one of: `auto-picked`, `none-detected`, `none-confident`, `skip-preserved`. Each maps to a distinct summary line (see Step 11).

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
  expected_opts=("Todo" "In Design" "In Progress" "In QA" "Done")
  actual_opts=$(gh api graphql -f query="{ organization(login: \"$PROJ_OWNER\") { projectV2(number: $PROJ_NUM) { field(name: \"Status\") { ... on ProjectV2SingleSelectField { options { name } } } } } }" --jq '.data.organization.projectV2.field.options[].name' 2>/dev/null || echo "")

  proj_missing=()
  for opt in "${expected_opts[@]}"; do
    if ! echo "$actual_opts" | grep -qx "$opt"; then
      proj_missing+=("$opt")
    fi
  done

  if [[ ${#proj_missing[@]} -gt 0 ]]; then
    echo "[sillok-init] Project $PROJ_OWNER/projects/$PROJ_NUM Status field missing options: ${proj_missing[*]}"
    echo "  Add via UI: https://github.com/orgs/$PROJ_OWNER/projects/$PROJ_NUM/settings"
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

## Step 10: Ensure spec/plan dirs

```bash
SPEC_DIR=$(jq -r '.docs.specs' "$CFG")
PLAN_DIR=$(jq -r '.docs.plans' "$CFG")
mkdir -p "$PROJECT_ROOT/$SPEC_DIR" "$PROJECT_ROOT/$PLAN_DIR"
```

## Step 11: Print summary

Compute the headline status icon from sub-step outcomes:

```bash
# Inputs (set by earlier steps):
#   CONFIG_STATUS   = ok | preserved | fail        (Step 6)
#   RULES_STATUS    = ok | fail                    (Step 7)
#   SHIM_STATUS     = ok | fail                    (Step 7b)
#   CLAUDE_MD_STATUS= ok | fail                    (Step 8)
#   AREA_STATUS     = auto-picked | none-detected | none-confident | skip-preserved | fail   (Step 8b)
#   LABELS_STATUS   = ok | skipped-no-repo | fail  (Step 9)
#   TYPES_STATUS    = ok | missing | fail          (Step 2b)
#   PROJECT_STATUS  = ok | incomplete | unconfigured | fail   (Step 9b)

# Critical steps — must all succeed for ✅
if [[ "$CONFIG_STATUS" == "fail" || "$RULES_STATUS" == "fail" || "$CLAUDE_MD_STATUS" == "fail" || "$LABELS_STATUS" == "fail" ]]; then
  HEADLINE="❌ sillok init FAILED"
elif [[ "$TYPES_STATUS" == "missing" || "$PROJECT_STATUS" == "incomplete" ]]; then
  HEADLINE="⚠️  sillok initialized (with warnings — see below)"
elif [[ "$SHIM_STATUS" == "fail" || "$AREA_STATUS" == "fail" ]]; then
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

Created:
- .claude/sillok/workflow.config.json                  [<CONFIG_STATUS>]
- .claude/sillok/rules/* (N files, M skipped: <list>)  [<RULES_STATUS>]
- .claude/commands/sillok-{start,design,execute,end,epic}.md  [<SHIM_STATUS>]
- CLAUDE.md (appended Sillok import block)             [<CLAUDE_MD_STATUS>]
- <SPEC_DIR>/ and <PLAN_DIR>/ (ensured)
- Labels on <REPO>                                     [<LABELS_STATUS>]
- Org Issue Types (Epic/Story/Feature/Task/Bug)        [<TYPES_STATUS>]
- Project + Status options                             [<PROJECT_STATUS>]
```

**Area-label sub-summary** (always printed when relevant):

| `AREA_STATUS` | Output |
|---|---|
| `auto-picked` | `📊 Area labels auto-selected (rank ≥ 2, top 15): area:<n1>, area:<n2>, …` followed by the "Not what you want?" guide below. |
| `none-detected` | `📊 No vertical-slice layout detected — no area labels created.` |
| `none-confident` | `📊 Slice candidates found but all rank 1 (single-family) — skipped auto-pick.` |
| `skip-preserved` | `📊 labels.areas already curated (<N> entries) — auto-pick skipped to preserve user edits.` |
| `fail` | `📊 Area auto-pick FAILED — re-run manually: bash <plugin>/scripts/detect-slices.sh "$PROJECT_ROOT"` |

The "Not what you want?" guide (for `auto-picked` only):

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
- Skip rule files that already exist (do NOT overwrite)
- Refresh shim command files that carry `sillok-shim: true` (so a plugin upgrade can update the shim format); leave foreign `.claude/commands/sillok-*.md` files untouched
- Skip CLAUDE.md import-block append if the marker is already present
- Skip label creation for labels that already exist (handled by `bootstrap-labels.sh` with `|| true`)
- Leave `workflow.config.json` alone if it already exists (report "config already present — edit manually to update")
- Preserve existing `labels.areas` array: if non-empty in the existing config, Step 8b reports `skip-preserved` and does NOT overwrite (user's curation wins over auto-pick)
