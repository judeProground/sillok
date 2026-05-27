# Plan: Remove legacy stage label references

**Spec:** `docs/superpowers/specs/2026-05-27-remove-legacy-stage-label-references.md`
**Issue:** #22

## Tasks

- [x] **Task 1: Migrate self-hosting config to v2 shape**
  - File: `.claude/sillok/workflow.config.json`
  - Remove `labels.types`, `labels.stages`, `labels.defaults.type`, `labels.defaults.stage`
  - Add `project`, `types`, `labels.natures` sections (match `templates/workflow.config.json`)

- [x] **Task 2: Update sillok-workflow.md rule template**
  - File: `templates/rules/sillok-workflow.md`
  - Lines 9-11: `label X→Y` → `status X→Y` (project status names)
  - Line 15: stage labels sentence → project status sentence
  - Line 52: `Don't manually flip stage labels` → `Don't manually change project status`

- [x] **Task 3: Update precompute script comments**
  - `scripts/precompute-design.sh` line 4: `current stage label` → `project status`
  - `scripts/precompute-execute.sh` line 3: `stage` → `project status`
  - `scripts/precompute-end.sh` line 3: `stage` → `project status`

- [x] **Task 4: Update command description comments**
  - `commands/sillok-execute.md` lines 9, 21: `stage` → `project status`
  - `commands/sillok-design.md` line 21: `stage` → `project status`; line 48: remove `designed` label example; line 63: `stage` → `status`; line 97: remove historical migration note
  - `commands/sillok-end.md` line 9: `stage` → `project status`

- [x] **Task 5: Run tests + verify no remaining legacy references**
  - Run full test suite
  - Grep for stray `stage label` / `todo→designed` / `designed→in-progress` / `in-progress→in-review` in non-doc files
