---
name: co-review
description: Use when reviewing a pull request with agentic peer review before posting GitHub comments
---

# co-review

Automate agentic peer review of a pull request. Claude and Codex review the PR diff in parallel, Claude synthesizes both reviews into a single issue list, posts pending GitHub comments, and handles re-reviews when the author pushes changes.

**Do not use this skill to approve, request changes, or merge the PR.**

## Preconditions

- If the user provided a PR number (e.g., `/co-review 2369`), use it.
- Otherwise run `gh pr view --json number` to infer from the current branch.
- If no PR can be determined, ask the user for the number and stop.

## Review Prompt

Read [review-prompt.md](review-prompt.md) from this skill's directory (not repo cwd). Both Claude and Codex use this same prompt. Replace `{PR_NUMBER}` with the actual PR number before use.

## Initial Review Flow

Announce: **"Starting parallel review of PR #{number}."**

**Step 1 — Pre-review.** Before touching the diff, gather context:

- `gh pr view {number}` for title, description, and linked references
- Follow linked PRs or repos explicitly referenced in the description
- Find and read any CLAUDE.md or AGENTS.md files
- Check for symlinked repositories — use them to verify code examples, API references, and technical details

**Step 2 — Parallel review.** Kick off Codex in the background with `run_in_background: true` and a timeout of `600000` ms:

```bash
cat <<'CO_REVIEW_EOF' | codex exec --dangerously-bypass-approvals-and-sandbox -
[REVIEW PROMPT WITH PR NUMBER FILLED IN]
CO_REVIEW_EOF
```

While Codex runs, Claude reviews the diff simultaneously using the same prompt and `gh pr diff {number}`. True parallel — do not wait for Codex before starting Claude's review.

If Codex fails (non-zero exit, empty response, timeout), continue with Claude's review alone and tell the user Codex errored. Codex is additive — Claude's review stands on its own.

**Step 3 — Synthesize.** Once Codex finishes, merge both reviews:

- Deduplicate overlapping findings
- Apply Claude's judgment — reject overkill, out-of-scope, and low-value pedantry
- Add rejected items to a **Dismissed** section with brief rationale for each
- Produce a single numbered issue list in the format from review-prompt.md
- **Proactively flag confidence for each issue.** For every issue, decide whether Claude has a clear fix or whether it's better raised as a comment/question for the author. Mark each issue visibly (e.g., `[Direct fix ready]` vs `[Needs author input]`). The user shouldn't have to ask.

**Step 4 — Present and prompt.**

```
Review complete. N issues found.

1. Post all as pending review comments
2. Post all and submit the review
3. Make direct fixes (optionally mixed with comments)
4. Let me adjust (tell me what to change)
```

Do not post anything or make any changes until the user chooses.

**Step 5 — Act on the choice.**

### Option 1 — Post all as pending review comments

Create pending review comments via `gh api`. To keep the review pending, omit the `event` field entirely — do NOT set it to `"PENDING"`. Valid event values are only `APPROVE`, `REQUEST_CHANGES`, and `COMMENT`.

Build comment anchors from the current diff and head SHA (`gh pr view --json headRefOid`). If GitHub rejects an anchor (e.g., line not in diff hunk), adapt with judgment — re-target the comment or inform the user. Do not fail the whole review.

### Option 2 — Post all and submit the review

Create comments and submit the review with event type `COMMENT`. Same anchor/adapt rules as Option 1.

### Option 3 — Direct Fix Flow

Handles both "fix everything directly" and mixed "some fixes, some comments" cases.

1. **Ask which issues to fix directly.** Example: "Which issues should I fix directly? You can also pull items from the Dismissed list if you want them included."
2. **Make the fixes locally.** Do NOT commit or push yet. Let the user review the changes first.
3. **Summarize what changed.** Present a concise bulleted summary per issue so the user can review before committing.
4. **Wait for approval.** The user reviews and either approves, asks for adjustments, or iterates.
5. **On approval, commit, push, and announce.** Use a commit message matching the repo's style from `git log --oneline -20`. After pushing, post an announce comment on the PR (see "Direct Fix Announce Comment" below).
6. **Any remaining issues stay as comments.** If the user wanted a mixed approach — some issues fixed directly, some left as comments — post the remaining issues as pending review comments in the same pass (Option 1 behavior). The Direct Fix Announce Comment is separate from these inline comments.

### Option 4 — Let me adjust

Free-form. The user tells Claude what to change about the review.

## Direct Fix Announce Comment

When changes are pushed directly as part of Option 3, post a top-level PR comment (not a review comment) that announces the fixes to the author. Use `gh pr comment {number} --body-file -` with a heredoc.

**Structure:**

1. **Opening line** — announces direct push with the short commit SHA (`git rev-parse --short HEAD`). Example: "Pushed some changes directly in `abc1234`."
2. **Bulleted summary** — concise but comprehensive. One bullet per fix. Match the tone of the summary Claude showed the user for approval.
3. **Closing line** — varied, not robotic. Rotate through alternatives so consecutive PRs don't all end the same way.

**Closing line alternatives** (rotate — never pick the same one twice in a row):

- "Let me know if anything didn't land right — happy to iterate or revert."
- "Let me know what you think. Happy to tweak or roll back if needed."
- "Ping me if any of these missed the mark — easy to adjust or revert."
- "Let me know if these aren't quite right. Happy to keep iterating."
- "Give them a look and let me know — happy to revise or revert if they're off."

**Tone rules** (same as review comments):

- First person, as if the user is speaking — not Claude.
- Straightforward but not cold.
- Don't be overly apologetic.

## Re-review Flow

Triggered by natural language: "re-review", "review again", "author made changes", etc. Claude recognizes a re-review because the conversation already contains the previous issue list.

**Step 1 — Pull latest.** Pull down the author's changes so the local worktree matches the current PR state.

**Step 2 — Parallel re-review.** Same parallel pattern — Codex in background, Claude simultaneously. Both check:

- Which previously flagged issues were addressed
- Which remain unresolved
- Any new concerns introduced by the changes

Include the previous issue list and **Dismissed** section in the Codex prompt so it doesn't resurface rejected nits.

**Step 3 — Synthesize.** Produce a categorized breakdown:

- **Addressed** — issues the author fixed
- **Unresolved** — issues that remain
- **New** — new concerns found
- **Dismissed** — carried forward, updated only if needed

**Step 4 — Present and prompt.**

```
Re-review complete. Issues X, Y addressed. Issue Z unresolved. New issue N found.

1. Post new comments + resolve addressed threads
2. Post new comments only (I'll resolve threads manually)
3. Let me adjust (tell me what to change)
```

**Step 5 — Post and resolve.** Based on the user's choice:

- Post new/unresolved comments via `gh api`
- To resolve addressed threads: fetch existing review comments (`gh api repos/{owner}/{repo}/pulls/{pr}/comments`), map issues to GitHub thread IDs, then resolve via GraphQL `resolveReviewThread` mutation
- If thread mapping is ambiguous, ask the user before resolving

This loop repeats until the PR is clean or the user approves it.

## GitHub Comment Tone

When posting comments, write them as if the user is speaking — first person, not Claude:

- Straightforward but not cold. Concise but comprehensive.
- Inquisitive, humble, and unassuming. Pose a question first — seeking clarity, not making demands.
- Don't be overly apologetic. Assume the reviewer doesn't have the same context as the author.
- When a fix is straightforward, include a concrete suggestion or code snippet.
- When it's a design question, just raise the concern.
