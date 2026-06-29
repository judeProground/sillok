# sillok skill-triggering eval

Regression fixtures + method for checking that sillok's **auto-fire** skill
descriptions trigger on the right natural-language intent and stay quiet on
near-misses. Produced under issue #38 ("verify and harden sillok skill
triggering"). **No description was changed** — the check verified they already
discriminate correctly (see Result).

## What's auto-fire vs not

Only **`user-invocable: true`** skills trigger from a natural-language message:

- `workflow` — the single NL entry point ("start/continue/finish feature work")
- `gh-issue-management` — GitHub issue create/triage/link/sprint
- `verify-gate` — whole-branch lint/typecheck/format/code-review
- `verify-spec-gate` — does the code match its spec

The 8 **stage** skills (`start`/`design`/`execute`/`end`/`story`/`add`/`init`/`epic`)
are `user-invocable: false` — entered via a `/sillok-*` command or a
`sillok:workflow` handoff, never auto-fired on NL. They are intentionally
out of scope here.

## The fixtures

`eval-<skill>.json` — ~18 queries each, `{query, should_trigger}`, ~9 positive /
~9 near-miss negatives. The negatives are deliberately **adjacent** (share
vocabulary with the target but belong to a sibling skill), e.g. for `workflow`:
"create a github issue for this bug" (→ `gh-issue-management`), "does it match
the spec?" (→ `verify-spec-gate`).

## How to re-run (do NOT use skill-creator run_loop)

Judge each query **with all 12 skill descriptions present** (an Opus panel that
reads every `skills/*/SKILL.md` frontmatter and decides which skill wins),
comparing to the `should_trigger` label. This models real triggering
(discrimination against siblings) without side effects.

**Do not** use skill-creator's isolated `run_eval`/`run_loop`: they create a
command file for a single skill in a bare temp project and run local `claude -p`.
For sillok that measured **recall ≈ 0%** even on near-verbatim queries — an
artifact, because sillok skills need a real codebase + workflow state to be
consulted, and the isolation strips the sibling competition the descriptions are
tuned against. (It also spawns many parallel local `claude -p` processes, which
can OOM the host.)

## Result (2026-06-18, on 3.2.0)

With all 12 skills present: **70/70 correct, precision = recall = accuracy = 1.00**
for all four auto-fire skills. No false positive or false negative, including
across the hardest adjacent pairs (`workflow`↔`gh-issue-management`,
`verify-gate`↔`verify-spec-gate`). Descriptions left **as-is** — at a perfect
proxy score, editing can only regress a currently-correct boundary.

Next time an auto-fire description changes, re-run this check; only edit wording
once a *failing* query pins a confusion to specific text.
