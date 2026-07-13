# Issue body templates

Canonical, copy-pasteable issue-body skeletons per Issue Type. Sillok stages (`/sillok-start`, `/sillok-design`, `/sillok-execute`, `/sillok-end`, `/sillok-story`, `/sillok-epic`) paste these directly when composing or updating issue bodies — this file is the single source of truth for their exact shape.

### Feature / Task template

```markdown
Parent: #<M>            <!-- omit line if standalone -->

## Summary

<1–2 sentences describing intent>

## Key decisions            <!-- composed at /sillok-design's review gate (step 6), recorded in step 8; always present, may be empty -->

- **<decision>** — <reason>

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

Stories are parent tracking issues (≥2 sub-issues, Type `Story`, integration branch). They have no `## Design` (code-level spec) / Plan / PR sections — those live on the sub-issues. Instead, `/sillok-design` in story-design mode fills `## Key decisions` and `## Architecture` from brainstorming. No spec file is created for a story.

```markdown
<1-line summary>

## Integration branch                     <!-- filled by /sillok-story; do not hand-edit -->

`story/issue-<N>-<slug>`

## Key decisions                          <!-- filled by /sillok-design (story mode); may be empty -->

- **<decision>** — <reason>

## Architecture                           <!-- filled by /sillok-design (story mode): brainstorming output -->

<tech choices, data flow, component boundaries — prose, not a file link>

## Sub-issues                             <!-- GitHub renders the native sub-issues panel from GraphQL; this is a human-readable plan until each becomes a real sub-issue via /sillok-start --parent <N> -->

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

Epics are the cross-repo PRD parent. They live in a dedicated PRD repo (`epicRepo`, e.g. `acme/projects`) and are created by `/sillok-epic`. Code-repo children attach via cross-repo `addSubIssue`. No Design / Plan / PR sections — those live on the per-repo sub-issues.

**The Epic body is intentionally light — NOT the full PRD inline.** The PRD lives in `epicRepo` at `<category>/<project-name>/prd.md` (a living doc — written there directly or synced from Notion); the Epic links to that path (and to the Notion source when synced) rather than embedding it, which would create an impossible sync burden. The PRD backing every Epic must follow the team PRD template's five validated sections: **배경** (Background) / **목표** (Goal) / **실행** (Execution) / **AI Agent Role** / **평가** (Evaluation).

```markdown
## Summary
<1-paragraph summary>

## Metadata
- 피쳐목표: <feature_goal>
- Main/Sub: <task_type>
- Sprint: <sprint>
- 개발기간: <dev_period>
- 담당자: <owners>
- 상태: <status>
- 숫자: <metric>
- 출시일: <release_date>
- 평가 예정일: D+3 <eval.d3>, D+7 <eval.d7>

## PRD
- 원본(Notion): <notion-url>
- 위치: <epicRepo>/<category>/<project-name>/prd.md permalink
```

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
