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

## Result (2026-07-13, post rules→skills migration, story #100)

Re-ran the panel method after #100 moved GH-issue conventions out of the
always-mounted `gh-issue-conventions.md` rule into the `sillok:gh-issue-management`
skill (and moved `pr-convention`/`worktree-setup`/`spec-driven-development` into
the end/start/execute skills). The competitive field is now larger — `fable-orchestra`
and `prd` exist since the v3.2.0 baseline.

With all skills present: **70/70 correct, precision = recall = accuracy = 1.00** —
identical to the v3.2.0 baseline. All 9 `gh-issue-management` positives still fire:
moving the schema into the skill did not weaken triggering, because the skill's
description enumerates the migrated content (title/body conventions, Issue Types,
priority, nature labels, milestone naming, cross-repo linking). No false positives
from the new skills — `fable-orchestra` is double-gated ("on a Fable session" AND
model×effort routing) so it grabs no generic dispatch/coding query, and `prd` is
`user-invocable: false` so it cannot auto-fire.

Known nuance (pre-existing, not a regression): terse backlog utterances
("백로그에 추가해줘", "make a backlog item") route to `gh-issue-management` (a
convention-full issue) rather than the `add` stage's no-branch/Backlog treatment,
since `add` is non-auto-fire and `workflow`'s description is scoped to
feature-lifecycle. Optional future refinement: name backlog capture in `workflow`'s
description. Descriptions left **as-is** — migration preserved triggering at a
perfect proxy score.
