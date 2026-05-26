# Org/User Repo Detection with Label Fallback — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Detect org vs user repo at init time, store `orgMode` in config, and branch helper functions so Issue Types + createLinkedBranch are only used on org repos (user repos fall back to labels + skip linked branches).

**Architecture:** Single boolean `orgMode` in config, read by helper functions at runtime. Commands get minimal changes (issue creation REST calls branch on orgMode for type vs label). Everything else stays in the helper layer.

**Tech Stack:** Bash 3.2, `gh` CLI, `jq`. No new deps.

**Working directory:** `/Users/jihoopark/sillok/.worktrees/17-add-org-user-repo-detection-with-label`

**Spec:** `docs/superpowers/specs/2026-05-26-add-org-user-repo-detection-with-label.md`

---

### Task 1: Schema + template — add `orgMode` field

**Files:**
- Modify: `schema/v1.json`
- Modify: `templates/workflow.config.json`

- [ ] **Step 1: Add `orgMode` to schema**

In `schema/v1.json`, after the `"prdRepo"` property, add:

```json
"orgMode": {
  "type": "boolean",
  "default": false,
  "description": "Auto-detected by /sillok-init. true = org repo (Issue Types + linked branches). false = user repo (label fallback)."
},
```

- [ ] **Step 2: Add `orgMode` to template**

In `templates/workflow.config.json`, after `"prdRepo": "",` add:

```json
"orgMode": false,
```

- [ ] **Step 3: Validate JSON**

```bash
jq empty schema/v1.json && jq empty templates/workflow.config.json && echo "OK"
```

Expected: `OK`

- [ ] **Step 4: Commit**

```bash
git add schema/v1.json templates/workflow.config.json
git commit -m "feat(schema): add orgMode boolean for org/user detection (#17)"
```

---

### Task 2: `scripts/lib/issue-types.sh` — orgMode branching

**Files:**
- Modify: `scripts/lib/issue-types.sh`

- [ ] **Step 1: Add orgMode guard to `sillok_issue_type_id`**

At the top of the function body (after `local name="$1"`), insert:

```bash
  local org_mode
  org_mode=$(sillok_config orgMode)
  if [[ "$org_mode" != "true" ]]; then
    # User repo: Issue Types not available
    echo ""
    return 0
  fi
```

- [ ] **Step 2: Replace `sillok_issue_type_set` with orgMode-aware version**

Replace the entire `sillok_issue_type_set` function (lines 61-70) with:

```bash
# Apply an Issue Type to an existing issue.
# Org mode: sets via REST type field.
# User mode: falls back to adding a lowercase label.
sillok_issue_type_set() {
  local repo="$1"
  local issue_n="$2"
  local type_name="$3"

  local org_mode
  org_mode=$(sillok_config orgMode)

  if [[ "$org_mode" == "true" ]]; then
    gh api -X PATCH \
      -H "X-GitHub-Api-Version: 2026-03-10" \
      "/repos/$repo/issues/$issue_n" \
      -f "type=$type_name" >/dev/null
  else
    # User repo: Issue Types not available. Fall back to label.
    local label
    label=$(printf '%s' "$type_name" | tr '[:upper:]' '[:lower:]')
    gh issue edit "$issue_n" --repo "$repo" --add-label "$label" 2>/dev/null || true
  fi
}
```

- [ ] **Step 3: Verify function existence test still passes**

```bash
bash tests/issue-types.test.sh
```

Expected: `OK: required functions exist`

- [ ] **Step 4: Commit**

```bash
git add scripts/lib/issue-types.sh
git commit -m "feat(issue-types): orgMode branching — type API or label fallback (#17)"
```

---

### Task 3: `scripts/lib/dev-link.sh` — skip in user mode

**Files:**
- Modify: `scripts/lib/dev-link.sh`

- [ ] **Step 1: Add orgMode guard to `sillok_link_branch`**

At the very top of `sillok_link_branch` function body (line 40, after `local issue_id="$1"`), insert BEFORE the existing local declarations:

```bash
  local org_mode
  org_mode=$(sillok_config orgMode)
  if [[ "$org_mode" != "true" ]]; then
    # User repo: createLinkedBranch not available. Skip.
    # PRs will still auto-link via Closes #N.
    return 0
  fi
```

- [ ] **Step 2: Verify function existence test still passes**

```bash
bash tests/dev-link.test.sh
```

Expected: `OK: required functions exist`

- [ ] **Step 3: Commit**

```bash
git add scripts/lib/dev-link.sh
git commit -m "feat(dev-link): skip createLinkedBranch when orgMode=false (#17)"
```

---

### Task 4: `scripts/bootstrap-labels.sh` — type labels in user mode

**Files:**
- Modify: `scripts/bootstrap-labels.sh`

- [ ] **Step 1: Read orgMode from config and conditionally bootstrap type labels**

After the Priorities section (after `create p4 ...`) and before the Areas section (`# Areas`), insert:

```bash
# Type labels — only for user-mode repos (org repos use Issue Types instead)
SCRIPT_DIR_BL=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=lib/config.sh
source "$SCRIPT_DIR_BL/lib/config.sh" 2>/dev/null || true
ORG_MODE=$(sillok_config orgMode 2>/dev/null || echo "false")
if [[ "$ORG_MODE" != "true" ]]; then
  echo "  Type labels (user-repo fallback)..."
  create feature  0e8a16 "New user-facing functionality"
  create story    8B5CF6 "In-repo composite with integration branch"
  create bug      d73a4a "Broken behavior"
  create task     666666 "Generic work unit"
fi
```

Note: the script doesn't currently source `config.sh` (it takes `--config` flag for areas only). The defensive `source ... || true` ensures no breakage if config isn't available (e.g., running standalone without a project config — falls through to `ORG_MODE=false` which is the safe default: create type labels).

- [ ] **Step 2: Parse check**

```bash
bash -n scripts/bootstrap-labels.sh && echo "OK"
```

Expected: `OK`

- [ ] **Step 3: Commit**

```bash
git add scripts/bootstrap-labels.sh
git commit -m "feat(bootstrap): type labels when orgMode=false (#17)"
```

---

### Task 5: `commands/sillok-init.md` — org detection + conditional skip

**Files:**
- Modify: `commands/sillok-init.md`

- [ ] **Step 1: Read the current file**

`cat commands/sillok-init.md` — identify exact line numbers for Step 2, Step 2b, Step 6 jq block, Step 11 summary.

- [ ] **Step 2: Insert Step 2a (org detection) after Step 2**

Find where Step 2 (Detect repo and base branch) ends. Insert:

```markdown
## Step 2a: Detect org mode

\`\`\`bash
OWNER_TYPE=$(gh api "/repos/$REPO" --jq '.owner.type' 2>/dev/null || echo "User")
if [[ "$OWNER_TYPE" == "Organization" ]]; then
  ORG_MODE=true
else
  ORG_MODE=false
  echo "[sillok-init] ⚠️  User-owned repo detected. Issue Types and linked branches unavailable — using label fallback mode."
fi
\`\`\`
```

Also add `ORG_MODE=false` to the Step 1 status-variable initialization block (alongside `CONFIG_STATUS=fail`, etc.).

- [ ] **Step 3: Update Step 2b (Verify org Issue Types) — skip when user mode**

At the very start of Step 2b, add:

```markdown
If `$ORG_MODE` is `false`, skip this step entirely (Issue Types are org-only):

\`\`\`bash
if [[ "$ORG_MODE" != "true" ]]; then
  TYPES_STATUS=skip-user-repo
else
  # ... existing type verification code ...
fi
\`\`\`
```

Wrap the existing verification logic inside the `else` branch.

- [ ] **Step 4: Update Step 6 (Write workflow.config.json) — include orgMode**

In the `jq -n` invocation, add `--argjson orgMode "$ORG_MODE"` to the args, and `"orgMode": $orgMode,` after `"prdRepo": "",` in the JSON template.

- [ ] **Step 5: Update Step 11 (Print summary)**

Add a line to the summary:

```
- Org mode: <ORG_MODE> (<OWNER_TYPE>)                     [detected]
```

Add `skip-user-repo` to the `TYPES_STATUS` mapping in the Area-label sub-summary table (or similar): `skip-user-repo → "📋 User-owned repo — Issue Types skipped (using label fallback)."`.

Update headline calculation: `TYPES_STATUS=skip-user-repo` is NOT a warning — it's informational. Do NOT trigger ⚠️ for this.

- [ ] **Step 6: Commit**

```bash
git add commands/sillok-init.md
git commit -m "feat(sillok-init): detect orgMode + conditional type verification (#17)"
```

---

### Task 6: `commands/sillok-start.md` — issue creation REST branching

**Files:**
- Modify: `commands/sillok-start.md`

- [ ] **Step 1: Find Step 7 (Create the issue)**

Locate the REST `gh api -X POST` block.

- [ ] **Step 2: Add orgMode branching for type vs label**

Replace the issue creation block with an if/else that reads orgMode:

```markdown
Read orgMode from config (`sillok_config orgMode`). Branch the REST call:

**Org mode (`orgMode=true`):**

\`\`\`bash
issue_url=$(gh api -X POST \
  -H "X-GitHub-Api-Version: 2026-03-10" \
  "/repos/$REPO/issues" \
  -f title="<title>" \
  -f body="<body>" \
  -f type="<Issue-Type-name>" \
  -f "assignees[]=$(gh api user --jq .login)" \
  -f "labels[]=<priority>" \
  --jq '.html_url')
\`\`\`

**User mode (`orgMode=false`):**

\`\`\`bash
issue_url=$(gh api -X POST \
  -H "X-GitHub-Api-Version: 2026-03-10" \
  "/repos/$REPO/issues" \
  -f title="<title>" \
  -f body="<body>" \
  -f "assignees[]=$(gh api user --jq .login)" \
  -f "labels[]=<priority>" \
  -f "labels[]=<type-lowercased>" \
  --jq '.html_url')
\`\`\`

(Difference: org mode has `-f type=X`, user mode has `-f labels[]=x` instead.)
```

- [ ] **Step 3: Commit**

```bash
git add commands/sillok-start.md
git commit -m "feat(sillok-start): orgMode branch for issue creation (#17)"
```

---

### Task 7: `commands/sillok-story.md` — same branching

**Files:**
- Modify: `commands/sillok-story.md`

- [ ] **Step 1: Find the issue creation block in §2 (Standalone story creation)**

Locate the `gh api -X POST` block that creates the story issue.

- [ ] **Step 2: Apply the same orgMode branching as Task 6**

Same pattern: org mode uses `-f type=Story`, user mode uses `-f labels[]=story` instead.

- [ ] **Step 3: Commit**

```bash
git add commands/sillok-story.md
git commit -m "feat(sillok-story): orgMode branch for issue creation (#17)"
```

---

### Task 8: Tests + verification

**Files:**
- Modify: `tests/issue-types.test.sh` (add orgMode-aware test)
- No new test files needed

- [ ] **Step 1: Run full test suite**

```bash
for t in tests/*.test.sh; do echo "=== $(basename $t) ==="; bash "$t" 2>&1 | tail -2; done
```

All 11 tests must pass (the function-existence tests still work since we only changed function internals, not signatures).

- [ ] **Step 2: Verify orgMode field present in schema + template**

```bash
jq '.properties.orgMode.type' schema/v1.json          # "boolean"
jq '.orgMode' templates/workflow.config.json            # false
```

- [ ] **Step 3: Verify orgMode branching exists in helpers**

```bash
grep -c "org_mode\|orgMode" scripts/lib/issue-types.sh scripts/lib/dev-link.sh scripts/bootstrap-labels.sh
```

Each file should show at least 1 match.

- [ ] **Step 4: Parse check all modified bash scripts**

```bash
bash -n scripts/lib/issue-types.sh && echo "issue-types OK"
bash -n scripts/lib/dev-link.sh && echo "dev-link OK"
bash -n scripts/bootstrap-labels.sh && echo "bootstrap OK"
```

All should print OK.

- [ ] **Step 5: Commit (if any test fixes needed)**

```bash
git add tests/
git commit -m "test: verify orgMode fallback (#17)"
```

(Skip if no changes needed.)

---

## Self-Review

**Spec coverage:**
- ✅ Detection at init (Task 5)
- ✅ Config storage (Task 1)
- ✅ `sillok_issue_type_set` branching (Task 2)
- ✅ `sillok_issue_type_id` guard (Task 2)
- ✅ `sillok_link_branch` skip (Task 3)
- ✅ `bootstrap-labels.sh` type labels in user mode (Task 4)
- ✅ `sillok-init.md` type verification skip (Task 5)
- ✅ `sillok-start.md` REST branching (Task 6)
- ✅ `sillok-story.md` REST branching (Task 7)
- ✅ Tests (Task 8)

**Placeholder scan:** No TBDs found.

**Type consistency:** `orgMode` (config key) and `org_mode` (bash local) used consistently.

---

## Execution Handoff

Plan complete and saved to `docs/superpowers/plans/2026-05-26-add-org-user-repo-detection-with-label.md`.

**Locked execution mode: Subagent-Driven** (per `/sillok-execute` Step 4).
