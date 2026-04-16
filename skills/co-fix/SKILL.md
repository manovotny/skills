---
name: co-fix
description: Use when Claude has authored code on a PR and needs agentic peer review and fixes before merge
---

# co-fix

Run an agentic peer review loop on a pull request Claude authored. Codex reviews, Claude filters feedback (rejecting overkill into a Dismissed list), fixes the code, commits, and iterates until Codex is satisfied or the loop hits its cap.

**Do not use this skill to create a PR.** If no PR exists, run `/co-pr draft` first.

**Scope:** JS/TS repos only for now (detected via `package.json`). Same as `/co-pr`.

## Preconditions

Run `gh pr view --json number,state,url` on the current branch.

- **No PR** → error: "No PR exists for this branch. Run `/co-pr draft` first."
- **`OPEN`** → continue.
- **`CLOSED` or `MERGED`** → error: "The PR on this branch is `{state}`. `/co-fix` only operates on open PRs."
- **`gh` fails (auth/remote/network)** → surface the actual error and stop.

## Shared Pre-Commit Flow

When committing local changes (uncommitted work, or fixes during the loop), follow the same pre-commit flow as `/co-pr`:

1. Stage everything except symlinks
2. Run lint/format with autofix (detected from `package.json`, never hardcoded)
3. Re-stage files modified by autofixes
4. Run tests/typechecks if the change is meaningful (judgment-based)
5. Commit with a message matching the repo's style + co-author trailer
6. Push (detect upstream, fall back to `origin`)

**Hard rule: never amend after push.** All post-push fixes are new commits. Amending would require force-push, which destabilizes review threads and confuses anyone who pulled the branch.

## Review-and-Fix Loop

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

**Step 4 — Check CI status.** After receiving Codex's review, also check PR checks:

```bash
gh pr checks --json name,state,bucket,link,description
```

Treat CI failures as first-class findings alongside Codex's code review — a broken build matters as much as a code comment. Investigate failures with `gh run view <run-id> --log-failed` and fix them in the same pass as code review findings.

**Step 5 — Handle Codex errors.** If `codex exec` fails (non-zero exit, empty response, timeout, not installed), stop the loop and tell the user. There is no fallback reviewer here — Codex is the only reviewer.

**Step 6 — Apply judgment.** Process Codex's findings and CI failures together:
- Do not blindly accept feedback.
- Keep findings that improve correctness, maintainability, performance, or test coverage.
- **Do not dismiss touched-file diagnostics as "pre-existing."** Diagnostics, LSP output, or linter warnings in changed files or their direct ripple are actionable regardless of whether they predate the diff. Pre-existence alone is not grounds for rejection. If a diagnostic is kept (e.g., framework-required signature, false positive), either surface it to the user with the rationale or apply an intentional suppression/rename — do not silently drop it into `Dismissed`.
- Reject overkill, premature abstraction, pedantry, and out-of-scope work.
- Track rejected items in a **Dismissed** list (for round 2+ context and possible PR body update).

**Step 7 — Fix the code.** Make the smallest change that fully addresses each accepted finding. If the clean fix is broader than the feature deserves, surface that instead of smuggling in a refactor. Commit granularity is judgment-based:
- Multiple related fixes (e.g., type safety) → 1 commit
- Unrelated concerns (bug + test + refactor) → separate commits
- Logical grouping over mechanical one-commit-per-issue

**Don't dismiss diagnostics as "pre-existing."** If diagnostics, LSP output, or linter warnings surface in changed files or their direct ripple — unused code, type errors, deprecated APIs, etc. — treat them as actionable alongside the accepted findings. Either fix them in the same pass or surface them for the user's call. Pre-existence alone is not grounds for dismissal.

**Step 8 — Pre-commit and push.** Run the shared pre-commit flow on the fixes (lint/format always, tests/typechecks when meaningful). Commit and push. **No amending.**

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

## Step 10 — PR Description Update (Conditional)

After the loop exits, decide whether to update the PR description:

- **Conditionally update the body** if the fixes meaningfully changed the PR narrative — Claude's judgment.
- **Conditionally update the "Not Planned" section** if any dismissed items reflect a real scope or product decision worth surfacing. Trivial nits (overkill, premature abstraction, pedantry) stay internal — they don't belong in the PR body.

If updating, follow the same preservation rules as `/co-pr update`:
- Rewrite stale prose freely
- Preserve user-added structural sections, callouts, images, external links, and code blocks
- Use `gh pr edit --body-file -` with heredoc, never inline `--body`

## Output

When the loop finishes successfully, print:

```
Fixed N issues, dismissed M. X commits pushed.
[PR URL]
```

If the loop stops because of a Codex failure or the 4-round cap, explain what happened and stop.
