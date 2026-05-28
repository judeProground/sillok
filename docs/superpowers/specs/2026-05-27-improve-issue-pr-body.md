# Improve issue body and PR body conventions (#18)

**Issue:** [#18](https://github.com/judeProground/sillok/issues/18)
**Status:** Designed
**Authored:** 2026-05-27
**Type:** Story

## Background

현재 sillok-design Step 8이 spec.md 전체를 issue body `## Design` 섹션에 붙여넣음. 긴 spec은 핵심이 묻히고, 3개월 후 이슈를 다시 열면 "왜 이렇게 했지?"를 알려면 spec 전체를 다시 읽어야 함.

또한 spec/plan .md 파일을 git에 커밋하고 있는데, 이슈 body가 canonical record이므로 파일은 작업 중 임시 아티팩트로 충분. 커밋하면 stale 문서가 repo에 남는 noise.

## Sub-issues (planned)

1. **Issue body에 Key Decisions 섹션 추가** — `sillok-design` Step 8 변경 + `gh-issue-conventions.md` 업데이트
2. **Spec/plan 파일 gitignore** — `sillok-init`에서 `.gitignore`에 추가, issue/PR body에서 경로 참조 제거
3. **PR body convention 개선** — `sillok-end` Step 5 변경 + `pr-convention.md` 업데이트

## Design

### Sub-issue 1: Key Decisions 섹션

#### Issue body 새 구조

```markdown
Parent: #M

## Summary

<1-2 sentences>

## Key decisions

- **<무엇을 결정했는가>** — <왜. 대안은 뭐였고 왜 안 골랐는지. 한 문장.>
- **<무엇을 결정했는가>** — <왜. 한 문장.>

## Design

<full spec content, as before>

## Plan link
## PR link
```

Key decisions가 Summary 바로 다음, Design(full spec) 위에 위치. 이슈를 열면 Summary + Key decisions만 첫 화면에 보임.

#### Key decision의 정의

"Decision" = 2개 이상 선택지가 있었고, 하나를 골랐고, 나중에 누군가 "왜 다른 걸 안 했지?"라고 물을 만한 것.

이 기준을 안 넘으면 key decision이 아니라 implementation detail → 포함하지 않음.

#### 품질 규칙 (sillok-design instruction에 삽입)

1. **2-5개 max.** 2개 강한 게 5개 약한 것보다 나음. 0개도 허용 (단순 bug fix 등).
2. **brainstorming 대화에서 추출.** spec 텍스트 요약이 아니라, 유저가 실제로 선택한 분기점에서 추출.
3. **유저가 쓴 용어 그대로.** LLM이 추상화하거나 기술 용어로 격상하지 않음.
4. **각 bullet이 독립적.** 이것만 읽고 맥락 없이 이해되어야 함.
5. **포맷 고정:** `- **<결정>** — <이유>`. 한 줄. 길어지면 결정이 너무 복잡한 것 → 분리하거나 단순화.

#### sillok-design 변경

Step 8 (issue body 업데이트) 전에 새 step 삽입:

**Step 7.5: Extract key decisions**

brainstorming (step 4)의 대화 맥락 + 확정된 spec에서 key decisions를 추출. 유저에게 보여주고 확인받음 (review loop의 일부로).

Step 8에서 issue body 재구성 시 `## Key decisions` 섹션을 `## Summary`와 `## Design` 사이에 삽입.

### Sub-issue 2: Spec/plan 파일 gitignore

- `sillok-init`에서 `.gitignore`에 `docs/superpowers/` 추가 (기존 프로젝트는 수동 추가 안내)
- `sillok-design` Step 8: issue body에서 `## Plan link` 의 경로 참조는 유지하되, 커밋 의무 제거
- `sillok-end` Step 5: PR body에서 Design/Plan 경로 섹션 제거 또는 optional로 변경
- `gh-issue-conventions.md` / `pr-convention.md` 업데이트

**Spec 파일의 lifecycle:**
1. `sillok-design`이 `<SPEC_DIR>/<date>-<slug>.md`에 작성 (로컬 워킹 아티팩트)
2. `sillok-execute`가 읽어서 plan 작성에 사용
3. Issue body에 full spec이 inline으로 존재 (canonical)
4. 머지 후 worktree 정리 시 파일 소멸 → OK, 이슈 body에 다 있음

### Sub-issue 3: PR body convention 개선

(별도 sub-issue에서 설계)

## Key decisions

- **Issue Forms YAML 안 씀** — GitHub forms는 웹 UI 전용이고 sillok은 API로 이슈 생성하므로 무의미.
- **Nygard ADR 템플릿 대신 한 줄 bullet** — 4섹션(Context/Decision/Status/Consequences)은 이슈 body에 과도. `**결정** — 이유` 한 줄이면 충분.
- **Spec/plan 파일은 커밋하지 않음** — 이슈 body가 canonical record. 파일은 brainstorming 중 임시 아티팩트.
- **`<details>` 접기 안 씀** — 유저가 원하지 않음. Key decisions가 상단에 있으면 full spec이 아래에 그대로 있어도 됨.
