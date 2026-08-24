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

## Orient to the PR branch

Once the PR is known, get the session's **current working directory** onto that PR's branch — so the diff, the app's Files panel, and any push target all match the PR. **Run every `gh`, `git commit`, and `git push` from this directory** — it's the checkout on the PR branch and the one the app is watching. The failure to avoid is moving your working position to a *different checkout of the repo* (a sibling clone or separate worktree) to run the review or land fixes — that checks the PR branch out where the app isn't looking and pushes from where the user can't see. Editing files that physically live elsewhere (symlinked into the project, sibling packages in a monorepo) is fine: that's file location, not your working position.

1. **Already on the PR's branch?** A question of *identity*, not currency: does `git branch --show-current` match the PR's head branch (for fork PRs whose local branch is renamed, fall back to `git rev-parse HEAD` vs the PR's `headRefOid`)? If yes, you're oriented — **no branch switch happens, so the guards below don't apply**. Being behind a freshly-pushed head isn't a switch either; `gh pr checkout {number}` just fast-forwards. A session already on the branch and current is a true no-op.
2. **Otherwise — you're on a *different* branch — a switch is needed, and these guards apply to it:**
   - **Clean tree, branch free** → `gh pr checkout {number}` to move this directory onto the PR branch.
   - **Dirty tree** → stop and ask first. Git will happily carry uncommitted changes onto the PR branch, dragging unrelated work into the review; confirm with the user rather than switching under them.
   - **Branch already checked out in another worktree/clone sharing this `.git`** → `gh pr checkout` fails and git names where the branch lives. Surface that and stop; do **not** relocate the user's other checkout to free the branch.

**Orientation is point-in-time, not durable.** If this directory is a repo's primary checkout that other agent sessions or scripts also operate in (session worktrees hanging off it in `git worktree list` are the tell), a parallel session can move HEAD between your orientation and a later commit. Re-run the step-1 identity check immediately before any `git commit` or `git push` — direct fixes (Option 3) and re-review fixes included; on a mismatch, stop and re-orient rather than committing onto whatever branch was left checked out.

Review-only (posting comments) runs off `gh pr diff` regardless of branch, but orienting up front is what makes the review step's premise that *the changes already exist locally* actually hold — the Files panel and any local file you open around the diff reflect the PR, not main — and lets direct fixes (Option 3) land without a mid-flow scramble.

## Review prompt

Read [review-prompt.md](review-prompt.md) from this skill's directory (not repo cwd). Both Claude and Codex use this same prompt. Replace `{PR_NUMBER}` with the actual PR number before use.

## Initial review flow

Announce: **"Starting parallel review of PR #{number}."**

**Step 1 — Pre-review.** Before touching the diff, gather context. The **authoritative checklist is review-prompt.md's "Pre-review" section** (Claude and Codex share it) — follow it there rather than relying on a separate list here. In brief:

- `gh pr view {number}` for title, description, and linked references; follow linked PRs/repos
- Project context files — CLAUDE.md, AGENTS.md, CONTRIBUTING*, STYLEGUIDE*, GUIDELINES* (following one-hop `@`/pointer imports), plus any guidance co-located with or in an ancestor directory of the changed files (the nearest one governs that file — repo-root scans miss a `GUIDELINES.md` sitting next to the content it governs)
- Authoritative sources — enumerate what this PR's claims depend on (upstream/sibling repos, dependency package sources, vendored code, API/spec definitions, generated artifacts; reachable via symlink, local clone, or installed package), note which are reachable versus missing, and ask the user for missing ones that block real verification
- Existing PR threads — bot reviewer comments (CodeRabbit, Cursor's Bugbot, the ChatGPT/Codex connector, Macroscope, …) enter the review as candidate findings to judge, never to blindly accept
- CI status (`gh pr checks {number} --json name,state,bucket,link,description,workflow`) and base staleness (`gh pr view {number} --json mergeStateStatus` → `BEHIND`) — failing checks and staleness are findings, not just context

**Step 2 — Parallel review.** Kick off Codex in the background with `run_in_background: true` and a timeout of `600000` ms:

```bash
cat <<'CO_REVIEW_EOF' | codex exec --dangerously-bypass-approvals-and-sandbox -
[REVIEW PROMPT WITH PR NUMBER FILLED IN]
CO_REVIEW_EOF
```

**Capture the session ID** from Codex's output (`session id: <uuid>`) — needed if the user runs a re-review later.

While Codex runs, Claude reviews the diff simultaneously using the same prompt and `gh pr diff {number}`. True parallel — do not wait for Codex before starting Claude's review.

**Do not poll for Codex's status with sleep/cat loops.** Background tasks notify you on completion automatically — the Bash tool will reject leading `sleep` commands (e.g., `sleep 30 && cat .../output | tail -80`). Launch Codex, do Claude's review in the meantime, and only read the background task's output once you receive the completion notification. If you genuinely need to watch a condition, use the `Monitor` tool with an `until` loop, never chained sleeps.

If Codex fails (non-zero exit, empty response, timeout), continue with Claude's review alone and tell the user Codex errored. Codex is additive — Claude's review stands on its own.

**Step 3 — Synthesize.** Once Codex finishes, merge both reviews:

- Deduplicate overlapping findings
- Apply Claude's judgment — reject overkill, out-of-scope, and low-value pedantry
- **Do not dismiss touched-file diagnostics as "pre-existing."** Diagnostics, LSP output, or linter warnings in changed files or their direct ripple are actionable regardless of whether they predate the diff. Pre-existence alone is not grounds for rejection. If a diagnostic is kept (e.g., framework-required signature, false positive), either surface it to the user with the rationale or apply an intentional suppression/rename — do not silently drop it into `Dismissed`.
- **Fold in CI failures and staleness as repo-level findings.** Treat failing/errored CI checks as findings at the severity the failure warrants (flag obvious infra/flake as such, not as a code bug). If Claude and Codex report the same CI failure, list it once. A `BEHIND`/stale base is its own finding; recommend `/co-merge`. These have no file anchor — mark them repo-level so posting routes them correctly (see Option 1). They come from reading check status, not from running builds locally.
- **Fold in bot reviewer comments.** A bot-raised finding that survives judgment joins the issue list carrying its `Bot thread` or `Bot top-level` reference — posting routes on that field instead of stacking a duplicate comment on the same anchor. If Claude or Codex independently found the same issue, merge them; the bot comment wins the anchor. Skipped ones go to **Dismissed** with rationale — every triaged bot comment gets an answer once the user picks a posting option (see "Bot reviewer thread replies").
- **Reviewer proposals are not requirements.** A broader guarantee or adjacent hardening that Claude or Codex proposes is not an acceptance criterion unless the user or an existing repo contract requires it — raise it as a `suggestion` and let the author decide. In re-reviews, judge findings against the PR's original scope, not against proposals from earlier rounds; an unadopted proposal doesn't become "unresolved" by being repeated.
- Add rejected items to a **Dismissed** section with brief rationale for each
- Produce a single numbered issue list in the format from review-prompt.md
- **Proactively flag confidence for each issue.** For every issue, decide whether Claude has a clear fix or whether it's better raised as a comment/question for the author. Mark each issue visibly (e.g., `[Direct fix ready]`, `[Needs author input]`, or `[Unverifiable — needs access to <source>]` for an objective claim blocked on a missing authoritative source). The user shouldn't have to ask.
- **Synthesis gate — verify or request, don't punt.** No finding may be marked `[Needs author input]` or left as flagged uncertainty on an objectively-checkable fact when an authoritative source is reachable or could be requested. If the source is reachable, verify against it. If it's missing, request it and mark the item `[Unverifiable — needs access to <source>]` so it stays visible instead of silently becoming an author question. Only genuinely intent- or scope-dependent items belong in `[Needs author input]`.

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

**Re-read `headRefOid` immediately before posting, not at review time.** Minutes or hours pass while the review is presented and the user decides; the author may push in that window, leaving the anchors built against a stale diff. If the head moved, stop and tell the user — the right move is usually the re-review flow against the new commits, not posting comments on code that already changed. Same post-time guard bot threads get.

**Repo-level findings (CI failures, base staleness) have no diff anchor — never force them onto a line.** When submitting a review (Option 2), put them in the review `body`. When leaving the review pending (Option 1, no event), post them as a single top-level PR comment via `gh pr comment {number} --body-file -` so they're visible without a submitted review. Group all repo-level findings into one comment; keep inline findings inline.

### Option 2 — Post all and submit the review

Create comments and submit the review with event type `COMMENT`. Same `--input` file approach and anchor/adapt rules as Option 1. Repo-level findings (CI failures, base staleness) go in the review `body`, not inline comments.

### Option 3 — Direct fix flow

Handles both "fix everything directly" and mixed "some fixes, some comments" cases.

**Don't dismiss diagnostics as "pre-existing."** If diagnostics, LSP output, or linter warnings surface in changed files or their direct ripple — unused code, type errors, deprecated APIs, etc. — treat them as actionable alongside the accepted findings. Either fix them in the same pass or surface them for the user's call. Pre-existence alone is not grounds for dismissal.

1. **Ask which issues to fix directly.** Example: "Which issues should I fix directly? You can also pull items from the Dismissed list if you want them included."
2. **Make the fixes locally.** Do NOT commit or push yet. Let the user review the changes first.
3. **Verify the fixes before showing them.** These are changes you authored and will push, so confirm they hold up — don't claim merge-ready on faith. Run the repo's fast checks on the change — **formatter, linter, type check, and tests** — when they're detectable and runnable. Detect the commands; never hardcode them. Prefer what CI runs (read CI config), then `package.json` scripts, `Makefile`/`justfile`, then the ecosystem's standard (`pyproject.toml`/`tox`/`ruff`, `cargo`, `go`, etc.).
   - **Run-when-runnable, report what you skip.** Format/lint/type check are fast and hermetic — run them whenever the toolchain is present. Tests may need infra/secrets or be slow — run them when runnable, otherwise skip. For anything you can't find or can't run, say exactly what and why; never guess a command, never silently skip.
   - **Scope auto-format to the files you changed; never reformat the tree.** Don't run a standalone formatter if formatting is already part of lint (e.g., the linter's `--fix`).
   - **Type check, not build.** Run the ecosystem's fast type/compile validation — `tsc --noEmit`, `cargo check`, `go build ./...`, etc. (in languages where compiling _is_ the type check, that compile step is the type check; static analyzers like `go vet` are lint, not the type check). Do **not** run the project's full `build`/bundle/codegen pipeline — it's the slow, side-effecting, env-specific one, and CI covers it on push.
   - If a check fails, fix it before continuing. In the chat summary (next step), name what actually ran ("format, lint, types, and tests pass locally") and what you skipped and why — don't assert a blanket "merge-ready" you didn't exercise. This recap is for the user only; it never goes in the announce comment.
4. **Summarize what changed.** Present a concise bulleted summary per issue so the user can review before committing.
5. **Wait for approval.** The user reviews and either approves, asks for adjustments, or iterates.
6. **On approval, commit, push, and announce.** Use a commit message matching the repo's style from `git log --oneline -20`. After pushing, post an announce comment on the PR (see "Direct fix announce comment" below).
7. **Any remaining issues stay as comments.** If the user wanted a mixed approach — some issues fixed directly, some left as comments — post the remaining issues as pending review comments in the same pass (Option 1 behavior). The Direct fix announce comment is separate from these inline comments.

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
2. **Bulleted summary** — concise but comprehensive. One bullet per fix. Match the tone of the summary Claude showed the user for approval, except verification status: typecheck/lint/format/test results never appear in the comment — not as a bullet, not as a trailing sentence. That recap belongs in the chat summary to the user; CI reports status on the PR.
3. **End of comment** — the comment ends after the last bullet. Include a closing line only when the user explicitly supplies or requests one; use their words.

**Tone rules** (same as review comments):

- First person, as if the user is speaking — not Claude.
- Straightforward but not cold.
- Don't be overly apologetic.
- Run it through the voice guide before posting, same as every comment this skill sends — read `voice.md`, apply the **PR & review comments** medium, and self-check the draft (see **GitHub comment tone**). Don't hand-apply from memory.

## Bot reviewer thread replies

Pre-review collects bot reviewer comments; synthesis gives each a verdict (in the issue list, or Dismissed). When the user picks a posting option, close the loop on every triaged bot comment in the same pass — one answer each:

- **Accepted + fixed directly (Option 3):** "Fixed in abc1234." — post after the push; plain-text hash so GitHub links the commit, same as the announce comment.
- **Accepted, left as a comment for the author (Options 1–2):** agree it's worth addressing, plus anything the thread is missing (a sharper fix, a caveat). If the bot already said it all, a one-line agreement is enough.
- **Dismissed:** the skip reason, brief and direct.

**Route by stream — the two id spaces are not interchangeable.** A `Bot thread` finding is an inline thread root; reply to its review comment id:

```bash
gh api repos/{owner}/{repo}/pulls/{pr}/comments/{review_comment_id}/replies -F body=@- <<'REPLY_EOF'
Fixed in abc1234.
REPLY_EOF
```

A `Bot top-level` finding has no reply thread, and an issue comment id sent to that endpoint fails. Those answers go in a PR-wide comment, and **any `Bot top-level` verdict guarantees one gets posted** — CI and staleness findings are not what earns it:

- Repo-level findings are already going out as a top-level comment (Option 1) → fold the bot answers into it.
- Otherwise → post one dedicated `gh pr comment` carrying them. This is the Option 2 case, where repo-level findings live in the submitted review body and bot answers can't ride along.
- Never append them to the direct-fix announce comment — that comment has a fixed structure (opening line, bullets, nothing after). Option 3 posts them separately.

Name the bot you're answering in each.

Replies post immediately — they cannot ride in a pending review — so they go out in the same pass as the user's chosen option, never before the choice.

**Re-check each thread immediately before posting, not at pre-review.** Minutes or hours pass while the review is presented and the user decides. Re-fetch, then skip any root that has since gained a human reply — that guard only holds if it's checked at post time.

**Dedupe on the revision, not the id.** The key is `(stream, id, updated_at)`, and each revision gets answered at most once. A bot that revises a summary in place keeps its id, so a changed `updated_at` makes it a candidate again — triage it, and answer only what's new or changed since the revision you already answered, not the whole comment over. An unchanged revision is already answered and stays untouched. Tone rules and voice are the same as review comments.

## Re-review flow

Triggered by natural language: "re-review", "review again", "author made changes", etc. Claude recognizes a re-review because the conversation already contains the previous issue list.

**Step 1 — Pull latest and re-validate.** Pull down the author's changes so the local worktree matches the current PR state. Then re-read CI status (`gh pr checks`) and re-check staleness (`gh pr view --json mergeStateStatus`) against the base — the author may have fixed checks, broken others, or the base may have moved again. If you make direct fixes during this re-review, verify them with the same checks as Option 3 ("Verify the fixes before showing them") before committing.

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
- Any bot reviewer comment whose `(stream, id, updated_at)` revision hasn't been answered yet — new comments and in-place revisions both qualify — triaged and answered per "Bot reviewer thread replies"; unchanged revisions stay untouched

**Step 3 — Synthesize.** Produce a categorized breakdown:

- **Addressed** — issues the author fixed
- **Unresolved** — issues that remain
- **New** — new concerns found
- **Dismissed** — carried forward, updated only if needed

**Proactively flag confidence** on each unresolved and new issue, same as initial review — `[Direct fix ready]`, `[Needs author input]`, or `[Unverifiable — needs access to <source>]`. The synthesis gate still applies: verify objective claims against a reachable source, or request a missing one — don't punt them to the author.

**Step 4 — Present and prompt.**

```
Re-review complete. Issues X, Y addressed. Issue Z unresolved. New issue N found.

1. Post new comments + resolve addressed threads
2. Post new comments only (I'll resolve threads manually)
3. Make direct fixes (optionally mixed with comments)
4. Let me adjust (tell me what to change)
```

**Step 5 — Act on the choice.**

**Repo-level findings (a newly failing check or a `BEHIND` base) have no diff anchor.** Post them as a single top-level PR comment via `gh pr comment {number} --body-file -` — never anchor them to a line. This applies whichever option the user picks.

### Option 1 — Post new comments + resolve addressed threads

- Post new/unresolved comments via `gh api` (same `--input` file approach as initial review)
- To resolve addressed threads: fetch existing review comments (`gh api repos/{owner}/{repo}/pulls/{pr}/comments`), map issues to GitHub thread IDs, then resolve via GraphQL `resolveReviewThread` mutation
- If thread mapping is ambiguous, ask the user before resolving

### Option 2 — Post new comments only

Same as Option 1 but skip thread resolution. User will resolve threads manually on GitHub.

### Option 3 — Direct fix flow

Same flow as initial review (see "Direct fix flow" under Initial review flow). Fix locally → show summary → wait for approval → commit/push/announce. The announce comment uses the same template — no closing line.

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

Every comment this skill posts speaks as the user — review comments, thread replies, direct-fix announces, and bot-thread answers alike. So each one goes through the voice guide before it goes to GitHub, no exceptions:

1. **Read the guide, don't recall it.** `~/.claude/skills/co-write/voice.md`, resolved from that path — this skill runs from any repo. Medium is **PR & review comments**: apply Core voice, then that overlay, and re-read the overlay's canonical excerpts before writing; they set rhythm the rules can't. Reading it turns ago and drafting from memory is not applying it — that's exactly when a slang idiom, a punchy metaphor, or a Claude-ism slips in.
2. **Self-check right before posting.** Re-read the draft against the guide and fix what fails. Never post prose that would flunk `/co-write check`. When a phrase reaches for color the user wouldn't use, cut it and state the point plainly.

Then, writing as if the user is speaking — first person, not Claude:

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
