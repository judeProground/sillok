#!/usr/bin/env bash
# Tests scripts/prd-snapshot.sh: arg validation, frontmatter compose, the
# Contents-API upsert fork (create vs update w/ sha), frontmatter preservation
# on update, and the stdout contract (permalink only).
# Hermetic: gh is stubbed (no network); config lives in a throwaway git project.
set -euo pipefail

PLUGIN_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT"
SCRIPT="$PLUGIN_ROOT/scripts/prd-snapshot.sh"

fail() { echo "FAIL: $1" >&2; exit 1; }
pass() { echo "  ok: $1"; }

WORKDIR=$(mktemp -d)
export ARGS_LOG="$WORKDIR/args.log"
export GH_MODE_FILE="$WORKDIR/gh-mode"   # "create" → GET 404 / "update" → GET returns sha+content
trap 'rm -rf "$WORKDIR"' EXIT

# gh stub:
#  - `gh api repos/o/p/contents/<path>?ref=...` (GET) → mode=create: exit 1 (404);
#    mode=update: JSON with .sha and base64 .content (frontmatter with QUOTED
#    epic/review_at — simulates a file written by the current, quoting version);
#    mode=update-legacy: same but epic/review_at UNQUOTED (simulates a file
#    written before frontmatter quoting existed) — preservation must still work
#  - `gh api -X PUT ...` → record argv, print JSON with .commit.sha
STUB="$WORKDIR/bin"
mkdir -p "$STUB"
cat > "$STUB/gh" <<'STUB'
#!/bin/sh
MODE=$(cat "$GH_MODE_FILE" 2>/dev/null || echo create)
is_put=false
for a in "$@"; do [ "$a" = "PUT" ] && is_put=true; done
if [ "$is_put" = true ]; then
  : > "$ARGS_LOG"
  for a in "$@"; do printf '%s\n' "$a" >> "$ARGS_LOG"; done
  echo '{"commit":{"sha":"cafe1234"},"content":{"path":"projects/basic/test-feature/prd.md"}}'
  exit 0
fi
# GET contents
if [ "$MODE" = "update" ]; then
  b64=$(printf -- '---\ntitle: old\nowner: "@old"\nupdated: 2026-01-01\nstatus: 기획\nsource: https://notion.so/old\nsnapshot_date: 2026-01-01\nepic: "acme/projects#99"\nreview_at: "2026-02-01"\ntags: [type/prd, area/basic]\n---\n\n# old body\n' | base64)
  printf '{"sha":"oldsha123","content":"%s"}\n' "$b64"
  exit 0
fi
if [ "$MODE" = "update-legacy" ]; then
  b64=$(printf -- '---\ntitle: old\nowner: "@old"\nupdated: 2026-01-01\nstatus: 기획\nsource: https://notion.so/old\nsnapshot_date: 2026-01-01\nepic: acme/projects#99\nreview_at: 2026-02-01\ntags: [type/prd, area/basic]\n---\n\n# old body\n' | base64)
  printf '{"sha":"oldsha123","content":"%s"}\n' "$b64"
  exit 0
fi
echo '{"message":"Not Found"}' >&2
exit 1
STUB
chmod +x "$STUB/gh"

DIR="$WORKDIR/proj"
mkdir -p "$DIR/.claude/sillok"
git init -q "$DIR"
cat > "$DIR/.claude/sillok/workflow.config.json" <<'CFG'
{ "version": 1, "repo": "o/r", "baseBranch": "main", "branchPrefix": "{type}/issue-",
  "epicRepo": "o/p" }
CFG

BODY="$WORKDIR/prd.md"
printf '# 테스트 피처\n\n## 배경\nx\n\n## 목표\ny\n\n## 실행\nz\n\n## AI Agent Role\na\n\n## 평가\nb\n' > "$BODY"

run() { ( cd "$DIR"; PATH="$STUB:$PATH" bash "$SCRIPT" "$@" ); }
log_has() { grep -qF "$1" "$ARGS_LOG"; }

# ── 1. create 모드: permalink만 stdout ────────────────────────────────
echo create > "$GH_MODE_FILE"
out=$(run --domain basic --name test-feature --title "테스트 피처" --source "https://notion.so/x" \
          --snapshot-date 2026-07-03 --body-file "$BODY")
[ "$out" = "https://github.com/o/p/blob/cafe1234/projects/basic/test-feature/prd.md" ] \
  || fail "stdout must be the permalink only, got: $out"
pass "create: permalink on stdout"

# ── 2. PUT payload: path·message·frontmatter ─────────────────────────
log_has "repos/o/p/contents/projects/basic/test-feature/prd.md" || fail "PUT path wrong"
log_has "docs(prd): snapshot basic/test-feature (2026-07-03)" || fail "commit message wrong"
put_content=$(awk '/^content=/{sub(/^content=/,""); print}' "$ARGS_LOG" | base64 -d)
echo "$put_content" | grep -q '^source: "https://notion.so/x"$' || fail "frontmatter source missing"
echo "$put_content" | grep -q '^snapshot_date: 2026-07-03$' || fail "frontmatter snapshot_date missing"
echo "$put_content" | grep -q '^title: "테스트 피처"$' || fail "title should come from --title arg"
echo "$put_content" | grep -q 'area/basic' || fail "area tag missing"
pass "create: PUT payload composed"

# ── 3. sha 없이 create (신규 파일엔 -f sha 미전송) ─────────────────────
grep -q '^sha=' "$ARGS_LOG" && fail "create must not send sha"
pass "create: no sha field"

# ── 4. update 모드: sha 전송 + 기존 epic/review_at 보존 (quoted prev file) ──
echo update > "$GH_MODE_FILE"
out=$(run --domain basic --name test-feature --source "https://notion.so/new" \
          --snapshot-date 2026-07-03 --body-file "$BODY")
log_has "sha=oldsha123" || fail "update must send existing sha"
put_content=$(awk '/^content=/{sub(/^content=/,""); print}' "$ARGS_LOG" | base64 -d)
echo "$put_content" | grep -q '^epic: "acme/projects#99"$' || fail "existing epic must be preserved"
echo "$put_content" | grep -q '^review_at: "2026-02-01"$' || fail "existing review_at must be preserved"
echo "$put_content" | grep -q '^snapshot_date: 2026-07-03$' || fail "snapshot_date must be refreshed"
pass "update: sha sent + epic/review_at preserved"

# ── 4b. update 모드: 이전 파일이 unquoted(legacy) epic/review_at 여도 보존 ──
echo update-legacy > "$GH_MODE_FILE"
out=$(run --domain basic --name test-feature --source "https://notion.so/new" \
          --snapshot-date 2026-07-03 --body-file "$BODY")
put_content=$(awk '/^content=/{sub(/^content=/,""); print}' "$ARGS_LOG" | base64 -d)
echo "$put_content" | grep -q '^epic: "acme/projects#99"$' || fail "legacy unquoted epic must be preserved and requoted (not double-quoted)"
echo "$put_content" | grep -q '^review_at: "2026-02-01"$' || fail "legacy unquoted review_at must be preserved and requoted (not double-quoted)"
pass "update: legacy unquoted epic/review_at preserved without double-quoting"

# ── 5. --epic 명시 시 새 값이 이김 ─────────────────────────────────────
echo update > "$GH_MODE_FILE"
out=$(run --domain basic --name test-feature --source "https://notion.so/new" \
          --snapshot-date 2026-07-03 --epic "o/p#123" --body-file "$BODY")
put_content=$(awk '/^content=/{sub(/^content=/,""); print}' "$ARGS_LOG" | base64 -d)
echo "$put_content" | grep -q '^epic: "o/p#123"$' || fail "explicit --epic must win"
pass "update: explicit --epic wins"

# ── 6. 검증 실패들: 잘못된 domain / name / epicRepo 미설정 ──────────────
echo create > "$GH_MODE_FILE"
run --domain nope --name t --source s --snapshot-date 2026-07-03 --body-file "$BODY" 2>/dev/null \
  && fail "unknown domain must exit non-zero" || pass "invalid domain rejected"
run --domain basic --name "Bad_Name" --source s --snapshot-date 2026-07-03 --body-file "$BODY" 2>/dev/null \
  && fail "non-kebab name must exit non-zero" || pass "non-kebab name rejected"
run --domain basic --name test-feature --source s --snapshot-date "2026/07/03" --body-file "$BODY" 2>/dev/null \
  && fail "bad snapshot-date format must exit non-zero" || pass "bad snapshot-date format rejected"
NOEPIC="$WORKDIR/proj2"; mkdir -p "$NOEPIC/.claude/sillok"; git init -q "$NOEPIC"
echo '{ "version": 1, "repo": "o/r" }' > "$NOEPIC/.claude/sillok/workflow.config.json"
( cd "$NOEPIC"; PATH="$STUB:$PATH" bash "$SCRIPT" --domain basic --name t --source s \
  --snapshot-date 2026-07-03 --body-file "$BODY" ) 2>/dev/null \
  && fail "missing epicRepo must exit non-zero" || pass "missing epicRepo rejected"

# ── 7. 5섹션 누락은 경고만 (exit 0) ────────────────────────────────────
THIN="$WORKDIR/thin.md"; printf '# 제목만\n\n본문\n' > "$THIN"
out=$(run --domain basic --name test-feature --source s --snapshot-date 2026-07-03 --body-file "$THIN" 2>"$WORKDIR/err")
[ -n "$out" ] || fail "thin PRD must still succeed (warn only)"
grep -q "warn" "$WORKDIR/err" || fail "missing sections must print a warning to stderr"
put_content=$(awk '/^content=/{sub(/^content=/,""); print}' "$ARGS_LOG" | base64 -d)
echo "$put_content" | grep -q '^title: "test-feature"$' || fail "title must fall back to --name (never the body H1)"
pass "missing sections warn but do not block"

# ── 8. PRD-convention args → frontmatter 키 매핑 ───────────────────────
echo create > "$GH_MODE_FILE"
out=$(run --domain basic --name test-feature --source "https://notion.so/x" \
          --snapshot-date 2026-07-03 --body-file "$BODY" \
          --feature-goal "리텐션 +5%p" --task-type "MainTask" --sprint "Sprint 12" \
          --dev-period "2026-07-01 ~ 2026-07-14" --owners "@a, @b" \
          --metric "DAU +1000" --release-date "2026-07-20" \
          --eval-dates "d3: 2026-07-23, d7: 2026-07-27")
put_content=$(awk '/^content=/{sub(/^content=/,""); print}' "$ARGS_LOG" | base64 -d)
echo "$put_content" | grep -q '^feature_goal: "리텐션 +5%p"$' || fail "feature_goal missing/mismatched"
echo "$put_content" | grep -q '^task_type: "Main"$' || fail "task_type must be normalized MainTask→Main"
echo "$put_content" | grep -q '^sprint: "Sprint 12"$' || fail "sprint missing/mismatched"
echo "$put_content" | grep -q '^dev_period: "2026-07-01 ~ 2026-07-14"$' || fail "dev_period missing/mismatched"
echo "$put_content" | grep -q '^owners: \["@a", "@b"\]$' || fail "owners missing/mismatched"
echo "$put_content" | grep -q '^metric: "DAU +1000"$' || fail "metric missing/mismatched"
echo "$put_content" | grep -q '^release_date: 2026-07-20$' || fail "release_date missing/mismatched"
echo "$put_content" | grep -q '^eval_dates: { d3: 2026-07-23, d7: 2026-07-27 }$' || fail "eval_dates missing/mismatched"
pass "PRD-convention args mapped into frontmatter"

# ── 8b. update 모드: PRD-convention 키도 epic/review_at처럼 보존 ───────
echo update > "$GH_MODE_FILE"
cat > "$STUB/gh" <<'STUB'
#!/bin/sh
MODE=$(cat "$GH_MODE_FILE" 2>/dev/null || echo create)
is_put=false
for a in "$@"; do [ "$a" = "PUT" ] && is_put=true; done
if [ "$is_put" = true ]; then
  : > "$ARGS_LOG"
  for a in "$@"; do printf '%s\n' "$a" >> "$ARGS_LOG"; done
  echo '{"commit":{"sha":"cafe1234"},"content":{"path":"projects/basic/test-feature/prd.md"}}'
  exit 0
fi
if [ "$MODE" = "update" ]; then
  b64=$(printf -- '---\ntitle: old\nowner: "@old"\nupdated: 2026-01-01\nstatus: 기획\nsource: https://notion.so/old\nsnapshot_date: 2026-01-01\nfeature_goal: "old goal"\ntask_type: "Sub"\nsprint: "Sprint 1"\ndev_period: "2026-01-01 ~ 2026-01-14"\nowners: ["@old1", "@old2"]\nmetric: "old metric"\nrelease_date: 2026-01-15\neval_dates: { d3: 2026-01-18, d7: 2026-01-22 }\nepic: "acme/projects#99"\nreview_at: "2026-02-01"\ntags: [type/prd, area/basic]\n---\n\n# old body\n' | base64)
  printf '{"sha":"oldsha123","content":"%s"}\n' "$b64"
  exit 0
fi
if [ "$MODE" = "update-legacy" ]; then
  b64=$(printf -- '---\ntitle: old\nowner: "@old"\nupdated: 2026-01-01\nstatus: 기획\nsource: https://notion.so/old\nsnapshot_date: 2026-01-01\nepic: acme/projects#99\nreview_at: 2026-02-01\ntags: [type/prd, area/basic]\n---\n\n# old body\n' | base64)
  printf '{"sha":"oldsha123","content":"%s"}\n' "$b64"
  exit 0
fi
echo '{"message":"Not Found"}' >&2
exit 1
STUB
chmod +x "$STUB/gh"
out=$(run --domain basic --name test-feature --source "https://notion.so/new" \
          --snapshot-date 2026-07-03 --body-file "$BODY")
put_content=$(awk '/^content=/{sub(/^content=/,""); print}' "$ARGS_LOG" | base64 -d)
echo "$put_content" | grep -q '^feature_goal: "old goal"$' || fail "feature_goal must be preserved"
echo "$put_content" | grep -q '^owners: \["@old1", "@old2"\]$' || fail "owners must be preserved verbatim"
echo "$put_content" | grep -q '^eval_dates: { d3: 2026-01-18, d7: 2026-01-22 }$' || fail "eval_dates must be preserved verbatim"
pass "update: PRD-convention keys preserved when no new value passed"

# ── 9. --domain common 허용 ────────────────────────────────────────────
echo create > "$GH_MODE_FILE"
run --domain common --name test-feature --source s --snapshot-date 2026-07-03 --body-file "$BODY" >/dev/null 2>&1 \
  || fail "--domain common must be accepted"
pass "--domain common accepted"

echo "ALL PASS"
