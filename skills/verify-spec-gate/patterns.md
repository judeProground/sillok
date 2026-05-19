# Design Patterns

**Load when:** designing a new component, considering a refactor, naming an abstraction, or trying to articulate why a structure feels wrong.

**Source:** [refactoring.guru/design-patterns/catalog](https://refactoring.guru/design-patterns/catalog). This file is a terse index — when a pattern looks like it might fit, follow the link for the full discussion.

**Heuristic:** every non-trivial structure in our code should be explainable in terms of one of these patterns. If it isn't, that's a signal — either rename it (so the pattern is visible) or restructure it (because the design is confused).

**Counter-heuristic:** don't reach for a pattern when a function will do. Patterns earn their keep by handling *variation*. Without variation, they add noise.

---

## Creational — *how objects are constructed*

| Pattern | Idea | When it fits | Project example |
|---|---|---|---|
| [Factory Method](https://refactoring.guru/design-patterns/factory-method) | Subclass decides which concrete to instantiate | Need to defer the concrete choice to a subclass or config | Creating exchange clients per ticker config |
| [Abstract Factory](https://refactoring.guru/design-patterns/abstract-factory) | Build families of related objects together | Variants must be matched (spot + perp + transfer) | Pairing spot+perp families per environment |
| [Builder](https://refactoring.guru/design-patterns/builder) | Construct a complex object step-by-step | Many optional fields, especially when order matters | Order construction with optional TIF / post-only / reduce-only flags |
| [Prototype](https://refactoring.guru/design-patterns/prototype) | Clone an existing instance | Construction is expensive or context-dependent | Rare in our code |
| [Singleton](https://refactoring.guru/design-patterns/singleton) | One shared instance | Genuinely global, immutable-ish state | `ConfigManager`-style only. Hides dependencies — use sparingly |

## Structural — *how objects compose*

| Pattern | Idea | When it fits | Project example |
|---|---|---|---|
| [Adapter](https://refactoring.guru/design-patterns/adapter) | Wrap an incompatible interface in the expected one | Bringing a third-party SDK into our shape | Wrapping CCXT or raw HTTP into `IExchange` |
| [Bridge](https://refactoring.guru/design-patterns/bridge) | Decouple abstraction from implementation | Two dimensions vary independently | Order type × exchange (when both vary) |
| [Composite](https://refactoring.guru/design-patterns/composite) | Tree of uniform parts treated like one | Group + leaf share the same interface | Multi-leg orders treated like single orders |
| [Decorator](https://refactoring.guru/design-patterns/decorator) | Wrap to add behavior without subclassing | Add concerns (logging, retry, rate-limit) per call site | Logging/retry around an exchange client |
| [Facade](https://refactoring.guru/design-patterns/facade) | Simple front for a complex subsystem | Many internal moving parts, one external use case | `arbitrage` CLI hiding strategy + executor + recovery |
| [Flyweight](https://refactoring.guru/design-patterns/flyweight) | Share state to save memory | Many near-duplicate objects | Rare — only when object count is huge |
| [Proxy](https://refactoring.guru/design-patterns/proxy) | Stand-in that controls access | Dry-run, lazy init, access control | Dry-run mode wrapping a live executor |

## Behavioral — *how objects communicate*

| Pattern | Idea | When it fits | Project example |
|---|---|---|---|
| [Chain of Responsibility](https://refactoring.guru/design-patterns/chain-of-responsibility) | Pass a request along handlers until one handles it | Pipeline of independent gates | Validation pipeline (premium gate → liquidity gate → balance gate) |
| [Command](https://refactoring.guru/design-patterns/command) | Encapsulate a request as an object | Need to queue / log / undo | Reified trade actions for recording and replay |
| [Iterator](https://refactoring.guru/design-patterns/iterator) | Walk a collection without exposing structure | Custom traversal | Mostly built into JS — note when you implement one |
| [Mediator](https://refactoring.guru/design-patterns/mediator) | Centralize complex many-to-many comms | EventEmitter spaghetti emerges | When event topology becomes a graph, not a tree |
| [Memento](https://refactoring.guru/design-patterns/memento) | Snapshot/restore state | Need rollback or replay | Cycle state checkpoints for recovery |
| [Observer](https://refactoring.guru/design-patterns/observer) | Subjects notify subscribers | Decouple producers from consumers | **Project default** — see "EventEmitter Decoupling" rule in root CLAUDE.md |
| [State](https://refactoring.guru/design-patterns/state) | Behavior changes with internal state | Object behaves differently in different phases | Cycle lifecycle (idle → setup → arb → unwind → done) |
| [Strategy](https://refactoring.guru/design-patterns/strategy) | Swap algorithm via interface | Multiple ways to do the same thing | Pluggable arbitrage strategies; limit vs. market order placement |
| [Template Method](https://refactoring.guru/design-patterns/template-method) | Skeleton in base, steps in subclass | Common flow, varying steps | `BaseExchange` / `BasePerpExchange` are exactly this |
| [Visitor](https://refactoring.guru/design-patterns/visitor) | Add operations to a class hierarchy externally | Operations grow faster than node types | Rare — usually a sign hierarchy ownership is wrong |

---

## Anti-pattern check

- **God Object as Facade** — a Facade delegates; a god object implements everything itself. If the "facade" is 500 lines, it isn't one.
- **Strategy with one concrete** — that's just a function with a wrapper. Inline it until a second strategy actually appears.
- **Singleton holding business state** — that's a hidden global. Refactor to a regular instance passed explicitly.
- **Observer with one listener** — overhead with no decoupling benefit. Direct call instead.
- **Factory of Factories** — almost always speculative generality. Collapse a layer.
