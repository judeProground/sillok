# Principles

**Load when:** designing new code, refactoring, making architectural decisions, evaluating tradeoffs in a PR.

**North star:** readability and maintainability. Every principle below serves those two — not the other way around. If applying a principle would make the code harder for a teammate to read in six months, the principle loses.

---

## SOLID

### S — Single Responsibility
A class/module has one reason to change.
- Bad: a class that fetches, validates, and persists.
- Good: separate fetcher, validator, writer.
- **Project example:** `BaseExchange` owns connection lifecycle; orderbook parsing lives in per-exchange subclasses.

### O — Open/Closed
Open for extension, closed for modification.
- Adding a new exchange should not require editing existing exchange code.
- **Project example:** new spot exchange = extend `BaseExchange`; never edit `UpbitExchange`.

### L — Liskov Substitution
Subclasses must be substitutable for the parent without surprises.
- A `BinancePerpExchange` honors every contract of `BasePerpExchange`. If it can't honor one (throws/no-ops), the abstraction is wrong — split it.

### I — Interface Segregation
Many small interfaces beat one fat one.
- Don't make every exchange implement methods it doesn't use.
- Split capability interfaces (`IWithdrawable`, `IFundingRateSource`) when only some implementers care.

### D — Dependency Inversion
Depend on abstractions, not concretes.
- High-level code (arbitrage logic) imports `IExchange`, not `UpbitExchange`.
- This is what makes dry-run mode and tests possible.

---

## DRY — Don't Repeat Yourself
Each piece of knowledge has a single, authoritative representation.
- **Caveat:** premature DRY is worse than duplication. Wait for the **third** occurrence before extracting; the first abstraction off two examples almost always picks the wrong axis.
- Three similar lines is better than one wrong abstraction.

## YAGNI — You Aren't Gonna Need It
Build for today's requirement, not tomorrow's hypothesis.
- No "future flexibility" parameters.
- No options nothing currently sets.
- No abstractions for one caller.

## KISS — Keep It Simple, Stupid
Prefer the simplest code that works.
- Plain function over a class hierarchy when one function suffices.
- Direct call over event/queue when there's no second listener.

---

## OOP fundamentals

- **Encapsulation:** state lives next to the methods that mutate it. Public surface is intentional.
- **Composition over inheritance:** prefer "has-a" to "is-a" unless the LSP test passes cleanly.
- **Tell, don't ask:** call a method on an object instead of pulling its data out and acting on it externally.

---

## When principles conflict

- **DRY vs YAGNI:** YAGNI wins early; DRY wins only after duplication is real and stable (3+ copies).
- **SRP vs KISS:** don't split a 30-line file because it does two things; split when those two things start changing for *different reasons*.
- **OCP vs YAGNI:** don't add extension points speculatively. Add them when the second variant arrives.

The tiebreaker is always **readability + maintainability for the next person reading this code.**
