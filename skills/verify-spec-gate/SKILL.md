---
name: verify-spec-gate
description: Use when checking whether implemented code matches the spec it was derived from. Loads three reference files (patterns, principles, smells) covering canonical design patterns, design principles, and code-smell heuristics.
---

# Spec compliance gate

This skill is the spec-compliance counterpart of `sillok:verify-gate` (which handles lint/typecheck/format/code-review). Use it when reviewing whether a diff actually fulfills its spec — not just whether it compiles.

## When to use

- During `/sillok-execute`, the implementer subagent applies these heuristics before reporting DONE.
- Final whole-branch review at end of plan (delegated by `/sillok-execute` step 8).
- Manually, before opening a PR, when you suspect the implementation drifted from the spec.

## Reference files

- `patterns.md` — canonical design patterns (Gang of Four + modern). Use when designing a new component or articulating why a structure feels wrong.
- `principles.md` — design principles (SOLID, DRY, YAGNI, etc.). Use when justifying a refactor or rejecting one.
- `smells.md` — code smells. Use when reviewing a diff for "this looks off but I can't name why".

Load whichever subfile applies to the current concern. Don't load all three unless you need to.
