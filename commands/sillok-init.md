---
description: Bootstrap a project for sillok. Zero-prompt — detects repo, base branch, package manager, gitignored config files, and branch prefix automatically. Idempotent.
---

You are running `/sillok-init` to bootstrap the current project for sillok.

**This command takes no arguments and asks no questions.** If detection of any field fails, the field is left empty in the generated config and a warning is printed; the user edits `.claude/sillok/workflow.config.json` afterward.

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
```

## Step 2: Detect repo and base branch

```bash
REPO=$(gh repo view --json owner,name --jq '"\(.owner.login)/\(.name)"' 2>/dev/null || echo "")
BASE_BRANCH=$(gh repo view --json defaultBranchRef --jq '.defaultBranchRef.name' 2>/dev/null || echo "main")
```

If `REPO` is empty, set a warning flag (printed at end). The user will need to fill `repo` in the generated config manually.

## Step 3: Detect package manager and verify commands

```bash
PROJECT_ROOT=$(git rev-parse --show-toplevel)
eval "$(bash "${CLAUDE_PLUGIN_ROOT}/scripts/detect-stack.sh" "$PROJECT_ROOT")"
# Sets: install, lint, typecheck, format
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

Find gitignored files in the project root that match common config patterns:

```bash
COPY_FILES=()
while IFS= read -r f; do
  case "$f" in
    *.env|*.env.local|*.env.production|.env|.env.*) COPY_FILES+=("$f") ;;
    eas.json) COPY_FILES+=("$f") ;;
    google-services.json|GoogleService-Info.plist) COPY_FILES+=("$f") ;;
  esac
done < <(cd "$PROJECT_ROOT" && git ls-files --others --ignored --exclude-standard 2>/dev/null | head -50)
```

## Step 6: Write `workflow.config.json`

```bash
mkdir -p "$PROJECT_ROOT/.claude/sillok"
CFG="$PROJECT_ROOT/.claude/sillok/workflow.config.json"

# If config already exists, do NOT overwrite — print notice and skip this step.
if [[ -f "$CFG" ]]; then
  echo "[sillok-init] $CFG already exists — leaving as-is. Edit manually to update."
else
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
      "worktree": { "enabled": true, "dir": ".worktrees", "copyFiles": $copyFiles },
      "install": $install,
      "verify": { "lint": $lint, "typecheck": $typecheck, "format": $format },
      "docs": { "specs": "docs/superpowers/specs", "plans": "docs/superpowers/plans" },
      "commit": { "coAuthor": "" },
      "milestone": { "naming": "YYYY-MM-Wn", "sprintWeeks": 2, "weekStart": "monday" },
      "labels": {
        "types": ["feature","bug","improvement","infra","epic"],
        "stages": ["backlog","todo","designed","in-progress","in-review"],
        "priorities": ["p1","p2","p3","p4"],
        "areas": [],
        "defaults": { "type": "feature", "stage": "todo", "priority": "p3" }
      }
    }' > "$CFG"
fi
```

## Step 7: Scaffold rules

```bash
mkdir -p "$PROJECT_ROOT/.claude/sillok/rules"
SKIPPED_RULES=()
for src in "${CLAUDE_PLUGIN_ROOT}/templates/rules/"*.md; do
  name=$(basename "$src")
  dest="$PROJECT_ROOT/.claude/sillok/rules/$name"
  if [[ -f "$dest" ]]; then
    SKIPPED_RULES+=("$name")
  else
    cp "$src" "$dest"
  fi
done
```

## Step 8: Append `CLAUDE.md` imports

```bash
CLAUDE_MD="$PROJECT_ROOT/CLAUDE.md"
SNIPPET="${CLAUDE_PLUGIN_ROOT}/templates/claude-md-snippet.md"
if [[ ! -f "$CLAUDE_MD" ]]; then
  echo "# CLAUDE.md" > "$CLAUDE_MD"
  echo >> "$CLAUDE_MD"
fi
# Only append the import section if the marker line is not already there.
if ! grep -q "## Sillok workflow rules" "$CLAUDE_MD"; then
  echo >> "$CLAUDE_MD"
  cat "$SNIPPET" >> "$CLAUDE_MD"
fi
```

## Step 8b: Detect and offer area labels

Scan the project for vertical-slice candidates so the user can opt into a richer label taxonomy beyond the universal 14.

1. Run the detector:

   ```bash
   CANDIDATES=$(bash "${CLAUDE_PLUGIN_ROOT}/scripts/detect-slices.sh" "$PROJECT_ROOT" 2>/dev/null || true)
   ```

2. If `$CANDIDATES` is empty (no recognized slice layout), skip silently.
3. Otherwise, take the top 30 lines and present them via `AskUserQuestion` with `multiSelect: true`. Format each option as `<name> (in <rank> dirs)`; the rank suffix helps the user judge signal vs. noise (a name appearing in 4 layout families is almost certainly a domain; one in 1 is probably accidental).

   Question text: "Detected N candidate vertical slices in your project. Select the ones to create as `area:<name>` GitHub labels (any subset; cancel for none):"

4. For each selected name, write the array to `labels.areas` in `$CFG`:

   ```bash
   # Assume $selected holds a space-separated list of accepted names.
   selected_json=$(printf '%s\n' $selected | jq -R . | jq -s .)
   tmp=$(mktemp)
   jq --argjson areas "$selected_json" '.labels.areas = $areas' "$CFG" > "$tmp" && mv "$tmp" "$CFG"
   ```

5. Print a one-line confirmation: `labels.areas = [...]`.

If the user accepts none or cancels, leave `labels.areas: []` (the default written in Step 6).

## Step 9: Bootstrap labels

```bash
if [[ -n "$REPO" ]]; then
  bash "${CLAUDE_PLUGIN_ROOT}/scripts/bootstrap-labels.sh" "$REPO" --config "$CFG"
fi
```

The `--config` flag picks up `labels.areas` from the config (empty by default) and creates corresponding `area:<name>` labels with color `c9d4dd` (muted blue-gray).

If `$REPO` is empty (detection failed), skip with a warning that the user must run `bash ${CLAUDE_PLUGIN_ROOT}/scripts/bootstrap-labels.sh <owner>/<repo> --config <path-to-config>` manually.

## Step 10: Ensure spec/plan dirs

```bash
SPEC_DIR=$(jq -r '.docs.specs' "$CFG")
PLAN_DIR=$(jq -r '.docs.plans' "$CFG")
mkdir -p "$PROJECT_ROOT/$SPEC_DIR" "$PROJECT_ROOT/$PLAN_DIR"
```

## Step 11: Print summary

Print a single-screen summary:

```
✅ sillok initialized

Repo:          <REPO or "(detect failed, edit manually)">
Base branch:   <BASE_BRANCH>
Branch prefix: <BRANCH_PREFIX>
Stack:         <one of pnpm/yarn/npm/bun/bundler/go/cargo/poetry/pipenv or "unknown">

Created:
- .claude/sillok/workflow.config.json
- .claude/sillok/rules/* (N files, M skipped: <skipped list>)
- CLAUDE.md (appended Sillok import block)
- <SPEC_DIR>/ and <PLAN_DIR>/ (ensured)
- Labels on <REPO> (14 universal + N area labels, or "skipped — set repo first")

Warnings: <list, if any>

Next: /sillok-start to create your first feature.
```

## Idempotency guarantees

Re-running `/sillok-init` must:
- Skip rule files that already exist (do NOT overwrite)
- Skip CLAUDE.md import-block append if the marker is already present
- Skip label creation for labels that already exist (handled by `bootstrap-labels.sh` with `|| true`)
- Leave `workflow.config.json` alone if it already exists (report "config already present — edit manually to update")
