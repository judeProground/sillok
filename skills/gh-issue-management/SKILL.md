---
name: gh-issue-management
description: Use when creating, updating, closing, triaging, or linking GitHub issues in your project. Covers issue title and body conventions, label taxonomy (type, stage, priority), milestone naming, sub-issue parent-child linking via GraphQL, and the eight management flows (new feature, pick up existing, quick fix, new project, search and dedup, sprint planning, triage backlog, mid-session discovery).
---

# Sillok GH Issue Management

Canonical procedure for every GH-issue-touching operation in your project.

> **Repository:** All `gh` commands target the repository defined in `.claude/sillok/workflow.config.json` under the `repo` key. Where this skill shows literal templates (`${REPO}`, `${OWNER}`, `${NAME}`, `${BRANCH_PREFIX}`), substitute the configured values at runtime.

**Core principle:** Schema is declarative; flows are procedural. Both live in this skill. The rule file `.claude/sillok/rules/gh-issue-conventions.md` is the always-on source of truth — this skill applies it.

## When to use this skill

- Creating a new issue (any type)
- Closing an issue
- Adding/removing labels or milestones
- Linking sub-issues to a parent
- Searching the backlog or planning a sprint
- Filing a mid-session discovery (bug found while working on something else)

## Repository

`${REPO}` (from config). All `gh` commands implicitly target this repo unless otherwise stated. For commands that need explicit owner/name (GraphQL queries), use the values literally.

## Issue schema

### Title

Verb-form imperative. Examples:

- ✅ `Add volume-ranked selection to candidate picker`
- ✅ `Fix recording timer negative after pause`
- ✅ `Refactor useRecording to features/recording`
- ❌ `Bug: timer broken` (no type prefix; the label conveys this)
- ❌ `Recording timer issue` (not verb-form)

≤ 72 characters. No trailing period.

### Body templates (per type)

The body shape differs by issue type. Full templates with copy-pasteable skeletons live in `.claude/sillok/rules/gh-issue-conventions.md` under "Issue Body". Quick reference:

**Feature / improvement / infra** — Parent (if sub) → Summary → PRD link → Design (inline spec) → Plan link → PR link → Done note. The Design / Plan link / PR link / Done note sections are filled progressively by `/sillok-{design,execute,end}`.

**Epic** — 1-line summary → Architecture (optional) → Sub-issues checkbox list → Context → Non-goals. NO Design / Plan / PR sections (those live on sub-issues). `#69` is the canonical example.

**Bug** — Parent (if sub) → Summary → Repro → Impact → Suspected cause (optional) → PR link → Done note. Bugs skip Design entirely. Keep tight (5–10 lines).

Design specs are **pasted inline** as canonical text — never just linked. File at `docs/superpowers/specs/<date>-<slug>.md` is the authoring artifact; body wins on drift; re-paste via `/sillok-design` step 8. Plans stay linked (not inlined — too long).

### Label taxonomy

**Type** (apply ONE):

| Label         | When                                            |
| ------------- | ----------------------------------------------- |
| `feature`     | New user-facing functionality                   |
| `bug`         | Broken behavior                                 |
| `improvement` | Enhances existing functionality                 |
| `infra`       | Tooling, CI, config, refactor — not user-facing |
| `epic`        | Parent tracking issue with ≥3 sub-issues        |

**Stage** (transitions over lifecycle; apply ONE):

| Label         | When applied                                |
| ------------- | ------------------------------------------- |
| `backlog`     | Raw idea, not yet prioritized               |
| `todo`        | Prioritized, ready to start, not yet begun  |
| `designed`    | Spec exists at `docs/superpowers/specs/...` |
| `in-progress` | Plan exists, work started                   |
| `in-review`   | PR open                                     |

`done` is NOT a label — closed state implies done.

**Priority** (apply ONE; default `p3`): `p1` urgent | `p2` high | `p3` normal | `p4` low.

### Milestone

Two-week sprints. Format `YYYY-MM-Wn` where `n = ceil(sprint_start_day / 7)`.

| Sprint start                      | Milestone                       |
| --------------------------------- | ------------------------------- |
| May 4, 2026                       | `2026-05-W1`                    |
| May 18, 2026                      | `2026-05-W3`                    |
| May 25, 2026 (crossing into June) | `2026-05-W4` (start month wins) |

Sprints start on Monday. Issues without a milestone are valid.

### Sub-issue linking

Use GraphQL `addSubIssue`. The `gh` CLI has no native command for this:

```bash
PARENT_ID=$(gh api graphql -f query='query { repository(owner:"${OWNER}", name:"${NAME}") { issue(number:<P>) { id } } }' --jq '.data.repository.issue.id')
CHILD_ID=$(gh api graphql -f query='query { repository(owner:"${OWNER}", name:"${NAME}") { issue(number:<C>) { id } } }' --jq '.data.repository.issue.id')
gh api graphql -f query="mutation { addSubIssue(input: { issueId: \"$PARENT_ID\", subIssueId: \"$CHILD_ID\" }) { issue { number } subIssue { number } } }"
```

Do NOT also add `- [ ] #N` task-list syntax to the parent body — GitHub's native sub-issue panel renders from the GraphQL relationship. Manual checklists become duplicate state and drift.

### Type vs Structure relationship

Type labels and parent/sub-issue structure are partially overlapping. The rules:

1. **`epic` is the only type allowed as a parent.** Any issue with sub-issues must be labeled `epic`. An `epic` always has sub-issues — a childless `epic` is a labeling mistake. The `epic` body acts as tracking/coordination; no code changes attach to an `epic` directly.
2. **Other types are work-unit labels.** A `feature` / `bug` / `improvement` / `infra` issue can be standalone (ships in 1 PR) OR a sub-issue (one piece of an epic). It cannot be a parent.
3. **Sub-issue type composition is free.** An `epic` can have any mix of `feature` / `bug` / `improvement` / `infra` children. Each child's type describes that child's work, not the parent's.
4. **Decomposition trigger = re-label as `epic`.** If you started a `feature` (or other type) and then realize it needs ≥2 sub-issues, change its type to `epic` and rewrite its body as a tracking summary. The original code work moves into the new sub-issues.

#### Heuristic at creation

| Question                                             | Answer                                                        |
| ---------------------------------------------------- | ------------------------------------------------------------- |
| Does this ship in 1 PR?                              | Standalone — pick `feature` / `bug` / `improvement` / `infra` |
| Does this need ≥2 PRs to ship?                       | Parent `epic` + sub-issues (each sub-issue ships its own PR)  |
| Does this span multiple sessions / multiple authors? | Parent `epic` + sub-issues regardless of PR count             |

`epic` does not carry a work-type label of its own — its sub-issues do.

### Branch naming

- Single-issue work: `${BRANCH_PREFIX}<N>-<slug>` (e.g., `feat/issue-42-volume-picker`)
- Umbrella (multi-issue effort): `feature/<name>` (e.g., `feature/harness`)

## The eight flows

Each flow has the same shape: When → Steps → Done state.

### 1. New Feature

**When:** PRD exists, no GH issue yet.

1. Read the PRD (use main agent's Read tool — no JSON intermediate).
2. Draft issue title (verb-form, derived from PRD title; rewrite noun-phrases to verb-form).
3. `gh issue create` with `feature` (or appropriate type), default to stage `todo` if starting work soon, else `backlog`. Default priority `p3`.
4. Link to current sprint milestone if active.
5. Optional: create branch `${BRANCH_PREFIX}<N>-<slug>` and open a worktree.

### 2. Pick Up Existing

**When:** Issue exists, you're starting work on it.

1. `gh issue view N` to read context (don't open in browser).
2. Checkout `${BRANCH_PREFIX}<N>-<slug>` — create from `main` if it doesn't exist.
3. Read spec/plan if linked in the issue body.
4. Flip stage label: `gh issue edit N --remove-label todo --add-label in-progress` (or from `designed` if spec was already done).

### 3. Quick Fix

**When:** Small bug, no design needed.

1. `gh issue create` with `bug` type, `todo` stage, priority appropriate to severity (default `p2` for user-affecting bugs).
2. Branch immediately, fix, commit with `(#N)` suffix per `.claude/rules/commit-conventions.md`.
3. PR with `Closes #N` in body. Auto-closes on merge.

### 4. New Project

**When:** Effort spans ≥3 sub-issues.

1. Create parent with `epic` type, `todo` stage, summary describing the overall effort.
2. Create child issues — each with normal type (`feature`/`bug`/`improvement`/`infra`).
3. For each child, link to parent using the GraphQL mutation in [Sub-issue linking](#sub-issue-linking).
4. Do NOT add task-list syntax in the parent body. The GitHub UI renders the sub-issue tree natively from the GraphQL relationship.

### 5. Search & Dedup

**When:** About to file a new issue.

1. `gh issue list --search "<keywords>" --state all` (search both open and closed).
2. Review hits manually.
3. If a duplicate exists: comment on the existing issue with new context. Don't file a new one.
4. If similar but distinct: file new and reference the existing in the body for cross-context.

### 6. Sprint Planning

**When:** Starting a new sprint or adjusting mid-sprint.

1. List candidates: `gh issue list --label todo --state open` and `gh issue list --label backlog --state open`.
2. Prioritize via priority labels (`p1`/`p2`/`p3`/`p4`).
3. Pull selected into the sprint: `gh issue edit N --milestone "<YYYY-MM-Wn>"`.
4. For re-scheduled items from a previous sprint, change milestone with the same command.

### 7. Triage Backlog

**When:** Backlog has grown unwieldy.

1. `gh issue list --label backlog --state open`.
2. Close stale (>3 months untouched, no longer relevant): `gh issue close N --reason "not planned" --comment "Stale; closing during triage."`.
3. Re-prioritize survivors with priority labels.
4. Promote ready items: `gh issue edit N --remove-label backlog --add-label todo`.

### 8. Mid-Session Discovery

**When:** Working on issue X, find a separate bug or idea worth filing.

1. Note the discovery briefly.
2. `gh issue create` with `bug` (or appropriate type), `backlog` stage. Don't triage immediately — the goal is to NOT context-switch.
3. Continue current task X.
4. Revisit during next sprint planning (flow 6) or backlog triage (flow 7).

## Cross-references

**REQUIRED BACKGROUND:**

- `.claude/sillok/rules/gh-issue-conventions.md` — authoritative rule layer (loaded via CLAUDE.md `@` import). If any value here seems wrong, the rule file wins.
- `.claude/rules/pr-convention.md` — PR title/body/squash-merge rules
- `.claude/rules/commit-conventions.md` — `<type>(<scope>): <subject> (#N)` format

## Common mistakes

- Creating an issue without any stage label — default to `backlog` if uncertain
- Forgetting `epic` on parent tracking issues — they get lost in filters that look for `feature|bug|improvement|infra`
- Using task-list syntax (`- [ ] #N`) in the parent body alongside the GraphQL sub-issue mutation — pick one (GraphQL is the new way)
- Mid-session triage of a discovered bug — file with `backlog` and move on
- Using `Sprint 1` or ISO week (`2026-W17`) as milestone — must be `YYYY-MM-Wn` (year-month-week-of-month) per slice 4 design
- `gh` CLI default repo gotcha — use `gh repo set-default ${REPO}` once per machine to avoid `--repo` on every command

## Worked example: New Project flow

User: "We want to add a recording-export feature. It'll need backend changes, frontend UI, native recording-service updates, and analytics events. Big effort."

Steps:

1. Create parent (`epic`):

   ```bash
   gh issue create \
     --title "Add recording export end-to-end" \
     --label epic --label todo --label p2 \
     --body "Tracking issue for recording-export feature spanning backend/frontend/native/analytics. Sub-issues to follow."
   ```

   Returns issue #100.

2. Create child issues. Use heredoc for the body so newlines are real (bash double-quotes do NOT interpret `\n` — a literal `\n` would land in the rendered issue body):

   ```bash
   gh issue create --title "Add /v1/exports endpoint" \
     --label feature --label todo --label p2 \
     --body "$(cat <<'EOF'
   Parent: #100

   ## Summary
   New POST /v1/exports endpoint that returns a signed URL.
   EOF
   )"

   gh issue create --title "Add export button to recording detail UI" \
     --label feature --label todo --label p2 \
     --body "$(cat <<'EOF'
   Parent: #100

   ## Summary
   Button in records detail screen calling features/records useExport hook.
   EOF
   )"

   gh issue create --title "Add native export pipeline to recording-service" \
     --label feature --label todo --label p2 \
     --body "$(cat <<'EOF'
   Parent: #100

   ## Summary
   Kotlin export bridge using existing audio-trimmer module.
   EOF
   )"
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
