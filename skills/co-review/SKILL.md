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

**Step 4 — Present and prompt.**

```
Review complete. N issues found.

1. Post all as pending review comments
2. Post all and submit the review
3. Let me adjust (tell me what to change)
```

Do not post anything until the user chooses.

**Step 5 — Post comments.** Based on the user's choice:

- Option 1: create pending review comments via `gh api`
- Option 2: create comments and submit the review with event type `COMMENT`
- Build comment anchors from the current diff and head SHA (`gh pr view --json headRefOid`)
- If GitHub rejects an anchor (e.g., line not in diff hunk), adapt with judgment — re-target the comment or inform the user. Do not fail the whole review.

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
