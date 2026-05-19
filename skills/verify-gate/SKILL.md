---
name: verify-gate
description: Use after all tasks in an implementation plan are complete (final whole-branch verification before /sillok-end). Also use manually before any push when uncertain about a non-trivial commit. Per-task usage during execute is now optional, not required.
---

# Sillok Verify Gate

Whole-branch verification protocol for your codebase. Primary use case is end-of-plan (after all tasks land, before `/sillok-end`). Per-task usage is allowed but optional — `superpowers:subagent-driven-development` already runs spec + code-quality reviews per task.

**Core principle:** Auto-fix tier runs silently; approval tier surfaces findings to the user per item.

## When to use this skill

- **End-of-plan whole-branch (REQUIRED).** Run on the aggregate diff `<base-sha>..HEAD` after the last task lands, before `/sillok-end`.
- Before opening a PR (same as above when triggered manually).
- After resolving merge conflicts.
- Manually after a commit you're unsure about.
- **Per-task during execute (OPTIONAL).** Only if a task introduces a new lint/tsc surface or you genuinely doubt the change. Not required by the workflow anymore.

**Skip when:**

- Commit is docs-only (`*.md` only) — both tiers.
- Commit is comment-only (no semantic LOC change) — both tiers.
- The orchestrator passed `--skip-verify`.

(The prior "≤ 5 LOC = tier 2 only" rule has been removed. End-of-plan diffs are usually larger; per-task tiny commits should just skip the whole skill — the end-of-plan run will cover them.)

## Tier 1: auto-fix (silent)

Run in this order. Each step has a fix-and-rerun loop: on failure, fix the surfaced issues and re-run. Bail if 2 consecutive runs fail with the same errors (likely human-required).

1. `${VERIFY_LINT}` (from config) — linter. Auto-fixable issues should be fixed.
2. `${VERIFY_TYPECHECK}` (from config) — type-check only. Fix surfaced type errors.
3. `${VERIFY_FORMAT}` (from config) — formatter in write mode. Auto-applies; no re-run needed.

If any of the three is empty in `workflow.config.json` (because `detect-stack.sh` could not infer it, or because the user blanked it deliberately), skip that step silently. Note it in the tier 1 summary as `<step>: skipped (not configured)`. Skipping is not an error — it lets language-agnostic projects opt out of unsupported steps without losing the rest of the gate.

Output to user: one summary line.

- Pass: `✅ tier 1 clean (lint, tsc, format)`
- Partial: `⚠️ tsc still has 3 errors after auto-fix; see below`. Then list the errors and stop — do not advance to tier 2 until tier 1 is clean.

## Tier 2: approval (per-item user gate)

Only run after tier 1 is clean.

1. **Code review.** Dispatch the `superpowers:code-reviewer` subagent. Pass it a task summary plus the commit SHA range (`<base>..<head>`) as its prompt. The reviewer returns categorized findings.
2. **Display findings** with category (Critical / Important / Minor) and a per-item choice: Apply, Skip, Re-review.
   - For "Apply": dispatch a fix subagent. Do NOT modify files in the main context (context pollution; the implementer subagent should own the fix).
   - For "Skip": move on, note the skip in the gate output.
   - For "Re-review": send the same commit range back through `superpowers:code-reviewer` with additional context.
3. **Simplification pass.** After the code-review queue is empty, invoke the `simplify` skill. Unlike code-review fixes, simplify is a skill (not an agent) — it operates directly on the changed files in the main context. This is an intentional exception to the no-main-context-modification rule because simplify's scope is bounded to the diff range you give it; it doesn't carry forward task context that would pollute later turns. Per-item approval flow as above.
4. **Output.** Final line: `✅ verify gate passed (X applied, Y skipped, Z re-reviewed)` OR `⚠️ verify gate has unresolved blockers — see above`.

## Cross-references

**REQUIRED BACKGROUND:** Use `superpowers:verification-before-completion` for the underlying "evidence before assertions" principle. This skill is the sillok-specific application of that principle.

**Related:**

- `superpowers:requesting-code-review` — the template the code-reviewer agent expects
- `simplify` — invoked in tier 2

## Common mistakes

- Running tier 2 before tier 1 finishes — lint/tsc errors will dominate the reviewer's output and waste cycles
- Modifying files in the main context based on reviewer feedback — context pollution; dispatch a fix subagent instead
- Treating "Apply" as the only valid choice — Skip is fine for false positives or when the user has a different preference
- Skipping tier 2 because tier 1 was clean — they catch different things (tier 1 = mechanical, tier 2 = judgment)

## Worked example

Task 3 just completed. Implementer reported DONE at SHA `abc1234`. Plan-orchestrator invokes verify-gate.

Tier 1 (config has `verify.lint = "pnpm lint"`, `verify.typecheck = "npx tsc --noEmit"`, `verify.format = "pnpm format"`):

```
$ pnpm lint
✓ All files pass

$ npx tsc --noEmit
✓ No errors

$ pnpm format
✓ All files use code style
```

Output: `✅ tier 1 clean (lint, tsc, format)`

Tier 2:

```
[Dispatch superpowers:code-reviewer for abc1234]

Findings:
- (Important) src/features/auth/ui/LoginForm.tsx:42 — handler prop drilling
- (Minor) src/features/auth/model/useLogin.ts:18 — magic number

For each, choose: Apply, Skip, Re-review.
```

User picks Apply for both. Two fix subagents dispatched. Re-review confirms green.

```
[Dispatch simplify]

Suggestions:
- LoginForm.tsx:55 — duplicate styling could use Tailwind variant

User: Skip.
```

Final output: `✅ verify gate passed (2 applied, 1 skipped, 0 re-reviewed)`. Orchestrator advances to Task 4.
