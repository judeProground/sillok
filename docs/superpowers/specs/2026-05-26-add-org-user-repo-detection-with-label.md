# Org/User repo detection with label fallback (#17)

**Issue:** [#17](https://github.com/judeProground/sillok/issues/17)
**Status:** Designed
**Authored:** 2026-05-26

## Background

sillok v2의 핵심 기능 (Issue Types via REST + createLinkedBranch GraphQL) 이 org-owned repo 에서만 동작. User-owned repo 에서는 API 가 에러 없이 silent null 반환. 팀원이 user repo 에서 sillok v2 쓰면 type 설정과 linked branch 가 조용히 실패.

검증 결과 (2026-05-25):

| 기능 | User repo | Org repo |
|---|---|---|
| Issue Type 설정 (`PATCH -f type=`) | ❌ silent null | ✅ |
| `createLinkedBranch` | ❌ silent null | ✅ |
| Project status update | ✅ | ✅ |

## Goal

`/sillok-init` 에서 org/user 자동 감지 → config 에 `orgMode` 저장 → helper layer 에서 분기:
- **Org mode**: Issue Types API + createLinkedBranch (현재 v2 동작)
- **User mode**: label fallback + linked branch skip

Command 파일은 최소 변경 (issue 생성 REST 에서 type vs label 분기 3줄 if). 나머지 분기는 helper 내부.

## Design

### 감지 + 저장

`/sillok-init` Step 2a:
```bash
OWNER_TYPE=$(gh api "/repos/$REPO" --jq '.owner.type' 2>/dev/null || echo "User")
ORG_MODE=$([[ "$OWNER_TYPE" == "Organization" ]] && echo true || echo false)
```
→ `workflow.config.json` 에 `"orgMode": true|false` 저장. Default: `false` (conservative).

### 동작 비교 (깔끔 분리 — 중복 label 없음)

| 컴포넌트 | Org mode (`orgMode=true`) | User mode (`orgMode=false`) |
|---|---|---|
| Issue 생성 REST | `-f type=Feature` (label 안 붙임) | `-f labels[]=feature` (type 안 붙임) |
| Type 변경 (promotion) `sillok_issue_type_set` | `PATCH -f type=Story` | `gh issue edit --add-label story` |
| Linked branch `sillok_link_branch` | `createLinkedBranch` GraphQL | `return 0` (skip) |
| Label bootstrap | natures + priorities + areas (type labels 안 만듦) | natures + priorities + areas + **type labels** (feature/story/bug/task) |
| Init Issue Type 검증 | 5개 타입 존재 확인 | skip (`TYPES_STATUS=skip-user-repo`) |
| Project status | 변경 없음 | 변경 없음 |

### 변경 파일

| 파일 | 변경 내용 |
|---|---|
| `schema/v1.json` | `orgMode` boolean 필드 추가 |
| `templates/workflow.config.json` | `"orgMode": false` 추가 |
| `commands/sillok-init.md` | Step 2a: org 감지, Step 2b: orgMode=false 면 type 검증 skip, Step 6: jq 에 orgMode 포함, Step 11: org mode 상태 표시 |
| `commands/sillok-start.md` | Step 7: orgMode 분기 — true 면 `-f type=X`, false 면 `-f labels[]=x` |
| `commands/sillok-story.md` | issue 생성 블록: 동일 분기 |
| `scripts/lib/issue-types.sh` | `sillok_issue_type_set`: orgMode=true → PATCH type, false → add-label. `sillok_issue_type_id`: orgMode=false → return empty |
| `scripts/lib/dev-link.sh` | `sillok_link_branch`: orgMode=false → return 0 |
| `scripts/bootstrap-labels.sh` | orgMode=false 일 때 type labels (feature/story/bug/task) 추가 생성 |

### 안 바뀌는 것

- `commands/sillok-design.md` — 변경 없음 (project status 만 건드림)
- `commands/sillok-execute.md` — 변경 없음
- `commands/sillok-end.md` — 변경 없음
- `scripts/precompute-*.sh` — 변경 없음
- `scripts/lib/project.sh` — 변경 없음 (project status 는 모든 repo 에서 동작)

### Type label 색상 (user mode bootstrap)

| Label | 색상 | 설명 |
|---|---|---|
| `feature` | `0e8a16` (green) | New user-facing functionality |
| `story` | `8B5CF6` (purple) | In-repo composite with integration branch |
| `bug` | `d73a4a` (red) | Broken behavior |
| `task` | `666666` (gray) | Generic work unit |

### Edge cases

- **Repo 가 나중에 org 로 transfer 됨**: `/sillok-init` 재실행하면 `orgMode=true` 로 업데이트. 기존 label-tagged 이슈는 그대로 (해롭지 않음). 새 이슈부터 Issue Type 적용.
- **orgMode 수동 override**: config 에서 직접 `"orgMode": true` 로 변경 가능 (테스트 용도). init 재실행하면 감지값으로 덮어씀.
- **Project 가 없는 user repo**: project status update 가 fail 하지만 이건 별개 문제 (project config 미설정). orgMode 와 무관.

## Verification plan

- `sillok_issue_type_set` user mode: label 추가 확인
- `sillok_issue_type_set` org mode: type API 호출 확인
- `sillok_link_branch` user mode: 아무것도 안 하고 return 0
- `bootstrap-labels.sh` user mode: type labels 4개 생성 확인
- `bootstrap-labels.sh` org mode: type labels 생성 안 함 확인
- 전체 test suite 유지 (11/11)

## Out of scope

- v3: label 완전 제거 + Issue Types only (user repo 미지원 선언)
- Stage label fallback (project status 는 모든 mode 에서 동작하므로 불필요)
