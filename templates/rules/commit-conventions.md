# Commit Conventions

## Format

`<type>(<scope>): <subject> (#N)`

## Types

| Type       | Use for                                  |
| ---------- | ---------------------------------------- |
| `feat`     | New feature                              |
| `fix`      | Bug fix                                  |
| `refactor` | Code restructure without behavior change |
| `docs`     | Documentation only                       |
| `test`     | Test additions or fixes                  |
| `chore`    | Tooling, dependencies, CI, config        |
| `style`    | Formatting, whitespace, non-behavioral   |
| `perf`     | Performance improvement                  |

## Scope (optional)

Feature slice or area — `(recording)`, `(widget)`, `(auth)`, `(android)`, `(ios)`, `(rules)`, `(claude)`.

Omit the parens entirely if no scope applies.

## Subject

- Imperative mood: "add X", not "added X" or "adds X"
- ≤ 72 characters
- No trailing period
- Lowercase first letter after type/scope

## Issue Suffix `(#N)`

When working on a harness branch (`<branchPrefix><N>-<slug>` (configurable) or similar), every commit MUST end with `(#N)` where `N` is the issue number. This allows GitHub to cross-link commits to issues automatically.

Derive `N` from the current branch name. If the branch does not encode an issue number (e.g. `main`, `feature/harness`), the `(#N)` suffix is optional but still recommended when the commit clearly belongs to a known issue.

## Co-author Trailer

For Claude-authored commits, include at the end of the commit body:

```
Co-Authored-By: <configured co-author from workflow.config.json>
```

(Replace the model name/version with whatever Claude identifies as.)

## Examples

```
feat(recording): add volume cap per ticker (#42)

fix(ios): handle NaN in premium calculator (#55)

chore: remove linear-workflow integration (#68)

docs(rules): add rn-component-patterns, gh-issue, pr, commit conventions (#68)
```
