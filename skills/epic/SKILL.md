---
name: epic
description: Internal sillok stage skill — enter via the /sillok-epic command only (epic sits outside the workflow chain and is never routed by sillok:workflow). Validates a team PRD and creates a light Epic issue in epicRepo for cross-repo parenting.
user-invocable: false
---

# Sillok Epic

You are running the sillok `epic` stage: ingest a team PRD, validate it against the team convention, and create a light Epic issue in `epicRepo` for cross-repo parenting. This command sits OUTSIDE the workflow chain (like `add` and `init`): `sillok:workflow` never routes to it, and it never hands off to a next stage. The Epic it creates is the parent that `/sillok-start --parent <epicRepo>#<N>` links sub-issues to.

PRDs live in `epicRepo` at a path ending in `prd.md` — by convention `<category>/<project-name>/prd.md` (e.g. `basic/onboarding-reminder/prd.md`). sillok does NOT hard-code the categories; it discovers any `*/prd.md` at any depth.

## Step 1: Parse args

The user's input is an optional `<source>` and, for Notion only, an optional `<target>`:

- `<source>` — a PRD path inside `epicRepo` (`<category>/<project>/prd.md`, or just the project dir `<category>/<project>`), OR a local `.md` path, OR a Notion URL (`https://...notion...`), OR empty (picker mode).
- `<target>` — Notion source ONLY: the destination project dir in `epicRepo` (e.g. `basic/onboarding-reminder`) under which the synced `prd.md` is committed.

Capture `SOURCE` (may be empty) and `TARGET` (may be empty).

## Step 2: State derivation

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/precompute-epic.sh "${SOURCE:-}" "${TARGET:-}"
```

If the precompute exits non-zero (e.g., `epicRepo` not configured), surface its error message and STOP.

Otherwise show the printed block to the user as the current state summary, and read:

- `### PRD repo` → `EPIC_REPO` (e.g. `myorg/projects`)
- `### Source` → `mode` (one of: `pick`, `path`, `notion`)
- `### Candidate PRDs` → existing `*/prd.md` paths already in `epicRepo`
- `### Language` → language preference (`auto` / `ko` / `en`)

## Language

Read the `### Language` section (from step 1's precompute block) and apply the `output-language.md` rule (`.claude/sillok/rules/output-language.md`) to all generated content (Epic body).

## Step 3: Resolve the PRD content + its repo path

Resolve the PRD markdown AND the path it lives at in `epicRepo` (`PRD_PATH`), by `mode`:

**`path` mode** — `<source>` points at a PRD:

- If `<source>` is a readable LOCAL file, read it directly. Ask the user for its destination project dir in `epicRepo` (e.g. `basic/onboarding-reminder`) so it can be committed in Step 6 — `PRD_PATH = <dir>/prd.md`.
- Otherwise treat `<source>` as a path INSIDE `epicRepo`: if it ends in `.md`, `PRD_PATH = <source>`; otherwise it is a project dir, so `PRD_PATH = <source>/prd.md`. Fetch it:

```bash
gh api "repos/$EPIC_REPO/contents/$PRD_PATH" --jq '.content' | base64 -d
```

If the path 404s, tell the user it does not exist, show the `### Candidate PRDs` list, and STOP.

**`pick` mode** — no source given. If `### Candidate PRDs` shows the `(none found …)` fallback, print: "`<epicRepo>`에 `*/prd.md` 가 없습니다 — PRD를 먼저 작성/동기화한 뒤 다시 실행하세요" and STOP (`/sillok-epic` is a consume tool, not an authoring tool). Otherwise present the candidate paths and ask the user to choose one — that path is `PRD_PATH`; fetch it as above.

**`notion` mode** — if Notion MCP tools are available, fetch the page at the given URL and convert it to markdown. You need `TARGET` (the destination project dir): if `<target>` was not given, ask for it (e.g. `basic/onboarding-reminder`). Set `PRD_PATH = <TARGET>/prd.md`. If Notion MCP tools are NOT available, print the following and STOP (a graceful exit, not an error):

> Notion MCP가 없습니다 — md 파일 경로를 주거나 MCP를 설치하라
>
> - **md 경로 직접 전달** — 예: `/sillok-epic basic/onboarding-reminder/prd.md`
> - **Notion MCP 설치** — Notion MCP 서버(플러그인)를 설치한 뒤 `/mcp` 로 Notion OAuth 인증
>
> 설치·인증 후 `/sillok-epic <notion-url> <category>/<project>` 를 다시 실행하세요.

## Step 4: Validate against the PRD convention

Read `${CLAUDE_PLUGIN_ROOT}/skills/epic/prd-template.md` raw. Apply every rule in the checklist to the resolved PRD content.

**On any `block` violation:**

1. Print the full checklist with each failing item clearly marked (e.g. `[ ] MISSING: feature_goal`).
2. Print: "PRD 검증 실패 — 위 항목을 수정한 뒤 `/sillok-epic` 를 다시 실행하세요."
3. STOP. Do NOT create the Epic or commit anything.

**On `warn`-only gaps (no `block` failures):** print warnings listing the missing recommended items, then continue.

## Step 5: Extract metadata + Epic title

From the validated PRD frontmatter, extract the 9 metadata values: `feature_goal`, `task_type`, `sprint`, `dev_period`, `owners`, `status`, `metric`, `release_date`, `eval_dates`. Extract a one-sentence `summary` from the PRD body (first meaningful sentence under `# 배경`, or the first non-heading paragraph).

The Epic **title** is the **project name** — the directory that contains `prd.md` in `PRD_PATH` (e.g. `basic/onboarding-reminder/prd.md` → `onboarding-reminder`), humanized (hyphens/underscores → spaces). NOT `feature_goal`, which is a goal *category* (e.g. `리텐션개선`) shared across many PRDs. Show the derived title and let the user adjust: "Epic title: `<title>` — OK? (yes / edit)".

## Step 6: Commit the PRD to epicRepo (only when it is not already there)

- **`notion` mode** (and any LOCAL-file source whose content is not yet in `epicRepo`): commit the markdown to `PRD_PATH`, creating `<category>/<project>/prd.md`:

```bash
CONTENT_B64=$(base64 < "<local-or-converted-md>" | tr -d '\n')
# Create-or-update: if PRD_PATH already exists, fetch its blob sha so the PUT UPDATES it
# instead of failing with HTTP 422 (GitHub's contents API requires sha to overwrite).
EXISTING_SHA=$(gh api "repos/$EPIC_REPO/contents/$PRD_PATH" --jq '.sha' 2>/dev/null || true)
PRD_URL=$(gh api -X PUT "repos/$EPIC_REPO/contents/$PRD_PATH" \
  -f message="docs(prd): sync $PRD_PATH" \
  -f content="$CONTENT_B64" \
  ${EXISTING_SHA:+-f sha=$EXISTING_SHA} \
  --jq '.content.html_url')
```

- **`path` / `pick` mode**: the PRD already lives in `epicRepo` at `PRD_PATH` — do NOT commit. Record its permalink as `PRD_URL` (`https://github.com/$EPIC_REPO/blob/<default-branch>/$PRD_PATH`).

## Step 7: Create the Epic issue

Compose the issue body:

```
## Summary

<summary — one sentence from Step 5>

## Metadata

- feature_goal: <value>
- task_type: <value>
- sprint: <value>
- dev_period: <value>
- owners: <value>
- status: <value>
- metric: <value>
- release_date: <value>
- eval_dates: <value>

## PRD

- 원본(Notion): <Notion URL if notion mode — otherwise omit this line>
- 위치: <PRD_URL>   (epicRepo의 prd.md)
```

Create the Epic via `scripts/create-issue.sh` with `--plain` — the Epic targets `epicRepo` (cross-repo, independent of this consumer's `orgMode`) and its type is PATCHed non-fatally in the next step, so it bypasses the helper's orgMode fork and creates a bare issue. `--body-file -` avoids argv quoting hazards with the body's backticks:

```bash
EPIC_URL=$(bash ${CLAUDE_PLUGIN_ROOT}/scripts/create-issue.sh \
  --repo "$EPIC_REPO" \
  --title "<title>" \
  --plain \
  --body-file - <<'BODY'
<body>
BODY
)
EPIC_N=$(echo "$EPIC_URL" | awk -F/ '{print $NF}')
```

**Set Issue Type (always attempt — epicRepo may be an org repo even when the consumer repo has `orgMode: false`):**

```bash
gh api -X PATCH \
  -H "X-GitHub-Api-Version: 2026-03-10" \
  "repos/$EPIC_REPO/issues/$EPIC_N" \
  -f type="$(sillok_config types.defaults.epic)"
```

If this PATCH fails, WARN: "Epic Issue Type을 설정하지 못했습니다 — epicRepo가 org repo가 아니거나 Epic 타입이 정의돼 있지 않을 수 있습니다" and CONTINUE (the Epic issue is already created; Issue Type failure is non-fatal). The epic URL is still returned.

## Step 8: Output

Print:

- Epic URL: `<EPIC_URL>`
- PRD: `<PRD_URL>`

Then print the exact command for the user's next step:

```
To start a sub-feature under this Epic, run:

  /sillok-start --parent <EPIC_REPO>#<EPIC_N>
```

No handoff. Do NOT invoke `sillok:workflow` — PRD intake is not a stage transition in the chain.

## Integration

- `sillok:start` — adopt `--parent <epicRepo>#<N>` to link sub-issues to the Epic created here; sub-issues are linked at start time, NOT here.
- `sillok:gh-issue-management` — canonical issue title/body conventions.
