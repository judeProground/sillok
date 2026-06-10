---
name: gh-issue-management
description: Use when creating, updating, closing, triaging, or linking GitHub issues in your project. Covers issue title and body conventions, GitHub Issue Types (Epic/Story/Feature/Task/Bug), Projects v2 Status field for stage, priority + nature labels, milestone naming, cross-repo sub-issue parent-child linking via GraphQL, linked-branch registration, and the eight management flows (new feature, pick up existing, quick fix, new project, search and dedup, sprint planning, triage backlog, mid-session discovery).
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

**Feature / Task** (optionally with `improvement` / `infra` / `refactor` nature labels) — Parent (if sub) → Summary → PRD link → Design (inline spec) → Plan link → PR link → Done note. The Design / Plan link / PR link / Done note sections are filled progressively by `/sillok-{design,execute,end}`.

**Story** — 1-line summary → Integration branch → Architecture (optional) → Sub-issues checkbox list → Context → Non-goals. NO Design / Plan / PR sections (those live on sub-issues).

**Epic** — Lives in the PRD repo. Cross-repo parent for a multi-repo initiative; child issues in code repos link via cross-repo sub-issue API.

**Bug** (any nature labels are optional) — Parent (if sub) → Summary → Repro → Impact → Suspected cause (optional) → PR link → Done note. Bugs skip Design entirely. Keep tight (5–10 lines).

Design specs are **pasted inline** as canonical text — never just linked. File at `docs/superpowers/specs/<date>-<slug>.md` is the authoring artifact; body wins on drift; re-paste via `/sillok-design` step 8. Plans stay linked (not inlined — too long).

### Type (GitHub Issue Type — applied via API, not as a label)

Each issue carries exactly one Issue Type from the org-level Issue Types catalogue. Sillok ships with five:

| Type        | When                                                       |
| ----------- | ---------------------------------------------------------- |
| `Epic`      | Cross-repo PRD parent (lives in the PRD repo)              |
| `Story`     | In-repo composite (has integration branch + sub-issues)    |
| `Feature`   | New user-facing functionality (single PR)                  |
| `Task`      | Generic work unit, no user-facing change                   |
| `Bug`       | Broken behavior                                            |

Types are set during issue creation via REST: `POST /repos/{owner}/{repo}/issues -f type=<Type>` with header `X-GitHub-Api-Version: 2026-03-10`. Updates via `PATCH /repos/{owner}/{repo}/issues/{N} -f type=<Type>`. The `improvement` / `infra` / `refactor` categories from v1 are no longer Types — they're now Nature labels (see below).

### Stage (Projects v2 Status field — not a label)

Lifecycle stage lives in the project's Status single-select field, not on the issue as a label. The five canonical statuses:

| Status         | When applied                                          | Set by                           |
| -------------- | ----------------------------------------------------- | -------------------------------- |
| `Todo`         | Issue created, ready to start                         | `/sillok-start` + auto-add WF    |
| `In Design`    | Spec exists at `docs/superpowers/specs/...`           | `/sillok-design`                 |
| `In Progress`  | Plan exists, work started                             | `/sillok-execute`                |
| `In QA`        | PR open, review/QA underway                           | `/sillok-end`                    |
| `Done`         | Issue closed (PR merged or manually closed)           | Project workflow ("item closed") |

Sillok writes status via GraphQL `updateProjectV2ItemFieldValue`. The exact option names are configurable per project in `workflow.config.json` under `project.statuses`.

**Priority** (one label per issue; default `p3`): `p1` urgent | `p2` high | `p3` normal | `p4` low.

### Nature (optional cross-cutting labels)

Nature labels describe a property orthogonal to the Issue Type. Multiple natures can attach to one issue — a nature is never required, but at most a handful of natures should land on any single issue:

| Label          | Meaning                                            |
| -------------- | -------------------------------------------------- |
| `improvement`  | Enhances existing functionality                    |
| `refactor`     | Code restructuring with no behavioral change       |
| `infra`        | Tooling, CI, build config                          |
| `docs`         | Documentation only                                 |
| `security`     | Security-relevant change                           |
| `performance`  | Performance-relevant change                        |

These are configured under `labels.natures` in `workflow.config.json`. A `Feature` typed issue can also carry the `refactor` label, etc.

### Milestone

Two-week sprints. Format `YYYY-MM-Wn` where `n = ceil(sprint_start_day / 7)`.

| Sprint start                      | Milestone                       |
| --------------------------------- | ------------------------------- |
| May 4, 2026                       | `2026-05-W1`                    |
| May 18, 2026                      | `2026-05-W3`                    |
| May 25, 2026 (crossing into June) | `2026-05-W4` (start month wins) |

Sprints start on Monday. Issues without a milestone are valid.

### Sub-issue linking (including cross-repo)

Use GraphQL `addSubIssue`. The `gh` CLI has no native command for this.

**Same-repo example:**

```bash
PARENT_ID=$(gh api graphql -f query='query { repository(owner:"${OWNER}", name:"${NAME}") { issue(number:<P>) { id } } }' --jq '.data.repository.issue.id')
CHILD_ID=$(gh api graphql -f query='query { repository(owner:"${OWNER}", name:"${NAME}") { issue(number:<C>) { id } } }' --jq '.data.repository.issue.id')
gh api graphql -f query="mutation { addSubIssue(input: { issueId: \"$PARENT_ID\", subIssueId: \"$CHILD_ID\" }) { issue { number } subIssue { number } } }"
```

**Cross-repo example** (parent in PRD repo, child in code repo — same org):

```bash
PARENT_ID=$(gh api graphql -f query='query { repository(owner:"myorg", name:"prd") { issue(number:42) { id } } }' --jq '.data.repository.issue.id')
CHILD_ID=$(gh api graphql -f query='query { repository(owner:"myorg", name:"frontend") { issue(number:101) { id } } }' --jq '.data.repository.issue.id')
gh api graphql -f query="mutation { addSubIssue(input: { issueId: \"$PARENT_ID\", subIssueId: \"$CHILD_ID\" }) { issue { number } } }"
```

Same-org cross-repo sub-issue linking is natively supported. Do NOT also add `- [ ] #N` task-list syntax — GitHub renders the sub-issue panel from the GraphQL relationship.

### Linked branches (Development panel)

GitHub's Development panel on an issue auto-links PRs via `Closes #N` in PR body. **Branches must be explicitly linked** via the `createLinkedBranch` GraphQL mutation; sillok handles this in `/sillok-start` and `/sillok-story` via `scripts/lib/dev-link.sh`. createLinkedBranch is CREATE-ONLY — it must run BEFORE the branch first exists on the remote (sillok runs link-then-push); once the branch exists, the mutation silently returns null and `sillok_link_branch` emits a WARN (non-fatal).

```bash
# Example: link a branch to an issue
gh api graphql -f query='mutation {
  createLinkedBranch(input: {
    issueId: "<issue-node-id>",
    name: "feature/issue-42-add-cart",
    oid: "<commit-sha>"
  }) { linkedBranch { id ref { name } } }
}'
```

### Type vs Structure relationship

`Epic` and `Story` are the only types that may have sub-issues:

1. **`Epic` parents live cross-repo.** PRDs are authored in a dedicated PRD repo and are the canonical Epic-typed issue. Child issues in code repos reference the Epic via the cross-repo sub-issue API.
2. **`Story` parents live in-repo.** A `Story` is an in-repo composite with an `story/issue-<N>-<slug>` integration branch plus a worktree. Sub-features cut from and PR back to this integration branch.
3. **`Feature` / `Task` / `Bug` are atomic work units.** Each ships in one PR. They can be standalone (no parent) OR a sub-issue of an `Epic` or `Story`.
4. **Decomposition trigger.** Started as a `Feature` and realized it needs sub-issues? Run `/sillok-story` to promote: type flips to `Story`, branch renames to `story/issue-<N>-<slug>`, body is rewritten as a tracking summary.

#### Heuristic at creation

| Question                                             | Answer                                                                  |
| ---------------------------------------------------- | ----------------------------------------------------------------------- |
| Does this ship in 1 PR?                              | Standalone — pick `Feature` / `Task` / `Bug` Type                       |
| Does this need ≥2 PRs in one repo?                   | Parent `Story` + sub-issues (each sub-issue ships its own PR)           |
| Does this span multiple repos?                       | Parent `Epic` in the PRD repo + cross-repo sub-issues in each code repo |
| Does this span multiple sessions / multiple authors? | `Story` (single repo) or `Epic` (multi-repo)                            |

`Epic` and `Story` issues do not carry nature labels of their own — their sub-issues do.

### Branch naming

- Single-issue work: `${BRANCH_PREFIX}<N>-<slug>` (e.g., `feat/issue-42-volume-picker`)
- Umbrella (multi-issue effort): `feature/<name>` (e.g., `feature/harness`)

## The eight flows

Each flow has the same shape: When → Steps → Done state.

### 1. New Feature

**When:** PRD exists, no GH issue yet.

1. Read the PRD (use main agent's Read tool — no JSON intermediate).
2. Draft issue title (verb-form, derived from PRD title; rewrite noun-phrases to verb-form).
3. Create issue via REST with `type=Feature` (or appropriate Type), optional nature labels, default priority `p3`. The project workflow sets Status to `Todo` on add.
4. Link to current sprint milestone if active.
5. Optional: create branch `${BRANCH_PREFIX}<N>-<slug>` and open a worktree. `/sillok-start` registers the linked branch via `createLinkedBranch`.

### 2. Pick Up Existing

**When:** Issue exists, you're starting work on it.

1. `gh issue view N` to read context (don't open in browser).
2. Checkout `${BRANCH_PREFIX}<N>-<slug>` — create from `main` if it doesn't exist.
3. Read spec/plan if linked in the issue body.
4. Move Status to `In Progress` via `sillok_project_status_set` (the project Status field — not a label).

### 3. Quick Fix

**When:** Small bug, no design needed.

1. Create issue with `type=Bug`, priority appropriate to severity (default `p2` for user-affecting bugs). Project workflow sets Status to `Todo` on add.
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
2. Prioritize via priority labels (`p1`/`p2`/`p3`/`p4`).
3. Pull selected into the sprint: `gh issue edit N --milestone "<YYYY-MM-Wn>"`.
4. For re-scheduled items from a previous sprint, change milestone with the same command.

### 7. Triage Backlog

**When:** Backlog has grown unwieldy.

1. Query project items with Status unset (or with a `Backlog` extension status if configured under `project.statuses`).
2. Close stale (>3 months untouched, no longer relevant): `gh issue close N --reason "not planned" --comment "Stale; closing during triage."`.
3. Re-prioritize survivors with priority labels.
4. Promote ready items: set Status to `Todo` via `sillok_project_status_set`.

### 8. Mid-Session Discovery

**When:** Working on issue X, find a separate bug or idea worth filing.

1. Note the discovery briefly.
2. Create issue with `type=Bug` (or appropriate Type). Don't triage immediately — the goal is to NOT context-switch.
3. Continue current task X.
4. Revisit during next sprint planning (flow 6) or backlog triage (flow 7).

## Cross-references

**REQUIRED BACKGROUND:**

- `.claude/sillok/rules/gh-issue-conventions.md` — authoritative rule layer (loaded via CLAUDE.md `@` import). If any value here seems wrong, the rule file wins.
- `.claude/rules/pr-convention.md` — PR title/body/squash-merge rules
- `.claude/rules/commit-conventions.md` — `<type>(<scope>): <subject> (#N)` format

## Language

The `language` config key (`sillok_config language`) controls the language of generated prose in issue/PR bodies and specs:

- `auto` (default): match the session language — if the user is speaking Korean, write Korean; if English, write English.
- `ko`: always write in Korean.
- `en`: always write in English.

Structural markers (section headers like `## Summary`, `## Design`, the `Parent:` line, label names, branch names) are always English regardless of this setting. Only prose content (descriptions, summaries, acceptance criteria text) follows the language preference.

## Common mistakes

- Manually changing project status outside sillok commands — use `sillok_project_status_set` or let the commands handle it.
- Forgetting to register the linked branch — the Development panel stays empty until `createLinkedBranch` runs — and registering it AFTER the first push, which silently no-ops (create-only mutation).
- Using task-list syntax (`- [ ] #N`) in the parent body alongside the GraphQL sub-issue mutation — pick one (GraphQL is the new way)
- Mid-session triage of a discovered bug — file and move on
- Using `Sprint 1` or ISO week (`2026-W17`) as milestone — must be `YYYY-MM-Wn` (year-month-week-of-month) per slice 4 design
- `gh` CLI default repo gotcha — use `gh repo set-default ${REPO}` once per machine to avoid `--repo` on every command

## Worked example: New Project flow

User: "We want to add a recording-export feature. It'll need backend changes, frontend UI, native recording-service updates, and analytics events. Big effort."

Steps:

1. Create parent (`Story` — single-repo composite):

   ```bash
   gh api repos/${OWNER}/${NAME}/issues \
     -H "X-GitHub-Api-Version: 2026-03-10" \
     -f title="Add recording export end-to-end" \
     -f type=Story \
     -f labels[]=p2 \
     -f body="Tracking issue for recording-export feature spanning backend/frontend/native/analytics. Sub-issues to follow."
   ```

   Returns issue #100. Project workflow assigns Status `Todo`.

2. Create child issues. Use heredoc for the body so newlines are real (bash double-quotes do NOT interpret `\n` — a literal `\n` would land in the rendered issue body):

   ```bash
   gh api repos/${OWNER}/${NAME}/issues \
     -H "X-GitHub-Api-Version: 2026-03-10" \
     -f title="Add /v1/exports endpoint" \
     -f type=Feature \
     -f labels[]=p2 \
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
