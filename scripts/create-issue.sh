#!/usr/bin/env bash
# create-issue.sh — create a GitHub issue, branching on orgMode (read from config).
#
# Centralizes the `gh api -X POST /issues` block that was duplicated, near-
# verbatim, across /sillok-start (Step 7), /sillok-add (Step 4), and
# /sillok-story (step 2.4). The LLM composes title/body/type; this script owns
# the API mechanics, the orgMode fork, and the API-version header.
#
# Usage:
#   create-issue.sh --repo <owner/name> --title <t> (--body <b> | --body-file <path|->) \
#                   --type-name <IssueTypeName> --type-label <feature|bug|task|story> \
#                   [--priority <p-label>] [--label <extra-label>]... [--assignee <login>] [--plain]
#
#   --body-file -    reads the body from stdin (preferred for multi-paragraph
#                    bodies — avoids argv quoting headaches with backticks/$).
#   --plain          bypass the orgMode fork entirely: create a bare issue
#                    (title/body/assignees + version header), no type field and
#                    no priority/type label. The caller owns type/labels after
#                    creation. Used by /sillok-epic, whose target is epicRepo
#                    (independent of the consumer's orgMode) and whose Epic type
#                    is PATCHed non-fatally post-create.
#
# Behavior:
#   - orgMode is read from workflow.config.json (single source of truth) — never
#     passed by callers.
#   - orgMode=true  : `-f type=<type-name>`, NO priority label (org priority is the
#     board issue field, set by the caller AFTER creation).
#   - orgMode=false : no `type=` field; adds `labels[]=<type-label>` and
#     `labels[]=<priority>` (defaults to labels.defaults.priority when --priority
#     is omitted).
#   - Extra --label values (area:*, nature labels) are appended in BOTH modes.
#   - The X-GitHub-Api-Version header is always sent.
#   - --assignee defaults to the authenticated gh user.
#
# Output: prints ONLY the created issue's html_url on stdout (diagnostics → stderr).
# Exits non-zero with no stdout if the gh call fails.
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "$SCRIPT_DIR/lib/config.sh"

REPO=""; TITLE=""; BODY=""; BODY_FILE=""; TYPE_NAME=""; TYPE_LABEL=""
PRIORITY=""; ASSIGNEE=""; HAVE_BODY=0; PLAIN=0
EXTRA_LABELS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo)       REPO="$2"; shift 2 ;;
    --title)      TITLE="$2"; shift 2 ;;
    --body)       BODY="$2"; HAVE_BODY=1; shift 2 ;;
    --body-file)  BODY_FILE="$2"; HAVE_BODY=1; shift 2 ;;
    --type-name)  TYPE_NAME="$2"; shift 2 ;;
    --type-label) TYPE_LABEL="$2"; shift 2 ;;
    --priority)   PRIORITY="$2"; shift 2 ;;
    --label)      EXTRA_LABELS+=("$2"); shift 2 ;;
    --assignee)   ASSIGNEE="$2"; shift 2 ;;
    --plain)      PLAIN=1; shift ;;
    *) echo "[create-issue] unknown arg: $1" >&2; exit 2 ;;
  esac
done

[[ -z "$REPO" ]] && REPO=$(sillok_config repo)
[[ -z "$REPO" ]]  && { echo "[create-issue] --repo required (or set repo in config)" >&2; exit 2; }
[[ -z "$TITLE" ]] && { echo "[create-issue] --title required" >&2; exit 2; }
[[ "$HAVE_BODY" -eq 0 ]] && { echo "[create-issue] --body or --body-file required" >&2; exit 2; }

# Resolve the body. --body-file wins over --body; "-" reads stdin.
if [[ -n "$BODY_FILE" ]]; then
  if [[ "$BODY_FILE" == "-" ]]; then BODY=$(cat); else BODY=$(cat "$BODY_FILE"); fi
fi

[[ -z "$ASSIGNEE" ]] && ASSIGNEE=$(gh api user --jq .login)

# bash 3.2-safe arg array.
args=(-X POST -H "X-GitHub-Api-Version: 2026-03-10" "/repos/$REPO/issues"
      -f "title=$TITLE" -f "body=$BODY" -f "assignees[]=$ASSIGNEE")

if [[ "$PLAIN" == "1" ]]; then
  : # --plain: bare create. No orgMode fork, no type field, no priority label —
    # the caller stamps type/labels afterward (e.g. /sillok-epic's non-fatal
    # Epic-type PATCH on epicRepo, which is independent of the consumer orgMode).
elif [[ "$(sillok_config orgMode)" == "true" ]]; then
  [[ -n "$TYPE_NAME" ]] && args+=(-f "type=$TYPE_NAME")
  # No priority label in org mode — caller sets the board Priority issue field.
else
  [[ -z "$PRIORITY" ]] && PRIORITY=$(sillok_config labels.defaults.priority)
  [[ -n "$TYPE_LABEL" ]] && args+=(-f "labels[]=$TYPE_LABEL")
  [[ -n "$PRIORITY" ]]   && args+=(-f "labels[]=$PRIORITY")
fi

# Extra labels (area:*, nature) in both modes — skip empties so we never emit a
# bare `labels[]=` (GitHub 422s on that).
if [[ ${#EXTRA_LABELS[@]} -gt 0 ]]; then
  for l in "${EXTRA_LABELS[@]}"; do
    [[ -n "$l" ]] && args+=(-f "labels[]=$l")
  done
fi

gh api "${args[@]}" --jq '.html_url'
