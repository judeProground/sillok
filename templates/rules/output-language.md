# Output Language

The single source of truth for the language of **all sillok-generated text** — issue bodies, PR bodies, spec content, commit summaries, key decisions, and any other generated prose.

The `language` config key (`sillok_config language`) controls this. Sillok commands surface the resolved preference in their precompute output's `### Language` section — read it there and apply the contract below.

## Contract

- `auto` (default) → write all generated content in the same language as the current conversation session — if the user is speaking Korean, write Korean; if English, write English.
- `ko` → always write all generated content in Korean.
- `en` → always write all generated content in English.

Structural markers — section headers (`## Summary`, `## Design`, `## Integration branch`, the `Parent:` line, `Closes #N`, etc.), label names, branch names, and GitHub API field names — are **always English** regardless of this setting. Only prose content (descriptions, summaries, acceptance criteria text, key decisions) follows the language preference.

## Korean prose style

When the resolved language is Korean, generated prose (spec, key decisions, summaries) follows this style contract:

- Write complete sentences with explicit subjects and conjugated endings (~한다/~했다) — NOT 개조식 noun-ending fragments ("기각", "필요해짐", "벗어남"). Those read like compressed logs, not explanations.
- Never calque English idioms word-for-word — describe the behavior instead ("graceful degradation" → "실패해도 빈 목록으로 조용히 동작한다", not "우아한 성능 저하").
- Wrap code/API tokens in backticks so Korean particles don't collide with them (`first: 20` 페이지에서 — not "first: 20 페이지에서").
- Key-decision bullets read as full sentences in 결정 → 이유 → 기각한 대안 order.

BAD (real sample):

> Search API(type: qualifier)로 교체, 클라이언트 측 필터링 기각 — 클라이언트 필터링은 first: 20 페이지에 Story/Epic이 없으면 누락되어 페이지네이션이 필요해짐. 단순 버그픽스 범위를 벗어남.

GOOD:

> Story/Epic 조회를 Search API의 `type:` qualifier 기반으로 교체했다. 클라이언트 측 필터링은 첫 `first: 20` 페이지에 Story/Epic이 없으면 결과가 누락되어 페이지네이션이 필요해지는데, 그건 단순 버그픽스의 범위를 벗어나므로 기각했다.
