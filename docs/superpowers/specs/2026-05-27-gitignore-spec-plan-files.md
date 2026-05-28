# Gitignore spec/plan files and remove path references (#28)

**Issue:** [#28](https://github.com/judeProground/sillok/issues/28)
**Parent:** [#18](https://github.com/judeProground/sillok/issues/18)
**Status:** Designed
**Authored:** 2026-05-27

## Goal

spec/plan .md 파일을 커밋하지 않고 로컬 워킹 아티팩트로만 사용. 이슈 body가 canonical record. issue/PR body에서 파일 경로 참조 제거.

## Changes

### 1. `commands/sillok-init.md` — .gitignore에 추가

init 과정에서 `.gitignore`에 다음 2줄 추가 (이미 있으면 skip):

```
docs/superpowers/specs/
docs/superpowers/plans/
```

기존 프로젝트는 수동 추가 안내 (init은 .gitignore를 append만, 기존 내용 수정 안 함).

### 2. `templates/rules/gh-issue-conventions.md` — Plan link 섹션 변경

Feature/Task template에서 `## Plan link` 경로 참조를 marker로 교체:

변경 전:
```markdown
## Plan link                 <!-- filled by /sillok-execute -->

docs/superpowers/plans/<date>-<slug>.md
```

변경 후:
```markdown
## Plan                      <!-- filled by /sillok-execute -->

Plan written. See local file at `docs/superpowers/plans/<date>-<slug>.md` (not committed).
```

### 3. `templates/rules/pr-convention.md` — Design/Plan 경로 섹션 제거

변경 전:
```markdown
## Design

<docs.specs>/<date>-<slug>.md

## Plan

<docs.plans>/<date>-<slug>.md
```

변경 후: `## Design` / `## Plan` 섹션 완전 제거. PR body는:

```markdown
Closes #N

## Summary

<2-3 lines on what and why>

## Test plan

- [ ] ...
```

이유: spec은 이슈 body에 inline으로 있음 (Closes #N으로 연결). plan은 로컬 아티팩트. PR body에 경로를 넣어도 리뷰어가 클릭할 수 없음 (커밋 안 되니까).

### 4. `commands/sillok-end.md` — Step 5 PR body template 변경

Step 5의 heredoc에서 `## Design` / `## Plan` 섹션 제거. 남는 구조:

```bash
PR_BODY=$(cat <<EOF
Closes #<N>

## Summary

<2-3 lines describing the work>

## Test plan

- [ ] <manual test items>
EOF
)
```

Story-finalize PR body (Step 5b)는 이미 Design/Plan 참조가 없으므로 변경 없음.

### 5. `commands/sillok-execute.md` — Step 4 issue body update 변경

현재: plan 작성 후 `## Plan link\n\n<path>` 를 issue body에 추가.
변경: `## Plan\n\nPlan written.` marker만 추가.

## Key decisions

- **specs/ + plans/ 만 gitignore** — `docs/superpowers/` 전체가 아닌 하위 디렉토리만. 다른 파일이 들어갈 여지 남김.
- **PR body에서 Design/Plan 완전 제거** — 경로가 있어도 커밋 안 되면 클릭 불가. 이슈 body에 spec이 inline으로 있으니 `Closes #N`이 충분한 링크.
- **Plan은 marker만** — "Plan written" 한 줄로 plan이 존재한다는 사실만 기록. 경로는 로컬 참조용.
