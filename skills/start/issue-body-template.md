# Issue proposal — title, body draft, type

How to compose the issue proposal during PRD intake (`sillok:start` Step 3). Covers both intake branches.

**If `[prd-path]` provided:**

- Read the file with the Read tool.
- From the PRD content, propose:
  - Issue title (verb-form imperative; rewrite noun-phrases per `sillok:gh-issue-management` skill flow 1)
  - Issue body draft (Summary + scope from PRD)
  - Type label suggestion: default `feature`; `bug` if PRD says "fix"/"broken"; `infra` if tooling/CI keywords; `improvement` if "enhance"/"optimize" keywords

**If no PRD path:**

- Prompt user: "Describe the feature in 1–2 sentences. I'll draft the issue from there."
- Use the response to propose title + body + type.
