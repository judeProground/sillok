#!/usr/bin/env bash
# prd-snapshot.sh — record a completed PRD markdown into epicRepo as
# <prd.basePath>/<domain>/<name>/prd.md via the GitHub Contents API (upsert).
#
# The snapshot is record-only: the PRD's source of truth is Notion, review
# happens there, so this commits straight to epicRepo's default branch (no PR).
# Used by /sillok-prd (skills/prd) and by gihoek's prd-creator.
#
# Usage:
#   prd-snapshot.sh --domain <d> --name <kebab> --source <url> --snapshot-date <YYYY-MM-DD> \
#                   [--title <피처명>] \
#                   [--epic <owner/repo#N>] [--owner <@handle>] [--status <기획|approved|shipped>] \
#                   [--feature-goal <text>] [--task-type <Main|Sub>] [--sprint <text>] \
#                   [--dev-period <YYYY-MM-DD ~ YYYY-MM-DD>] [--owners <@a,@b,...>] \
#                   [--metric <text>] [--release-date <YYYY-MM-DD>] \
#                   [--eval-dates "d3: <YYYY-MM-DD>, d7: <YYYY-MM-DD>"] \
#                   (--body-file <path|->)
#
#   --body-file -   reads the PRD markdown from stdin.
#   --title         frontmatter title (the feature name). Falls back to --name
#                   when omitted. The body's first H1 is NEVER used — PRD
#                   bodies start with the section header `# 배경` by design.
#   --task-type     accepts Main/Sub; interview labels MainTask/SubTask are
#                   normalized to Main/Sub.
#
#   The --feature-goal/--task-type/--sprint/--dev-period/--owners/--metric/
#   --release-date/--eval-dates flags are all OPTIONAL and map 1:1 to the
#   PRD-convention frontmatter keys /sillok-epic's prd-template.md validates
#   (feature_goal/task_type/sprint/dev_period/owners/metric/release_date/
#   eval_dates — `status` already existed via --status). Omitting one just
#   omits that key from the frontmatter (snapshot still succeeds — blocking
#   validation is /sillok-epic's job, not this script's). --owners takes a
#   comma-separated list and is emitted as a YAML flow sequence (`[...]`).
#   --eval-dates takes the raw `d3: ..., d7: ...` mapping body (no braces —
#   the script wraps it) and is emitted as a YAML flow mapping (`{ ... }`).
#
# Behavior:
#   - target repo = epicRepo (required config), path root = prd.basePath
#     (default "projects"), allowed domains = prd.domains (default
#     basic/pro/ai-native/infra/common).
#   - upsert: GET the existing file's sha → PUT update; on 404 → PUT create.
#     On update, existing frontmatter `epic`/`review_at` and all of the
#     PRD-convention keys above are preserved unless new values are passed.
#   - missing PRD sections (배경/목표/실행/AI Agent Role/평가) only warn —
#     blocking validation is /sillok-epic's job.
#
# Output: prints ONLY the commit-pinned permalink on stdout
#   (https://github.com/<epicRepo>/blob/<commit-sha>/<path>). Diagnostics → stderr.
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "$SCRIPT_DIR/lib/config.sh"

DOMAIN="" NAME="" TITLE="" SOURCE="" SNAPSHOT_DATE="" EPIC="" OWNER="" STATUS="" BODY_FILE=""
FEATURE_GOAL="" TASK_TYPE="" SPRINT="" DEV_PERIOD="" OWNERS="" METRIC="" RELEASE_DATE="" EVAL_DATES=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --domain)        DOMAIN="$2"; shift 2 ;;
    --name)          NAME="$2"; shift 2 ;;
    --title)         TITLE="$2"; shift 2 ;;
    --source)        SOURCE="$2"; shift 2 ;;
    --snapshot-date) SNAPSHOT_DATE="$2"; shift 2 ;;
    --epic)          EPIC="$2"; shift 2 ;;
    --owner)         OWNER="$2"; shift 2 ;;
    --status)        STATUS="$2"; shift 2 ;;
    --feature-goal)  FEATURE_GOAL="$2"; shift 2 ;;
    --task-type)     TASK_TYPE="$2"; shift 2 ;;
    --sprint)        SPRINT="$2"; shift 2 ;;
    --dev-period)    DEV_PERIOD="$2"; shift 2 ;;
    --owners)        OWNERS="$2"; shift 2 ;;
    --metric)        METRIC="$2"; shift 2 ;;
    --release-date)  RELEASE_DATE="$2"; shift 2 ;;
    --eval-dates)    EVAL_DATES="$2"; shift 2 ;;
    --body-file)     BODY_FILE="$2"; shift 2 ;;
    *) echo "[prd-snapshot] unknown arg: $1" >&2; exit 2 ;;
  esac
done

for req in DOMAIN NAME SOURCE SNAPSHOT_DATE BODY_FILE; do
  [[ -z "${!req}" ]] && { echo "[prd-snapshot] missing --$(echo "$req" | tr '[:upper:]_' '[:lower:]-')" >&2; exit 2; }
done

EPIC_REPO=$(sillok_config_required epicRepo)

BASE_PATH=$(sillok_config prd.basePath); BASE_PATH=${BASE_PATH:-projects}
DOMAINS=$(sillok_config_array prd.domains)
[[ -z "$DOMAINS" ]] && DOMAINS=$'basic\npro\nai-native\ninfra\ncommon'
grep -qxF "$DOMAIN" <<<"$DOMAINS" || {
  echo "[prd-snapshot] domain '$DOMAIN' not in allowed set: $(tr '\n' ' ' <<<"$DOMAINS")" >&2; exit 1; }
[[ "$NAME" =~ ^[a-z0-9]+(-[a-z0-9]+)*$ ]] || {
  echo "[prd-snapshot] name must be kebab-case: $NAME" >&2; exit 1; }
[[ "$SNAPSHOT_DATE" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || {
  echo "[prd-snapshot] snapshot-date must be YYYY-MM-DD: $SNAPSHOT_DATE" >&2; exit 1; }

if [[ "$BODY_FILE" == "-" ]]; then BODY=$(cat); else BODY=$(cat "$BODY_FILE"); fi

# warn-only section check (blocking validation belongs to /sillok-epic)
for sec in "배경" "목표" "실행" "AI Agent Role" "평가"; do
  grep -q "$sec" <<<"$BODY" || echo "[prd-snapshot] warn: PRD section not found: $sec" >&2
done

# Title comes from --title (the feature name). Never sniff the body's first
# H1 — PRD bodies start with the section header `# 배경` by template design,
# which used to leak in as the title of every snapshot.
TITLE=${TITLE:-$NAME}

# Normalize interview-label task types to the convention values (Main/Sub).
case "$TASK_TYPE" in
  MainTask) TASK_TYPE="Main" ;;
  SubTask)  TASK_TYPE="Sub" ;;
esac
[[ -z "$OWNER" ]] && OWNER="@$(git config user.name 2>/dev/null | tr -d ' ' || echo unknown)"
STATUS=${STATUS:-기획}
TODAY=$(date +%Y-%m-%d)
FILE_PATH="$BASE_PATH/$DOMAIN/$NAME/prd.md"

# ── upsert: fetch existing sha + preserved frontmatter fields ────────────────
# Preservation is scoped to the FIRST frontmatter block only (between the
# opening `---` and the next `---`) so it never scans into the PRD body.
_prev_field() { sed -n "s/^$1: //p" <<<"$prev_fm" | head -1; }
# Strip surrounding double quotes — values may have been written unquoted
# (legacy) or quoted (current format); requoting below must not double up.
_strip_quotes() { sed -e 's/^"//' -e 's/"$//' <<<"$1"; }

SHA="" PREV_EPIC="" PREV_REVIEW_AT=""
PREV_FEATURE_GOAL="" PREV_TASK_TYPE="" PREV_SPRINT="" PREV_DEV_PERIOD=""
PREV_METRIC="" PREV_RELEASE_DATE="" PREV_OWNERS_RAW="" PREV_EVAL_DATES_RAW=""
if existing=$(gh api "repos/$EPIC_REPO/contents/$FILE_PATH" 2>/dev/null); then
  SHA=$(jq -r '.sha' <<<"$existing")
  prev_content=$(jq -r '.content' <<<"$existing" | base64 -d 2>/dev/null || true)
  prev_fm=$(awk '/^---$/{n++; next} n==1{print} n>=2{exit}' <<<"$prev_content")
  PREV_EPIC=$(_strip_quotes "$(_prev_field epic)")
  PREV_REVIEW_AT=$(_strip_quotes "$(_prev_field review_at)")
  PREV_FEATURE_GOAL=$(_strip_quotes "$(_prev_field feature_goal)")
  PREV_TASK_TYPE=$(_strip_quotes "$(_prev_field task_type)")
  PREV_SPRINT=$(_strip_quotes "$(_prev_field sprint)")
  PREV_DEV_PERIOD=$(_strip_quotes "$(_prev_field dev_period)")
  PREV_METRIC=$(_strip_quotes "$(_prev_field metric)")
  PREV_RELEASE_DATE=$(_strip_quotes "$(_prev_field release_date)")
  # owners/eval_dates are YAML flow sequence/mapping, not quoted scalars —
  # keep the brackets/braces verbatim so re-emission doesn't need reformatting.
  PREV_OWNERS_RAW=$(_prev_field owners)
  PREV_EVAL_DATES_RAW=$(_prev_field eval_dates)
fi
[[ -z "$EPIC" && -n "$PREV_EPIC" ]] && EPIC="$PREV_EPIC"
REVIEW_AT="$PREV_REVIEW_AT"
[[ -z "$FEATURE_GOAL" && -n "$PREV_FEATURE_GOAL" ]] && FEATURE_GOAL="$PREV_FEATURE_GOAL"
[[ -z "$TASK_TYPE" && -n "$PREV_TASK_TYPE" ]] && TASK_TYPE="$PREV_TASK_TYPE"
[[ -z "$SPRINT" && -n "$PREV_SPRINT" ]] && SPRINT="$PREV_SPRINT"
[[ -z "$DEV_PERIOD" && -n "$PREV_DEV_PERIOD" ]] && DEV_PERIOD="$PREV_DEV_PERIOD"
[[ -z "$METRIC" && -n "$PREV_METRIC" ]] && METRIC="$PREV_METRIC"
[[ -z "$RELEASE_DATE" && -n "$PREV_RELEASE_DATE" ]] && RELEASE_DATE="$PREV_RELEASE_DATE"

# YAML plain scalars break on ": " (e.g. a title containing "결과: 2주차");
# quote the free-text/user-controlled values and escape embedded quotes.
_yaml_escape() { sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' <<<"$1"; }

# owners: comma-separated input -> a quoted YAML flow sequence, e.g. [@a, @b]
# (note: "${out[*]}" joining can't use a 2-char IFS separator — only its
# first char is used — so join with a manual loop instead.)
_yaml_owners_seq() {
  local input="$1" item joined="" parts=()
  local IFS=,
  read -ra parts <<<"$input"
  for item in "${parts[@]}"; do
    item=$(sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' <<<"$item")
    [[ -z "$item" ]] && continue
    [[ -n "$joined" ]] && joined+=", "
    joined+="\"$(_yaml_escape "$item")\""
  done
  echo "$joined"
}

OWNERS_FMT=""
if [[ -n "$OWNERS" ]]; then
  OWNERS_FMT="[$(_yaml_owners_seq "$OWNERS")]"
elif [[ -n "$PREV_OWNERS_RAW" ]]; then
  OWNERS_FMT="$PREV_OWNERS_RAW"
fi

EVAL_DATES_FMT=""
if [[ -n "$EVAL_DATES" ]]; then
  EVAL_DATES_FMT="{ $EVAL_DATES }"
elif [[ -n "$PREV_EVAL_DATES_RAW" ]]; then
  EVAL_DATES_FMT="$PREV_EVAL_DATES_RAW"
fi

FM="---
title: \"$(_yaml_escape "$TITLE")\"
owner: \"$(_yaml_escape "$OWNER")\"
updated: $TODAY
status: \"$(_yaml_escape "$STATUS")\"
source: \"$(_yaml_escape "$SOURCE")\"
snapshot_date: $SNAPSHOT_DATE"
[[ -n "$FEATURE_GOAL" ]] && FM+=$'\n'"feature_goal: \"$(_yaml_escape "$FEATURE_GOAL")\""
[[ -n "$TASK_TYPE" ]] && FM+=$'\n'"task_type: \"$(_yaml_escape "$TASK_TYPE")\""
[[ -n "$SPRINT" ]] && FM+=$'\n'"sprint: \"$(_yaml_escape "$SPRINT")\""
[[ -n "$DEV_PERIOD" ]] && FM+=$'\n'"dev_period: \"$(_yaml_escape "$DEV_PERIOD")\""
[[ -n "$OWNERS_FMT" ]] && FM+=$'\n'"owners: $OWNERS_FMT"
[[ -n "$METRIC" ]] && FM+=$'\n'"metric: \"$(_yaml_escape "$METRIC")\""
[[ -n "$RELEASE_DATE" ]] && FM+=$'\n'"release_date: $RELEASE_DATE"
[[ -n "$EVAL_DATES_FMT" ]] && FM+=$'\n'"eval_dates: $EVAL_DATES_FMT"
[[ -n "$EPIC" ]] && FM+=$'\n'"epic: \"$(_yaml_escape "$EPIC")\""
[[ -n "$REVIEW_AT" ]] && FM+=$'\n'"review_at: \"$(_yaml_escape "$REVIEW_AT")\""
FM+=$'\n'"tags: [type/prd, area/$DOMAIN]
---"

FULL="$FM

$BODY"

MSG="docs(prd): snapshot $DOMAIN/$NAME ($SNAPSHOT_DATE)"
args=(-X PUT "repos/$EPIC_REPO/contents/$FILE_PATH"
      -f message="$MSG"
      -f content="$(base64 <<<"$FULL" | tr -d '\n')")
[[ -n "$SHA" ]] && args+=(-f sha="$SHA")

resp=$(gh api "${args[@]}") || { echo "[prd-snapshot] Contents API PUT failed" >&2; exit 1; }
COMMIT_SHA=$(jq -r '.commit.sha' <<<"$resp")
[[ -z "$COMMIT_SHA" || "$COMMIT_SHA" == "null" ]] && { echo "[prd-snapshot] no commit sha in response" >&2; exit 1; }

action=$([[ -n "$SHA" ]] && echo updated || echo created)
echo "[prd-snapshot] $action $FILE_PATH in $EPIC_REPO" >&2
echo "https://github.com/$EPIC_REPO/blob/$COMMIT_SHA/$FILE_PATH"
