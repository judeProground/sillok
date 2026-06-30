#!/usr/bin/env bash
# W0 guard: SKILL.md command-block surface (issue #43, behavior-preserving refactor).
#
# WHY: SKILL.md bash blocks are the prompt the executing agent copies and runs,
# but they are NOT covered by the script-level tests. PR #51 shipped 3 production
# regressions exactly here — script tests stayed green while the SKILL.md command
# blocks broke (empty variables, a dropped `--label` slot, a reordered push). This
# test grep-anchors the load-bearing slots/captures/orderings in the create-issue,
# linked-branch, sub-issue-link, and priority surfaces of start/story/add so that
# the W3·W5 bash refactors can't silently delete or reorder them.
#
# RELOCATION CONTRACT: where a later item (W3) may move an inline invariant into a
# sourced helper, each assertion accepts EITHER the inline form OR the helper-call
# form via a grep -E alternation — so extracting the helper does not false-fail
# this guard. When you DO relocate, keep the new helper name in the alternation.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SKILLS="$REPO_ROOT/skills"

fail() { echo "FAIL: $1" >&2; exit 1; }
pass() { echo "  ok: $1"; }

# grep -Eq against a file; fail with msg when the pattern is absent.
need() { # <file> <ere> <msg>
  grep -Eq "$2" "$1" || fail "$3"
}

# Line number of the FIRST line in <file> matching <ere> (empty if none).
first_line() { grep -nE "$2" "$1" | head -1 | cut -d: -f1; }

START="$SKILLS/start/SKILL.md"
STORY="$SKILLS/story/SKILL.md"
ADD="$SKILLS/add/SKILL.md"

for f in "$START" "$STORY" "$ADD"; do
  [[ -f "$f" ]] || fail "missing skill file: $f"
done

# ----------------------------------------------------------------------------
# (a) story Step 1 captures the current branch.
#     Load-bearing: §3 promotion renames this branch; losing the capture breaks
#     promotion detection. Accept the inline assignment in any whitespace form.
# ----------------------------------------------------------------------------
need "$STORY" 'branch=\$\(git branch --show-current' \
  "story/SKILL.md: Step 1 must capture the current branch via 'branch=\$(git branch --show-current ...)'"
pass "story Step 1 captures current branch"

# ----------------------------------------------------------------------------
# (b) link-before-push: in start AND in story's standalone path, the linked-branch
#     creation must appear BEFORE the push. createLinkedBranch is create-only, so
#     reversing the order silently drops the Development-panel link.
#
#     Accept the inline order (link marker before `git push -u`) OR a combined
#     helper (sillok_link_and_push) that bakes the order in. The combined helper,
#     if present, satisfies the contract by construction.
# ----------------------------------------------------------------------------
LINK_MARK='sillok_link_branch|createLinkedBranch|sillok_link_and_push'
PUSH_MARK='git push -u'

check_link_before_push() { # <file> <label>
  local f="$1" label="$2"
  # Combined helper present anywhere -> order is structurally enforced.
  if grep -Eq 'sillok_link_and_push' "$f"; then
    pass "$label: link-before-push enforced via sillok_link_and_push helper"
    return
  fi
  local link_ln push_ln
  link_ln=$(first_line "$f" "$LINK_MARK")
  push_ln=$(first_line "$f" "$PUSH_MARK")
  [[ -n "$link_ln" ]] || fail "$label: no linked-branch creation found (sillok_link_branch/createLinkedBranch)"
  [[ -n "$push_ln" ]] || fail "$label: no 'git push -u' found"
  [[ "$link_ln" -lt "$push_ln" ]] \
    || fail "$label: linked-branch creation (line $link_ln) must come BEFORE the first 'git push -u' (line $push_ln) — createLinkedBranch is create-only"
}

check_link_before_push "$START" "start"
check_link_before_push "$STORY" "story (standalone path)"
pass "link-before-push ordering holds in start and story"

# ----------------------------------------------------------------------------
# (c) sub-issue linking: start, story, add each link a sub-issue when a parent is
#     given. Accept the inline addSubIssue mutation, a delegating prose pointer
#     (add references start's Step 8), or a future sillok_subissue_link helper.
# ----------------------------------------------------------------------------
SUBISSUE_MARK='addSubIssue|sillok_subissue_link'
need "$START" "$SUBISSUE_MARK" \
  "start/SKILL.md: must link a sub-issue (addSubIssue / sillok_subissue_link)"
need "$STORY" "$SUBISSUE_MARK" \
  "story/SKILL.md: must link a sub-issue (addSubIssue / sillok_subissue_link)"
# add delegates to start's Step 8 by prose OR carries the mutation/helper itself.
grep -Eq "$SUBISSUE_MARK" "$ADD" \
  || fail "add/SKILL.md: must link a sub-issue (addSubIssue mutation, a pointer to start Step 8, or sillok_subissue_link)"
pass "start, story, add each link a sub-issue"

# ----------------------------------------------------------------------------
# (d) priority set is org-guarded: start, story, add each set priority behind an
#     orgMode check. The org/user fork must survive the refactor — accept inline
#     'if orgMode -> sillok_issue_priority_set' OR a sillok_priority_apply helper
#     that internalizes the guard.
# ----------------------------------------------------------------------------
PRIO_MARK='sillok_issue_priority_set|sillok_priority_apply'

check_priority_org_guard() { # <file> <label>
  local f="$1" label="$2"
  # A helper that internalizes the org-guard satisfies the contract by itself.
  if grep -Eq 'sillok_priority_apply' "$f"; then
    pass "$label: priority org-guard internalized in sillok_priority_apply"
    return
  fi
  need "$f" "$PRIO_MARK" "$label: must set priority (sillok_issue_priority_set / sillok_priority_apply)"
  need "$f" 'orgMode' "$label: priority must be guarded by an orgMode check"
  # The org-guard and the priority set must co-occur in the same fenced bash
  # block (an inline `if [[ "$(sillok_config orgMode)" == "true" ]]; then ...
  # sillok_issue_priority_set ...`). Scan each ```bash ... ``` block for both
  # markers together — this anchors the guard ONTO the priority call, not on an
  # unrelated earlier orgMode mention elsewhere in the prose.
  awk -v prio="$PRIO_MARK" '
    /^[[:space:]]*```bash/ { inblk=1; buf=""; next }
    inblk && /^[[:space:]]*```/ {
      inblk=0
      if (buf ~ /orgMode/ && buf ~ prio) { found=1 }
      next
    }
    inblk { buf = buf "\n" $0 }
    END { exit(found ? 0 : 1) }
  ' "$f" \
    || fail "$label: priority set must sit inside an orgMode-guarded bash block (if orgMode -> sillok_issue_priority_set)"
}

check_priority_org_guard "$START" "start"
check_priority_org_guard "$STORY" "story"
check_priority_org_guard "$ADD" "add"
pass "start, story, add set priority behind an orgMode guard"

# ----------------------------------------------------------------------------
# (e) create-issue area slot: start AND add include the `--label "area:` slot in
#     their create-issue block (the dropped-slot class of the #51 regression).
#     story standalone is intentionally EXCLUDED — a Story carries no area label.
# ----------------------------------------------------------------------------
# Fixed-string match with the `--` separator so the leading `--label` is not
# parsed as a grep option.
AREA_SLOT='--label "area:'
grep -Fq -- "$AREA_SLOT" "$START" \
  || fail "start/SKILL.md: create-issue block must include the --label \"area:<name>\" slot"
grep -Fq -- "$AREA_SLOT" "$ADD" \
  || fail "add/SKILL.md: create-issue block must include the --label \"area:<name>\" slot"
pass "start and add carry the --label \"area: create-issue slot"

# ----------------------------------------------------------------------------
# Bonus invariant: NON-FATAL priority semantics — the priority set is followed by
# a fail-soft (|| ...) so a missing org Priority field never aborts the run. This
# guards the fail-soft class of regression in all three skills.
# ----------------------------------------------------------------------------
for pair in "$START:start" "$STORY:story" "$ADD:add"; do
  f="${pair%%:*}"; label="${pair##*:}"
  # Either the inline 'priority_set ... || echo' fail-soft, or a helper that owns it.
  if grep -Eq 'sillok_priority_apply' "$f"; then
    pass "$label: NON-FATAL priority owned by sillok_priority_apply"
  else
    grep -Eq 'sillok_issue_priority_set.*\\|\\| |sillok_issue_priority_set' "$f" \
      || fail "$label: priority set must be present (NON-FATAL fail-soft expected)"
    # Confirm a fail-soft '||' appears in the priority block region.
    grep -Eq '\|\| echo .*priority' "$f" \
      || fail "$label: priority set must stay NON-FATAL (|| echo ... on the priority call)"
    pass "$label: priority set stays NON-FATAL"
  fi
done

echo
echo "All SKILL.md command-surface guards passed."
