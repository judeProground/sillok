---
name: prd
description: Internal sillok stage skill — enter via the /sillok-prd command. Use when a completed PRD markdown (from gihoek prd-creator, a local file, or pasted content) needs to be recorded into epicRepo as a prd.md snapshot.
user-invocable: false
---

# Sillok PRD Snapshot

You are running the sillok `prd` stage: record a completed PRD markdown into
`epicRepo` at `<prd.basePath>/<domain>/<name>/prd.md`. This command sits
OUTSIDE the workflow chain (like `epic`): `sillok:workflow` never routes to it.

The snapshot is **record-only** — the PRD's source of truth is Notion (or
wherever it was authored); review happens there, NOT in a git PR. Interviewing
and authoring belong to gihoek's `prd-creator`; Epic issue creation belongs to
`/sillok-epic`. This stage only records and returns a permalink.

## Step 1: Collect inputs

Required — ask only for what's missing, one question at a time:

- `domain` — one of the allowed domains (config `prd.domains`; default
  `basic` / `pro` / `ai-native` / `infra` / `common`)
- `name` — kebab-case project name (e.g. `onboarding-reminder`)
- `source` — the authoring origin URL (Notion page URL)
- `snapshot-date` — `YYYY-MM-DD` (default: today)
- PRD markdown body — a local file path, or content the caller provides
  inline (write it to a temp file first)

Optional: `--title <피처명>` (frontmatter title — the human feature name; falls
back to `--name` when omitted; the body's first H1 is never used), `--epic
<owner/repo#N>` (link to an existing Epic), `--owner <@handle>`, `--status
<기획|approved|shipped>`.

Also optional — map 1:1 to the PRD-convention frontmatter keys `/sillok-epic`'s
`prd-template.md` validates, so a snapshot written with them filled in passes
Epic validation without a manual frontmatter edit: `--feature-goal <text>`,
`--task-type <Main|Sub>`, `--sprint <text>`,
`--dev-period <YYYY-MM-DD ~ YYYY-MM-DD>`, `--owners <@a,@b,...>`,
`--metric <text>`, `--release-date <YYYY-MM-DD>`,
`--eval-dates "d3: <YYYY-MM-DD>, d7: <YYYY-MM-DD>"`. All are optional — the
snapshot still succeeds without them (blocking validation is `/sillok-epic`'s
job, not this stage's). On update, an omitted field falls back to the
previously-snapshotted value, same as `epic`/`review_at`.

## Step 2: Run the worker

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/prd-snapshot.sh \
  --domain "<domain>" --name "<name>" \
  --source "<source-url>" --snapshot-date "<YYYY-MM-DD>" \
  --body-file "<path-or-->"
```

The script validates domain/name, composes frontmatter (preserving an existing
snapshot's `epic`/`review_at` on update), and upserts via the GitHub Contents
API — committing straight to epicRepo's default branch (no PR; the snapshot is
not a review artifact).

On failure, surface the script's stderr to the user and STOP — do NOT fall
back to `gh api` calls of your own.

## Step 3: Output

Print for the user:

- Permalink (the script's stdout) — commit-pinned `blob/` URL
- Path in epicRepo (`<prd.basePath>/<domain>/<name>/prd.md`)
- Reminder: for Epic creation, run `/sillok-epic <basePath>/<domain>/<name>/prd.md`
  (the epicRepo path) — `sillok:epic`'s `<source>` contract expects an epicRepo
  path / local md / Notion URL, not a blob URL. The permalink is for
  humans/records (e.g. pasting into docs or the Epic body).

## Integration

- `sillok:epic` — consumes the permalink this stage outputs (PRD link in the
  Epic body). This stage does NOT create issues.
- gihoek `prd-creator` — the usual caller: authors the PRD md, uploads it to
  Notion, then invokes this stage with the same md.
