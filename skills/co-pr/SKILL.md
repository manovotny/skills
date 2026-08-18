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

## Voice

Covers every piece of prose this skill writes: the PR title, the PR body, and commit message bodies.

1. **Read the guide.** `~/.claude/skills/co-write/voice.md`, resolved from that path — this skill runs from any repo. Medium is **PR & review comments**: apply Core voice, then that overlay. Re-read the overlay's canonical excerpts before writing; they set rhythm in ways the rules can't.
2. **Write.**
3. **Self-check before publishing.** Re-read the draft against the guide and fix what fails. Never push prose that would flunk `/co-write check`. The misses that keep recurring in PR bodies:
   - Restating what the link already shows — CI status, file counts, "lint and typecheck pass". The reader clicks through for that, and it reads as answering your own worry instead of theirs.
   - Em dashes past the ration. Two in one paragraph means cut one.
   - Filler and hedges from the never-list.
   - Recap closers. Close on the next step, the ask, or nothing.

Apply `voice.md` directly. Do not invoke `co-write` for this, same as `co-review` and `co-fix`.

If `voice.md` is missing, or its Core voice section has no rules, write normally and say the prose isn't voiced. Don't improvise one from generic defaults.

**Format wins.** PR templates, required sections, commit subject conventions, and repo idiom all outrank voice. Voice shapes the prose inside that structure, never the structure.

## Shared pre-commit flow

Used by both create and update modes when there are uncommitted changes.

1. **Stage** — `git add` everything except symlinks and `docs/superpowers/`. Both are hard exclusions.
2. **Lint and format** — Read `package.json` scripts and dependencies. Run repo-defined commands with autofix (e.g., `pnpm lint --fix`, `pnpm format`). Never hardcode tool names.
3. **Re-stage** — Formatters modify files on disk. Re-run `git add` on affected files so autofixes are included in the commit.
4. **Tests/typechecks (judgment-based)** — Skip for small tweaks (CSS, docs, config). Run for meaningful changes (logic, refactors, new code). Use `pnpm test`, `pnpm typecheck`, `pnpm check`, etc.
5. **Commit** — First re-check `git branch --show-current` and confirm HEAD is still the branch you set out to commit to. Branch identity established earlier in the session is not durable: in a shared primary checkout (one that other agent sessions or scripts also operate in — session worktrees hanging off the clone in `git worktree list` are the tell), a parallel session can switch branches between your staging and your commit, silently landing the commit on whatever branch it parked (typically the default branch). On a mismatch, stop and re-orient — check the intended branch out again — rather than committing onto a branch you didn't choose. Then match the repo's commit style from `git log --oneline -20`. Style-matching covers subject and body only. The subject follows the repo's convention; the body prose follows [Voice](#voice). Always end the message with a `Co-Authored-By:` trailer crediting Claude, using verbatim the trailer string your own session guidance gives you — that string names the model actually running. If your session supplies no such trailer, fall back to:

   ```
   Co-Authored-By: Claude <noreply@anthropic.com>
   ```

   The model name comes from your session, never from a name written down elsewhere — trailers in this repo's `git log` and in this file credit whichever model wrote them, not you.

6. **Push** — Detect upstream from the branch, fall back to `origin`:

   ```bash
   if git rev-parse --abbrev-ref --symbolic-full-name @{upstream} >/dev/null 2>&1; then
     git push
   else
     git push -u origin {branch}
   fi
   ```

   If push fails, surface the actual error and stop. In fork mode, push to the `fork` remote with an explicit refspec instead (see [Fork mode](#fork-mode-external-contributor)).

## Fork mode (external contributor)

Some PRs target a repo the user can't push to — they're contributing from outside. Detect this before the first push, not from a failed one: when the target repo isn't obviously the user's own, check

```bash
gh repo view {owner}/{repo} --json viewerPermission --jq .viewerPermission
```

on the repo `origin` points to. `READ` means fork mode. The flow stays the same except for four things:

1. **Fork without touching remotes.** `gh repo fork {upstream} --clone=false`, then `git remote add fork git@github.com:{user}/{repo}.git`. Never `gh repo fork --remote` — it renames `origin` to `upstream` and repoints `origin` at the fork, and remotes are shared across every worktree and session using the clone, so that rewiring leaks beyond this branch. If the fork already exists, `gh repo fork` says so harmlessly; reuse it.
2. **Pick the branch name the upstream would.** The local branch may carry a session-generated name that means nothing upstream. Read head-branch conventions from `gh pr list --repo {upstream} --state all --limit 10 --json headRefName,title` and push under a matching name — the refspec decouples local from remote naming:

   ```bash
   git push fork HEAD:refs/heads/{branch}
   ```

3. **Name the repo on every `gh pr` call.** Branch-based resolution can't find a PR whose head lives on the fork under a different name. Create with `gh pr create --repo {upstream} --base {default-branch} --head {user}:{branch}`; view, edit, and list with `--repo {upstream}` plus the PR number or URL. This includes Step 5's title-style detection — `gh pr list` without `--repo` may read the wrong repo's conventions.
4. **Expect quiet CI.** Workflow runs on a first-time contributor's PR wait for maintainer approval, so "no checks reported" is normal on a fresh fork PR — mention it, don't chase it.

Fork mode also changes the audience: the PR body reads as a proposal to a maintainer who didn't ask for the change, not a teammate expecting it. Lead the Summary with the problem the change solves for the project's users, and keep repo conventions (branch names, commit style, localization parity, changelog entries) tight — they're the first thing a maintainer checks on an outside contribution.

## Create mode (`/co-pr` and `/co-pr draft`)

**Step 1 — Precondition.** Run `gh pr view --json number,state` on the current branch. **Run this alone — do not parallelize with other commands**, because `gh` exits non-zero when no PR exists (the expected happy path), and parallel tool calls cancel siblings on non-zero exit. In fork mode, branch-based resolution misses fork-hosted heads — check with `gh pr list --repo {upstream} --head {user}:{branch} --json number,state` instead.
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

Write the body prose per [Voice](#voice), including the self-check before you create the PR.

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

**Step 3 — Identify preserved content.** Read the existing title and body via `gh pr view --json title,body` *now* — do not rely on prior reads from earlier in the session, since the user may have edited the body between then and now. Use heuristics (no markers) to identify user-added elements that must survive:
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

**Step 5 — Rewrite narrative.** Refresh stale prose to match current direction, per [Voice](#voice), including the self-check before you edit the PR. Preserve all user-added elements identified in Step 3 — reposition is fine, remove is not.

**Step 6 — Update the PR.** Use `--body-file -` with heredoc, never inline `--body`:

```bash
gh pr edit {number} --title "..." --body-file - <<'CO_PR_BODY'
[UPDATED BODY]
CO_PR_BODY
```

**Step 7 — Output.** Print the PR URL.
