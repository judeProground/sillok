# GitHub Issue Conventions

Rules for creating and managing GitHub issues. Used by Claude and humans alike. The skill `sillok:gh-issue-management` applies these rules; this file is the source of truth.

## Issue Title

Verb-form, imperative mood:

- `Add X to Y`
- `Fix X in Y`
- `Refactor X to use Y`
- `Remove X`

≤ 72 characters. No trailing period. Do **not** write titles like "Bug: something broke" or "Feature idea" — the Issue Type conveys this.

## Branch Naming

`{type}/issue-<N>-<slug>` where `{type}` is the Issue Type lowercased (`feature`, `task`, `bug`, `story`) and `<N>` is the issue number. The exact template is configured under `branchPrefix` in `workflow.config.json`.

Examples: `feature/issue-42-volume-picker`, `bug/issue-87-timer-negative`, `story/issue-100-recording-export`.

Exception: umbrella branches spanning multiple unrelated issues may use `feature/<name>`.

## Type (Issue Type — applied via REST API, not as a label)

Each issue carries exactly one Issue Type from the org-level Issue Types catalogue. Sillok ships with five:

| Type      | Use for                                                    |
| --------- | ---------------------------------------------------------- |
| `Epic`    | Cross-repo PRD parent (lives in the PRD repo)              |
| `Story`   | In-repo composite (integration branch + sub-issues)        |
| `Feature` | New user-facing functionality (single PR)                  |
| `Task`    | Generic work unit, no user-facing change (single PR)       |
| `Bug`     | Broken behavior (single PR)                                |

Types are set via REST on create (`POST /repos/{owner}/{repo}/issues -f type=<Type>` with header `X-GitHub-Api-Version: 2026-03-10`) and update via `PATCH ... -f type=<Type>`. Never apply Types as plain labels.

## Stage (Projects v2 Status field — not a label)

Lifecycle stage lives in the project's Status single-select field. The five canonical statuses and the sillok command that writes each:

| Status        | Meaning                                       | Written by                       |
| ------------- | --------------------------------------------- | -------------------------------- |
| `Todo`        | Issue created, ready to start                 | `/sillok-start` (+ auto-add WF)  |
| `In Design`   | Spec exists at `docs/superpowers/specs/...`   | `/sillok-design`                 |
| `In Progress` | Plan exists, work started                     | `/sillok-execute`                |
| `In QA`       | PR open, review/QA underway                   | `/sillok-end`                    |
| `Done`        | Issue closed (PR merged or manually closed)   | Project workflow ("item closed") |

Sillok writes status via GraphQL `updateProjectV2ItemFieldValue` (helper: `sillok_project_status_set`). Option names are configurable per project under `project.statuses` in `workflow.config.json`. Do **not** flip stage as a label — there are no `todo` / `designed` / `in-progress` labels.

## Nature Labels (optional, cross-cutting, multiple allowed)

Nature labels describe a property orthogonal to the Issue Type. Zero or more per issue:

| Label         | Meaning                                      |
| ------------- | -------------------------------------------- |
| `improvement` | Enhances existing functionality              |
| `refactor`    | Code restructuring with no behavioral change |
| `infra`       | Tooling, CI, build config                    |
| `docs`        | Documentation only                           |
| `security`    | Security-relevant change                     |
| `performance` | Performance-relevant change                  |

A `Feature` typed issue can also carry `refactor`; a `Task` can also carry `infra`. Configured under `labels.natures` in `workflow.config.json`.

## Priority Labels

One per issue. Default `p3`:

- `p1` urgent
- `p2` high
- `p3` normal (default — don't agonize)
- `p4` low

## Area Labels

`area:<slice>` labels mark the code surface touched (e.g., `area:recording`, `area:auth`). Configured under `labels.areas` in `workflow.config.json`; auto-detected during `/sillok-init` from the project layout. Multiple area labels per issue are allowed when work spans slices.

## Milestone

Two-week sprints, named `YYYY-MM-Wn` where `n = ceil(sprint_start_day / 7)` based on the sprint's start date.

| Sprint start                      | Milestone                       |
| --------------------------------- | ------------------------------- |
| May 4, 2026                       | `2026-05-W1`                    |
| May 18, 2026                      | `2026-05-W3`                    |
| May 25, 2026 (crossing into June) | `2026-05-W4` (start month wins) |
| June 1, 2026                      | `2026-06-W1`                    |

Sprints start on Monday by convention. Issues without a milestone are valid (e.g., long-tail backlog). Alphabetical sort = chronological order, across year boundaries (`2026-12-W3` → `2027-01-W1`).

## Sub-issue Linking (cross-repo capable)

GitHub's native sub-issue feature is exposed only through GraphQL. Use the `addSubIssue` mutation — same-repo and same-org cross-repo links work identically:

```bash
PARENT_ID=$(gh api graphql -f query='query { repository(owner:"${OWNER}", name:"${PARENT_REPO}") { issue(number:<P>) { id } } }' --jq '.data.repository.issue.id')
CHILD_ID=$(gh api graphql -f query='query { repository(owner:"${OWNER}", name:"${CHILD_REPO}") { issue(number:<C>) { id } } }' --jq '.data.repository.issue.id')
gh api graphql -f query="mutation { addSubIssue(input: { issueId: \"$PARENT_ID\", subIssueId: \"$CHILD_ID\" }) { issue { number } subIssue { number } } }"
```

For same-repo links, set `${PARENT_REPO}` and `${CHILD_REPO}` to the same value. For cross-repo (`Epic` in PRD repo + child in code repo), set them to different repos in the same org.

Do **not** add `- [ ] #N` task-list syntax in the parent body — GitHub renders the native sub-issues panel from the GraphQL relationship, and a manual checklist becomes duplicate state that drifts.

## Type vs Structure

Parent-capable types vs atomic work units:

1. **`Epic` parents live cross-repo.** A PRD authored in a dedicated PRD repo is the canonical `Epic`. Child issues in code repos reference the Epic via cross-repo `addSubIssue`. No code changes attach to an `Epic` directly.
2. **`Story` parents live in-repo.** A `Story` has a `story/issue-<N>-<slug>` integration branch + worktree. Sub-features cut from and PR back to this integration branch; the `Story` PR then `--merge`s to base (preserving sub-feature commits), not `--squash`.
3. **`Feature` / `Task` / `Bug` are atomic.** Each ships in one PR. Standalone OR a sub-issue of an `Epic` or `Story`. They cannot have sub-issues themselves.
4. **Decomposition trigger.** Started as a `Feature` and realized it needs ≥2 sub-issues? Run `/sillok-story` to promote — Type flips to `Story`, branch renames to `story/issue-<N>-<slug>`, body becomes a tracking summary.

### Heuristic at creation

| Question                                  | Choose                                                                  |
| ----------------------------------------- | ----------------------------------------------------------------------- |
| Ships in 1 PR?                            | Standalone — `Feature` / `Task` / `Bug`                                 |
| Needs ≥2 PRs in one repo?                 | Parent `Story` + sub-issues                                             |
| Spans multiple repos?                     | Parent `Epic` in the PRD repo + cross-repo sub-issues in each code repo |
| Spans multiple sessions / authors?        | `Story` (single repo) or `Epic` (multi-repo)                            |

`Epic` and `Story` parents do not carry nature labels of their own — their sub-issues do.

## Issue Body

Body shape depends on Type. Sections appear in this order; sillok commands fill them progressively.

### Feature / Task template

```markdown
Parent: #<M>            <!-- omit line if standalone -->

## Summary

<1–2 sentences describing intent>

## PRD link                  <!-- omit section if no PRD -->

docs/<path>.md

## Design                    <!-- filled by /sillok-design step 8 -->

<full spec content pasted inline here>

## Plan                      <!-- filled by /sillok-execute -->

Plan written.

## PR link                   <!-- filled by /sillok-end -->

https://github.com/${REPO}/pull/<PR>

## Done note                 <!-- added at close-time, embedded in PR Summary -->

<1–2 sentences describing actual outcome>
```

**Design specs are pasted inline as canonical text.** The file at `docs/superpowers/specs/<date>-<slug>.md` is the authoring artifact (Obsidian/editor friendly, version-controlled), but anyone reading the issue on GitHub must see the full design without checking out the repo. Drift policy: file wins. Re-run `/sillok-design` step 8 to re-paste — do not hand-edit the GH body. Plans stay linked (not inlined — too long).

### Story template

Stories are parent tracking issues (≥2 sub-issues, Type `Story`, integration branch). They don't have Design / Plan / PR sections themselves — those live on the sub-issues.

```markdown
<1-line summary>

## Integration branch                     <!-- filled by /sillok-story; do not hand-edit -->

`story/issue-<N>-<slug>`

## Architecture                           <!-- optional, link the design spec -->

- docs/superpowers/specs/<date>-<slug>.md

## Sub-issues                             <!-- GitHub renders the native sub-issues panel from GraphQL; this is a human-readable mirror, not the source of truth -->

- [ ] #<N> · <title>
- [ ] #<N> · <title>

## Context

- <bullet on motivation>
- <bullet on prior work or replacement>

## Non-goals

- <out-of-scope item>

<closing note — e.g., "This issue closes when the last sub-issue merges.">
```

### Epic template (PRD repo only)

Epics are the cross-repo PRD parent. They live in a dedicated PRD repo and are referenced from each code-repo child via cross-repo `addSubIssue`. Body is PRD-shaped (problem, scope, success criteria, sub-issues across repos). No Design / Plan / PR sections — those live on the per-repo sub-issues.

### Bug template

Bugs skip the design step (no `## Design` section).

```markdown
Parent: #<M>            <!-- omit line if standalone -->

## Summary

<1 sentence: what's broken>

## Repro

1. <step>
2. <step>
3. <observed vs expected>

## Impact

<who/what is affected — frequency, severity, user-visible vs internal>

## Suspected cause            <!-- optional -->

<if anything is known>

## PR link                    <!-- filled by /sillok-end -->

https://github.com/${REPO}/pull/<PR>

## Done note                  <!-- added at close-time -->

<root cause + fix in 1–2 sentences>
```

Keep bug bodies tight — 5–10 lines including repro. No design doc needed.

## Linked Branches (Development panel)

GitHub's Development panel on an issue auto-links PRs via `Closes #N` in PR body. **Branches must be explicitly linked** via the `createLinkedBranch` GraphQL mutation; sillok handles this in `/sillok-start` and `/sillok-story` via `scripts/lib/dev-link.sh`. The helper is idempotent.

## WIP Limits

- 3 active (`In Progress`) issues per assignee is normal.
- Hard cap at 5 — finish something before starting new work.

## Mid-Session Discovery

When you find a bug or idea while working on something else, create a separate issue immediately rather than scope-creeping the current work. Then continue the original task — don't context-switch.
