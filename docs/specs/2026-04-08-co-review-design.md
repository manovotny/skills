# co-review Skill Design Spec

## Overview

A Claude Code skill (`/co-review`) that automates agentic peer review of pull requests. Claude and Codex review the PR diff in parallel, Claude synthesizes both reviews into a single issue list, posts pending GitHub comments, and handles re-reviews when the author pushes changes.

Second skill in the `co-` prefix collection, alongside `/co-plan`.

## Scope

- **In scope:** PR detection, parallel review (Claude + Codex), synthesis, GitHub comment posting, re-review lifecycle, symlinked repo verification
- **Out of scope:** Submitting the final review approval (user does this on GitHub), CI/CD checks, merge decisions

## Skill Identity

```yaml
name: co-review
description: Use when reviewing a pull request with agentic peer review before posting GitHub comments
```

- **Installed to:** `~/.claude/skills/co-review/SKILL.md` (Claude-only)
- **Trigger:** `/co-review` (auto-detects PR from current branch) or `/co-review 2369` (explicit PR number)
- **Precondition:** Must be in a git repo with a PR-associated branch. If no PR is detected and none provided, ask the user for the PR number.

## Architecture

Two-file skill:
- **`SKILL.md`** — orchestration: parallel review, Codex invocation, synthesis, GitHub comment posting, re-review handling, multi-choice prompts
- **`review-prompt.md`** — the review prompt template used by both Claude and Codex. Resolved relative to the skill directory (not repo cwd). Separated because it's the part most likely to evolve.

## File Structure

```
enshrined-flavor/
  skills/
    co-plan/
      SKILL.md
    co-review/
      SKILL.md
      review-prompt.md
  docs/
    specs/
      ...
  README.md
```

Installation: symlink or copy `skills/co-review/` to `~/.claude/skills/co-review/`.

## Initial Review Flow

### Step 1 — Detect PR

If no PR number provided, run `gh pr view --json number` to infer from the current branch. If that fails, ask the user for the PR number and exit.

### Step 2 — Pre-review

Read context before reviewing:
- `gh pr view {number}` for title, description, linked PRs
- Follow any linked PRs or repos referenced in the description
- Find and read any CLAUDE.md or AGENTS.md files
- Check for symlinked repositories in the workspace — use them to verify code examples, API references, and technical details

### Step 3 — Parallel review

Kick off Codex in the background (`run_in_background: true`, timeout 600000ms) with the review prompt from `review-prompt.md`. Claude reviews the diff simultaneously using the same prompt. Both use `gh pr diff {number}`.

This is the `Promise.all` — true parallel execution. Claude always finishes first and waits for Codex.

### Step 4 — Synthesize

Once Codex finishes, merge both reviews:
- Deduplicate overlapping findings
- Apply Claude's judgment — reject overkill or out-of-scope feedback, keep what's substantive
- Add rejected items to a **Dismissed** section with brief rationale for each
- Produce a single numbered issue list in the standard format (title, file, lines, severity, code, issue, solutions)

### Step 5 — Present and prompt

```
Review complete. 7 issues found.

1. Post all as pending review comments
2. Post all and submit the review
3. Let me adjust (tell me what to change)
```

### Step 6 — Post comments

Based on user's choice, use `gh api` to create pending review comments or submit the review. "Submit" uses the `COMMENT` event type — the user handles approval or request-changes themselves. Claude handles the API call directly, adapting to errors (e.g., line not in diff hunk due to new changes) with judgment rather than failing.

## Re-review Flow

Triggered by natural language: "re-review", "review again", "author made changes", etc. Claude recognizes a re-review because the conversation already contains the previous issue list.

### Step 1 — Pull latest

Pull down the author's changes to get the updated code locally.

### Step 2 — Parallel re-review

Same parallel pattern as initial review — Codex in background, Claude simultaneously. Both review the updated diff, checking:
- Which previously flagged issues were addressed
- Which remain unresolved
- Any new concerns introduced by the changes
- The **Dismissed** list is included in the Codex prompt so it doesn't resurface rejected nits

### Step 3 — Synthesize

Produce a categorized breakdown:
- **Addressed** — issues the author fixed
- **Unresolved** — issues that remain
- **New** — new concerns found in the updated changes
- **Dismissed** — carried forward, updated if needed

### Step 4 — Present and prompt

```
Re-review complete. Issues 1, 3, 5 addressed. Issue 2 unresolved. New issue 8 found.

1. Post new comments + resolve addressed threads
2. Post new comments only (I'll resolve threads manually)
3. Let me adjust (tell me what to change)
```

### Step 5 — Post/resolve

Based on choice, post new comments and optionally resolve addressed threads via the GitHub API. To resolve threads, Claude fetches existing review comments (`gh api repos/{owner}/{repo}/pulls/{pr}/comments`) to map issues to GitHub thread IDs before calling the GraphQL `resolveReviewThread` mutation.

This loop repeats until the PR is clean or the user approves it.

## Codex Invocation Details

- **Command:** `codex exec --dangerously-bypass-approvals-and-sandbox` via stdin heredoc with `CO_REVIEW_EOF` delimiter
- **Timeout:** 600000ms (10 minutes). Codex is slow, especially on initial review.
- **Working directory:** Current directory (Superset worktree)
- **Model and reasoning:** Inherited from `~/.codex/config.toml` (currently gpt-5.4, reasoning high). No CLI flags needed.
- **Background execution:** Uses `run_in_background: true` so Claude can review in parallel.
- **Error handling:** If Codex fails, Claude continues with its own review alone and tells the user Codex errored. Unlike co-plan where the loop stops on error, here Codex is supplementary — Claude's review stands on its own.

## The Review Prompt (review-prompt.md)

The review prompt is used by both Claude and Codex. It covers:

1. **Pre-review** — read PR context via `gh pr view`, follow linked PRs/repos, read project-specific context files (CLAUDE.md, AGENTS.md)
2. **Symlinked repos** — check for symlinked repositories in the workspace and use them to verify code examples, API references, and technical details
3. **Review criteria:**
   - Logic and correctness — bugs, edge cases, technical accuracy, simpler alternatives
   - Readability — clarity, maintainability, repository best practices
   - Performance — obvious concerns, parallelizable fetches, loop optimizations
   - Test coverage — adequate tests for changes (skip for docs-only changes)
   - Content — code blocks in content reviewed as code, content flow, hierarchy, typos, ambiguity, verbosity
4. **Review style** — flag uncertainty explicitly rather than asking clarifying questions (Codex runs in non-interactive exec mode), don't be overly pedantic, nits only if relevant
5. **Output format** — summary of general code quality, then numbered issue list with: title, file, lines, severity (bug/suggestion/nit), code snippet, issue summary, potential solutions

## Not Planned

- **Automated PR approval/merge:** The user decides when to approve and merge. The skill only posts comments and optionally submits the review.
- **CI/CD integration:** The skill reviews code, not build/test status.
- **Codex model/reasoning overrides:** Inherited from config. Users who want different settings change their `~/.codex/config.toml`.
- **Shell script for GitHub API calls:** The `gh api` call requires judgment when it fails (line not in diff hunk, etc.). Keeping it in Claude's control allows adaptive error handling.
- **Shared installation with Codex agents:** Claude-only skill — Codex is invoked as a peer reviewer, not running the skill itself.
- **State persistence between sessions:** Re-review context lives in the conversation. If you start a new session, invoke `/co-review` fresh.

## Dismissed (Codex Review Feedback)

- **Durable anchor model for comment posting:** Claude already constructs `path`, `commit_id`, and line metadata from the diff and `gh pr view --json headRefOid` at posting time. When lines shift, Claude sees the API error and adapts. This is the judgment-based approach we intentionally chose over a rigid script.
- **Incremental diff tracking via headRefOid:** Claude has the previous issue list in conversation context and checks whether each issue still exists in the current full diff. Judgment-based comparison works — no need to track and diff commit SHAs.
- **Cross-repo PR resolution:** The user is always in a Superset worktree checked out from the PR. `gh pr view` works because the remote is already configured. Cross-repo is not a real scenario.
- **Dirty worktree safety checks for pull:** Superset creates clean worktrees per PR. Dirty state isn't a realistic concern, and Claude can handle a failed `git pull` if it somehow happens.
- **Hop limits for linked resource discovery:** "Follow linked PRs" means read links in the PR description — bounded by what the author wrote. Claude already does this sensibly without spiraling.
