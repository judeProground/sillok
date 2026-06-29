# PRD 컨벤션 검증 체크리스트

This subfile is the canonical validation checklist for `/sillok-epic`. `SKILL.md` reads it
raw at runtime and applies each rule to the submitted PRD. Rules are marked **block** (stop
validation, do not create the Epic) or **warn** (emit a warning and continue).

---

## frontmatter 메타데이터 (9 keys)

All 9 keys must be present and non-empty in the YAML frontmatter block. Any missing or empty
value is a **block**.

```yaml
---
feature_goal: <피쳐목표>
task_type: <Main/Sub>
sprint: <Sprint N>
dev_period: <YYYY-MM-DD ~ YYYY-MM-DD>
owners: [<담당자>]
status: <기획|개발중|...>
metric: <숫자 목표>
release_date: <YYYY-MM-DD>
eval_dates: { d3: <YYYY-MM-DD>, d7: <YYYY-MM-DD> }
---
```

Required key checklist — each empty value is a **block**:

| Key | Description | Rule |
|-----|-------------|------|
| `feature_goal` | 피쳐목표 | block if empty |
| `task_type` | Main/Sub 구분 | block if empty |
| `sprint` | Sprint 번호 | block if empty |
| `dev_period` | 개발기간 (날짜 범위) | block if empty |
| `owners` | 담당자 (≥1) | block if empty |
| `status` | 현재 상태 | block if empty |
| `metric` | 수치 목표 | block if empty |
| `release_date` | 출시일 | block if empty |
| `eval_dates` | 평가 예정일 (d3, d7) | block if empty |

---

## 구조 검증 — 필수 H1 목차 5개

The PRD body must contain exactly these five top-level H1 headings (in any order). A missing
section is a **block**.

| Section heading | Korean label | Rule |
|-----------------|--------------|------|
| `# 배경` | Background | block if missing |
| `# 목표` | Goal | block if missing |
| `# 실행` | Execution | block if missing |
| `# AI Agent Role` | AI Agent Role | block if missing |
| `# 평가` | Evaluation | block if missing |

---

## 섹션별 필수·권장 항목

### 배경 (Background)

| Item | Rule |
|------|------|
| 문제 상황 서술 (무엇이 왜 문제인지 명시) | block if absent |
| 데이터/수치 근거 포함 | warn if absent |

### 목표 (Goal)

| Item | Rule |
|------|------|
| Business Impact — 수치 필수 (예: 리텐션 +5%p) | block if absent |
| User Perspective — 사용자 관점 목표 | block if absent |

### 실행 (Execution)

| Item | Rule |
|------|------|
| 개발 범위 — 번호 리스트로 기능 열거 | block if absent |
| 기능별 동작 규칙 | block if absent |
| 데이터 수집 — Mixpanel 이벤트 테이블 또는 "없음" 명시 | block if absent |
| 대상 유저 그룹 | block if absent |
| 수익 구조 수치 (광고/보상 포함 시) | block if feature involves ads/rewards and absent |
| 배포 방식 | block if absent |

### AI Agent Role

| Item | Rule |
|------|------|
| 역할 정의 | block if absent |
| 실행 단계 | block if absent |
| 리포트 규칙 | block if absent |
| 후속 조치 | block if absent |
| 제약 조건 | block if absent |

### 평가 (Evaluation)

| Item | Rule |
|------|------|
| 평가 시점 | block if absent |
| 성공 기준 | block if absent |
| 데이터 측정 방법 | block if absent |
| 평가 실행일 실제 날짜 | block if absent |
| 비교 기간 | block if absent |
| Mixpanel 이벤트명 | block if absent |

---

## 머신파싱 필드 (존재 여부만 검증)

These fields are checked for presence only — their exact format is not validated at this stage.

| Field | Where | Rule |
|-------|-------|------|
| Mixpanel 이벤트 테이블 | `# 실행` section | block if absent (or explicit "없음") |
| 평가 예정일 (eval_dates) | frontmatter `eval_dates` key | block if absent |
| Slack thread URL | anywhere in PRD body (optional) | warn if absent |

---

## 검증 실패 동작

When one or more **block** items fail:

1. Print the full checklist with each failing item marked clearly.
2. Do NOT create the Epic issue.
3. Exit with a non-zero status.
4. Instruct the user to fix the PRD and re-run `/sillok-epic`.

When only **warn** items are missing:

1. Print warnings listing the missing recommended items.
2. Continue to Epic creation.
