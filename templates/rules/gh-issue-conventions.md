# GitHub Issue Conventions

Rules for creating and managing GitHub issues. Used by Claude and humans alike.

## Issue Title

Verb-form, imperative mood:

- `Add X to Y`
- `Fix X in Y`
- `Refactor X to use Y`
- `Remove X`

Do **not** write titles like "Bug: something broke" or "Feature idea".

## Branch Naming

`<branchPrefix><N>-<slug>` (configurable) where `N` is the issue number and `<slug>` is a short kebab-case summary.

Example: `<branchPrefix>68-cool-feature`.

Exception: long-running umbrella branches that span multiple issues (e.g. an umbrella branch) may use `feature/<name>`.

## Labels

**Type (pick one):**

| Label         | Use for                                            |
| ------------- | -------------------------------------------------- |
| `feature`     | New functionality                                  |
| `bug`         | Something broken                                   |
| `improvement` | Enhance existing functionality                     |
| `infra`       | Tooling, CI, config, refactoring (not user-facing) |
| `epic`        | Parent tracking issue spanning ≥3 sub-issues       |

**Stage (transitions as work progresses):**

| Label         | Meaning                                           |
| ------------- | ------------------------------------------------- |
| `backlog`     | Raw idea, not yet prioritized                     |
| `todo`        | Prioritized, ready to start, not yet begun        |
| `designed`    | Design doc exists and is linked in the issue body |
| `in-progress` | Plan exists and implementation is underway        |
| `in-review`   | PR is open                                        |

**Priority:** `p1` (urgent) / `p2` (high) / `p3` (normal, default) / `p4` (low).

Default to `p3`. Don't agonize.

## Milestone

Two-week sprints, named `YYYY-MM-Wn` where `n = ceil(sprint_start_day / 7)` based on the sprint's start date.

| Sprint start                      | Milestone                       |
| --------------------------------- | ------------------------------- |
| May 4, 2026                       | `2026-05-W1`                    |
| May 18, 2026                      | `2026-05-W3`                    |
| May 25, 2026 (crossing into June) | `2026-05-W4` (start month wins) |
| June 1, 2026                      | `2026-06-W1`                    |

Sprints start on Monday by convention. Issues without a milestone are valid (e.g., long-tail backlog). Alphabetical sort = chronological order, including across year boundaries (`2026-12-W3` → `2027-01-W1`).

## Sub-issue Linking

GitHub has a native sub-issue feature (separate from the legacy task-list-syntax-in-body approach). The `gh` CLI does not expose this; use the GraphQL `addSubIssue` mutation:

```bash
PARENT_ID=$(gh api graphql -f query='query { repository(owner:"${OWNER}", name:"${NAME}") { issue(number:<P>) { id } } }' --jq '.data.repository.issue.id')
CHILD_ID=$(gh api graphql -f query='query { repository(owner:"${OWNER}", name:"${NAME}") { issue(number:<C>) { id } } }' --jq '.data.repository.issue.id')
gh api graphql -f query="mutation { addSubIssue(input: { issueId: \"$PARENT_ID\", subIssueId: \"$CHILD_ID\" }) { issue { number } subIssue { number } } }"
```

Do NOT use task-list syntax (`- [ ] #N`) in the parent body — GitHub renders the native sub-issues panel from the GraphQL relationship, and the manual checklist becomes duplicate state that drifts.

## Type vs Structure relationship

Type labels and parent/sub-issue structure are partially overlapping. The rules:

1. **`epic` is the only type allowed as a parent.** Any issue with sub-issues must be labeled `epic`. An `epic` always has sub-issues — a childless `epic` is a labeling mistake. The `epic` body acts as tracking/coordination; no code changes attach to an `epic` directly.
2. **Other types are work-unit labels.** A `feature` / `bug` / `improvement` / `infra` issue can be standalone (ships in 1 PR) OR a sub-issue (one piece of an epic). It cannot be a parent.
3. **Sub-issue type composition is free.** An `epic` can have any mix of `feature` / `bug` / `improvement` / `infra` children. Each child's type describes that child's work, not the parent's.
4. **Decomposition trigger = re-label as `epic`.** If you started a `feature` (or other type) and then realize it needs ≥2 sub-issues, change its type to `epic` and rewrite its body as a tracking summary. The original code work moves into the new sub-issues.

### Heuristic at creation

| Question                                             | Answer                                                        |
| ---------------------------------------------------- | ------------------------------------------------------------- |
| Does this ship in 1 PR?                              | Standalone — pick `feature` / `bug` / `improvement` / `infra` |
| Does this need ≥2 PRs to ship?                       | Parent `epic` + sub-issues (each sub-issue ships its own PR)  |
| Does this span multiple sessions / multiple authors? | Parent `epic` + sub-issues regardless of PR count             |

`epic` does not carry a work-type label of its own — its sub-issues do.

## Issue Body

The body shape depends on issue type. Use the matching template below.

### Feature / improvement / infra template

Sections, in order:

1. **Parent** (if this is a sub-issue): `Parent: #NN`
2. **Summary** — 1-2 sentences describing intent
3. **PRD link** — path to the markdown PRD when applicable
4. **Design** — full spec content pasted inline once design is done (see rule below)
5. **Plan link** — `docs/superpowers/plans/...` once the plan is written
6. **PR link** — once a PR is open
7. **Done note** — short outcome summary when closed (added at merge time)

```markdown
Parent: #<M>            <!-- omit line if standalone -->

## Summary

<1–2 sentences describing intent>

## PRD link                  <!-- omit section if no PRD -->

docs/<path>.md

## Design                    <!-- filled by /sillok-design step 8 -->

<full spec content pasted inline here>

## Plan link                 <!-- filled by /sillok-execute -->

docs/superpowers/plans/<date>-<slug>.md

## PR link                   <!-- filled by /sillok-end -->

https://github.com/${REPO}/pull/<PR>

## Done note                 <!-- added at close-time, embedded in PR Summary -->

<1–2 sentences describing actual outcome>
```

**Design specs are pasted inline as the canonical text in the issue body.** The file at `<docs.specs>/<date>-<slug>.md` is the authoring artifact (Obsidian/editor friendly, version-controlled), but anyone reading the issue on GitHub must see the full design without checking out the repo. Drift policy: file wins. Re-run `/sillok-design` step 8 to re-paste — do not hand-edit the GH body.

Plans stay linked (not inlined) — they're typically much longer than specs and are stable artifacts whose path is enough for navigation.

### Epic template

Epics are parent tracking issues (≥3 sub-issues, must carry the `epic` label). They don't have Design / Plan / PR sections themselves — those live on the sub-issues. The epic body coordinates and contextualizes.

```markdown
<1-line summary>

## Architecture                           <!-- optional, link the design spec -->

- <docs.specs>/<date>-<slug>.md

## Sub-issues                             <!-- GitHub renders this from native sub-issue links automatically; this checkbox list is human-readable mirror, not a separate source of truth -->

- [ ] #<N> · <title>
- [ ] #<N> · <title>
- [ ] #<N> · <title>

## Context

- <bullet on motivation>
- <bullet on prior work or replacement>

## Non-goals

- <out-of-scope item>
- <out-of-scope item>

<closing note — when the epic closes, e.g., "This issue closes when slice 5 merges.">
```

the canonical epic example in your project is the canonical example.

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

## WIP Limits

- 3 active (`in-progress`) issues per assignee is normal.
- Hard cap at 5 — finish something before starting new work.

## Mid-Session Discovery

When you find a bug or idea while working on something else, create a separate issue immediately rather than scope-creeping the current work. Then continue the original task — don't context-switch.
