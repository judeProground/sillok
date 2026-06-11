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

**Handoff override:** when this skill is invoked as a STAGE-COMPLETION handoff (a stage just finished and printed its outputs), the just-completed stage and its printed outputs OVERRIDE branch sniffing — you already know where you are. In particular, after `start`, `cd` into the worktree path that start printed BEFORE routing, then route to `design` — the current shell is still outside the new worktree, so branch sniffing would misroute. Branch sniffing below is the fallback for cold entry only.

Derive position locally, then route:

```bash
source "${CLAUDE_PLUGIN_ROOT}/scripts/lib/config.sh"
branch=$(git branch --show-current)
regex=$(sillok_branch_prefix_regex)
issue_num=""
if printf '%s\n' "$branch" | grep -qE "^${regex}[0-9]+-.+$"; then
  issue_num=$(printf '%s\n' "$branch" | grep -oE "^${regex}[0-9]+" | grep -oE '[0-9]+$')
fi
if [ -n "$issue_num" ]; then echo "sillok branch: $branch → issue #$issue_num"; else echo "no sillok branch: $branch"; fi
```

- **No match (base branch or unrelated branch)** → position is *before the chain*: next stage is `start` (or `story` if the user wants a multi-issue composite).
- **Match with type `story`** (`story/issue-N-*`) → on a story integration branch: next is either `start --parent N` (next sub-issue) or `end` in story-finalize mode. Do NOT judge readiness by sub-issue open/closed state — sub-issues stay OPEN until the story PR merges to base (sub-PRs target the integration branch and don't auto-close them). A sub-issue counts as **landed** when its PR into the integration branch is MERGED:

  ```bash
  REPO=$(sillok_config_required repo)
  gh pr list --repo "$REPO" --base "$branch" --state merged --json number,title,headRefName
  ```

  Enumerate the PLANNED sub-issues from the story issue itself — the `## Sub-issues` checkbox list in its body plus GitHub's sub-issue list (`gh issue view N --repo "$REPO"`) — never from existing PRs alone: a planned sub-issue that has no branch/PR yet is invisible to the PR list but still unlanded. Route `end` (story-finalize) only when every planned sub-issue is landed: each has a merged PR into the integration branch, and none lacks a branch/PR. If any sub-issue is unlanded, do NOT route story-finalize — route `start --parent N` or report the unlanded list. **In full-auto this check is a HARD GATE:** never auto-route story-finalize past an unlanded sub-issue.
- **Match with any other type** (`feature/issue-N-*`, `bug/...`, etc.) → on an issue branch. Disambiguate by checking the issue body (spec/plan sections) and local plan files:
  - No spec on the issue → next is `design`.
  - Spec exists, no plan / tasks unchecked → next is `execute`.
  - Plan complete, verify-gate passed → next is `end`.

Note: the snippet is deliberately grep-pipeline based, NOT `[[ =~ ]]` + `BASH_REMATCH` — the Bash tool may run zsh, where `BASH_REMATCH` is empty even on a successful match. Positional captures are unreliable anyway: the `{type}` alternation in the regex injects a capture group BEFORE the issue number, so the issue number is not `\1`. Extracting the digit run that immediately follows the resolved prefix sidesteps both problems.

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

`init` and `add` are OUTSIDE the chain. `init` is always interactive and is NEVER auto-run by this skill — even in full-auto mode, a missing config means stop and suggest `/sillok-init`. `add` is backlog capture, not a stage: never route to it and never treat it as a position — the chain entry for a backlog issue is `/sillok-start <N>` (adopt).

## Stage routing

Invoke the stage skill directly:

| Stage | Invoke |
|-------|--------|
| start | `sillok:start` (with `--parent N` inside a story) |
| design | `sillok:design` |
| execute | `sillok:execute` |
| end | `sillok:end` (auto-detects story-finalize on `story/issue-N-*`) |
| story | `sillok:story` |

Pass user-provided arguments through verbatim. The `/sillok-*` slash commands are the equivalent user-facing entry — thin wrappers that delegate to these same stage skills — so a user typing the command and this skill routing the stage land in the same place.

## Propose mode (default)

**HARD GATE — no exceptions:**

At chain ENTRY and at EVERY stage boundary, propose the next stage in one line and WAIT:

> Next: sillok design for #42 — proceed?

- NEVER perform the first gh/git mutation of a stage (issue creation, branch creation, push, PR creation, project-status change) before the user confirms.
- Natural-language intent ("let's finish this branch") fires this skill, not the stage — the confirmation gate applies at entry too.
- If the user declines or redirects, follow the user. The map is the default path, not a cage.

## Full-auto mode (`automation.fullAuto: true`)

- **Entry confirmation (once, natural-language entry only):** when the chain is ENTERED via natural-language intent — not an explicit `/sillok-*` command and not a stage-completion handoff — state the interpreted intent ONCE (e.g. "Interpreting this as: start a new feature for X — go?") and **WAIT for the user's reply** before the first gh/git mutation. Announcing the interpretation is not confirmation. A forward-looking status question ("what's next here?") is a request for a REPORT, not chain entry — answer it; do not start mutating. After the single confirmation the chain runs unprompted; mid-chain stage boundaries stay unprompted. Explicit-command entry needs no confirmation.
- Invoke the next stage directly — no proposal, no waiting.
- Design-phase judgment calls (scope, approach, naming, trade-offs) are decided by Claude. EVERY such decision is recorded in the issue's `## Key decisions` section for post-hoc review. PR review is the safety net.
- The chain STOPS after PR creation. NEVER merge — not the sub-issue PR, not the story PR. The stop point is fixed.
- verify-gate is NEVER skipped — `sillok:verify-gate` still runs at end-of-plan before `end`.
- **Failure demotion:** on ANY failure — test failures, merge conflicts, gh/API errors — stop auto-progression immediately, report the current state (stage, issue, what failed), and fall back to propose mode for the rest of the session. Do not retry your way past a failure silently.

### Stage-internal gates under full-auto

ONLY when this skill invoked the stage as part of a confirmed full-auto chain — never in propose mode, regardless of what the config says — the stage's INTERNAL confirmation gates are auto-resolved by Claude and recorded; they must not stall the chain:

- **start** — accept the proposed issue title/type/labels (issue-settings confirm loop); accept the derived branch name; answer the epic-fit question `standalone` unless `--parent` was given; auto-create the missing sprint milestone.
- **design** — the single review gate (spec + key decisions, one combined confirmation) is treated as Claude-confirmed; every such decision is recorded in the issue's `## Key decisions` per the decide+record rule above, and the In Design status set proceeds.
- **end** — the dirty-tree and existing-PR prompts are NOT auto-resolved. They map to failure demotion: stop the chain, report the state, and demote to propose mode.

Auto-resolution applies to confirmation gates only — verify-gate is never skipped.

## Integration

Related skills and commands:

- `/sillok-init` — one-time project setup (interactive, never routed by this skill)
- `/sillok-add` — backlog capture (outside the chain — never routed by this skill; promotion path is `/sillok-start <N>`)
- `/sillok-start`, `/sillok-design`, `/sillok-execute`, `/sillok-end`, `/sillok-story` — thin wrapper commands over the stage skills (the user-facing entry; this skill routes to the skills directly)
- `sillok:verify-gate` — mandatory whole-branch verification at end-of-plan, in both modes
- `sillok:gh-issue-management` — issue conventions used inside the stages
- `superpowers:brainstorming`, `superpowers:writing-plans`, `superpowers:subagent-driven-development` — chained inside design/execute stages; this skill never touches superpowers-internal handoffs
