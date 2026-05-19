# Pull Request Convention

Rules for opening and merging PRs.

## Title

`<verb scope> (#N)` where `N` is the issue number the PR closes.

Examples:

- `Add volume-ranked selection to candidate picker (#42)`
- `Fix recording timer negative after pause (#55)`
- `Refactor useRecording to features/recording (#61)`

## Body Template

```markdown
Closes #N

## Summary

<2-3 lines on what and why>

## Design

<docs.specs>/<date>-<slug>.md

## Plan

<docs.plans>/<date>-<slug>.md

## Test plan

- [ ] ...
```

### `Closes #N` is mandatory

GitHub auto-closes the linked issue when the PR merges. Missing this keyword means the issue stays open indefinitely.

For PRs that resolve multiple sub-issues, list each: `Closes #68`, `Closes #69`, etc.

## Force Push

Force push to **any** branch is forbidden unless the user explicitly requests it. If a branch's history needs correction, use `git revert` or open a new PR.

## Merge Strategy

**Squash merge** is the default. It keeps `main` history linear and readable. Individual development commits on the feature branch collapse into a single commit on `main` with the PR title as the message.

## Review

Reviews are optional for solo-dev but recommended for high-risk or cross-cutting changes.
