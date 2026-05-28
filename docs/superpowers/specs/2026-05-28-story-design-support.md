# Support sillok-design for Story issues (#30)

**Issue:** [#30](https://github.com/judeProground/sillok/issues/30)
**Parent:** [#18](https://github.com/judeProground/sillok/issues/18)
**Status:** Designed
**Authored:** 2026-05-28

## Goal

Story branch에서 `/sillok-design` 실행 시, sub-issue 디자인뿐 아니라 Story 자체를 디자인할 수 있도록 umbrella mode 확장. Story-level brainstorming → architecture + sub-issue 분해 + key decisions를 story body에 반영.

## Changes

### 1. `commands/sillok-design.md` — umbrella mode 분기 확장

현재 umbrella mode:
```
"Which sub-issue are you designing? Reply with the issue number."
```

변경 후:
```
Story #<N> detected. What would you like to design?

(a) Design the story itself — brainstorm architecture, sub-issue breakdown, key decisions
(b) Design a sub-issue — pick from open sub-issues below

[list of open sub-issues]
```

**Option (a) — Story 자체 디자인:**

1. `superpowers:brainstorming` skill 호출. Seed:
   - Story title + body (Integration branch, Context, Non-goals 등)
   - Cross-repo PRD body (if prdRepo configured)
   - "This is a Story (composite issue). Brainstorm architecture, sub-issue breakdown, and key decisions. No code-level spec needed."

2. brainstorming 결과를 story body의 `## Architecture` 섹션에 반영 (기존 내용 replace).

3. Step 7.5 (key decisions 추출) 실행 — story body의 `## Key decisions` 에 삽입.

4. Sub-issue breakdown이 나오면 `## Sub-issues` 섹션에 human-readable plan으로 기록. 실제 sub-issue 생성은 `/sillok-start --parent N`으로 별도 수행 (이 step에서 자동 생성 안 함).

5. Spec 파일은 생성하지 않음 — story는 코드 변경이 아니므로 superpowers spec 불필요. story body가 canonical.

**Option (b) — 기존 umbrella mode 그대로.**

### 2. `commands/sillok-design.md` — Step 8 Story body 업데이트

Option (a) 선택 시 Step 8의 heredoc이 Feature/Task 형식 대신 Story 형식으로:

```bash
gh issue edit <N> -F - <<EOF
<preserved summary>

## Integration branch

<preserved>

## Key decisions

$key_decisions

## Architecture

$architecture_content

## Sub-issues

$sub_issues_plan

## Context

<preserved>

## Non-goals

<preserved>
EOF
```

Feature/Task의 `## Design` (full spec inline) 대신 `## Architecture` (brainstorming 산출물)를 사용.

### 3. `templates/rules/gh-issue-conventions.md` — Story template 업데이트

```markdown
<1-line summary>

## Integration branch

`story/issue-<N>-<slug>`

## Key decisions                          <!-- filled by /sillok-design (story mode) -->

- **<decision>** — <reason>

## Architecture                           <!-- filled by /sillok-design (story mode) -->

<brainstorming output: tech choices, data flow, component boundaries>

## Sub-issues

<planned breakdown — each becomes a real sub-issue via /sillok-start --parent N>

## Context

- <motivation>

## Non-goals

- <out of scope>
```

기존 Architecture의 `docs/superpowers/specs/<date>-<slug>.md` 경로 참조 제거 — story에는 spec 파일이 없음.

## Key decisions

- **Spec 파일 안 만듦** — story는 코드 변경이 아님. brainstorming 산출물은 story body에 직접 작성.
- **brainstorming은 호출함** — superpowers:brainstorming으로 architecture + sub-issue 분해. spec 파일 없이 body에 직접 반영.
- **Sub-issue 자동 생성 안 함** — breakdown은 plan으로만 기록. 실제 생성은 `/sillok-start --parent N`으로 유저가 제어.
- **Option 선택 UI** — story/sub-issue 디자인 선택을 항상 물어봄 (sub-issue 0개여도). story를 만들자마자 바로 디자인하는 게 자연스러운 flow.
