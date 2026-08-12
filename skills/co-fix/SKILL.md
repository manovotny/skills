---
name: co-fix
description: Use when Claude has authored code on a PR and needs agentic peer review and fixes before merge
---

# co-fix

Run an agentic peer review loop on a pull request Claude authored. Codex reviews, Claude filters feedback (rejecting overkill into a Dismissed list) along with CI failures and bot reviewer comments, fixes the code, commits, replies to bot threads, and iterates until Codex is satisfied or the loop hits its cap.

**Do not use this skill to create a PR.** If no PR exists, run `/co-pr draft` first.

**Scope:** JS/TS repos only for now (detected via `package.json`). Same as `/co-pr`.

## Preconditions

Run `gh pr view --json number,state,url` on the current branch.

- **No PR** → error: "No PR exists for this branch. Run `/co-pr draft` first."
- **`OPEN`** → continue.
- **`CLOSED` or `MERGED`** → error: "The PR on this branch is `{state}`. `/co-fix` only operates on open PRs."
- **`gh` fails (auth/remote/network)** → surface the actual error and stop.

**Run `git commit` and `git push` from the session's current directory.** `/co-fix` derives the PR from the current branch, so this directory is on the PR branch — keep commits and pushes anchored here so the work stays visible in the app and pushes from where the user can watch. Don't move your working position to a *different checkout of the repo* to land fixes. Editing files that live elsewhere (symlinked in, or sibling packages) is fine — that's file location, not your working position.

## Shared pre-commit flow

When committing local changes (uncommitted work, or fixes during the loop), follow the same pre-commit flow as `/co-pr`:

1. Stage everything except symlinks
2. Run lint/format with autofix (detected from `package.json`, never hardcoded)
3. Re-stage files modified by autofixes
4. Run tests/typechecks if the change is meaningful (judgment-based)
5. Verify HEAD is still the intended branch (in a shared checkout a parallel session can move it — re-check `git branch --show-current` right before committing), then commit with a message matching the repo's style + co-author trailer
6. Push (detect upstream, fall back to `origin`)

**Hard rule: never amend after push.** All post-push fixes are new commits. Amending would require force-push, which destabilizes review threads and confuses anyone who pulled the branch.

## Review-and-fix loop

**Critical: Use a single stateful Codex session across all rounds.** Round 1 uses `codex exec` (fresh session). Rounds 2+ use `codex exec resume <session_id>` to continue the **same** session. This keeps the full context — review prompt, previous findings, Claude's dismissals — naturally in Codex's memory without re-sending it as text every round.

**Step 1 — Pre-commit local changes.** If the worktree is dirty, run the shared pre-commit flow before starting the review.

**Step 2 — Announce.**

> Starting agentic peer review of PR #{number}. Round 1 of 4.

**Step 3 — Send to Codex (round 1).** Fresh session. Read the review prompt from `../co-review/review-prompt.md` and fill in `{PR_NUMBER}`:

```bash
cat <<'CO_FIX_EOF' | codex exec --dangerously-bypass-approvals-and-sandbox -
[FILLED REVIEW PROMPT]
CO_FIX_EOF
```

**Capture the session ID.** Codex prints `session id: <uuid>` near the top of its output. Extract and remember it for subsequent rounds.

- **Timeout:** `600000` ms
- **Working directory:** Current directory
- **Synchronous:** No background execution. Claude waits.

**Step 3b — Send to Codex (rounds 2+).** Use `codex exec resume <session_id>` to continue the same session. The previous findings and dismissals are already in Codex's context — just tell it to re-review the updated code:

```bash
cat <<'CO_FIX_EOF' | codex exec resume <session_id> --dangerously-bypass-approvals-and-sandbox -
I've addressed the accepted findings from the previous round. Please re-review PR #{PR_NUMBER} against the updated diff.

Dismissed items from my previous filtering (do not resurface these):
[DISMISSED LIST]
CO_FIX_EOF
```

The Dismissed list is still worth appending explicitly — it signals intent clearly ("I've decided these are out of scope") even though Codex could infer it from session history.

**Step 4 — Check CI status and bot reviewer threads.** After receiving Codex's review, also check PR checks:

```bash
gh pr checks --json name,state,bucket,link,description
```

Treat CI failures as first-class findings alongside Codex's code review — a broken build matters as much as a code comment. Investigate failures with `gh run view <run-id> --log-failed` and fix them in the same pass as code review findings.

Then pull both PR comment streams (`gh api --paginate repos/{owner}/{repo}/pulls/{pr}/comments` and `gh api --paginate repos/{owner}/{repo}/issues/{pr}/comments`) and collect **bot reviewer comments** — authors with `user.type == "Bot"` raising code concerns (CodeRabbit, Cursor's Bugbot, the ChatGPT/Codex connector, Macroscope, …); skip non-review bot noise (deploy previews, coverage summaries, changelog bots) and anything that already has a human reply. Re-fetch every round — bots often comment while the loop runs. **Track candidates by revision, keyed on `(stream, id, updated_at)`**, not by id alone: CodeRabbit revises its summary in place, so a changed `updated_at` on an id you already answered makes it a candidate again. Bot findings are candidates for Step 6's filter, not obligations.

Record each candidate as **stream plus id**, because the two streams are separate id spaces and only inline comments are repliable: an inline thread root (reply via its review comment id) or a top-level issue comment (no reply thread — answered PR-wide). Step 8b routes on this.

**Step 5 — Handle Codex errors.** If `codex exec` fails (non-zero exit, empty response, timeout, not installed), stop the loop and tell the user. There is no fallback reviewer here — Codex is the only reviewer.

**Step 6 — Apply judgment.** Process Codex's findings, CI failures, and bot reviewer threads together:
- Do not blindly accept feedback.
- Keep findings that improve correctness, maintainability, performance, or test coverage.
- **Do not dismiss touched-file diagnostics as "pre-existing."** Diagnostics, LSP output, or linter warnings in changed files or their direct ripple are actionable regardless of whether they predate the diff. Pre-existence alone is not grounds for rejection. If a diagnostic is kept (e.g., framework-required signature, false positive), either surface it to the user with the rationale or apply an intentional suppression/rename — do not silently drop it into `Dismissed`.
- Reject overkill, premature abstraction, pedantry, and out-of-scope work.
- Track rejected items in a **Dismissed** list (for round 2+ context, bot-thread replies, and possible PR body update).

**Step 7 — Fix the code.** Make the smallest change that fully addresses each accepted finding. If the clean fix is broader than the feature deserves, surface that instead of smuggling in a refactor. Commit granularity is judgment-based:
- Multiple related fixes (e.g., type safety) → 1 commit
- Unrelated concerns (bug + test + refactor) → separate commits
- Logical grouping over mechanical one-commit-per-issue

**Don't dismiss diagnostics as "pre-existing."** If diagnostics, LSP output, or linter warnings surface in changed files or their direct ripple — unused code, type errors, deprecated APIs, etc. — treat them as actionable alongside the accepted findings. Either fix them in the same pass or surface them for the user's call. Pre-existence alone is not grounds for dismissal.

**Prose fixes carry the voice.** When an accepted finding lands in prose that lives in the repo — docs, READMEs, blog posts, articles, changelogs, release notes — write that prose per `~/.claude/skills/co-write/voice.md` if it exists, using the medium overlay that matches the content (Docs, Blog & long-form, Release notes & changelogs, ...; core alone when none fits). Apply the guide directly; don't invoke `/co-write`. Format still wins: a local styleguide or repo convention outranks the voice, per the guide itself. And voice never widens the fix — revoice only the prose the fix already touches; rewriting the surrounding document is the same smuggled refactor as above.

**Step 8 — Pre-commit and push.** If the round produced fixes, run the shared pre-commit flow on them (lint/format always, tests/typechecks when meaningful), commit, and push. **No amending.** A round that accepted nothing has nothing to commit — skip straight to Step 8b rather than manufacturing a commit.

**Step 8b — Answer bot reviewer comments.** Right after this round's push — or immediately, when the round produced no commits — close the loop on every bot comment triaged this round. One answer each, posted autonomously (co-fix already commits and pushes unattended):

- **Fixed** → "Fixed in abc1234." — plain-text hash so GitHub renders the commit link.
- **Dismissed** → the skip reason, brief and direct — not apologetic. A dismissal never waits on a commit; it stands on its own.

**Route by stream (from Step 4) — the two id spaces are not interchangeable.** An inline thread root is repliable:

```bash
gh api repos/{owner}/{repo}/pulls/{pr}/comments/{review_comment_id}/replies -F body=@- <<'REPLY_EOF'
Fixed in abc1234.
REPLY_EOF
```

A top-level bot comment has no reply thread, and its issue comment id sent to that endpoint fails — answer those in one combined `gh pr comment` instead, naming the bot you're answering.

**Re-fetch each thread immediately before posting.** Codex runs and fixes take time, so a human may have replied since Step 4 — skip any root that has since gained one. Answer each `(stream, id, updated_at)` revision at most once: an unchanged revision you already answered stays untouched, while a revised one is answered again, covering only what changed since the revision you answered before. Write replies first person as the user; if `~/.claude/skills/co-write/voice.md` exists, apply it (medium: PR & review comments).

**Step 9 — Check termination.** Look for satisfaction signals in Codex's response:
- "this is ready"
- "this is solid"
- "no remaining gaps"
- "complete enough to execute"
- "no remaining findings"
- "don't see any substantive gaps"

If satisfied (even with trailing nits), exit the loop. Trailing nits fold into Step 10 below.

**Hard cap: 4 rounds.** If round 4 has no satisfaction signal, stop and ask the user for guidance.

If not satisfied and under cap, announce the next round and return to Step 3 with the carried Dismissed list.

## Step 10 — PR description update (conditional)

After the loop exits, decide whether to update the PR description:

- **Conditionally update the body** if the fixes meaningfully changed the PR narrative — Claude's judgment.
- **Conditionally update the "Not Planned" section** if any dismissed items reflect a real scope or product decision worth surfacing. Trivial nits (overkill, premature abstraction, pedantry) stay internal — they don't belong in the PR body.

If updating:

1. **Read the current body first** via `gh pr view --json title,body`. Do not rely on what the body looked like at the start of the loop — the user may have edited it (added Vercel previews, Linear/Slack links, screenshots, callouts) while Codex was running.
2. **Identify preserved content** using the same heuristics as `/co-pr update` Step 3 (structural sections, callouts, images, external links to deployments/tickets/resources, code blocks).
3. **Merge, don't replace.** Rewrite inline prose freely, applying `~/.claude/skills/co-write/voice.md` if it exists; reposition preserved elements if needed; never drop them.
4. Use `gh pr edit --body-file -` with heredoc, never inline `--body`.

## Output

When the loop finishes successfully, print:

```
Fixed N issues, dismissed M. X commits pushed. Replied to K bot threads.
[PR URL]
```

Drop the bot-threads clause when there were none.

If the loop stops because of a Codex failure or the 4-round cap, explain what happened and stop.
