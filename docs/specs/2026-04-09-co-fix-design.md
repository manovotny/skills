# co-fix Skill Design Spec

## Overview

A Claude Code skill (`/co-fix`) that runs an agentic peer review loop on a pull request Claude authored. Codex reviews the PR, Claude processes feedback (accepting substantive improvements, rejecting overkill), fixes the code, commits, and iterates until Codex is satisfied. Concludes with an optional PR description update.

Fourth skill in the `co-` prefix collection, alongside `/co-plan`, `/co-review`, and `/co-pr`.

## Scope

- **In scope:** Codex review loop, feedback processing with judgment filter, code fixes, lint/format/test verification, commit management, PR description update (conditional)
- **Out of scope:** Initial PR creation (that's `/co-pr`), merge decisions, reviewing someone else's PR (that's `/co-review`)
- **Language scope:** Currently targets JavaScript/TypeScript repositories (detection via `package.json`), same as `/co-pr`.

## Skill Identity

```yaml
name: co-fix
description: Use when Claude has authored code on a PR and needs agentic peer review and fixes before merge
```

- **Installed to:** `~/.claude/skills/co-fix/SKILL.md` (Claude-only)
- **Trigger:** `/co-fix` (auto-detects PR from current branch)
- **Precondition:** A PR must exist for the current branch. Error with:
  > No PR exists for this branch. Run `/co-pr draft` first.

## Architecture

Single-file skill (`SKILL.md`). Reuses the review prompt from `../co-review/review-prompt.md` — the review criteria are identical between the two skills, only the output handling differs.

## File Structure

```
enshrined-flavor/
  skills/
    co-review/
      SKILL.md
      review-prompt.md      ← reused by co-fix
    co-fix/
      SKILL.md
  docs/
    specs/
      2026-04-09-co-fix-design.md
  README.md
```

Installation: symlink `skills/co-fix/` to `~/.claude/skills/co-fix/`.

## Review-and-Fix Loop

### Step 1 — Precondition check

Run `gh pr view --json number,state` on the current branch. Distinguish these cases:

- **No PR found** → error: "No PR exists for this branch. Run `/co-pr draft` first."
- **PR exists and is `OPEN`** → proceed to Step 2.
- **PR exists but is `CLOSED` or `MERGED`** → error: "The PR on this branch is `{state}`. `/co-fix` only operates on open PRs."
- **`gh` command fails (auth, remote, network)** → surface the actual error and stop.

### Step 2 — Handle uncommitted changes

If there are uncommitted changes, follow the same pre-commit flow as `/co-pr`:
- Stage everything except symlinks
- Run lint/format
- Run tests/typechecks if the change is meaningful
- Commit with a message matching the repo's style
- Push

If there are no uncommitted changes, skip to Step 3.

### Step 3 — Announce and start

Announce: **"Starting agentic peer review of PR #{number}. Round 1 of 4."**

### Step 4 — Send to Codex

Read the review prompt from `../co-review/review-prompt.md`, fill in `{PR_NUMBER}`, and pipe to Codex.

**On rounds 2+, include the previous issue list and Dismissed items** so Codex doesn't resurface rejected nits. Same pattern as `/co-review` re-review:

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

- **Timeout:** `600000` ms (10 minutes)
- **Working directory:** Current directory
- **Model and reasoning:** Inherited from `~/.codex/config.toml`
- **No background execution:** Unlike `/co-review`, there's no parallel Claude review. Just a synchronous call and wait.

### Step 5 — Handle Codex errors

If `codex exec` fails (non-zero exit, empty response, not installed), stop the loop and tell the user what happened. Unlike `/co-review` where Claude's review can stand alone, `/co-fix` has no fallback — Codex is the only reviewer here.

### Step 6 — Process feedback

Apply Claude's judgment to Codex's findings:

- Do not blindly accept feedback
- Keep suggestions that improve correctness, maintainability, performance, or test coverage
- Reject overkill, premature abstraction, and out-of-scope suggestions
- Rejected items go into a **Dismissed** list (tracked internally for the PR description update in Step 11)

### Step 7 — Fix the code

Make the accepted changes. Commit granularity is Claude's judgment — logical grouping over mechanical one-commit-per-issue. Examples:

- 9 related type safety fixes → 1 commit
- 3 unrelated concerns (type safety, a bug, missing test) → 3 commits
- 1 narrow fix → 1 commit
- Multiple rounds of touch-ups → new commits per round

**No amending after push.** All post-push fixes are new commits. Amending would require force-push, which destabilizes review threads and can confuse reviewers who already pulled the branch. Clean history is less valuable than review stability.

### Step 8 — Pre-commit checks

Before committing fixes:
- Run lint/format (always)
- Run tests/typechecks if the change is meaningful (judgment-based)
- Re-stage files after autofixes (formatters modify files on disk)
- Fix any issues before committing
- Same detection rules as `/co-pr` — read `package.json`, don't hardcode tool names

### Step 9 — Commit and push

Commit the fixes with a message matching the repo's style. Push.

### Step 10 — Check termination

After each Codex response, check for satisfaction signals:
- "this is ready"
- "this is solid"
- "no remaining gaps"
- "complete enough to execute"
- "no remaining findings"
- "don't see any substantive gaps"

If Codex signals satisfaction — even with trailing nits — **exit the loop**. Fold trailing nits into Claude's judgment for Step 11.

**Hard cap: 4 rounds.** If round 4 has no satisfaction signal, stop and ask the user for guidance.

If not satisfied and under the cap, announce the next round number and return to Step 4 with the updated code.

**Note:** Unlike `/co-plan`, `/co-fix` does not perform a final self-review pass to strip overengineering. Claude already filters Codex's feedback in real time during Step 6 (rejecting overkill into the Dismissed list). By loop exit, the code is already clean.

### Step 11 — Update PR description (conditional)

Based on Claude's judgment:

- **Conditionally** update the PR's "Not Planned" section if any dismissed items reflect a meaningful scope or product decision worth surfacing to future reviewers. Trivial nits Claude rejected (overkill, premature abstraction, pedantry) stay in internal loop state — they don't belong in the PR body.
- **Conditionally** update the rest of the PR description if the fixes meaningfully changed direction — Claude decides whether an update is warranted.

Follow the same preservation rules as `/co-pr update`:
- Rewrite stale narrative/prose freely
- Preserve user-added elements via heuristics (structural sections, callouts, images, external links, code blocks)
- Use `gh pr edit --body-file -` with heredoc, never inline `--body`

### Step 12 — Output

Print a concise summary:

```
Fixed N issues, dismissed M. X commits pushed.
[PR URL]
```

## Codex Invocation Details

- **Command:** `codex exec --dangerously-bypass-approvals-and-sandbox` via stdin heredoc with `CO_FIX_EOF` delimiter
- **Review prompt:** Read from `../co-review/review-prompt.md`, resolved relative to the skill directory
- **Timeout:** `600000` ms
- **Working directory:** Current directory
- **Model and reasoning:** Inherited from `~/.codex/config.toml`
- **No background execution:** Synchronous call only
- **Error handling:** Stop the loop on any Codex failure. No fallback.

## Termination Strategy

Same semantic exit + hard cap pattern as `/co-plan`:

- **Semantic signals:** Parse Codex responses for satisfaction language
- **Hard cap:** 4 rounds maximum
- **Escalation:** If the cap is hit, stop and ask the user

## Not Planned

- **Final self-review pass:** The Dismissed filter in Step 6 does this work in real time. No separate cleanup needed.
- **Running tests unconditionally:** Tests are judgment-based. Small tweaks skip, meaningful changes run.
- **Creating a PR if none exists:** `/co-fix` is for fixing code on an existing PR. If no PR exists, error and direct the user to `/co-pr draft`.
- **Merging after Codex is satisfied:** `/co-fix` stops at the updated PR. The user marks it ready for review and merges manually.
- **Claude reviewing its own code:** Claude is the author. Even with "fresh eyes," it's biased. Codex is the sole reviewer here by design.
- **Posting GitHub review comments:** `/co-fix` fixes the code directly. It doesn't leave comments — the feedback loop is between Codex and Claude, not visible on GitHub.
- **Parallel execution with Claude review:** Unlike `/co-review`, there's no parallel work. Only Codex reviews.
- **Amending commits after push:** All post-push fixes are new commits. Amending requires force-push, which destabilizes review threads.
- **Multi-language verification (Python, Go, Rust, Ruby, etc.):** Out of scope. Same as `/co-pr` — JS/TS only for now.

## Dismissed (Codex Review Feedback)

- **Structured `STATUS: satisfied` trailer for termination:** Same reasoning as `/co-pr` — semantic detection works in practice and Codex ignores explicit instructions anyway. Claude's judgment on Codex satisfaction is more reliable than relying on a magic token.
- **Always surfacing all dismissed items in PR description:** Most dismissed items are exactly the overkill the user doesn't want memorialized. Only meaningful scope/product decisions get surfaced (now reflected in Step 11).
