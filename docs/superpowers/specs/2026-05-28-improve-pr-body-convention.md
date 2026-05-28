# Improve PR body convention in sillok-end (#29)

**Issue:** [#29](https://github.com/judeProground/sillok/issues/29)
**Parent:** [#18](https://github.com/judeProground/sillok/issues/18)
**Status:** Designed
**Authored:** 2026-05-28

## Goal

PR body의 Summary를 더 실질적으로 만들고, spec과 실제 구현 차이 + 리뷰/QA 수정사항을 기록.

## PR body 새 구조

```markdown
Closes #N

## Summary

<2-3 lines on what and why. Squash commit message + done-note.>

## Deviations from spec

- <spec과 다르게 구현된 부분과 이유>
- (없으면 빈 섹션)

## Review fixes

- <code review / verify-gate에서 발견되어 수정된 사항>
- (없으면 빈 섹션)

## Test plan

- [ ] <manual test items>
```

## Changes

### 1. `commands/sillok-end.md` — Step 5 변경

Step 5 heredoc 업데이트:

```bash
PR_BODY=$(cat <<EOF
Closes #<N>

## Summary

<2-3 lines describing the work. THIS BECOMES THE SQUASH COMMIT MESSAGE.>

## Deviations from spec

<List any differences between the spec (in issue body ## Design) and the actual
implementation. Include the reason for each deviation. If implementation matches
spec exactly, leave this section empty.>

## Review fixes

<List issues found during code review or verify-gate that were fixed before this PR.
If no review findings required changes, leave this section empty.>

## Test plan

- [ ] <manual test items derived from the spec's acceptance criteria>
EOF
)
```

**Deviations from spec 추출 방법:**

sillok-end 시점에 LLM은 이미 다음을 알고 있음:
- Issue body의 `## Design` (spec 전체)
- Execute 단계에서 실제로 구현한 내용 (대화 맥락)
- Code review에서 나온 피드백

추가 API 호출 없이 기존 컨텍스트에서 회고적으로 추출. 토큰 부담 거의 없음.

**Review fixes 추출 방법:**

superpowers의 code-reviewer / verify-gate 결과가 대화 맥락에 남아있음. sillok-end가 실행될 때 "Important 발견 → fix subagent → 재검증" 히스토리에서 추출.

### 2. `templates/rules/pr-convention.md` — body template 업데이트

```markdown
Closes #N

## Summary

<2-3 lines on what and why. This becomes the squash commit message AND the done-note on the closed issue.>

## Deviations from spec

<Differences between the spec and actual implementation, with reasons. Empty if none.>

## Review fixes

<Issues found during code review / verify-gate that were fixed. Empty if none.>

## Test plan

- [ ] ...
```

Spec is in the issue body (linked via `Closes #N`). Key decisions are also in the issue body. No need to duplicate in PR.

### 3. Story-finalize PR body (Step 5b) — 변경 없음

Story-finalize는 이미 자체 구조 (Sub-features + Recommended merge)를 가지고 있고, 개별 sub-feature PR에서 deviations/review fixes가 기록됨. Story PR에 중복할 필요 없음.

## Key decisions

- **Deviations/Review fixes 빈 섹션 유지** — 차이가 없어도 섹션 존재. 일관된 구조 + "확인했는데 없었다"는 명시적 신호.
- **Key decisions PR에 안 넣음** — issue body에 있으니 `Closes #N`으로 충분.
- **회고적 추출** — sillok-end 시점에 기존 컨텍스트에서 추출. 추가 API 호출이나 토큰 부담 없음.
