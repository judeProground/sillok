# Code Smells

**Load when:** reviewing code (yours or someone else's), before approving a PR, before committing, or when something feels off but you can't articulate why.

**Source:** [refactoring.guru/refactoring/smells](https://refactoring.guru/refactoring/smells). This file is a terse index — when a smell hits, follow the link for the recommended refactorings.

**Rule:** spotting a smell is not a verdict. It's a question — *"is this here for a real reason?"* Sometimes the answer is yes (irreducible domain complexity, locality of behavior, deadline). Note the smell, ask the question, accept the answer if it's reasoned. Don't reflexively rip it out.

---

## Bloaters — *grew too big to read*

Code, methods, and classes that have ballooned to gargantuan proportions. Usually accumulate over time as the program evolves.

| Smell | Trigger | Fix direction |
|---|---|---|
| [Long Method](https://refactoring.guru/smells/long-method) | Method spans many screens, multiple levels of indentation | Extract Method along seams of intent |
| [Large Class](https://refactoring.guru/smells/large-class) | Many fields, many responsibilities, hard to summarize | Extract Class / Extract Subclass |
| [Primitive Obsession](https://refactoring.guru/smells/primitive-obsession) | Tickers/prices/amounts as raw strings or numbers passed everywhere | Introduce types (`Ticker`, `Price`, `Volume`) |
| [Long Parameter List](https://refactoring.guru/smells/long-parameter-list) | More than 3-4 params, especially booleans | Introduce Parameter Object / Replace Param with Method Call |
| [Data Clumps](https://refactoring.guru/smells/data-clumps) | Same group of params/fields appearing together repeatedly | Extract Class — they're a hidden concept |

## Object-Orientation Abusers — *using OO incompletely or incorrectly*

| Smell | Trigger | Fix direction |
|---|---|---|
| [Alternative Classes with Different Interfaces](https://refactoring.guru/smells/alternative-classes-with-different-interfaces) | Two classes do similar work but disagree on naming / shape | Rename + extract common interface |
| [Refused Bequest](https://refactoring.guru/smells/refused-bequest) | Subclass overrides parent methods to no-op or throw | Wrong inheritance — prefer composition |
| [Switch Statements](https://refactoring.guru/smells/switch-statements) | `switch(exchange)` or `if (type === ...)` repeated across the code | Replace with polymorphism (Strategy / Template Method) |
| [Temporary Field](https://refactoring.guru/smells/temporary-field) | Field only set in some flows, null/empty otherwise | Extract Class for the partial case |

## Change Preventers — *one change forces many*

If a single conceptual change requires edits in many places, the structure is fighting you.

| Smell | Trigger | Fix direction |
|---|---|---|
| [Divergent Change](https://refactoring.guru/smells/divergent-change) | One class edited for unrelated reasons (logging, formatting, business logic) | Extract Class — SRP violation |
| [Parallel Inheritance Hierarchies](https://refactoring.guru/smells/parallel-inheritance-hierarchies) | Adding a subclass to A forces a subclass in B | Merge hierarchies / use composition |
| [Shotgun Surgery](https://refactoring.guru/smells/shotgun-surgery) | One conceptual change touches many files | Move Method/Field — locality is wrong |

## Dispensables — *delete me*

Code that exists for no good reason; removing it makes things cleaner.

| Smell | Trigger | Fix direction |
|---|---|---|
| [Comments](https://refactoring.guru/smells/comments) | Comment explains *what* the code does | Rename + extract until comment becomes redundant. Keep *why* comments. |
| [Duplicate Code](https://refactoring.guru/smells/duplicate-code) | Same logic in 3+ places | Extract Method/Class — but only after the third occurrence (DRY + YAGNI) |
| [Data Class](https://refactoring.guru/smells/data-class) | Class is only fields with getters/setters | Move behavior to it ("tell, don't ask") |
| [Dead Code](https://refactoring.guru/smells/dead-code) | Unreachable / unused | Delete. Git remembers. |
| [Lazy Class](https://refactoring.guru/smells/lazy-class) | Class that does almost nothing | Inline Class |
| [Speculative Generality](https://refactoring.guru/smells/speculative-generality) | Abstractions / params / hooks with one (or zero) callers | Inline / delete (YAGNI) |

## Couplers — *too entangled*

Excessive coupling between classes, or excessive delegation that replaces it.

| Smell | Trigger | Fix direction |
|---|---|---|
| [Feature Envy](https://refactoring.guru/smells/feature-envy) | Method uses another class's data more than its own | Move Method to that class |
| [Inappropriate Intimacy](https://refactoring.guru/smells/inappropriate-intimacy) | Two classes constantly reach into each other's internals | Extract Class / Move Method / introduce a Mediator |
| [Incomplete Library Class](https://refactoring.guru/smells/incomplete-library-class) | Library lacks a method you need | Extension method / wrapper class — don't fork |
| [Message Chains](https://refactoring.guru/smells/message-chains) | `a.b().c().d().e()` | Hide Delegate / Law of Demeter |
| [Middle Man](https://refactoring.guru/smells/middle-man) | Class only delegates, no value of its own | Remove Middle Man |

---

## Project-specific smells (this codebase)

These are not from the catalog — they're concrete bans / patterns specific to this repo, codified in root CLAUDE.md and memory.

- **Inline string symbol manipulation** (e.g. `` `${ticker}_KRW` ``) — Primitive Obsession + Shotgun Surgery. Always route through `SymbolConverter`.
- **`process.cwd()` for paths** — breaks under `pnpm --filter`. Always use `paths` from `@cex/config`.
- **Manual `build:deps` allowlist** in root `package.json` scripts — banned, caused 2026-04-28 stale-dist incident. Use `pnpm --filter "@cex/X^..." build` instead.
- **Direct method call where Observer is the project default** — EventEmitter is the default decoupling mechanism; bypass requires a justification.
- **Mocking the database in tests** — banned per memory. Integration tests hit a real DB.
- **Ad-hoc cron for long-running collectors** (e.g. notice collection) — `claude` CLI can't read login Keychain from cron. Run inside the long-lived monitor process instead.
