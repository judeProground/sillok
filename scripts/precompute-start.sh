#!/usr/bin/env bash
# sillok — precompute deterministic state for /sillok-start.
# Outputs a markdown block listing: current branch, open epics, computed sprint
# milestone (and whether it already exists in the repo). The command body reads
# this once instead of running 3 separate tool round-trips.
set -euo pipefail

# Optional positional arg: issue number to ADOPT (accepts "33" or "#33").
# When present, a "### Adopt" section with an ADOPT-OK/WARN/ABORT verdict is
# appended after the branch guard. No arg = original one-shot behavior.
ADOPT_N="${1:-}"
ADOPT_N="${ADOPT_N#\#}"
if [[ -n "$ADOPT_N" && ! "$ADOPT_N" =~ ^[0-9]+$ ]]; then
  echo "[precompute-start] invalid adopt argument: '$1' (expected an issue number)" >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/config.sh
source "$SCRIPT_DIR/lib/config.sh"

REPO=$(sillok_config_required repo)
BRANCH_PREFIX=$(sillok_config_required branchPrefix)

need_missing=""
for cmd in git gh jq date; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    need_missing="$need_missing $cmd"
  fi
done
if [[ -n "$need_missing" ]]; then
  echo "[precompute-start] missing tools:$need_missing" >&2
  exit 1
fi

branch=$(git branch --show-current 2>/dev/null || echo "")

echo "## precomputed state for /sillok-start"
echo
echo "- Current branch: \`$branch\`"

# Abort hint: already mid-feature on another issue (any sillok type EXCEPT
# story — starting a sub-feature FROM the story integration worktree is the
# documented loop, so a story branch is a sanctioned starting point).
prefix_regex=$(sillok_branch_prefix_regex)
if [[ -n "$prefix_regex" && "$branch" =~ ^${prefix_regex}([0-9]+)- ]]; then
  # The template may inject capture groups (e.g. {type} alternation), so walk
  # BASH_REMATCH from index 1: the first numeric capture is the issue number,
  # the first non-numeric capture is the matched type token.
  matched_n=""
  matched_type=""
  for cap in "${BASH_REMATCH[@]:1}"; do
    if [[ "$cap" =~ ^[0-9]+$ ]]; then
      if [[ -z "$matched_n" ]]; then
        matched_n="$cap"
      fi
    elif [[ -z "$matched_type" ]]; then
      matched_type="$cap"
    fi
  done
  if [[ "$matched_type" == "story" ]]; then
    echo "- STORY-BRANCH: \`$branch\` (issue #${matched_n:-?}) — sanctioned starting point for \`--parent ${matched_n:-<N>}\`"
  else
    echo "- ABORT: already on issue branch for #${matched_n:-?} — finish or stash before starting a new feature"
    exit 0
  fi
fi

# Adopt mode: fetch the target issue and emit a verdict block.
if [[ -n "$ADOPT_N" ]]; then
  source "$SCRIPT_DIR/lib/project.sh"
  echo
  echo "### Adopt"
  issue_json=$(gh api -H "X-GitHub-Api-Version: 2026-03-10" "/repos/$REPO/issues/$ADOPT_N" 2>/dev/null || echo "")
  if [[ -z "$issue_json" ]]; then
    echo "- ADOPT-ABORT: issue #$ADOPT_N not found in $REPO (or gh not authenticated)"
  else
    a_state=$(printf '%s' "$issue_json" | jq -r '.state // empty')
    a_title=$(printf '%s' "$issue_json" | jq -r '.title // empty')
    a_type=$(printf '%s' "$issue_json" | jq -r '.type.name // empty')
    a_labels=$(printf '%s' "$issue_json" | jq -r '[.labels[].name] | join(", ")')
    a_milestone=$(printf '%s' "$issue_json" | jq -r '.milestone.title // empty')
    a_assignees=$(printf '%s' "$issue_json" | jq -r '[.assignees[].login] | join(", ")')
    a_parent=$(printf '%s' "$issue_json" | jq -r '.body // ""' | grep -m1 -oE '^Parent: ([A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+)?#[0-9]+' | sed 's/^Parent: //' || true)

    # User-mode repos have no Issue Type — fall back to the first label that
    # names a configured type (types.list lowercased — the single source the
    # branch-prefix machinery already uses).
    if [[ -z "$a_type" ]]; then
      types_lc=$(sillok_config_array types.list | tr '[:upper:]' '[:lower:]')
      if [[ -n "$types_lc" ]]; then
        a_type=$(printf '%s' "$issue_json" | jq -r '.labels[].name' \
          | grep -ixF -f <(printf '%s\n' "$types_lc") | head -1 || true)
      fi
    fi
    a_type_lc=$(printf '%s' "$a_type" | tr '[:upper:]' '[:lower:]')

    echo "- Issue: #$ADOPT_N $a_title"
    echo "- State: $a_state"
    echo "- Type: ${a_type:-unknown}"
    echo "- Labels: ${a_labels:-none}"
    echo "- Milestone: ${a_milestone:-none}"
    echo "- Assignees: ${a_assignees:-none}"
    if [[ -n "$a_parent" ]]; then
      echo "- Parent: $a_parent"
    fi
    # Deterministic branch-type derivation — the skill reads this as ground
    # truth instead of re-deriving from the Type line (story/epic abort below).
    echo "- Branch type: ${a_type_lc:-feature}"

    if [[ "$a_state" != "open" && "$a_state" != "OPEN" ]]; then
      # Early exit: a dead issue never needs the branch/board lookups below.
      echo "- ADOPT-ABORT: issue #$ADOPT_N is $a_state"
    elif [[ "$a_type_lc" == "story" || "$a_type_lc" == "epic" ]]; then
      echo "- ADOPT-ABORT: #$ADOPT_N is a ${a_type} — composites go through /sillok-story, not adopt"
    else
      # Existing sillok branch (remote or local) for this issue number?
      # Each lookup is individually failure-masked: set -e + pipefail would
      # otherwise kill the script on a repo with no remote.
      remote_heads=$(git ls-remote --heads origin 2>/dev/null | awk '{print $2}' | sed 's#^refs/heads/##' || true)
      local_heads=$(git for-each-ref --format='%(refname:short)' refs/heads 2>/dev/null || true)
      existing_branch=$(printf '%s\n%s\n' "$remote_heads" "$local_heads" | grep -E "^${prefix_regex}${ADOPT_N}-" | head -1 || true)

      if [[ -n "$existing_branch" ]]; then
        echo "- ADOPT-ABORT: branch \`$existing_branch\` already exists for #$ADOPT_N — environment is already set up (switch to its worktree instead)"
      else
        # Board status — best-effort; empty when board unconfigured or not on it.
        a_status=""
        a_item_id=$(sillok_project_item_for_issue "https://github.com/$REPO/issues/$ADOPT_N" 2>/dev/null || echo "")
        if [[ -n "$a_item_id" ]]; then
          a_status=$(sillok_project_status_get "$a_item_id" 2>/dev/null || echo "")
        fi
        echo "- Project status: ${a_status:-not on board}"

        # Whitelist gate: only pre-work statuses (Backlog / Todo / not on
        # board) adopt silently. Anything else — In Design, In Progress,
        # In QA, Done, or a custom status — warns; the environment can still
        # be set up on confirmation, but the status is KEPT.
        s_backlog=$(sillok_config project.statuses.backlog)
        s_todo=$(sillok_config project.statuses.todo)
        if [[ -n "$a_status" && "$a_status" != "$s_backlog" && "$a_status" != "$s_todo" ]]; then
          echo "- ADOPT-WARN: #$ADOPT_N is already '$a_status' — confirm with the user before setting up the environment (board status will be KEPT, not reset to Todo)"
        else
          echo "- ADOPT-OK: ready to adopt (board status will be set to Todo)"
        fi
      fi
    fi
  fi
fi

# Open epics (for parent suggestion) — skipped in adopt mode: an adopted
# issue keeps its own parent relationship, so the parent prompt never runs
# and the 1-2 gh lookups here would be wasted.
if [[ -z "$ADOPT_N" ]]; then
  echo
  echo "### Open epics"

  # Local-repo stories/epics (for parent suggestion).
  # orgMode=true: query by Issue Type. orgMode=false: query by label fallback.
  ORG_MODE=$(sillok_config orgMode)
  if [[ "$ORG_MODE" == "true" ]]; then
    local_stories=$(gh api graphql -H "X-GitHub-Api-Version: 2026-03-10" \
      -f query="{ repository(owner: \"${REPO%%/*}\", name: \"${REPO##*/}\") {
        issues(first: 20, states: OPEN, filterBy: {issueType: \"Story\"}) {
          nodes { number title }
        }
      } }" --jq '.data.repository.issues.nodes[]? | "  - (in this repo) #\(.number) [Story] \(.title)"' 2>/dev/null || echo "")
  else
    # User repo: Issue Types unavailable. Fall back to label-based query.
    local_stories=$(gh issue list --repo "$REPO" --label story --state open --limit 20 --json number,title \
      --jq '.[]? | "  - (in this repo) #\(.number) [story] \(.title)"' 2>/dev/null || echo "")
  fi

  # Cross-repo PRD epics from prdRepo, if configured.
  PRD_REPO=$(sillok_config prdRepo)
  prd_epics=""
  if [[ -n "$PRD_REPO" ]]; then
    if [[ "$ORG_MODE" == "true" ]]; then
      prd_epics=$(gh api graphql -H "X-GitHub-Api-Version: 2026-03-10" \
        -f query="{ repository(owner: \"${PRD_REPO%%/*}\", name: \"${PRD_REPO##*/}\") {
          issues(first: 20, states: OPEN, filterBy: {issueType: \"Epic\"}) {
            nodes { number title }
          }
        } }" --jq ".data.repository.issues.nodes[]? | \"  - (in $PRD_REPO) #\(.number) [Epic] \(.title)\"" 2>/dev/null || echo "")
    else
      prd_epics=$(gh issue list --repo "$PRD_REPO" --label epic --state open --limit 20 --json number,title \
        --jq ".[]? | \"  - (in $PRD_REPO) #\(.number) [epic] \(.title)\"" 2>/dev/null || echo "")
    fi
  fi

  if [[ -z "$local_stories" && -z "$prd_epics" ]]; then
    echo "- (none — standalone unless --parent specified)"
  else
    if [[ -n "$prd_epics" ]]; then
      printf '%s\n' "$prd_epics"
    fi
    if [[ -n "$local_stories" ]]; then
      printf '%s\n' "$local_stories"
    fi
  fi
fi

# Sprint milestone: YYYY-MM-Wn where n = ceil(sprint_start_day / 7), sprint starts Monday
echo
echo "### Sprint milestone"
dow=$(date +%u)                                  # 1=Mon ... 7=Sun
monday=$(date -v-$((dow - 1))d +%Y-%m-%d)        # most recent Monday (today if today is Monday)
monday_day=$(date -j -f "%Y-%m-%d" "$monday" +%d | sed 's/^0*//')
monday_year=$(date -j -f "%Y-%m-%d" "$monday" +%Y)
monday_month=$(date -j -f "%Y-%m-%d" "$monday" +%m)
week_n=$(( (monday_day + 6) / 7 ))
milestone="${monday_year}-${monday_month}-W${week_n}"
echo "- Computed: \`$milestone\` (sprint start: $monday)"

ms_number=$(gh api "repos/$REPO/milestones" \
  --jq ".[] | select(.state==\"open\" and .title==\"$milestone\") | .number" 2>/dev/null || echo "")
if [[ -n "$ms_number" ]]; then
  echo "- Exists in repo: yes (number $ms_number)"
else
  echo "- Exists in repo: no (prompt user to create)"
fi

# Language preference
echo
echo "### Language"
LANG_PREF=$(sillok_config language)
echo "- Config: \`${LANG_PREF:-auto}\`"

exit 0
