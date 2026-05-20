## Pre-review

1. Read the PR title and description for context using `gh pr view {PR_NUMBER}`.
2. If the PR description contains links to other PRs and repos as reference, read those too for more context.
3. Find and read any project context files using glob patterns `**/CLAUDE.md`, `**/AGENTS.md`, `**/CONTRIBUTING*`, and `**/STYLEGUIDE*` (case-insensitive, recursive). Exclude `node_modules/**`, `.git/**`, `dist/**`, and `build/**` — we only want project-level files, not files from third-party dependencies or build artifacts. These contain project-specific context, rules, and best practices the PR should follow. If a context file's substantive content is just a pointer to another file — a lone `@path` import or a single relative-path/markdown link and nothing else (e.g., a `CLAUDE.md` that only says `@AGENTS.md`) — follow it **one hop** and read the referenced in-repo file. Follow only a sole pointer, only one level, only to a file inside the repo; don't chase arbitrary inline links or recurse further. Examples: `CONTRIBUTING.md`, `CONTRIBUTING-COMPONENTS-HOOKS.md`, `STYLEGUIDE.md`, `SSO.STYLEGUIDE.md`.
4. Check for symlinked repositories in the workspace. Use them to verify code examples, API references, and technical details when available. When a claim concerns an API signature, type, parameter, return value, or sync-vs-async behavior, resolve it against symlinked source **before** flagging it or deferring it to the author — prefer source over memory.
5. Read the PR's CI status: `gh pr checks {PR_NUMBER} --json name,state,bucket,link,description,workflow`. Failing or errored checks are ground truth about the change, not a footnote — a red build or a failing test is a finding. Summarize each failure by its check `name`, `description`, and `link` (this JSON has no run id — do not attempt `gh run view <run-id>`; open the `link` only if you need detail and it resolves easily). Handle the other states: checks still **pending/in-progress** are "not yet conclusive" — say so, don't treat them as passing; **skipped/cancelled** checks are not findings on their own. Apply judgment to failures — an obvious infrastructure/flake (runner timeout, network error) should be flagged as "possibly infra/flaky," not asserted as a code bug. If the PR has no checks configured, note that and move on.
6. Check whether the branch is stale against its base. Prefer GitHub's own computation: `gh pr view {PR_NUMBER} --json baseRefName,headRefOid,mergeStateStatus`. A `mergeStateStatus` of `BEHIND` means the head is out of date with the base — raise it as a finding: green checks may have run against an older base, and a sibling change merged since could have invalidated this diff; recommend merging the base in (e.g., `/co-merge`). If `mergeStateStatus` is `UNKNOWN` (GitHub hasn't computed it yet), you may confirm locally — but only when local `HEAD` equals `headRefOid` **and** `origin/<baseRefName>` resolves in this checkout; then `git fetch origin <baseRefName>` and `git rev-list --left-right --count origin/<baseRefName>...HEAD` for the count. For fork PRs `origin` may not track the base — if it doesn't resolve, skip the local check and rely on `mergeStateStatus`.

## Review

The changes already exist locally. Review the diff using `gh pr diff {PR_NUMBER}`, focusing on:

### What to review

1. **Logic and correctness** — Check for bugs, edge cases, technical accuracy, inaccurate comments, syntax errors, and potential issues. Is this the best possible, most long term maintainable way to solve this problem, or are there alternative or simpler solutions that we should consider?
2. **Security** — Flag obvious vulnerabilities in changed code: injection (SQL, command, template), XSS, authz/authn gaps, exposed secrets, unsafe input handling, and unsafe deserialization. Not a full audit — point users at `/security-review` for deeper passes.
3. **Readability** — Is the code clear and maintainable? Does it follow best practices in this repository?
4. **Performance** — Are there obvious performance concerns or optimizations that could be made? Fetches that could be parallelized, loops that could be optimized, etc.
5. **Test coverage** — Does the repository have testing patterns? If so, are there adequate tests for these changes? Skip for documentation-only changes.
6. **Content** — If there are content changes, review code in code blocks as if you're reviewing actual code. Assess content flow, content hierarchy, typos, ambiguity that needs to be clarified, and verbosity that needs to be simplified.
7. **Diagnostics in touched code** — Treat diagnostics, LSP output, and linter warnings in changed files and their direct ripple effects as review findings — unused code, type errors, deprecation warnings, missing dependencies, a11y issues, etc. Scope is the diff and the code it touches; do not audit the whole codebase. Pre-existence is not grounds for dismissal if the finding sits in changed code or its direct ripple.
8. **CI status and staleness** — Treat failing or errored CI checks (from Pre-review) as findings at the severity the failure warrants — a broken build or failing test is a bug, not a nit — unless the failure is clearly infrastructure/flaky, in which case say so rather than asserting a code bug. Surface a `BEHIND`/stale base as its own finding. These are **repo-level findings** with no file/line anchor — report them in the repo-level format (see Output). They are signals you read, not commands you run locally.

### How to review

- Flag uncertainty explicitly rather than asking clarifying questions.
- Don't be overly pedantic. Nitpicks are fine, but only if they are relevant issues within reason.

## Output

- Provide a succinct summary of general code quality.
- Present identified issues in a list with: index (1, 2, etc.), file, line number(s), severity (bug, suggestion, nit), code, issue, and potential solution(s) in the following format:

  1. {issue title}
  File: {relative path to file}
  Line(s): {line numbers}
  Severity: {bug, suggestion, nit}
  Code: {relevant code snippet}
  Issue: {issue summary}
  Solutions: {potential solutions}

  ---

  2. {issue title}
  // and so on...

- Most issues are file-anchored and use the format above. **Repo-level findings** (CI failures, base staleness — anything with no single file/line) use this shape instead:

  1. {issue title}
  Scope: {repository | CI: <check name> | branch}
  Severity: {bug, suggestion, nit}
  Detail: {what's wrong — e.g., failing check name + `link`, or "branch is BEHIND base `main`"}
  Solutions: {potential solutions — e.g., investigate the failing check, run `/co-merge`}

- If no issues are found, briefly state that the code meets best practices.
