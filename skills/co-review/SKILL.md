---
name: co-review
description: Use when reviewing a pull request with agentic peer review before posting GitHub comments
---

# co-review

Automate agentic peer review of a pull request. Claude and Codex review the PR diff in parallel, Claude synthesizes both reviews into a single issue list, posts pending GitHub comments, and handles re-reviews when the author pushes changes.

**Do not use this skill to approve, request changes, or merge the PR.**

## Preconditions

- If the user provided a PR number or URL (e.g., `/co-review 2369`), use it.
- Otherwise run `gh pr view --json number` to infer from the current branch.
- If `gh pr view` fails (common for fork PRs), get the current branch name and try `gh pr list --head "owner:branch" --json number` — replace the **first** `/` in the branch name with `:` to form the fork-qualified head ref (e.g., branch `michaelsthr/fix/outdated-expo-package` → `--head "michaelsthr:fix/outdated-expo-package"`).
- If no PR can be determined, ask the user for the number and stop.

## Review prompt

Read [review-prompt.md](review-prompt.md) from this skill's directory (not repo cwd). Both Claude and Codex use this same prompt. Replace `{PR_NUMBER}` with the actual PR number before use.

## Initial review flow

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

**Capture the session ID** from Codex's output (`session id: <uuid>`) — needed if the user runs a re-review later.

While Codex runs, Claude reviews the diff simultaneously using the same prompt and `gh pr diff {number}`. True parallel — do not wait for Codex before starting Claude's review.

If Codex fails (non-zero exit, empty response, timeout), continue with Claude's review alone and tell the user Codex errored. Codex is additive — Claude's review stands on its own.

**Step 3 — Synthesize.** Once Codex finishes, merge both reviews:

- Deduplicate overlapping findings
- Apply Claude's judgment — reject overkill, out-of-scope, and low-value pedantry
- **Do not dismiss touched-file diagnostics as "pre-existing."** Diagnostics, LSP output, or linter warnings in changed files or their direct ripple are actionable regardless of whether they predate the diff. Pre-existence alone is not grounds for rejection. If a diagnostic is kept (e.g., framework-required signature, false positive), either surface it to the user with the rationale or apply an intentional suppression/rename — do not silently drop it into `Dismissed`.
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

**Always write the full JSON payload to a temp file and use `--input`, not `--field`, for review submissions.** The `--field` flag treats nested arrays/objects (like `comments`) as strings, causing 422 errors. Example:

```bash
cat <<'REVIEW_JSON' > /tmp/review-payload.json
{ "commit_id": "<sha>", "comments": [{ "path": "...", "line": 1, "side": "RIGHT", "body": "..." }] }
REVIEW_JSON
gh api repos/{owner}/{repo}/pulls/{pr}/reviews --input /tmp/review-payload.json
```

Build comment anchors from the current diff and head SHA (`gh pr view --json headRefOid`). If GitHub rejects an anchor (e.g., line not in diff hunk), adapt with judgment — re-target the comment or inform the user. Do not fail the whole review.

### Option 2 — Post all and submit the review

Create comments and submit the review with event type `COMMENT`. Same `--input` file approach and anchor/adapt rules as Option 1.

### Option 3 — Direct fix flow

Handles both "fix everything directly" and mixed "some fixes, some comments" cases.

**Don't dismiss diagnostics as "pre-existing."** If diagnostics, LSP output, or linter warnings surface in changed files or their direct ripple — unused code, type errors, deprecated APIs, etc. — treat them as actionable alongside the accepted findings. Either fix them in the same pass or surface them for the user's call. Pre-existence alone is not grounds for dismissal.

1. **Ask which issues to fix directly.** Example: "Which issues should I fix directly? You can also pull items from the Dismissed list if you want them included."
2. **Make the fixes locally.** Do NOT commit or push yet. Let the user review the changes first.
3. **Summarize what changed.** Present a concise bulleted summary per issue so the user can review before committing.
4. **Wait for approval.** The user reviews and either approves, asks for adjustments, or iterates.
5. **On approval, commit, push, and announce.** Use a commit message matching the repo's style from `git log --oneline -20`. After pushing, post an announce comment on the PR (see "Direct fix announce comment" below).
6. **Any remaining issues stay as comments.** If the user wanted a mixed approach — some issues fixed directly, some left as comments — post the remaining issues as pending review comments in the same pass (Option 1 behavior). The Direct fix announce comment is separate from these inline comments.

### Option 4 — Let me adjust

Free-form. The user tells Claude what to change about the review.

## Direct fix announce comment

When changes are pushed directly as part of Option 3, post a top-level PR comment (not a review comment) that announces the fixes to the author. Use `gh pr comment {number} --body-file -` with a heredoc:

```bash
gh pr comment {number} --body-file - <<'ANNOUNCE_EOF'
Pushed some changes directly in abc1234.

- Tightened the foo handling in bar.ts
- Dropped the unused baz import
ANNOUNCE_EOF
```

**The body is raw markdown, rendered as-is — do NOT pipe JSON into `--body-file -`.** The JSON-to-file `--input` pattern shown in Option 1 is specific to `gh api` review-submission calls, which expect a JSON payload. `gh pr comment` takes the raw body; piping JSON will post the literal JSON text as the comment.

**Structure:**

1. **Opening line** — announces direct push with the short commit SHA (`git rev-parse --short HEAD`). Use plain text for the hash — not code backticks — so GitHub renders it as a clickable link to the commit. Example: "Pushed some changes directly in abc1234."
2. **Bulleted summary** — concise but comprehensive. One bullet per fix. Match the tone of the summary Claude showed the user for approval.
3. **Closing line** — optional. Acknowledges the author has context you don't and invites pushback without apology. Often the bullets stand on their own; no closing at all is a valid, useful choice — silence can be the most effective way to keep every PR from ending the same way.

**Writing the closing line:**

The sentiment to convey: you jumped in proactively to save the author a round-trip, but they own the code and the context. Nothing pushed is sacred — overrule, adjust, or revert freely.

Write it fresh each time. Vary length, shape, and register based on what fits. Short imperatives, self-aware asides, and context-acknowledging sentences all work. Omitting it entirely also works.

For reference only — these show the range of acceptable register. Do **not** pick from this list, and do **not** reuse verbatim:

- "Let me know if I got any of these wrong."
- "You're the expert here, but these caught my eye. Feel free to undo or adjust."
- "Change anything that feels off."

**Avoid:**

- "Happy to iterate/tweak/revise/roll back" — customer-service register; centers you instead of the author.
- Always pairing "adjust" with "revert" — becomes its own tell.
- Ending every PR with a closing line. Silence breaks the pattern.

**Tone rules** (same as review comments):

- First person, as if the user is speaking — not Claude.
- Straightforward but not cold.
- Don't be overly apologetic.

## Re-review flow

Triggered by natural language: "re-review", "review again", "author made changes", etc. Claude recognizes a re-review because the conversation already contains the previous issue list.

**Step 1 — Pull latest.** Pull down the author's changes so the local worktree matches the current PR state.

**Step 2 — Parallel re-review.** Same parallel pattern — Codex in background, Claude simultaneously. **Codex uses `codex exec resume <session_id>` with the session ID captured from the initial review**, so it already has the previous findings and Dismissed list in context:

```bash
cat <<'CO_REVIEW_EOF' | codex exec resume <session_id> --dangerously-bypass-approvals-and-sandbox -
Re-review PR #{number}. The author has pushed changes. Check which previously flagged issues were addressed, which remain unresolved, and whether any new concerns were introduced.

Previously dismissed items (do not resurface):
[DISMISSED LIST]
CO_REVIEW_EOF
```

If the session ID from the initial review isn't available (e.g., the user is starting fresh from a different session), fall back to a new `codex exec` call and append the previous findings and Dismissed list as text — but prefer resume when possible.

Both check:

- Which previously flagged issues were addressed
- Which remain unresolved
- Any new concerns introduced by the changes

**Step 3 — Synthesize.** Produce a categorized breakdown:

- **Addressed** — issues the author fixed
- **Unresolved** — issues that remain
- **New** — new concerns found
- **Dismissed** — carried forward, updated only if needed

**Proactively flag confidence** on each unresolved and new issue, same as initial review — `[Direct fix ready]` or `[Needs author input]`.

**Step 4 — Present and prompt.**

```
Re-review complete. Issues X, Y addressed. Issue Z unresolved. New issue N found.

1. Post new comments + resolve addressed threads
2. Post new comments only (I'll resolve threads manually)
3. Make direct fixes (optionally mixed with comments)
4. Let me adjust (tell me what to change)
```

**Step 5 — Act on the choice.**

### Option 1 — Post new comments + resolve addressed threads

- Post new/unresolved comments via `gh api` (same `--input` file approach as initial review)
- To resolve addressed threads: fetch existing review comments (`gh api repos/{owner}/{repo}/pulls/{pr}/comments`), map issues to GitHub thread IDs, then resolve via GraphQL `resolveReviewThread` mutation
- If thread mapping is ambiguous, ask the user before resolving

### Option 2 — Post new comments only

Same as Option 1 but skip thread resolution. User will resolve threads manually on GitHub.

### Option 3 — Direct fix flow

Same flow as initial review (see "Direct fix flow" under Initial review flow). Fix locally → show summary → wait for approval → commit/push/announce. The announce comment uses the same template and varied closings.

If the user wants a mixed approach (some direct fixes, some comments on remaining issues), post the remaining issues as new inline comments in the same pass. Thread resolution for addressed issues follows the same rules as Option 1.

### Option 4 — Let me adjust

Free-form. The user tells Claude what to change.

This loop repeats until the PR is clean or the user approves it.

## GitHub suggested changes

When a comment is marked `[Direct fix ready]` and the fix is a small, self-contained code change, use GitHub's suggestion syntax so the author can apply it with one click. Wrap the replacement code in a suggestion block inside the comment body:

````
```suggestion
<replacement lines>
```
````

**Rules:**

- The suggestion replaces the exact lines covered by the comment's line range. If the comment targets a single line, the suggestion replaces that one line. If it targets a multi-line range (`start_line` to `line`), the suggestion replaces that entire range.
- Preserve the original indentation exactly.
- Only use suggestions for concrete, unambiguous fixes — not for design questions or alternatives that need discussion.
- If the fix spans lines outside the comment's anchor range, don't force a suggestion — use a regular code snippet instead and explain what to change.

## Composing comments

Before building the review payload, group findings by anchor:

- **One comment per code location.** If multiple findings apply to the same line or range, merge them into a single comment with a numbered or bulleted list. Do not stack multiple comments on the same anchor.
- **One suggestion block per comment.** Combine multiple fixes into a single block that resolves everything at once.
- **For the same issue across files, write the reasoning once and reference it in the others** — e.g., "Same `foo` thoughts as the other comment." Don't rewrite the full justification in each file.

## GitHub comment tone

When posting comments, write them as if the user is speaking — first person, not Claude:

- **Lead with the observation.** No scene-setting ("On a reference page that's literally defining `someFunction`…"), no softening openers ("Small thing —", "Nit -", "Separately —", "Let's match:"), no restating the PR's goal back to the author. If the suggestion block already shows the fix, the body is the reason + the question — nothing else.
- **Ask one direct question.** The question itself is the softener — don't stack another on top. A grounded "Maybe X?" or "Would Y work better?" beats a statement with a trailing "— wdyt?".
- **Straightforward but not cold.** Don't be overly apologetic. Assume the reviewer doesn't have the same context as the author.
- **Inquisitive, not demanding.** Raise the concern, offer the alternative, let the author decide.
- When a fix is straightforward, use a GitHub suggestion block (see above) so the author can apply it directly.
- When it's a design question, just raise the concern.

**Before/after — verbose to tight:**

> Verbose: "On a reference page that's literally defining `someFunction`, the anchor text `this function` still leans on the preceding sentence to make sense. Naming it explicitly would match the PR's goal more cleanly — wdyt?"
>
> Tight: "`this function` still leans on the preceding sentence to make sense. Maybe make it explicit?"

The tight version drops scene-setting the author already has, drops justification the suggestion block already implies, and swaps "— wdyt?" for a grounded question. Roughly 70% shorter, same information.
