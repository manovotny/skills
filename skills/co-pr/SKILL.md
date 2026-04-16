---
name: co-pr
description: Use when creating or updating a GitHub pull request
---

# co-pr

Create or update a GitHub pull request from the current branch. Handles staging, lint/format, commit, push, PR description generation, and PR refreshes when the branch has drifted.

**Modes:**
- `/co-pr` — create a ready-for-review PR (default)
- `/co-pr draft` — create a draft PR
- `/co-pr update` — refresh title/body of an existing open PR

**Scope:** JS/TS repos only for now (detected via `package.json`). Symlinks are never staged or committed — they're for cross-repo verification only. `docs/superpowers/` files (specs, plans, designs) are never staged or committed — they're working artifacts for the current session only.

## Shared pre-commit flow

Used by both create and update modes when there are uncommitted changes.

1. **Stage** — `git add` everything except symlinks and `docs/superpowers/`. Both are hard exclusions.
2. **Lint and format** — Read `package.json` scripts and dependencies. Run repo-defined commands with autofix (e.g., `pnpm lint --fix`, `pnpm format`). Never hardcode tool names.
3. **Re-stage** — Formatters modify files on disk. Re-run `git add` on affected files so autofixes are included in the commit.
4. **Tests/typechecks (judgment-based)** — Skip for small tweaks (CSS, docs, config). Run for meaningful changes (logic, refactors, new code). Use `pnpm test`, `pnpm typecheck`, `pnpm check`, etc.
5. **Commit** — Match the repo's commit style from `git log --oneline -20`. Always include the trailer:

   ```
   Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>
   ```

6. **Push** — Detect upstream from the branch, fall back to `origin`:

   ```bash
   if git rev-parse --abbrev-ref --symbolic-full-name @{upstream} >/dev/null 2>&1; then
     git push
   else
     git push -u origin {branch}
   fi
   ```

   If push fails, surface the actual error and stop.

## Create mode (`/co-pr` and `/co-pr draft`)

**Step 1 — Precondition.** Run `gh pr view --json number,state` on the current branch. **Run this alone — do not parallelize with other commands**, because `gh` exits non-zero when no PR exists (the expected happy path), and parallel tool calls cancel siblings on non-zero exit.
- PR exists → error: "A PR already exists for this branch. Use `/co-pr update` to update it."
- `gh` fails (auth/remote/network) → surface the actual error, don't assume "no PR."
- No PR → continue.

**Step 2 — Pre-commit.** If there are uncommitted changes, run the shared pre-commit flow.

**Step 3 — Detect PR template.** Run `gh repo view --json pullRequestTemplates` (GitHub serves templates from the default branch). If nothing returns, fall back to checking common locations: `.github/pull_request_template.md`, `.github/PULL_REQUEST_TEMPLATE.md`, `pull_request_template.md`, `PULL_REQUEST_TEMPLATE.md`, `docs/pull_request_template.md`, or any `.md` file under `.github/PULL_REQUEST_TEMPLATE/`.

**Step 4 — Draft the PR body.** If a template was found, follow its structure. Otherwise use the default:
- **Summary** — one or two sentences on why
- **Changes** — bullet list of what was done
- **Not Planned** — anything intentionally skipped (only if relevant)
- **References** — substantive links: related PRs/issues, Linear tickets, Slack threads, research articles, docs (only if relevant — skip tangential links)

**Step 5 — Detect PR title style.** Run `gh pr list --state all --limit 10`. Match the dominant convention (conventional commits, ticket prefixes, sentence case, etc.).

**Step 6 — Create the PR.** Use `gh pr create` with `--draft` for `/co-pr draft`. **Always pass the body via `--body-file -` with a heredoc, never inline `--body`** — inline breaks on multi-line Markdown, quotes, backticks, code fences, and callouts.

```bash
gh pr create --title "..." --body-file - <<'CO_PR_BODY'
[PR BODY]
CO_PR_BODY
```

**Step 7 — Output.** Print the PR URL. Nothing else.

## Update mode (`/co-pr update`)

**Step 1 — Precondition.** Run `gh pr view --json number,title,body,state,url` on the current branch.
- No PR → error: "No PR exists for this branch. Use `/co-pr` to create one."
- `OPEN` → continue.
- `CLOSED` or `MERGED` → error: "The PR on this branch is `{state}`. Updates only apply to open PRs."
- `gh` fails → surface the actual error.

**Step 2 — Pre-commit.** If there are uncommitted changes, run the shared pre-commit flow.

**Step 3 — Identify preserved content.** Read the existing title and body. Use heuristics (no markers) to identify user-added elements that must survive:
- Structural sections: "Other references", "Preview(s)", "Screenshots", "Testing notes", etc.
- Callouts at the top: `[!NOTE]`, `[!WARNING]`, `[!TIP]`, `[!IMPORTANT]`, `[!CAUTION]`
- Images (Markdown or HTML)
- External links to specific deployments, tickets, or resources (Vercel previews, Linear, Slack)
- Code blocks (preserve unless clearly outdated and tied to stale narrative)

Inline prose is fair game to rewrite. Structural elements stay.

**Step 4 — Drift detection.** Compare the PR title/body against deterministic inputs:
- Existing PR narrative
- Commits since branch divergence (`git log base..HEAD`)
- Files changed (`gh pr diff` or `git diff base...HEAD --stat`)
- Conversation context if active

If no meaningful drift, output `PR description is still accurate. No changes made.` followed by the PR URL. Stop.

**Step 5 — Rewrite narrative.** Refresh stale prose to match current direction. Preserve all user-added elements identified in Step 3 — reposition is fine, remove is not.

**Step 6 — Update the PR.** Use `--body-file -` with heredoc, never inline `--body`:

```bash
gh pr edit {number} --title "..." --body-file - <<'CO_PR_BODY'
[UPDATED BODY]
CO_PR_BODY
```

**Step 7 — Output.** Print the PR URL.
