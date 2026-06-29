You are auditing a project for improvement opportunities. The goal is not "is this change correct?" (that is review) but "where can this project get faster, simpler, safer, and more consistent?"

Scope: {SCOPE}
Focus: {FOCUS}

## Pre-audit

1. Find and read project context files using glob patterns `**/CLAUDE.md`, `**/AGENTS.md`, `**/CONTRIBUTING*`, and `**/STYLEGUIDE*` (case-insensitive, recursive). Exclude `node_modules/**`, `.git/**`, `dist/**`, and `build/**` — only project-level files, not dependencies or build artifacts. These carry project-specific rules and best practices the audit must respect. If a context file's substantive content is just a pointer to another in-repo file (a lone `@path` import or a single relative link and nothing else), follow it one hop and read that file.
2. Detect the project type and stack: web/frontend, HTTP API, CLI, or library — plus the language, framework, hosting/deploy platform, and package manager. Read the manifest (`package.json` etc.), framework config, and entry points. The detected type decides which adaptive dimensions apply (below). A project can be more than one type (e.g. a web app that also exposes an API) — apply all that fit.
3. Confine the audit to {SCOPE}. If it is a path, only report findings under it (you may read outside it for context). If it is the whole project, audit broadly but prioritize ruthlessly — breadth is not licence to list everything.
4. Apply {FOCUS}. If a dimension focus is set, weight the audit toward it and lead with its findings, but still surface glaring issues in other dimensions. If there is no focus, run every applicable dimension.

## Dimensions

### Core (always)

1. **Performance & efficiency** — slow paths, serial work that could run in parallel, redundant or repeated work that could be hoisted or batched, missing bulk operations.
2. **Caching** — missing caches, suboptimal TTLs or cache keys, missed memoization, missing or incorrect revalidation.
3. **Data & queries** — N+1 queries, over-fetching, missing indexes, inefficient access patterns, queries that could be batched or narrowed.
4. **Security** — vulnerabilities and gaps: injection (SQL, command, template), XSS, authz/authn holes, exposed secrets, unsafe input handling or deserialization. This is a breadth pass, not a deep audit — recommend `/security-review` for depth.
5. **Error handling & resilience** — unhandled failure paths, missing timeouts/retries/backoff, no graceful degradation, swallowed or over-broad error handling.
6. **Consistency** — divergent patterns, naming, structure, and conventions that should be unified.
7. **Duplication & abstraction** — repeated logic that should be extracted or componentized — without over-abstracting (do not trade duplication for the wrong abstraction).
8. **Simplicity & maintainability** — simpler equivalents, dead code, needless complexity, code that is hard to change.
9. **Best practices & correctness** — language or framework idioms used incorrectly, footguns, deprecated APIs.
10. **Testing & types** — critical paths without tests, weak type safety, places where stricter types or a test would prevent real bugs. Respect the repo's existing testing posture — do not demand tests where the project has none by design.
11. **Dependencies & build** — outdated or vulnerable dependencies, unused dependencies, oversized bundles, build or config improvements. Verify version and vulnerability claims against the lockfile, `npm audit` / `npm outdated` (or the ecosystem equivalent), or official package metadata — do not assert a version or CVE from memory. If you cannot verify, mark it unverifiable rather than guessing.
12. **Documentation & content** — user-facing content that could be clearer or more concise without losing meaning; README or inline docs that are missing, stale, or wrong.

### Adaptive (apply by detected project type)

- **Web/frontend** — underused framework features (the framework's own data-fetching, routing, caching, or rendering primitives), underused hosting/platform features, asset and bundle optimization (code-splitting, image and font handling), accessibility, SEO/metadata, Core Web Vitals.
- **API** — versioning, pagination, consistent error shapes and status codes, rate limiting, idempotency, observability (logging, metrics, tracing).
- **CLI** — ergonomics: help text, flag and argument consistency, exit codes, machine-readable output options, sensible defaults.
- **Library** — public API design, semver discipline, tree-shakeability, exported types, usage examples and docs.

## How to audit

- **Prioritize by impact × effort.** A high-impact, low-effort fix outranks a low-impact, high-effort one. Lead with what matters.
- **Reject overkill.** Premature abstraction, churn for its own sake, and pedantry are not findings. An "improvement" that is not worth the change is noise — leave it out.
- **Respect the existing architecture.** Do not propose a rewrite disguised as an improvement unless the finding is specifically that the architecture is the problem — and then say so plainly.
- **Verify objective claims against source.** "The framework already provides X", "this API supports Y" — confirm against the framework or library source or docs, not memory. If you cannot verify, say so rather than asserting.
- **Anchor findings.** Use `file:line` where a finding has a location. Cross-cutting findings (dependencies, build, project-wide consistency) have no single anchor — mark them repo-level.
- **Stay in scope.** Report only findings within {SCOPE}.

## Output

Give a one-paragraph summary of overall project health, then a list of findings. For each:

  N. {title}
  Dimension: {which dimension}
  Location: {file:line(s) | repo-level}
  Impact: {high | med | low}
  Effort: {S | M | L}
  Issue: {what is suboptimal and why it matters}
  Fix: {the suggested change}

  ---

Rank findings high-impact first; break ties by lower effort. Omit dimensions where you found nothing material — do not pad the list to look thorough. If the project is in good shape on a dimension, say so briefly in the summary instead.
