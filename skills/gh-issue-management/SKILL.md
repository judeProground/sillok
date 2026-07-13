---
name: gh-issue-management
description: Use when creating, updating, closing, triaging, or linking GitHub issues in your project. Covers issue title and body conventions, GitHub Issue Types (Epic/Story/Feature/Task/Bug), Projects v2 Status field for stage, priority (labels on user repos / board Priority field on org repos) + nature labels, milestone naming, cross-repo sub-issue parent-child linking via GraphQL, linked-branch registration, and the eight issue-management flows (creation, triage, sprint planning, linking).
---

# Sillok GH Issue Management

Canonical procedure for every GH-issue-touching operation in your project.

> **Repository:** All `gh` commands target the repository defined in `.claude/sillok/workflow.config.json` under the `repo` key. Where this skill shows literal templates (`${REPO}`, `${OWNER}`, `${NAME}`, `${BRANCH_PREFIX}`), substitute the configured values at runtime.

**Core principle:** Schema is declarative; flows are procedural. Both live in this skill — this is the single source of truth for GH issue conventions. The rule file `.claude/sillok/rules/gh-issue-conventions.md` is a thin browse-only pointer stub (no longer `@`-imported into CLAUDE.md — the schema loads with this skill on trigger); if it ever disagrees with this skill, this skill wins.

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

The body shape differs by issue type. Full copy-pasteable skeletons live in `body-templates.md` (next to this file) — consult it whenever composing or updating an issue body. Quick reference:

**Feature / Task** (optionally with `improvement` / `infra` / `refactor` nature labels) — Parent (if sub) → Summary → Key decisions → PRD link → Design (inline spec) → Plan link → PR link → Done note. The Design / Plan link / PR link / Done note sections are filled progressively by `/sillok-{design,execute,end}`.

**Story** — 1-line summary → Integration branch → Key decisions → Architecture → Sub-issues checkbox list → Context → Non-goals. NO Design / Plan / PR sections (those live on sub-issues).

**Epic** (PRD repo only) — Summary → Metadata → PRD (Notion link + `epicRepo` path). Intentionally light, NOT the full PRD inline — the PRD lives at `<epicRepo>/<category>/<project-name>/prd.md` and must follow the team PRD template's five sections (배경/목표/실행/AI Agent Role/평가). Created by `/sillok-epic`; cross-repo parent, no Design/Plan/PR sections.

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

Lifecycle stage lives in the project's Status single-select field, not on the issue as a label. The six canonical statuses:

| Status         | When applied                                          | Set by                           |
| -------------- | ----------------------------------------------------- | -------------------------------- |
| `Backlog`      | Pre-sprint capture, set by `/sillok-add`; promote via `/sillok-start <N>` (adopt) | `/sillok-add` + auto-add WF |
| `Todo`         | Issue created, ready to start                         | `/sillok-start` + auto-add WF    |
| `In Design`    | Spec exists at `docs/superpowers/specs/...`           | `/sillok-design`                 |
| `In Progress`  | Plan exists, work started                             | `/sillok-execute`                |
| `In QA`        | PR open, review/QA underway                           | `/sillok-end`                    |
| `Done`         | Issue closed (PR merged or manually closed)           | Project workflow ("item closed") |

Sillok writes status via GraphQL `updateProjectV2ItemFieldValue`. The exact option names are configurable per project in `workflow.config.json` under `project.statuses`.

### Priority (org repos: board Priority field · user repos: p1–p4 labels)

One per issue. Default `p3` (configured under `labels.defaults.priority`). The priority *mechanism* depends on `orgMode`, mirroring how Type (REST) and Stage (Projects v2 field) above document theirs.

**Org repos (`orgMode: true`):** priority lives on the org-level **Priority issue field** (named per `project.priorityField`, default `Priority`) projected onto the project board — **not** a label. `/sillok-start` Step 10c sets it via `sillok_issue_priority_set`; the field itself is provisioned by `/sillok-init`. `p1`–`p4` map to the field's options via `project.priorities`:

| Key  | Option (default) | Meaning          |
| ---- | ----------------- | ---------------- |
| `p1` | `Urgent`           | urgent            |
| `p2` | `High`             | high              |
| `p3` | `Medium`           | normal (default)  |
| `p4` | `Low`              | low               |

No `p1`–`p4` labels are created or applied on org repos.

**User repos (`orgMode: false`):** priority is a label, one per issue, applied at issue-create time — `p1` urgent | `p2` high | `p3` normal (default — don't agonize) | `p4` low.

Set via `sillok_priority_apply <issue-url> <p-key>` (org-guarded + NON-FATAL wrapper around `sillok_issue_priority_set`) by `/sillok-start`, `/sillok-story`, and `/sillok-add`; the org issue field itself is ensured (created when missing — it is API-only, not GUI-creatable) by `/sillok-init`.

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

### Area labels

`area:<slice>` labels mark the code surface touched (e.g., `area:recording`, `area:auth`). Configured under `labels.areas` in `workflow.config.json`; auto-detected during `/sillok-init` from the project layout. Multiple area labels per issue are allowed when work spans slices.

### Milestone

Two-week sprints. Format `YYYY-MM-Wn` where `n = ceil(sprint_start_day / 7)`.

| Sprint start                      | Milestone                       |
| --------------------------------- | ------------------------------- |
| May 4, 2026                       | `2026-05-W1`                    |
| May 18, 2026                      | `2026-05-W3`                    |
| May 25, 2026 (crossing into June) | `2026-05-W4` (start month wins) |
| June 1, 2026                      | `2026-06-W1`                    |

Sprints start on Monday. Issues without a milestone are valid (e.g., long-tail backlog). Alphabetical sort = chronological order, across year boundaries (`2026-12-W3` → `2027-01-W1`).

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
PARENT_ID=$(gh api graphql -f query='query { repository(owner:"myorg", name:"projects") { issue(number:42) { id } } }' --jq '.data.repository.issue.id')
CHILD_ID=$(gh api graphql -f query='query { repository(owner:"myorg", name:"frontend") { issue(number:101) { id } } }' --jq '.data.repository.issue.id')
gh api graphql -f query="mutation { addSubIssue(input: { issueId: \"$PARENT_ID\", subIssueId: \"$CHILD_ID\" }) { issue { number } } }"
```

Same-org cross-repo sub-issue linking is natively supported. Do NOT also add `- [ ] #N` task-list syntax — GitHub renders the sub-issue panel from the GraphQL relationship. Sillok's stage skills (`/sillok-start`, `/sillok-story`, `/sillok-add`) run this exact mutation via `sillok_subissue_link` in `scripts/lib/subissue.sh` — this section is the canonical reference for the mutation it wraps.

### Linked branches (Development panel)

GitHub's Development panel on an issue auto-links PRs via `Closes #N` in PR body. **Branches must be explicitly linked** via the `createLinkedBranch` GraphQL mutation; sillok handles this in `/sillok-start` and `/sillok-story` via `scripts/lib/dev-link.sh` — the `sillok_link_and_push` helper bakes the link-before-push order in so a call site can't reverse it. createLinkedBranch is CREATE-ONLY — it must run BEFORE the branch first exists on the remote (sillok runs link-then-push); once the branch exists, the mutation silently returns null and `sillok_link_branch` emits a WARN (non-fatal).

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
2. **`Story` parents live in-repo.** A `Story` is an in-repo composite with an `story/issue-<N>-<slug>` integration branch plus a worktree. Sub-features cut from and PR back to this integration branch; the `Story` PR then `--merge`s to base (preserving sub-feature commits), not `--squash`. A `Story` can itself be a cross-repo child of an `Epic` (`epic → story → feature`), attached via `/sillok-story --parent <epicRepo#N>`.
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

`{type}/issue-<N>-<slug>` where `{type}` is the Issue Type lowercased (`feature`, `task`, `bug`, `story`) and `<N>` is the issue number — templated as `${BRANCH_PREFIX}<N>-<slug>` and configured under `branchPrefix` in `workflow.config.json`.

Examples: `feature/issue-42-volume-picker`, `bug/issue-87-timer-negative`, `story/issue-100-recording-export`.

Umbrella (multi-issue effort) branches spanning unrelated issues may use `feature/<name>` (e.g., `feature/harness`).

### WIP limits

- 3 active (`In Progress`) issues per assignee is normal.
- Hard cap at 5 — finish something before starting new work.

## The eight flows

The eight issue-management flows (New Feature, Pick Up Existing, Quick Fix, New Project, Search & Dedup, Sprint Planning, Triage Backlog, Mid-Session Discovery) and a full worked example of the New Project flow live in `flows.md` (next to this file). They are procedural reference, not always-on schema — consult `flows.md` when executing a specific flow.

## Cross-references

**REQUIRED BACKGROUND:**

- `body-templates.md` (next to this file) — the four full copy-pasteable issue-body templates this skill's "Body templates" section summarizes.
- `.claude/sillok/rules/gh-issue-conventions.md` — a thin browse-only pointer stub (no longer `@`-imported into CLAUDE.md). This skill is the source of truth; the rule file mirrors it, not the other way around.
- `sillok:end` skill (`skills/end/SKILL.md` + `pr-body-templates.md`) — PR title/body/squash-merge rules
- `.claude/sillok/rules/commit-conventions.md` — `<type>(<scope>): <subject> (#N)` format

## Language

The `language` config key (`sillok_config language`) controls the language of all generated prose (issue/PR bodies, specs). Apply the `output-language.md` rule (`.claude/sillok/rules/output-language.md`).

## Common mistakes

- Manually changing project status outside sillok commands — use `sillok_project_status_set` or let the commands handle it.
- Forgetting to register the linked branch — the Development panel stays empty until `createLinkedBranch` runs — and registering it AFTER the first push, which silently no-ops (create-only mutation).
- Using task-list syntax (`- [ ] #N`) in the parent body alongside the GraphQL sub-issue mutation — pick one (GraphQL is the new way)
- Mid-session triage of a discovered bug — file and move on
- Using `Sprint 1` or ISO week (`2026-W17`) as milestone — must be `YYYY-MM-Wn` (year-month-week-of-month) per slice 4 design
- `gh` CLI default repo gotcha — use `gh repo set-default ${REPO}` once per machine to avoid `--repo` on every command

## Flows and worked example

The eight issue-management flows and a full worked example of the New Project flow are in `flows.md` (next to this file) — consult it when executing a specific flow.
