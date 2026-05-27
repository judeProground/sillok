# Add Key Decisions section to issue body in sillok-design (#27)

**Issue:** [#27](https://github.com/judeProground/sillok/issues/27)
**Parent:** [#18](https://github.com/judeProground/sillok/issues/18)
**Status:** Designed
**Authored:** 2026-05-27

## Goal

sillok-design이 issue body를 업데이트할 때, `## Summary`와 `## Design` 사이에 `## Key decisions` 섹션을 삽입. Full spec은 그대로 유지.

## Changes

### 1. `commands/sillok-design.md` — Step 7.5 추가

Step 7 (project status) 이후, Step 8 (issue body) 이전에 새 step.

```markdown
## Step 7.5: Extract key decisions

After the spec is confirmed (step 6), extract key decisions from the brainstorming
conversation and the spec content.

A "key decision" is a choice where:
- 2+ viable options existed
- One was picked
- A future reader would ask "why not the other way?"

If no such choices exist (simple bug fix, mechanical change), produce an empty list —
the `## Key decisions` section will still appear in the issue body, just with no bullets.

Draft 2-5 bullet points:

- **<What was decided>** — <Why. What was the alternative and why it wasn't picked. One sentence.>

Rules:
1. Extract from the brainstorming conversation context, not just the spec text.
   If the spec already existed (no brainstorming), extract from the spec content.
2. Use the same terms the user used. Do not elevate to abstract patterns or jargon.
3. Each bullet must be self-contained — readable without the full spec.
4. Prefer fewer strong bullets over many weak ones. 2 strong > 5 weak.
5. Implementation details are not decisions.

Present to the user separately from the spec review:
"Key decisions for the issue body — edit or confirm:"

Iterate until user confirms. Store as `$key_decisions` for step 8.
```

### 2. `commands/sillok-design.md` — Step 8 변경

Issue body 재구성 시 `## Key decisions`를 `## Summary`와 `## Design` 사이에 삽입.

변경 후 body 구조:
```
Parent: #M
## Summary
## Key decisions    ← NEW (always present, may be empty)
## Design           ← full spec, as before
## Plan link
## PR link
```

Step 8 heredoc:
```bash
gh issue edit <N> -F - <<EOF
[Parent: #M line if applicable]

## Summary

<preserved summary>

## Key decisions

$key_decisions

## PRD link

<preserved PRD link if applicable>

## Design

$spec_content
EOF
```

### 3. `templates/rules/gh-issue-conventions.md` — Feature/Task template 업데이트

Feature/Task template에 `## Key decisions` 추가:

```markdown
## Key decisions              <!-- filled by /sillok-design step 7.5; always present -->

- **<decision>** — <reason>
```

위치: `## Summary`와 `## Design` 사이.

Bug template 변경 없음 — design step을 거치지 않음.
Story template 변경 없음 — 별도 #30.

## Key decisions

- **Full spec 유지** — key decisions가 있어도 `## Design`에 spec 전체를 계속 붙여넣음. 길지만 canonical record로서 가치 있음.
- **빈 섹션도 유지** — key decisions가 0개여도 `## Key decisions` 섹션은 남겨둠. 일관된 구조 유지.
- **회고적 추출** — brainstorming skill 수정 불가하므로 spec 확정 후 별도 step에서 추출.
- **Spec 파일 건드리지 않음** — spec은 superpowers가 작성. key decisions는 issue body에만 존재.
