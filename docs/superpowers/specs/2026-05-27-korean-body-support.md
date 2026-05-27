# Support Korean (and other languages) for generated body content (#19)

**Issue:** [#19](https://github.com/judeProground/sillok/issues/19)
**Status:** Designed
**Authored:** 2026-05-27

## Background

sillok이 생성하는 모든 텍스트 (issue body, PR body, spec, commit message summary) 가 영어 고정. 세션이 한글로 진행되어도 body는 영어로 나옴. 한국어 팀에서는 이슈/PR을 한글로 읽고 싶은 수요가 있음.

## Goal

`workflow.config.json`에 `language` 필드를 추가하여 body 생성 언어를 제어.

- `"auto"` (default): 세션 대화 언어와 동일하게 body 작성
- `"ko"`: 한국어 고정
- `"en"`: 영어 고정

## Design

### Config

`schema/v1.json`에 `language` 필드 추가:
```json
"language": {
  "type": "string",
  "enum": ["auto", "ko", "en"],
  "default": "auto"
}
```

`templates/workflow.config.json`에 `"language": "auto"` 추가.

### Precompute scripts

4개 precompute script (`precompute-{start,design,execute,end}.sh`) 에 `### Language` 섹션 추가. config에서 읽어 출력:

```
### Language
- Config: `auto`
```

### Command language instruction

각 command markdown 파일에 **language instruction block**을 추가. precompute 출력의 `### Language` 값을 읽어 body 생성 시 적용.

**적용 대상 (content-generating commands):**

| Command | 적용 위치 | 생성하는 content |
|---------|----------|-----------------|
| `sillok-start.md` | Step 3 (body draft), Step 7 (issue creation) | issue body |
| `sillok-design.md` | Step 4 (brainstorming), Step 5 (spec) | spec file, issue body |
| `sillok-end.md` | Step 5 (PR body) | PR body summary |
| `sillok-story.md` | Step 2.3 (story body), Step 3.5g (promotion body) | issue body |
| `sillok-execute.md` | (no direct body gen — delegates to superpowers) | plan file (via superpowers) |

**Instruction template** (각 command에 삽입):

```markdown
## Language

Read the `### Language` section from the precompute output.

- `auto` → write all generated content (issue body, PR body, spec, commit summary)
  in the same language as the current conversation session.
- `ko` → write all generated content in Korean.
- `en` → write all generated content in English.

Section headers (`## Summary`, `## Design`, `Parent:` etc.) and GitHub API field
names stay in English regardless of language setting — only prose content follows
the language preference.
```

### Scope boundary

- **Section headers are always English.** `## Summary`, `## Design`, `## Integration branch`, `Parent:` 등 구조적 마커는 language 설정과 무관하게 영어 유지. 파싱 의존성이 있음 (precompute scripts가 `grep -E '^Parent:'` 등으로 body를 읽음).
- **Label/type names are always English.** `feature`, `story`, `p3` 등.
- **Branch names are always English.** slug는 항상 ASCII.
- **Commit co-author line is always English.**
- **sillok-execute는 변경 없음.** plan 작성은 superpowers skill이 담당. language preference를 brainstorming seed context에 포함시키면 superpowers가 자연스럽게 따름.

### gh-issue-management skill

`skills/gh-issue-management/SKILL.md`에 language 가이드 섹션 추가:

```markdown
## Language

The `language` config key controls the language of generated prose:
- `auto`: match the session language
- `ko` / `en`: force that language

Structural markers (section headers, `Parent:` line, label names) are always English.
```

## Non-goals

- i18n framework나 번역 시스템 — 단순히 LLM instruction으로 해결
- 영어/한국어 외 추가 언어 enum — 향후 필요 시 enum 확장하면 됨
- 기존 이슈/PR body의 소급 번역

## Acceptance criteria

1. `language: "ko"` 설정 후 `/sillok-start` → issue body가 한국어로 생성됨
2. `language: "auto"` + 한국어 세션 → body가 한국어
3. `language: "en"` + 한국어 세션 → body가 영어
4. Section headers (`## Summary` 등)는 항상 영어
5. precompute 출력에 `### Language` 섹션이 포함됨
