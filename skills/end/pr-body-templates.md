# PR body templates

How to compose the PR body during the `sillok:end` stage. **Feature PR body** is the default (SKILL.md Step 5); **Story-finalize PR body** applies only when `MODE=story-finalize` (SKILL.md Step 5b — the empty-story guard there runs first).

## Feature PR body

Use a heredoc:

```bash
PR_BODY=$(cat <<EOF
Closes #<N>
[Single-issue mode: only the line above]
[Umbrella mode: also one Closes line per still-open sub-issue, plus Closes #<parent> if story-completing]

## Summary

<2-3 lines describing the work. THIS BECOMES THE SQUASH COMMIT MESSAGE WHEN MERGED, AND ALSO SERVES AS THE DONE-NOTE FOR THE CLOSED ISSUE. No separate post-merge comment needed.>

## Deviations from spec

<List any differences between the spec (in issue body ## Design) and the actual
implementation. Include the reason for each deviation. If implementation matches
spec exactly, leave this section empty — the heading stays for consistency.>

## Review fixes

<List issues found during code review (superpowers:requesting-code-review) or
verify-gate that were fixed before this PR. Extract from the conversation context
where "Important" findings led to fix subagents. If no review findings required
changes, leave this section empty.>

## Test plan

- [ ] <manual test items derived from the spec's acceptance criteria>
EOF
)
```

Spec is in the issue body (linked via `Closes #N`). Key decisions are also in the issue body. No need to duplicate either in the PR.

The Summary section is critical:

- It is shown verbatim on the issue (auto-closed via Closes #N) — fulfilling the `Done note` requirement of `gh-issue-conventions.md`.
- It is the squash commit message when the user merges with `gh pr merge --squash` — making the project's `main` log readable.

Write 2–3 substantive sentences here, not a 1-line summary.

## Story-finalize PR body

When the current branch is `story/issue-<N>-<slug>` (and the empty-story guard in SKILL.md Step 5b passed):

```bash
# precompute-end lists sub-issues under "### Sub-issues" with state tags like [OPEN]/[CLOSED]
closes_lines="Closes #$N"
while IFS= read -r sub_line; do
  sub_n=$(echo "$sub_line" | grep -oE '#[0-9]+' | head -1 | tr -d '#')
  [[ -n "$sub_n" ]] && closes_lines+=$'\n'"Closes #$sub_n"
done < <(echo "$precompute_output" | awk '/^### Sub-issues/{flag=1; next} /^### /{flag=0} flag && /^- #/')

sub_features_bullets=$(echo "$precompute_output" | awk '/^### Sub-issues/{flag=1; next} /^### /{flag=0} flag && /^- #/{print}')

PR_BODY=$(cat <<EOF
$closes_lines

## Summary

<2–3 lines: what this story accomplishes overall. The integration branch already has clean per-sub-feature commits; with --merge they remain visible on the base branch.>

## Sub-features

$sub_features_bullets

## Recommended merge

Use \`gh pr merge --merge\` (a merge commit) rather than \`--squash\`. This story was assembled on the integration branch with each sub-feature already squashed into a single commit. Merging keeps those sub-feature commits visible in $PR_BASE's history; squashing would flatten them into one giant blob.

## Test plan

- [ ] <items aggregated from acceptance criteria across all sub-feature specs>
EOF
)
```

PR title: story issue's title with `(#<N>)` appended (same as single-issue mode).
