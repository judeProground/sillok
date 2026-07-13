# Story body templates

The two issue-body shapes the `sillok:story` stage composes. **Standalone story body** is used in SKILL.md §2 (Standalone creation, step 3); **Promotion body rewrite** is used in SKILL.md §3 (Promotion, step 6h). Both follow the Story template in `sillok:gh-issue-management`'s `body-templates.md`.

## Standalone story body

Compose the new story's body from this skeleton. `<TBD>` in `## Integration branch` is replaced with the real branch name in §2 step 8 once the branch is resolved.

```markdown
<1-line summary>

## Integration branch

`story/issue-<TBD>-<slug>`

## Key decisions
<empty — filled by /sillok-design story mode>

## Architecture
<empty — filled by /sillok-design story mode>

## Sub-issues
<empty — fills as /sillok-start --parent runs>

## Context
<from prompt>

## Non-goals
<optional>
```

Architecture and Key decisions start empty — `/sillok-design` (story mode) fills them from brainstorming. The user can also write Architecture by hand if they skip design.

## Promotion body rewrite

Rewrite the promoted issue's body from this template, preserving the original `$summary`. When a parent was selected or preserved, include a `Parent: <ref>` line at the top. Post it back with `gh issue edit "$N" --repo "$REPO" -F -` (stdin heredoc):

```bash
gh issue edit "$N" --repo "$REPO" -F - <<EOF
${parent_n:+Parent: ${parent_owner}/${parent_repo}#${parent_n}
}$summary

## Integration branch

\`$story_branch\`

## Key decisions

(Run /sillok-design story mode to capture key decisions.)

## Architecture

(Promoted from $current_issue_type — run /sillok-design story mode, or fill in as sub-features emerge.)

## Sub-issues

## Context

(Original context preserved from the $current_issue_type issue; expand as needed.)

## Non-goals
EOF
```

The user can edit the body afterwards to flesh out Architecture / Context / Non-goals.
