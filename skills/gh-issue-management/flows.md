# GH Issue Management — Flows

Procedural reference for the eight issue-management flows plus a worked example. Consult this when executing a specific flow; the schema (titles, body templates, Type/Stage/Priority/Nature, milestones, sub-issue and linked-branch mechanics) lives in `SKILL.md`. Substitute the configured `${REPO}` / `${OWNER}` / `${NAME}` / `${BRANCH_PREFIX}` values at runtime.

## The eight flows

Each flow has the same shape: When → Steps → Done state.

### 1. New Feature

**When:** PRD exists, no GH issue yet.

1. Read the PRD (use main agent's Read tool — no JSON intermediate).
2. Draft issue title (verb-form, derived from PRD title; rewrite noun-phrases to verb-form).
3. Create issue via REST with `type=Feature` (or appropriate Type), optional nature labels, default priority `p3` (user repos: `p3` label; org repos: board Priority field after the project add). The project workflow sets Status to `Todo` on add.
4. Link to current sprint milestone if active.
5. Optional: create branch `${BRANCH_PREFIX}<N>-<slug>` and open a worktree. `/sillok-start` registers the linked branch via `createLinkedBranch`.

### 2. Pick Up Existing

**When:** Issue exists, you're starting work on it.

1. `/sillok-start <N>` — adopt mode runs the full environment setup (slug, branch, worktree, linked branch, push) and backfills assignee + sprint milestone, moving Backlog → Todo.
2. Already In Progress / In QA? adopt warns and, on confirm, keeps the board status while still setting up the environment.
3. Read spec/plan if linked in the issue body, then continue with `/sillok-design` or `/sillok-execute` per the issue's actual stage.

### 3. Quick Fix

**When:** Small bug, no design needed.

1. Create issue with `type=Bug`, priority appropriate to severity (default `p2` for user-affecting bugs; user repos: `p2` label; org repos: board Priority field after the project add). Project workflow sets Status to `Todo` on add.
2. Branch immediately, fix, commit with `(#N)` suffix per `.claude/rules/commit-conventions.md`.
3. PR with `Closes #N` in body. Auto-closes on merge.

### 4. New Project

**When:** Effort spans ≥3 sub-issues.

1. Create parent: `Story` if all sub-issues live in one repo (use `/sillok-story`); `Epic` in the PRD repo if the effort crosses repos.
2. Create child issues — each with `Feature` / `Task` / `Bug` Type, plus any relevant nature labels.
3. For each child, link to parent using the GraphQL mutation in [Sub-issue linking](#sub-issue-linking-including-cross-repo). Cross-repo links are natively supported within the same org.
4. Do NOT add task-list syntax in the parent body. The GitHub UI renders the sub-issue tree natively from the GraphQL relationship.

### 5. Search & Dedup

**When:** About to file a new issue.

1. `gh issue list --search "<keywords>" --state all` (search both open and closed).
2. Review hits manually.
3. If a duplicate exists: comment on the existing issue with new context. Don't file a new one.
4. If similar but distinct: file new and reference the existing in the body for cross-context.

### 6. Sprint Planning

**When:** Starting a new sprint or adjusting mid-sprint.

1. List candidates by querying the project's Status field (`Todo` items + un-prioritized inbox). The `gh project item-list` command surfaces status; pure-label queries no longer work in v2.
2. Prioritize per the priority split: `p1`–`p4` labels on user repos, the org Priority issue field (`sillok_issue_priority_set`) on org repos.
3. Pull selected into the sprint: `gh issue edit N --milestone "<YYYY-MM-Wn>"`.
4. For re-scheduled items from a previous sprint, change milestone with the same command.

### 7. Triage Backlog

**When:** Backlog has grown unwieldy.

1. Query project items with Status `Backlog` (plus items with Status unset).
2. Close stale (>3 months untouched, no longer relevant): `gh issue close N --reason "not planned" --comment "Stale; closing during triage."`.
3. Re-prioritize survivors (priority labels on user repos; the board's Priority field on org repos).
4. Promote ready items: `/sillok-start <N>` (adopt) when starting now, or set Status to `Todo` via `sillok_project_status_set` when just queueing.

### 8. Mid-Session Discovery

**When:** Working on issue X, find a separate bug or idea worth filing.

1. Note the discovery briefly.
2. Create it with `/sillok-add` — backlog capture works from any branch and does not disturb the current worktree. Don't triage immediately — the goal is to NOT context-switch.
3. Continue current task X.
4. Revisit during next sprint planning (flow 6) or backlog triage (flow 7).

## Worked example: New Project flow

User: "We want to add a recording-export feature. It'll need backend changes, frontend UI, native recording-service updates, and analytics events. Big effort."

Steps:

1. Create parent (`Story` — single-repo composite):

   ```bash
   gh api repos/${OWNER}/${NAME}/issues \
     -H "X-GitHub-Api-Version: 2026-03-10" \
     -f title="Add recording export end-to-end" \
     -f type=Story \
     -f body="Tracking issue for recording-export feature spanning backend/frontend/native/analytics. Sub-issues to follow."
   ```

   Returns issue #100. Project workflow assigns Status `Todo`. This is an org repo (`type=` works), so NO `p*` label — set the urgency on the org Priority issue field instead (it lands on the issue and projects onto the board): `sillok_issue_priority_set <issue-url> p2`.

2. Create child issues. Use heredoc for the body so newlines are real (bash double-quotes do NOT interpret `\n` — a literal `\n` would land in the rendered issue body):

   ```bash
   gh api repos/${OWNER}/${NAME}/issues \
     -H "X-GitHub-Api-Version: 2026-03-10" \
     -f title="Add /v1/exports endpoint" \
     -f type=Feature \
     -f body="$(cat <<'EOF'
   Parent: #100

   ## Summary
   New POST /v1/exports endpoint that returns a signed URL.
   EOF
   )"

   # ...repeat for the UI and native sub-issues with type=Feature.
   ```

   Returns #101, #102, #103.

3. Link each as sub-issue of #100. Hoist `PARENT_ID` outside the loop so it isn't recomputed per iteration:

   ```bash
   PARENT_ID=$(gh api graphql -f query='query { repository(owner:"${OWNER}", name:"${NAME}") { issue(number:100) { id } } }' --jq '.data.repository.issue.id')
   for child in 101 102 103; do
     CHILD_ID=$(gh api graphql -f query="query { repository(owner:\"${OWNER}\", name:\"${NAME}\") { issue(number:$child) { id } } }" --jq '.data.repository.issue.id')
     gh api graphql -f query="mutation { addSubIssue(input: { issueId: \"$PARENT_ID\", subIssueId: \"$CHILD_ID\" }) { issue { number } subIssue { number } } }"
   done
   ```

4. Done. Parent #100's GitHub UI now shows the three children in the native sub-issues panel. No task-list syntax needed in the body.
