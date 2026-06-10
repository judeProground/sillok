# Story-design mode

Design flow when the resolved issue is a `Story` and the user chose option (a) in SKILL.md Step 1 — design the story itself. The goal is architecture and decomposition, not a code-level spec. No spec file is created — skip SKILL.md Steps 3 and 5 (the brainstorming output goes straight into the story body's `## Architecture` section).

## Brainstorming seed

Seed `superpowers:brainstorming` differently — the goal is architecture and decomposition, not a code-level spec:

- Story title + full body (Integration branch, Context, Non-goals)
- Cross-repo PRD body (if `prdRepo` configured)
- Framing: "This is a Story (composite tracking issue). Brainstorm the architecture (tech choices, data flow, component boundaries) and the sub-issue breakdown. No code-level spec — the output goes into the story body's Architecture and Sub-issues sections."

The brainstorming output is stored as `$architecture_content` (Architecture prose) and `$sub_issues_plan` (the planned breakdown) for the story-body update below.

## After brainstorming

Continue with SKILL.md Step 6 (review loop), Step 7 (set project status to In Design), and Step 7.5 (extract key decisions). Skip the spec-file write in Step 5. Then perform the story-body update below instead of SKILL.md Step 8.

## Update story body

No spec file. Rebuild the story body using the Story template (per `gh-issue-conventions.md`), preserving the summary / Integration branch / Context / Non-goals from SKILL.md step 1, and inserting the brainstorming output:

```bash
gh issue edit <N> -F - <<EOF
<preserved 1-line summary>

## Integration branch

\`<preserved integration branch>\`

## Key decisions

$key_decisions

## Architecture

$architecture_content

## Sub-issues

$sub_issues_plan

## Context

<preserved context>

## Non-goals

<preserved non-goals>
EOF
```

`$sub_issues_plan` is a human-readable breakdown — each item becomes a real sub-issue later via `/sillok-start --parent <N>`. Do NOT auto-create sub-issues here.

## Output

- Issue URL with status `In Design`
- Story body updated with Architecture + Sub-issues breakdown + Key decisions
- Each item in the breakdown is created as a real sub-issue later via `/sillok-start --parent <N>`.

Then finish with SKILL.md's Handoff section.
