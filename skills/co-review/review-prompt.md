## Pre-review

1. Read the PR title and description for context using `gh pr view {PR_NUMBER}`.
2. If the PR description contains links to other PRs and repos as reference, read those too for more context.
3. Find and read any project context files using glob patterns `**/CLAUDE.md`, `**/AGENTS.md`, `**/CONTRIBUTING*`, `**/STYLEGUIDE*`, and `**/GUIDELINES*` (case-insensitive, recursive). Exclude `node_modules/**`, `.git/**`, `dist/**`, and `build/**` — we only want project-level files, not files from third-party dependencies or build artifacts. These contain project-specific context, rules, and best practices the PR should follow. If a context file's substantive content is just a pointer to another file — a lone `@path` import or a single relative-path/markdown link and nothing else (e.g., a `CLAUDE.md` that only says `@AGENTS.md`) — follow it **one hop** and read the referenced in-repo file. Follow only a sole pointer, only one level, only to a file inside the repo; don't chase arbitrary inline links or recurse further. Examples: `CONTRIBUTING.md`, `CONTRIBUTING-COMPONENTS-HOOKS.md`, `STYLEGUIDE.md`, `SSO.STYLEGUIDE.md`, `GUIDELINES.md`.

   **Then resolve the guidance that governs the changed files specifically.** Repo-root context files miss rulebooks that live next to the content they govern — a `GUIDELINES.md` beside `changelog/` posts, a `README` in a content directory, a nested `STYLEGUIDE`. For each path this PR changes, walk from its directory up to the repo root and read any such guidance you find along the way; the nearest one governs that file. This is the file a repo-root-only scan overlooks — and the reason an off-house-style change can pass review while its own rulebook sits one directory away.
4. **Map the authoritative sources this PR's claims depend on** — treat this as a pre-review deliverable, not an afterthought. A claim about an API signature, type, parameter, return value, sync-vs-async behavior, or other objective detail is settled by source, not memory. Enumerate the sources the diff leans on (upstream/sibling repos, dependency package sources, vendored code, API/spec definitions, generated artifacts) and note which are reachable in the workspace versus missing. Sources may be reachable via symlink, local clone, or installed package — don't assume symlinks are the only mechanism. Resolve objective claims against reachable source **before** flagging them or deferring them to the author. For a source that is missing but would settle a real claim, ask the user to make it available rather than guessing or punting to the author. For a **docs** change, the authoritative sources include **sibling documentation pages** — a page in the same repo documenting the behavior the changed page describes is a source to reconcile against, not off-limits archaeology.
5. Read the PR's CI status: `gh pr checks {PR_NUMBER} --json name,state,bucket,link,description,workflow`. Failing or errored checks are ground truth about the change, not a footnote — a red build or a failing test is a finding. Summarize each failure by its check `name`, `description`, and `link` (this JSON has no run id — do not attempt `gh run view <run-id>`; open the `link` only if you need detail and it resolves easily). Handle the other states: checks still **pending/in-progress** are "not yet conclusive" — say so, don't treat them as passing; **skipped/cancelled** checks are not findings on their own. Apply judgment to failures — an obvious infrastructure/flake (runner timeout, network error) should be flagged as "possibly infra/flaky," not asserted as a code bug. Note that `gh pr checks` exits **non-zero in normal situations** — exit 1 when no checks are reported, exit 8 when checks are still pending — so capture its output and interpret by exit code/message rather than treating any non-zero exit as a command failure that aborts the review. If the PR has no checks configured, note that and move on. On a fork PR, "no checks reported" is often the platform, not the project: workflow runs on a first-time contributor's PR wait for maintainer approval — note it as expected setup, not a finding.
6. **Fetch existing PR threads, including bot reviewers.** Pull both comment streams, paginated: inline review comments (`gh api --paginate repos/{owner}/{repo}/pulls/{PR_NUMBER}/comments`) and top-level issue comments (`gh api --paginate repos/{owner}/{repo}/issues/{PR_NUMBER}/comments`). Group inline comments into threads by `in_reply_to_id`. Identify **bot reviewers** — authors with `user.type == "Bot"` raising code concerns (CodeRabbit, Cursor's Bugbot, the ChatGPT/Codex connector, Macroscope, and the like); ignore non-review bot noise (deploy previews, coverage summaries, changelog bots). A bot finding with no human reply yet is a **candidate finding — evaluate it on merits during the review, never accept it blindly**. Human-authored threads are context, not candidates.

   **The two streams are separate id spaces, and only inline comments are repliable.** Record each candidate as its stream plus id — an inline thread root (repliable) or a top-level issue comment (no reply thread; it gets answered PR-wide). Carry `updated_at` alongside `created_at`: bots like CodeRabbit revise a summary comment in place instead of posting a new one, so a later pass has to compare both.
7. Check whether the branch is stale against its base. Prefer GitHub's own computation: `gh pr view {PR_NUMBER} --json baseRefName,headRefOid,mergeStateStatus`. A `mergeStateStatus` of `BEHIND` means the head is out of date with the base — raise it as a finding: green checks may have run against an older base, and a sibling change merged since could have invalidated this diff; recommend merging the base in (e.g., `/co-merge`). If `mergeStateStatus` is `UNKNOWN` (GitHub hasn't computed it yet), you may confirm locally — but only when local `HEAD` equals `headRefOid` **and** `origin/<baseRefName>` resolves in this checkout; then `git fetch origin <baseRefName>` and `git rev-list --left-right --count origin/<baseRefName>...HEAD` for the count. For fork PRs `origin` may not track the base — if it doesn't resolve, skip the local check and rely on `mergeStateStatus`.

## Review

The changes already exist locally. Review the diff using `gh pr diff {PR_NUMBER}`, focusing on:

### What to review

1. **Logic and correctness** — Check for bugs, edge cases, technical accuracy, inaccurate comments, syntax errors, and potential issues. Is this the best possible, most long term maintainable way to solve this problem, or are there alternative or simpler solutions that we should consider?
2. **Security** — Flag obvious vulnerabilities in changed code: injection (SQL, command, template), XSS, authz/authn gaps, exposed secrets, unsafe input handling, and unsafe deserialization. Not a full audit — point users at `/security-review` for deeper passes.
3. **Readability & reuse** — Is the code clear and maintainable? Does it follow best practices in this repository? Does new code duplicate an obvious or readily discoverable existing utility, component, or helper instead of reusing it? Stay within the diff and its immediate neighborhood — no whole-codebase archaeology.
4. **Performance & efficiency** — Obvious performance concerns or optimizations in changed code: fetches that could be parallelized, loops that could be optimized, redundant or repeated work that could be hoisted or batched. Includes **query efficiency** (N+1, over-fetching, missing bulk operations in changed data access) and **caching opportunities** (new code that should use an existing cache or memoize an expensive computation).
5. **Test coverage** — Does the repository have testing patterns? If so, are there adequate tests for these changes? Skip for documentation-only changes.
6. **Content** — If there are content changes, review code in code blocks as if you're reviewing actual code. Assess content flow, content hierarchy, typos, ambiguity that needs to be clarified, and verbosity that needs to be simplified. For **repo prose** — changelog, blog, docs, marketing copy, release notes — also check it against the guidance that governs it: the nearest local rulebook found in Pre-review (a `GUIDELINES.md`, `STYLEGUIDE.md`, or the like), and, if it exists, the author's voice guide at `~/.claude/skills/co-write/voice.md` (apply the matching medium overlay). Flag voice and tone problems, not just mechanics: passive openers ("A new X has been introduced"), filler and superlatives, market-y abstraction, canned closers ("Stay tuned"), and gerund/passive phrasing where the guidance calls for active voice. Voice is a first-class content finding, not a nitpick.

   **Reconcile capability and absolute claims across sibling docs.** A docs claim's authority often lives on another page — the one documenting the behavior the changed page asserts. When changed prose states a capability ("a user needs X to Y") or an absolute (*only / always / never / must / can't / the only way*), don't settle it against the local page alone: find the sibling doc describing that behavior and reconcile against it, same as any authoritative source (per Pre-review's source-mapping step). Absolutes are the highest-risk phrasing — they read as true in isolation and are the ones most often falsified by an edge case documented elsewhere — so scan changed prose for them specifically and verify each against source, code or sibling doc, before it passes.

   **When the governing rulebook enumerates specific terms — proper nouns to capitalize, banned words, required spellings — treat it as a mechanical sweep, not a judgment call.** Grep the *entire* diff for those terms and verify every occurrence, including the strings prose review glosses: headings, frontmatter `title`/`description`, nav/manifest entries, table cells, link anchor text, and image alt text. A term applied correctly in body copy is routinely wrong in a heading or nav entry *in the same file* — that split (right in paragraphs, wrong in titles) is the signature of this miss, and eyeballing the prose won't catch it. If the rule is stable enough to enumerate, note whether the repo enforces it statically (a linter/CI check); an unenforced terminology rule that keeps generating follow-up PRs is itself a finding — recommend codifying it.
7. **Diagnostics in touched code** — Treat diagnostics, LSP output, and linter warnings in changed files and their direct ripple effects as review findings — unused code, type errors, deprecation warnings, missing dependencies, a11y issues, etc. Scope is the diff and the code it touches; do not audit the whole codebase. Pre-existence is not grounds for dismissal if the finding sits in changed code or its direct ripple.
8. **CI status and staleness** — Treat failing or errored CI checks (from Pre-review) as findings at the severity the failure warrants — a broken build or failing test is a bug, not a nit — unless the failure is clearly infrastructure/flaky, in which case say so rather than asserting a code bug. Surface a `BEHIND`/stale base as its own finding. These are **repo-level findings** with no file/line anchor — report them in the repo-level format (see Output). They are signals you read, not commands you run locally.
9. **Error handling & resilience** — In changed code, flag unhandled failure paths, missing timeouts/retries on network or IO calls, swallowed errors, and missing graceful degradation. Suggestion-level unless an unhandled path is an outright bug.
10. **Framework features** — Does the changed code re-implement a verified framework or platform feature (data fetching, routing, caching, validation, etc.)? Point at the built-in — confirm it exists rather than assuming. Suggestion-level, scoped to the diff.
11. **Accessibility** — For UI changes, a quick UI-specific pass for a11y gaps not already surfaced by diagnostics (item 7): missing labels/alt text, non-semantic interactive elements, keyboard traps, insufficient contrast. Web/UI only; skip for non-UI diffs. Complements item 7 rather than creating a second home for the same finding.
12. **Bot reviewer threads** — Give every candidate bot finding (from Pre-review) a verdict: worth addressing, or skipped with a reason. Judge each like your own finding — is it a real improvement here, or overkill/noise? Don't duplicate: if your review independently surfaces an issue a bot already flagged, report it once as that bot thread's verdict rather than a second finding on the same line.

### How to review

- Flag uncertainty about **intent or scope** explicitly rather than asking the author to explain it.
- Uncertainty about an **objective fact** (type name, signature, endpoint, parameter, return value, behavior) is not a finding yet — resolve it against an authoritative source first. If the source that would settle it isn't reachable in the workspace, ask the user to make it available before downgrading the item to "needs author input."
- Don't be overly pedantic. Nitpicks are fine, but only if they are relevant issues within reason.
- Improvement-oriented findings (caching, query efficiency, error handling, framework features, duplication, accessibility) are usually `suggestion` or `nit`, not `bug` — raise them when they're clearly worth the change and let the author decide. Apply the same overkill filter: skip churn that isn't worth it.

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

- A finding that confirms a bot reviewer's comment adds one field to the standard format, naming the stream so posting routes it correctly. For an inline thread root:

  Bot thread: {bot login}, review comment id {id}

  For a PR-wide summary, which has no reply thread:

  Bot top-level: {bot login}, issue comment id {id}

- Close with a **Skipped bot comments** list using those same two shapes, each followed by `: {one-line skip reason}`, so every triaged bot comment carries a verdict. Omit the list when there are no bot comments.
- If no issues are found, briefly state that the code meets best practices.
