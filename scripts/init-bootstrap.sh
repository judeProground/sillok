#!/usr/bin/env bash
# sillok — deterministic, side-effecting bootstrap for /sillok-init.
#
# This script relocates the deterministic bash from skills/init/SKILL.md so the
# skill body stays thin (intro + the two genuinely-interactive/LLM steps: the
# empty-case project-URL prompt and the area-label classification). It runs in
# TWO phases because the LLM writes `labels.areas` BETWEEN phase1 and phase2
# (Step 8b sits between Step 8 and Step 9 in the original flow), and a single
# straight-through script cannot interleave LLM judgment.
#
# Communication channel (same proven mechanism as detect-stack.sh /
# precompute-*.sh): a flat KEY=value status block on STDOUT, one key per line.
# Human-facing notices/warnings go to STDERR so they still surface but never
# pollute the status lines. The skill reads stdout with a
#   while IFS='=' read -r key val; ... done
# field-reader — NEVER `eval`: values like MERGE_SUMMARY contain spaces, so
# `eval` would mis-parse them (detect-stack.sh's header documents the same).
#
# This script self-derives SCRIPT_DIR and sources libs + invokes sibling
# scripts/templates via $SCRIPT_DIR (NEVER ${CLAUDE_PLUGIN_ROOT}) so tests can
# invoke it directly. The SKILL.md still calls THIS script via
# ${CLAUDE_PLUGIN_ROOT} (substitution is guaranteed in skill bodies).
#
# usage:
#   init-bootstrap.sh phase1 [--proj-owner <owner>] [--proj-num <number>]
#   init-bootstrap.sh phase2
#
# bash 3.2 compatible: no mapfile/readarray, no ${var,,}; lowercase via tr.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=lib/config.sh
source "$SCRIPT_DIR/lib/config.sh"

PHASE="${1:-}"
shift || true

# --proj-owner / --proj-num let the skill pass a user-typed board (from the
# in-skill empty-case URL prompt) into a later phase1 re-run if needed; they
# override the auto-detected values when present.
OVERRIDE_PROJ_OWNER=""
OVERRIDE_PROJ_NUM=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --proj-owner) OVERRIDE_PROJ_OWNER="${2:-}"; shift 2 ;;
    --proj-num)   OVERRIDE_PROJ_NUM="${2:-}"; shift 2 ;;
    *) shift ;;
  esac
done

# ---------------------------------------------------------------------------
# phase1 — Steps 1–3, 5–8 + the deterministic arms of 2a-2.
# Detects/mutates; prints human notices to stderr and a KEY=value block to
# stdout, plus the project-tree fenced between sentinels for the skill's 8b.
# ---------------------------------------------------------------------------
phase1() {
  # --- Step 1: Verify prerequisites ---------------------------------------
  need_missing=""
  for cmd in git gh jq; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
      need_missing="$need_missing $cmd"
    fi
  done
  if [[ -n "$need_missing" ]]; then
    echo "[sillok-init] missing tools:$need_missing" >&2
    echo "[sillok-init] install them and re-run /sillok-init" >&2
    exit 1
  fi

  if ! git rev-parse --show-toplevel >/dev/null 2>&1; then
    echo "[sillok-init] not inside a git repository — cd into the project root first" >&2
    exit 1
  fi

  # Initialize sub-step status variables consumed by the Step 11 summary.
  # Each step below sets its own; defaulting to "fail" makes any skipped step
  # visible in the final status icon rather than silently masquerading as ok.
  CONFIG_STATUS=fail
  RULES_STATUS=fail
  SHIM_STATUS=fail
  CLAUDE_MD_STATUS=fail
  TYPES_STATUS=fail
  ORG_MODE=false

  # --- Step 2: Detect repo and base branch --------------------------------
  REPO=$(gh repo view --json owner,name --jq '"\(.owner.login)/\(.name)"' 2>/dev/null || echo "")
  BASE_BRANCH=$(gh repo view --json defaultBranchRef --jq '.defaultBranchRef.name' 2>/dev/null || echo "main")

  # If REPO is empty, the user must fill `repo` in the generated config manually.

  # --- Step 2a: Detect org mode -------------------------------------------
  OWNER_TYPE=$(gh api "/repos/$REPO" --jq '.owner.type' 2>/dev/null || echo "User")
  if [[ "$OWNER_TYPE" == "Organization" ]]; then
    ORG_MODE=true
  else
    ORG_MODE=false
    echo "[sillok-init] ⚠️  User-owned repo detected. Issue Types and linked branches unavailable — using label fallback mode." >&2
  fi

  # --- Step 2a-2: Auto-detect project (deterministic arms only) -----------
  # The empty-case URL prompt is interactive and STAYS in the skill; here we
  # only run the single/multi-project auto-detect arms. PROJ_NUM=0 signals the
  # empty-case so the skill runs the in-skill URL prompt; PROJ_TOTAL drives its
  # closed/hidden note.
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
    echo "[sillok-init] Auto-detected project: $PROJ_TITLE (#$PROJ_NUM)" >&2
  elif [[ "$proj_count" -gt 1 ]]; then
    echo "[sillok-init] Multiple projects found for $PROJ_OWNER:" >&2
    echo "$proj_json" | jq -r '.projects[] | "  \(.number)) \(.title)"' >&2
    echo "[sillok-init] Set project.owner and project.number in workflow.config.json manually." >&2
  fi
  # The empty-case (proj_count == 0) is handled in-skill via the URL prompt;
  # leave PROJ_NUM=0 so the skill knows to prompt. PROJ_TOTAL is emitted so the
  # skill can print the closed/hidden note.

  # A board passed from the skill's in-skill URL prompt overrides detection.
  if [[ -n "$OVERRIDE_PROJ_OWNER" ]]; then PROJ_OWNER="$OVERRIDE_PROJ_OWNER"; fi
  if [[ -n "$OVERRIDE_PROJ_NUM" ]]; then PROJ_NUM="$OVERRIDE_PROJ_NUM"; fi

  # --- Step 2b: Verify org Issue Types ------------------------------------
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
      echo "[sillok-init] Required org issue types missing: ${missing[*]}" >&2
      echo "  Ask your org owner to run:" >&2
      for t in "${missing[@]}"; do
        echo "    gh api -X POST -H 'X-GitHub-Api-Version: 2026-03-10' /orgs/$OWNER/issue-types -f name=$t" >&2
      done
      echo "  Or via UI: https://github.com/organizations/$OWNER/settings/issue-types" >&2
      TYPES_STATUS=missing
    else
      TYPES_STATUS=ok
    fi
  fi

  # --- Step 3: Detect package manager and verify commands -----------------
  # detect-stack.sh emits one key=value line per field; values often contain
  # whitespace (e.g. install=yarn install), so a field reader is used, NOT eval.
  PROJECT_ROOT=$(git rev-parse --show-toplevel)
  install=""; lint=""; typecheck=""; format=""
  while IFS='=' read -r key val; do
    case "$key" in
      install)   install="$val" ;;
      lint)      lint="$val" ;;
      typecheck) typecheck="$val" ;;
      format)    format="$val" ;;
    esac
  done < <(bash "$SCRIPT_DIR/detect-stack.sh" "$PROJECT_ROOT")
  # If install is empty: unknown stack — the user fills verify.* manually.

  # Derive the single STACK label from the install command (for the summary).
  case "$install" in
    "pnpm install")     STACK=pnpm ;;
    "yarn install")     STACK=yarn ;;
    "npm install")      STACK=npm ;;
    "bun install")      STACK=bun ;;
    "bundle install")   STACK=bundler ;;
    "go mod download")  STACK=go ;;
    "cargo fetch")      STACK=cargo ;;
    "poetry install")   STACK=poetry ;;
    "pipenv install")   STACK=pipenv ;;
    *)                  STACK=unknown ;;
  esac

  # --- Step 4: Branch prefix default --------------------------------------
  # The default template uses {type}/issue-, which substitutes to feature/issue-,
  # bug/issue-, epic/issue-, etc. at branch-creation time. Users can override to
  # any literal or templated string by editing workflow.config.json.
  BRANCH_PREFIX="{type}/issue-"

  # --- Step 5: Detect worktree copy files ---------------------------------
  # Two-stage filter: the first grep narrows the gitignored list to per-worktree
  # config candidates (so node_modules/** doesn't drown out the root config);
  # the second grep -v drops matches inside dependency caches/build outputs; the
  # case-filter inside the loop is a final defence-in-depth check.
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

  # --- Step 6: Write workflow.config.json ---------------------------------
  mkdir -p "$PROJECT_ROOT/.claude/sillok"
  CFG="$PROJECT_ROOT/.claude/sillok/workflow.config.json"

  MERGE_SUMMARY=""

  # Existing config — deep-merge in any missing template keys (user values win).
  if [[ -f "$CFG" ]]; then
    if MERGE_SUMMARY=$(bash "$SCRIPT_DIR/migrate-config.sh" \
        "$CFG" "$PLUGIN_ROOT/templates/workflow.config.json"); then
      if [[ -n "$MERGE_SUMMARY" ]]; then
        echo "$MERGE_SUMMARY" >&2
        CONFIG_STATUS=migrated
      else
        CONFIG_STATUS=ok
      fi
    else
      CONFIG_STATUS=fail
    fi
  else
    CONFIG_STATUS=ok
    # Build copyFiles JSON array. Guard the array expansion for bash 3.2 under
    # `set -u`: an empty array makes a bare ${arr[@]} count as an unbound var.
    copyfiles_json=$(printf '%s\n' ${COPY_FILES[@]+"${COPY_FILES[@]}"} | jq -R . | jq -s 'map(select(length > 0))')

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
        "epicRepo": "",
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
            "epic": "Epic"
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

  # --- Step 7: Scaffold rules ---------------------------------------------
  RULES_DIR="$PROJECT_ROOT/.claude/sillok/rules"
  if REFRESH_SUMMARY=$(bash "$SCRIPT_DIR/refresh-rules.sh" \
      "$RULES_DIR" "$PLUGIN_ROOT/templates/rules"); then
    RULES_STATUS=ok
    [[ -n "$REFRESH_SUMMARY" ]] && echo "$REFRESH_SUMMARY" >&2
  else
    RULES_STATUS=fail
  fi

  # --- Step 7b: Write command shortcut shims (REQUIRED) -------------------
  # Redirect the script's human-facing chatter to stderr so it never pollutes
  # the KEY=value status block on stdout.
  if bash "$SCRIPT_DIR/write-shim-commands.sh" "$PROJECT_ROOT" >&2; then
    SHIM_STATUS=ok
  else
    SHIM_STATUS=fail
  fi

  # --- Step 8: Append CLAUDE.md imports -----------------------------------
  CLAUDE_MD="$PROJECT_ROOT/CLAUDE.md"
  SNIPPET="$PLUGIN_ROOT/templates/claude-md-snippet.md"
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

  # --- Step 8b tree (deterministic part only) -----------------------------
  # The LLM classification stays in-skill; here we only emit the pruned tree so
  # the skill reads it from the fenced block instead of re-running the script.
  TREE=$(bash "$SCRIPT_DIR/project-tree.sh" "$PROJECT_ROOT" 2>/dev/null || true)

  # --- Status block (stdout) ----------------------------------------------
  echo "## sillok init phase1"
  echo "REPO=$REPO"
  echo "BASE_BRANCH=$BASE_BRANCH"
  echo "ORG_MODE=$ORG_MODE"
  echo "OWNER_TYPE=$OWNER_TYPE"
  echo "STACK=$STACK"
  echo "PROJ_OWNER=$PROJ_OWNER"
  echo "PROJ_NUM=$PROJ_NUM"
  echo "PROJ_TOTAL=$proj_total"
  echo "BRANCH_PREFIX=$BRANCH_PREFIX"
  echo "CFG_PATH=$CFG"
  echo "PROJECT_ROOT=$PROJECT_ROOT"
  echo "CONFIG_STATUS=$CONFIG_STATUS"
  echo "RULES_STATUS=$RULES_STATUS"
  echo "SHIM_STATUS=$SHIM_STATUS"
  echo "CLAUDE_MD_STATUS=$CLAUDE_MD_STATUS"
  echo "TYPES_STATUS=$TYPES_STATUS"
  echo "### project-tree"
  printf '%s\n' "$TREE"
  echo "### end-project-tree"
}

# ---------------------------------------------------------------------------
# phase2 — Steps 9, 9b, 9c, 10.
# Re-reads CFG_PATH/config FRESH from disk: it depends on NO phase1 shell vars.
# `labels.areas` was written by the skill's in-skill Step 8b between the phases,
# so bootstrap-labels.sh here creates the right area: labels.
# ---------------------------------------------------------------------------
phase2() {
  LABELS_STATUS=fail
  PROJECT_STATUS=fail
  PRIORITY_STATUS=fail

  PROJECT_ROOT=$(git rev-parse --show-toplevel)
  CFG="$PROJECT_ROOT/.claude/sillok/workflow.config.json"

  REPO=$(jq -r '.repo // ""' "$CFG" 2>/dev/null || echo "")
  ORG_MODE=$(jq -r '.orgMode // false' "$CFG" 2>/dev/null || echo "false")

  # --- Step 9: Bootstrap labels -------------------------------------------
  # bootstrap-labels.sh prints per-label progress to stdout; redirect to stderr
  # so it never pollutes the KEY=value status block.
  if [[ -n "$REPO" ]]; then
    if bash "$SCRIPT_DIR/bootstrap-labels.sh" "$REPO" --config "$CFG" >&2; then
      LABELS_STATUS=ok
    else
      LABELS_STATUS=fail
    fi
  else
    LABELS_STATUS=skipped-no-repo
  fi

  # --- Step 9b: Verify project + Status field options ---------------------
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
      echo "[sillok-init] Project $PROJ_OWNER/projects/$PROJ_NUM Status field missing options: ${proj_missing[*]}" >&2
      echo "  Add via UI: https://github.com/orgs/$PROJ_OWNER/projects/$PROJ_NUM/settings (or /users/$PROJ_OWNER/projects/$PROJ_NUM/settings for a user board)" >&2
      PROJECT_STATUS=incomplete
    else
      PROJECT_STATUS=ok
    fi
  else
    PROJECT_STATUS=unconfigured
    echo "[sillok-init] Cross-repo PRD: set 'project.owner' and 'project.number' in workflow.config.json to enable status transitions" >&2
  fi

  # --- Step 9c: Priority field (org mode only — ensure the org issue field)
  if [[ "$ORG_MODE" != "true" ]]; then
    PRIORITY_STATUS=skip-user-repo
  elif [[ -z "$PROJ_OWNER" || "$PROJ_NUM" == "0" || "$PROJ_NUM" == "null" ]]; then
    PRIORITY_STATUS=unconfigured
  else
    PRIORITY_FIELD=$(jq -r '.project.priorityField // "Priority"' "$CFG")
    # shellcheck source=lib/project.sh
    source "$SCRIPT_DIR/lib/project.sh"
    if sillok_org_priority_field_ensure; then
      # Field exists (discovered or just created + projected). Verify its options
      # cover the config mapping. A field sillok just created always matches
      # (options built from project.priorities); a pre-existing org field might
      # not — a coverage gap is a non-fatal `incomplete` warning.
      pri_mapped=0
      pri_missing=0
      for key in p1 p2 p3 p4; do
        want=$(jq -r ".project.priorities.$key // \"\"" "$CFG")
        if [[ -n "$want" ]]; then
          pri_mapped=$((pri_mapped + 1))
          resolved=$(sillok_org_issue_field_resolve "$PRIORITY_FIELD" "$want" 2>/dev/null || echo "")
          opt_id="${resolved#* }"
          if [[ -z "$opt_id" || "$resolved" == "$opt_id" ]]; then pri_missing=1; fi
        fi
      done
      if [[ "$pri_mapped" == "0" ]]; then
        PRIORITY_STATUS=fail
        echo "[sillok-init] project.priorities maps no option names — fill in p1–p4 in workflow.config.json (the schema requires all four)" >&2
      elif [[ "$pri_missing" == "1" ]]; then
        PRIORITY_STATUS=incomplete
        echo "[sillok-init] org Priority issue field '$PRIORITY_FIELD' is missing some options mapped in project.priorities — add them in the org's issue-field settings, or adjust the mapping" >&2
      else
        PRIORITY_STATUS=ok
      fi
    else
      PRIORITY_STATUS=fail
      echo "[sillok-init] could not ensure the org Priority issue field '$PRIORITY_FIELD' — an org owner must create it (org-admin permission required)" >&2
    fi
  fi

  # --- Step 10: Ensure spec/plan dirs + gitignore -------------------------
  SPEC_DIR=$(jq -r '.docs.specs' "$CFG")
  PLAN_DIR=$(jq -r '.docs.plans' "$CFG")
  mkdir -p "$PROJECT_ROOT/$SPEC_DIR" "$PROJECT_ROOT/$PLAN_DIR"

  GITIGNORE="$PROJECT_ROOT/.gitignore"
  for entry in "$SPEC_DIR/" "$PLAN_DIR/"; do
    if ! grep -qxF "$entry" "$GITIGNORE" 2>/dev/null; then
      echo "$entry" >> "$GITIGNORE"
    fi
  done

  # --- Status block (stdout) ----------------------------------------------
  echo "## sillok init phase2"
  echo "LABELS_STATUS=$LABELS_STATUS"
  echo "PROJECT_STATUS=$PROJECT_STATUS"
  echo "PRIORITY_STATUS=$PRIORITY_STATUS"
}

case "$PHASE" in
  phase1) phase1 ;;
  phase2) phase2 ;;
  *)
    echo "[sillok-init] usage: init-bootstrap.sh {phase1|phase2}" >&2
    exit 2
    ;;
esac
