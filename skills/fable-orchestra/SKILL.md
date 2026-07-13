---
name: fable-orchestra
description: Use on a Fable main-loop session whenever you are about to dispatch a subagent, pick a model/effort for delegated work, or write a long document (spec, plan, report) yourself — and at sillok:workflow chain entry on a Fable session (the orchestrator applies this skill to every stage). Keeps Fable a thin orchestrator — plan, route, judge — delegating bulk coding to Sonnet workers and hard/long reasoning to Opus workers by model×effort, so most tokens bill at the cheaper worker rate. The "Fable orchestrator" pattern.
---

# Fable Orchestra

Turn a Fable session into a **thin orchestrator**. Fable is the strongest reasoner but the most expensive tier, and it burns tokens fastest in two places: long high-effort reasoning, and long-form output. So do not let it grind and do not let it type: keep Fable at the routing altitude — plan, decide, delegate, review, merge — and push the expensive work **down** to cheaper subagents. Because a subagent's full exploration bills at the subagent's tier and only its final summary returns to Fable, most tokens end up at the cheaper worker rate.

This skill is a discipline, not a tool: it does not switch models. It tells the Fable main loop *how* to delegate.

## 1. Precondition — you must be Fable

A skill cannot change the session model; only `/model` can. This discipline only pays off when the **main loop** is Fable (so orchestration overhead is the one unavoidable Fable cost, and everything expensive is delegated away from it).

- If you are running as Fable → proceed.
- If you are **not** Fable → stop and tell the user: *"fable-orchestra assumes a Fable main loop. Run `/model fable`, then invoke me again."* Do not try to emulate the pattern from another model — the economics only work when the delegated tiers are genuinely cheaper than the main loop.

## 2. Model rankings — the judgment layer

Rankings, higher = better. **Intelligence** is how hard a problem you can hand the model unsupervised. **Taste** covers UI/UX, code quality, API design, and copy.

| model | cost | intelligence | taste |
|-------|------|--------------|-------|
| sonnet | 7 | 5 | 7 |
| opus | 4 | 7 | 8 |
| fable | 2 | 9 | 9 |

How to apply:

- **These are defaults, not limits.** You have standing permission to override them: if a cheaper model's output doesn't meet the bar, rerun or redo the work with a smarter model without asking. Judge the output, not the price tag. Escalating costs less than shipping mediocre work.
- **Cost is a tie-breaker only**; when axes conflict for anything that ships, **intelligence > taste > cost**.
- Anything user-facing (UI, copy, API design) needs **taste ≥ 7** — sonnet is the floor, opus/fable when it matters.
- Reviews of plans/implementations: **opus** by default; a high-risk or subtle diff justifies a **fable reviewer** — reviews read much and write little, which is the one worker shape where fable's price is affordable.
- Never dispatch a worker at **fable** for implementation or exploration — fable's seat is the main loop.

## 3. Routing — the `model × effort` matrix

Every step you take, place it in one of three roles. `model` and `effort` are **both** levers.

| Role | Model | Effort | What it does |
|------|-------|--------|--------------|
| **Orchestrator** (you, the main loop) | fable | low–medium (high at most; never xhigh/max) | Routing, decisions, delegation specs, reading worker reports, reviewing drafts, merging results. |
| **Hard-reasoning worker** | opus | high–xhigh | Architecture, ambiguous debugging, design judgment, security-sensitive logic — anything where a subtly wrong answer silently poisons downstream work. |
| **Coding worker** | sonnet | low–medium | Implement to a spec, write tests, search/explore the codebase, mechanical refactors, draft long documents from an outline. The volume workhorse. |

**Two delegation signals** — the moments Fable must hand off instead of doing it:

1. **You want to think long at `xhigh`** → that is an **Opus worker**, not a deeper breath. Fable stays at low–medium (high at most) — `xhigh`/`max` on fable is a token furnace with no output-quality payoff.
2. **You are about to write a long document** (spec, plan, report — anything past roughly a page) → **Sonnet drafts it from your outline; you review.** Output tokens are the most expensive thing fable produces. Fable writes decisions and outlines, never long prose.

Token-hungry task *types* follow the same logic: codebase analysis, bulk file reading, wide exploration — dispatch them cheap (sonnet) and have results reported back as summaries.

**Per-step decision** — classify by *reasoning difficulty × blast radius*:

- Pure coordination, reading a report, writing the next delegation spec, a trivial 1–2 line edit in a known file → **do it as Fable.**
- Well-specified, self-contained execution you can write crisp acceptance criteria for → **Sonnet worker.**
- High-blast-radius reasoning that is expensive to redo (a wrong answer corrupts N later steps) → **Opus worker.**
- **Tie-breaker:** write the spec first, then pick the *cheapest* model that clears the bar (§2 rankings). If you cannot write crisp acceptance criteria, the step is a reasoning step in disguise — send it to Opus; do not hand ambiguity to a Sonnet worker.

## 4. Delegation convention

Delegation is where this pattern is won or lost. Two failure modes dominate: a worker starved of context that guesses and returns plausible-but-wrong work, and a Fable context that balloons from re-reading fat transcripts.

- **Always specify `model` AND `effort` on every dispatch.** An omitted `model` inherits your session model — Fable — the most expensive tier, silently defeating the whole point. This is the single most common way the pattern fails.
- **Front-load a self-contained spec + explicit acceptance criteria.** The worker does not share your conversation. Include the files/paths, the relevant convention, and any prior decision that lives only in your context. If you would not accept the task with only what you wrote, neither can the worker.
- **Verify worker output before it becomes an input.** Never chain an unverified result into the next dispatch — one wrong answer compounds.
- **Keep return payloads terse — final summary only.** Ask workers to return a short summary, not full diffs or logs. Fat returns grow your Fable-priced context for no benefit.

## 5. Escalation & merge — the 4-status handoff

A worker that hits a wall must **stop and report**, not invent output. Read the status and respond by cause — mapped onto the `model × effort` ladder. (This mirrors `superpowers:subagent-driven-development`.)

| Status | Cause | Your response as orchestrator |
|--------|-------|-------------------------------|
| **DONE** | Complete | Verify, then merge / proceed. |
| **DONE_WITH_CONCERNS** | Done but flagged doubts | Read the concerns; resolve correctness/scope before building on the result. |
| **NEEDS_CONTEXT** | Your delegation spec was missing something | Fill the gap, **re-dispatch the same model**. |
| **BLOCKED** | Under-powered model / ambiguous spec / task too big / external blocker | Escalate to **Opus** (needs more reasoning), **disambiguate or split** the task yourself (routing is your job), or escalate to the **human** (credentials, product calls). |

Beyond BLOCKED, there is **quality escalation** (§2): a worker can return DONE and still miss the bar. When it does, redo the step one tier up without asking — that is the standing permission, and it is cheaper than building on mediocre work.

Never force the same model to retry unchanged — if it reported stuck, something must change. A BLOCKED worker is the safety net working, not a failure.

## 6. With sillok — per-stage routing

On a Fable session, `sillok:workflow` applies this skill at chain entry; every stage then routes as follows. The division of labor: **judgment stays with Fable, typing and volume go down.**

| Stage | Fable does | Delegated |
|-------|-----------|-----------|
| **start / add / end** | Everything — coordination, short issue/PR bodies | — (too small to delegate) |
| **design** | The brainstorming itself — interactive, frontier-quality judgment; and the review of the drafted spec against the decisions | **Spec document writing** → sonnet worker drafts from Fable's decisions + outline; Fable reviews, then pastes to the issue |
| **execute** | Routing, plan review, worker-report judgment | **Plan document** → sonnet drafts from the spec, Fable reviews. **Implementation** → superpowers tiers pinned: cheap → `sonnet`/low, standard → `sonnet`/medium, most-capable → `opus`/high–xhigh. **Whole-branch review** → opus (fable for high-risk diffs, per §2). Implementation/exploration workers are never fable (§2's review carve-out aside). |

The superpowers `subagent-driven-development` skill says "use the most capable available model" for architecture and final review — on a Fable session, read that as **opus** (fable is the orchestrator seat, not a worker tier; §2 reviews-rule is the exception).

## Red flags — you are drifting off-pattern

| Thought | Correction |
|---------|------------|
| "I'll just reason through this hard part myself." | That's the Opus signal. Delegate it. |
| "I'll write out this spec/plan real quick." | That's the long-document signal. Outline it; sonnet drafts; you review. |
| "Let me crank effort up to xhigh for this." | Fable never runs xhigh/max. Want xhigh-grade thinking → opus worker. |
| "I'll skip `model:` on this dispatch." | It inherits Fable. Always set `model` + `effort`. |
| "The worker can figure out the context." | It can't — it doesn't see your conversation. Write the spec. |
| "I'll have the worker return the full diff so I can check." | Return a summary. Verify by targeted read, not by absorbing everything. |
| "The output is mediocre but resending costs tokens." | Escalating costs less than shipping mediocre work. One tier up, redo. |
| "This is one big task, one big worker." | If it's really ≥2 tasks, split it — big vague dispatches come back BLOCKED. |
