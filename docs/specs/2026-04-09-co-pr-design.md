# co-pr Skill Design Spec

## Overview

A Claude Code skill (`/co-pr`) that creates or updates GitHub pull requests. Handles the full lifecycle from staging changes through posting a well-written PR description, with separate modes for creating ready PRs, creating drafts, and updating existing PRs when their description has drifted.

Third skill in the `co-` prefix collection, alongside `/co-plan` and `/co-review`.

## Scope

- **In scope:** Staging, linting, formatting, committing, pushing, PR title/description generation, PR template detection, create/update mode handling, symlink exclusion
- **Out of scope:** Automated testing strategy (runs existing test scripts only), merge decisions, approval, review flow (`/co-fix` handles that)
- **Language scope:** Currently targets JavaScript/TypeScript repositories (detection via `package.json`). Other language ecosystems (Python, Go, Rust, etc.) are out of scope for now and can be added later if needed.

## Skill Identity

```yaml
name: co-pr
description: Use when creating or updating a GitHub pull request
```

- **Installed to:** `~/.claude/skills/co-pr/SKILL.md` (Claude-only)
- **Triggers:**
  - `/co-pr` — create a ready-for-review PR (default)
  - `/co-pr draft` — create a draft PR
  - `/co-pr update` — update the title/description of an existing PR on the current branch

## Architecture

Single-file skill (`SKILL.md`). All three modes (create, draft, update) are handled inline. The default PR template structure and verification logic are kept inline rather than extracted — small enough that separation is premature abstraction.

## File Structure

```
enshrined-flavor/
  skills/
    co-pr/
      SKILL.md
  docs/
    specs/
      2026-04-09-co-pr-design.md
  README.md
```

Installation: symlink `skills/co-pr/` to `~/.claude/skills/co-pr/`.

## Create Mode Flow (`/co-pr` and `/co-pr draft`)

### Step 1 — Precondition check

Run `gh pr view --json number` on the current branch. If a PR exists, error with:
> A PR already exists for this branch. Use `/co-pr update` to update it.

### Step 2 — Stage and filter

Run `git status` to see all changes. Stage everything **except symlinks**.

Symlinks are a hard rule — the user uses them for cross-repo verification (e.g., symlinking `clerk/javascript` into `clerk-docs` worktree) and they must never be committed.

### Step 3 — Run lint and format

Detect available tools from `package.json` scripts and dependencies. Do not assume specific tools (Biome, Oxlint, ESLint, Prettier, dprint, etc. all vary by repo). Run what exists — typically `pnpm lint --fix` and `pnpm format` or equivalents.

If checks fail and Claude can't auto-fix, stop and tell the user.

**Re-stage after autofixes.** Formatters modify files on disk. After running lint/format, re-run `git add` on the affected files so the autofixes are included in the commit.

### Step 4 — Run tests (judgment-based)

Use Claude's judgment based on the scope of the change:
- Small tweaks (CSS, docs, config): skip tests
- Big changes (logic, refactors, new code): run tests/typechecks

Detect test scripts from `package.json` (e.g., `pnpm test`, `pnpm typecheck`). `pnpm test` often includes lint + typecheck + unit tests as a bundle in modern setups — useful as a single command when available.

### Step 5 — Commit

Detect the repo's commit message style from recent `git log --oneline -20`. Write a commit message matching that style. Include the co-author trailer:

```
Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>
```

### Step 6 — Push

Detect the push remote from the branch's upstream if set, otherwise default to `origin`:

```bash
# Try to use the existing upstream
UPSTREAM=$(git rev-parse --abbrev-ref --symbolic-full-name @{upstream} 2>/dev/null)
if [ -n "$UPSTREAM" ]; then
  git push
else
  git push -u origin {branch}
fi
```

If push fails, tell the user the error and stop.

### Step 7 — Write the PR description

Detect the repo's PR template using `gh repo view --json pullRequestTemplates` (GitHub serves templates from the default branch, which may differ from the current worktree). If a template is returned, follow its format.

As a fallback, check common local locations: `.github/pull_request_template.md`, `.github/PULL_REQUEST_TEMPLATE.md`, `./pull_request_template.md`, `./PULL_REQUEST_TEMPLATE.md`, `docs/pull_request_template.md`, `docs/PULL_REQUEST_TEMPLATE.md`, or any `.md` files under `.github/PULL_REQUEST_TEMPLATE/`.

If no template is found, use the default structure:

- **Summary** — one or two sentences on why the change was needed
- **Changes** — bullet list of what was done
- **Not Planned** — anything intentionally skipped or out of scope (only if relevant)
- **References** — substantive links: related PRs/issues, Linear tickets, Slack threads, research articles, documentation (only if relevant)

The References section should be Claude's judgment call on what was substantive vs. tangential. Skip "random blog post we glanced at" type references.

### Step 8 — Detect PR title style

Run `gh pr list --state all --limit 10` to see recent PR titles. Match the convention (prefix patterns, conventional commits, ticket IDs, etc.).

### Step 9 — Create the PR

Use `gh pr create` with `--draft` if `/co-pr draft` was invoked, otherwise without the draft flag. Pass the title with `--title` and the body via stdin using `--body-file -`:

```bash
gh pr create --title "..." --body-file - <<'CO_PR_BODY'
[PR BODY CONTENT]
CO_PR_BODY
```

**Always use `--body-file -` with heredoc, never `--body "..."`.** Inline `--body` breaks on multi-line Markdown, quotes, backticks, code fences, and callouts.

### Step 10 — Output

Print the PR URL. No summary, no preamble — just the URL.

## Update Mode Flow (`/co-pr update`)

### Step 1 — Precondition check

Run `gh pr view --json number,title,body,state` on the current branch. Distinguish these cases:

- **No PR found** → error: "No PR exists for this branch. Use `/co-pr` to create one."
- **PR exists and is `OPEN`** → proceed to Step 2.
- **PR exists but is `CLOSED` or `MERGED`** → error: "The PR on this branch is `{state}`. Updates only apply to open PRs."
- **`gh` command fails (auth, remote, network)** → surface the actual error and stop. Don't silently assume "no PR."

### Step 2 — Handle uncommitted changes

If there are uncommitted changes, follow the same staging/linting/testing/committing/pushing flow as create mode (Steps 2-6). If there are no uncommitted changes, skip to Step 3.

### Step 3 — Read existing PR

Use `gh pr view` to fetch the current title and body. Identify user-added elements that must be preserved using heuristics (no provenance markers):

- **Structural sections** — named sections that look like user-managed areas: "Other references", "Preview(s)", "Screenshots", "Testing notes", etc.
- **Callouts** at the top of the description: `[!NOTE]`, `[!WARNING]`, `[!TIP]`, `[!IMPORTANT]`, `[!CAUTION]`
- **Images** — Markdown image syntax or HTML `<img>` tags
- **External links** that reference specific deployments, tickets, or resources (Vercel preview URLs, Linear tickets, Slack threads)
- **Code blocks** — preserve unless clearly outdated and tied to stale narrative

Inline prose is fair game to rewrite. Structural elements are preserved.

### Step 4 — Assess whether an update is needed

Compare the existing title/description against deterministic inputs:

- Current PR title and body (from `gh pr view`)
- Commits on the branch since divergence from base (`git log base..HEAD`)
- Files changed on the branch (`gh pr diff` or `git diff base...HEAD --stat`)
- Current conversation context (if the session has been active)

Has the direction meaningfully changed? Are key details stale, missing, or inaccurate?

- **If no meaningful drift** — skip the update. Output `PR description is still accurate. No changes made.` followed by the PR URL.
- **If drift is detected** — proceed to Step 5.

### Step 5 — Rewrite narrative

Update the title and prose of the description to reflect current direction.

**Preservation rule:** Rewrite stale narrative/prose freely, but preserve all user-added elements — images, code blocks, links, callouts, and template sections like "Other references" and "Preview(s)". You may reorganize or reposition them, but never remove them. Your job is to update the narrative; the user's additions stay.

### Step 6 — Update the PR

Use `gh pr edit` with `--body-file -` via heredoc (never inline `--body`):

```bash
gh pr edit {number} --title "..." --body-file - <<'CO_PR_BODY'
[UPDATED PR BODY]
CO_PR_BODY
```

### Step 7 — Output

Print the PR URL.

## Verification Detection Rules

Both create and update modes run lint/format/test checks before committing. The detection rules:

- **Never hardcode tool names** (no assumptions about Prettier, ESLint, etc.)
- **Read `package.json` scripts** — common ones: `lint`, `format`, `test`, `typecheck`, `check`
- **Read `package.json` dependencies** — detect what's installed
- **Use what the repo provides** — if `pnpm lint` exists, run it. If `pnpm check` is the catch-all, run that instead.
- **Turborepo detection** — some monorepos use `turbo lint` at the root
- **Run lint/format always**, run tests/typechecks based on judgment of change scope
- **If a check fails and it's clearly unrelated to the change**, flag it to the user before proceeding

## Commit Message Detection Rules

- Run `git log --oneline -20` to see recent commits
- Detect patterns: conventional commits (`feat:`, `fix:`, `chore:`), ticket prefixes (`[DOCS-1234]`), emoji prefixes, plain descriptive text, etc.
- Match the dominant pattern in recent history
- Always include the co-author trailer

## PR Title Detection Rules

- Run `gh pr list --state all --limit 10` to see recent PR titles
- Detect patterns and match them
- Some repos enforce title patterns via CI/bots — auto-detection handles that for free

## Not Planned

- **Interactive commit splitting:** The skill commits everything uncommitted as one commit. If the user wants multiple commits, they should commit manually before invoking `/co-pr`.
- **Branch creation:** The skill assumes the current branch is where the work lives. It does not create branches.
- **Merge operations:** The skill creates/updates PRs, never merges.
- **Rewriting user-added content during update:** User-added elements are preserved, never removed. Even if they appear outdated, the user manages them manually.
- **Running full CI locally:** The skill runs repo-defined lint/format/test scripts, not full CI pipelines.
- **Multi-language verification (Python, Go, Rust, Ruby, etc.):** Out of scope. The skill targets JS/TS repos via `package.json`. Can be added later if needed.

## Dismissed (Codex Review Feedback)

- **Structured `STATUS: satisfied` trailer for termination:** Requiring Codex to output a specific token adds brittleness — Codex has already shown it ignores explicit instructions (e.g., "do not execute the plan"). Semantic signal detection worked fine in `/co-plan` and is more resilient in practice.
- **Safety rails for unrelated/stray files in `git add`:** In the Superset workflow, each worktree represents one task. All files in the worktree belong to the current work by design. This isn't a real-world risk.
- **Managed markers (e.g., HTML comments) for preserved sections:** The user frequently interleaves edits inside Claude's prose, which would make markers either too permissive (Claude rewrites user content) or too restrictive (Claude refuses to update anything). Heuristic-based preservation handles the real cases.
- **Always surfacing dismissed review items in the PR description:** Most dismissed items are the trivial overkill the user specifically doesn't want memorialized. Dismissed items stay in internal loop state. Only meaningful scope/product decisions get surfaced, and that's handled in `/co-fix` conditionally.
