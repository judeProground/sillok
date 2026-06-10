---
name: workflow
description: Use when the user expresses sillok-workflow intent in natural language — starting, continuing, or finishing feature work ("let's start a feature", "continue this issue", "finish this branch", "what's next here") — in a project configured with sillok (.claude/sillok/workflow.config.json exists). Also use when a sillok stage completes and the next step must be decided.
---

# Sillok Workflow Orchestrator

The single entry point that owns sillok's stage chain. Stage skills do one stage; this skill alone knows the transition map and reads the `automation` config to decide whether to propose the next stage or run it.

## Step 1: Activation guard

Check that the project is sillok-configured:

```bash
test -f "$(git rev-parse --show-toplevel)/.claude/sillok/workflow.config.json" && echo "sillok: configured" || echo "sillok: NOT configured"
```

If NOT configured (or not a git repo): tell the user sillok isn't set up in this project, suggest running `/sillok-init`, and STOP. Do not route any stage.

## Step 2: Read the automation mode

```bash
source "${CLAUDE_PLUGIN_ROOT}/scripts/lib/config.sh"
echo "fullAuto=$(sillok_config automation.fullAuto)"
```

Dot-path nested reads work. **An absent key == `false` == propose mode** — `config.sh` falls back per-key to the plugin template, which ships `automation.fullAuto: false`. Only the literal value `true` enables full-auto.

## Step 3: Determine current position

Derive position locally, then route:

```bash
source "${CLAUDE_PLUGIN_ROOT}/scripts/lib/config.sh"
branch=$(git branch --show-current)
regex=$(sillok_branch_prefix_regex)
[[ "$branch" =~ ^${regex}([0-9]+)-(.+)$ ]] && echo "matched: $branch" || echo "no sillok branch: $branch"
```

- **No match (base branch or unrelated branch)** → position is *before the chain*: next stage is `start` (or `story` if the user wants a multi-issue composite).
- **Match with type `story`** (`story/issue-N-*`) → on a story integration branch: next is either `start --parent N` (next sub-issue) or `end` in story-finalize mode (when all sub-issues are done).
- **Match with any other type** (`feature/issue-N-*`, `bug/...`, etc.) → on an issue branch. Disambiguate by checking the issue body (spec/plan sections) and local plan files:
  - No spec on the issue → next is `design`.
  - Spec exists, no plan / tasks unchecked → next is `execute`.
  - Plan complete, verify-gate passed → next is `end`.

Note: the `{type}` alternation in the regex injects a capture group BEFORE the issue number — walk `BASH_REMATCH` for the first numeric capture rather than hardcoding indices.

## Transition map

**Single issue:**

```
start → design → execute → end
```

**Story (integration branch):**

```
story → (start --parent N → design → execute → end)  [repeat per sub-issue]
      → end  (story-finalize, when current branch is story/issue-N-*)
```

`init` is OUTSIDE the chain. It is always interactive and is NEVER auto-run by this skill — even in full-auto mode, a missing config means stop and suggest `/sillok-init`.

## Stage routing

Invoke the stage. Stage bodies currently live in the canonical slash commands — until the per-stage skills land (`sillok:start`, `sillok:design`, `sillok:execute`, `sillok:end`, `sillok:story`), routing means running the existing command for that stage:

| Stage | Invoke |
|-------|--------|
| start | `/sillok-start` (with `--parent N` inside a story) |
| design | `/sillok-design` |
| execute | `/sillok-execute` |
| end | `/sillok-end` (auto-detects story-finalize on `story/issue-N-*`) |
| story | `/sillok-story` |

Treat the table as "invoke the stage" — when stage skills exist, the same routing targets them instead. Pass user-provided arguments through verbatim.

## Propose mode (default)

**HARD GATE — no exceptions:**

At chain ENTRY and at EVERY stage boundary, propose the next stage in one line and WAIT:

> Next: sillok design for #42 — proceed?

- NEVER perform the first gh/git mutation of a stage (issue creation, branch creation, push, PR creation, project-status change) before the user confirms.
- Natural-language intent ("let's finish this branch") fires this skill, not the stage — the confirmation gate applies at entry too.
- If the user declines or redirects, follow the user. The map is the default path, not a cage.

## Full-auto mode (`automation.fullAuto: true`)

- Invoke the next stage directly — no proposal, no waiting.
- Design-phase judgment calls (scope, approach, naming, trade-offs) are decided by Claude. EVERY such decision is recorded in the issue's `## Key decisions` section for post-hoc review. PR review is the safety net.
- The chain STOPS after PR creation. NEVER merge — not the sub-issue PR, not the story PR. The stop point is fixed.
- verify-gate is NEVER skipped — `sillok:verify-gate` still runs at end-of-plan before `end`.
- **Failure demotion:** on ANY failure — test failures, merge conflicts, gh/API errors — stop auto-progression immediately, report the current state (stage, issue, what failed), and fall back to propose mode for the rest of the session. Do not retry your way past a failure silently.

## Integration

Related skills and commands:

- `/sillok-init` — one-time project setup (interactive, never routed by this skill)
- `/sillok-start`, `/sillok-design`, `/sillok-execute`, `/sillok-end`, `/sillok-story` — canonical stage commands this skill routes between
- `sillok:verify-gate` — mandatory whole-branch verification at end-of-plan, in both modes
- `sillok:gh-issue-management` — issue conventions used inside the stages
- `superpowers:brainstorming`, `superpowers:writing-plans`, `superpowers:subagent-driven-development` — chained inside design/execute stages; this skill never touches superpowers-internal handoffs
