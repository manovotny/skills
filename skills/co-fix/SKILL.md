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

**Step 1 — Pre-commit local changes.** If the worktree is dirty, run the shared pre-commit flow before starting the review.

**Step 2 — Announce.**

> Starting agentic peer review of PR #{number}. Round 1 of 4.

**Step 3 — Send to Codex.** Read the review prompt from `../co-review/review-prompt.md` and fill in `{PR_NUMBER}`. **On rounds 2+, append the previous findings and Dismissed list** so Codex doesn't resurface rejected nits:

```bash
cat <<'CO_FIX_EOF' | codex exec --dangerously-bypass-approvals-and-sandbox -
[FILLED REVIEW PROMPT]

---

Previous review findings (from earlier round):
[PREVIOUS ISSUE LIST]

Previously dismissed items (do not resurface):
[DISMISSED LIST]
CO_FIX_EOF
```

- **Timeout:** `600000` ms
- **Working directory:** Current directory
- **Synchronous:** No background execution. Claude waits.

**Step 4 — Handle Codex errors.** If `codex exec` fails (non-zero exit, empty response, timeout, not installed), stop the loop and tell the user. There is no fallback reviewer here — Codex is the only reviewer.

**Step 5 — Apply judgment.** Process Codex's findings:
- Do not blindly accept feedback.
- Keep findings that improve correctness, maintainability, performance, or test coverage.
- Reject overkill, premature abstraction, pedantry, and out-of-scope work.
- Track rejected items in a **Dismissed** list (for round 2+ context and possible PR body update).

**Step 6 — Fix the code.** Make the accepted changes. Commit granularity is judgment-based:
- Multiple related fixes (e.g., type safety) → 1 commit
- Unrelated concerns (bug + test + refactor) → separate commits
- Logical grouping over mechanical one-commit-per-issue

**Step 7 — Pre-commit checks and push.** Run the shared pre-commit flow on the fixes (lint/format always, tests/typechecks when meaningful). Commit and push. **No amending.**

**Step 8 — Check termination.** Look for satisfaction signals in Codex's response:
- "this is ready"
- "this is solid"
- "no remaining gaps"
- "complete enough to execute"
- "no remaining findings"
- "don't see any substantive gaps"

If satisfied (even with trailing nits), exit the loop. Trailing nits fold into Step 9.

**Hard cap: 4 rounds.** If round 4 has no satisfaction signal, stop and ask the user for guidance.

If not satisfied and under cap, announce the next round and return to Step 3 with the carried Dismissed list.

## Step 9 — PR Description Update (Conditional)

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
