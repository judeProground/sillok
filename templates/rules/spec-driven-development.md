# Spec-Driven Development

**Spec acceptance-criteria violations are not allowed without explicit user agreement.**

The spec written during `/sillok-design` is the canonical statement of what the implementation must do. If the implementation drifts from the spec — either because a requirement turns out to be infeasible, or because a better idea surfaces during build — surface the proposed deviation and get explicit user agreement before merging. Silent drift is not acceptable.

When the spec and the issue body diverge (e.g., the spec file was edited but the issue body was not re-pasted), the spec file wins. Re-run `/sillok-design` step 8 to re-paste the spec into the issue body.
