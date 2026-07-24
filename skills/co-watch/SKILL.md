---
name: co-watch
description: Use when watching a pull request after review — notify on new comments, re-review new commits, and clean up the worktree on merge/close
---

# co-watch

Watch a pull request after `/co-review` and keep the user informed without babysitting it. co-watch runs locally as a self-rescheduling heartbeat. On each tick it notifies on new comments/replies from others, re-runs `/co-review` when the author pushes commits, and cleans up the local worktree when the PR merges or closes.

**co-watch never writes to GitHub or commits anything unattended.** It observes, re-reviews locally, notifies, and cleans up the local worktree. Every GitHub write or commit stays gated behind a user decision via the normal co-review options.

## Invocation

```
/co-watch [interval] [PR]
```

- `interval` — optional, default `20m`. Accepts forms like `20m`, `30m`, `1h`. Convert to seconds for `ScheduleWakeup` (the runtime clamps to a 60m / 3600s max — if the user passes more, tell them it's capped at 60m).
- `PR` — optional. Resolve in this order:
  1. Explicit PR number/URL argument.
  2. The PR from the preceding `/co-review` in this session's context.
  3. The current branch: `gh pr view --json number`. If that fails (common for fork PRs), get the branch name and try `gh pr list --head "owner:branch"`, replacing the **first** `/` in the branch name with `:` (e.g., `michael/fix/thing` → `--head "michael:fix/thing"`).
  4. If none can be determined, ask the user and stop.

co-watch only watches a PR in the **current worktree's repo** — re-review pulls the PR's commits into this worktree and cleanup removes this worktree, neither of which makes sense for another repo. If an explicit PR number/URL resolves to a base repo other than the one `gh repo view` reports for this checkout, reject it and stop: *"co-watch watches a PR in this worktree's repo (`{ownerRepo}`); PR #X belongs to `<other-repo>`. Switch to that repo's checkout and run /co-watch there."*

## Preconditions

co-watch is meant to run **after `/co-review` in the same session**, so the Codex session ID, the prior issue list, and the Dismissed list are in context for re-reviews.

- If present, re-reviews use `codex exec resume <codexSessionId>` and carry the prior findings and Dismissed list forward.
- If absent (e.g., a fresh session), co-watch still works — re-review falls back to a cold `codex exec` like co-review does — but say so up front so the user knows re-reviews won't have prior context.

## Watch state

Persist a JSON state file at `<scratchpad>/co-watch-state.json` (the session scratchpad directory) so the watch survives context summarization. Fields:

- `watchId` — a generation token for this watch (e.g., `pr{number}-{short-sha}` captured at startup). Every tick checks it; see the generation guard.
- `pr` — PR number.
- `ownerRepo` — `owner/repo` of the current worktree's repo (`gh repo view --json owner,name --jq '.owner.login + "/" + .name'`). co-watch only watches a PR in the current worktree's repo (see Invocation), so every `gh` call resolves against this checkout; `ownerRepo` is used for the comment API paths.
- `interval` — the configured tick interval (e.g., `20m`).
- `worktreePath` — absolute path of the watched worktree (`git rev-parse --show-toplevel`).
- `codexSessionId` — captured from the preceding co-review, or null.
- `lastReviewedSha` — the head SHA the most recent review/re-review covered.
- `lastSeenIssueComment` — cursor `{ createdAt, id }` for the newest issue comment seen, or `null` if the stream has none.
- `lastSeenReviewComment` — cursor `{ createdAt, id }` for the newest review (inline) comment seen, or `null` if the stream has none.

An active watch is detected by this file existing with a non-empty `watchId`.

## Startup (first invocation)

1. Resolve the PR and interval (see Invocation).
2. **A state file already exists for this PR:**
   - **No interval passed** → treat it as a status query: report current state (PR, interval, `lastReviewedSha`, the two comment cursors) and stop. Do not start a second loop.
   - **Interval passed** → update `interval`, rotate `watchId` to a fresh value (this supersedes the prior wakeup via the generation guard), keep the existing `lastReviewedSha` and comment cursors, write state, and schedule the next tick. Do not re-baseline.
3. **A state file exists for a different PR** → tell the user a watch is already active on PR #X and ask whether to replace it. Only on confirmation, overwrite the state with a fresh `watchId` for the new PR (this supersedes the old loop via the generation guard).
4. **Otherwise initialize:** set a new `watchId`; capture `pr`, `ownerRepo`, `interval`, `worktreePath`, `codexSessionId`; baseline `lastReviewedSha` to the current `headRefOid`; baseline each comment cursor to the newest existing comment in that stream (`{ createdAt, id }`), or `null` if the stream has no comments — so only activity *after* startup is reported.
5. Write the state file, tell the user the watch started (PR + interval), and schedule the first tick with `ScheduleWakeup`. Convert the interval to seconds for the delay, and use a prompt that re-enters this skill and carries the generation token, e.g. *"Run the co-watch tick from `<scratchpad>/co-watch-state.json` (watchId=`<watchId>`)."*

## Tick logic

Each tick runs the **generation guard** first, then the checks below in order. Every non-terminal tick ends with the **scheduling step**.

**Generation guard.** Read the state file. If it is missing, or its `watchId` differs from the one carried in this wakeup's prompt, this loop has been superseded or stopped — exit silently and do not reschedule.

### 1. State check (always wins)

`gh pr view {pr} --json state,mergedAt`. If `MERGED` or `CLOSED` → run **Cleanup on merge/close**, push-notify, and **stop the loop** (do not reschedule).

### 2. New commits → re-review

Compare `gh pr view {pr} --json headRefOid` against `lastReviewedSha`. If it changed (and the new head is not a commit just pushed via a user-approved direct fix — see "Re-reviewing our own pushes"):

- Run **co-review's re-review flow through Step 3 only** — follow co-review's "Re-review flow": Step 1 pull latest so the worktree matches the PR and re-check CI + base staleness; Step 2 parallel Claude + Codex via `codex exec resume <codexSessionId>` (or a cold `codex exec` if no session ID); Step 3 synthesize the **Addressed / Unresolved / New / Dismissed** breakdown. **Stop after Step 3 — do not enter co-review's Step 4 (present options) or Step 5 (act on a choice);** the tick is unattended, so acting on findings stays gated behind a later explicit user choice. Do not reimplement review logic — delegate to co-review.
- **Only after synthesis completes**, update `lastReviewedSha` to the new head. If the tick fails before synthesis, leave `lastReviewedSha` unchanged so the next tick retries the same head.
- Push-notify either way:
  - **Findings present** → notify with the counts, surface the breakdown in-session, and keep ticking. Findings are pending in the conversation, not a loop-stopper. Do not post or fix anything — that stays gated behind the user's choice via the normal co-review options.
  - **Clean (no findings)** → notify "re-reviewed new commits, all clear" and keep ticking.
- **Superseding:** if findings from an earlier tick are still pending and newer commits arrive, recompute the breakdown from scratch against the new head and flag it explicitly: *"New commits arrived — previous findings are superseded by this re-review."*

### 3. New comments/replies → notify

- Fetch both streams paginated:
  - Issue comments: `gh api --paginate repos/{ownerRepo}/issues/{pr}/comments`
  - Review (inline) comments: `gh api --paginate repos/{ownerRepo}/pulls/{pr}/comments`
- In each stream, select comments newer than that stream's cursor (`lastSeenIssueComment` / `lastSeenReviewComment`) by `(created_at, id)` ordering: a comment is new when its `created_at` is later than the cursor's `createdAt`, **or** `created_at` equals `createdAt` **and** its `id` is **greater than** the cursor's `id` (a `null` cursor means every comment is new). The `id` tiebreak matters because one review submission posts several inline comments sharing the same `created_at`; GitHub comment ids increase with creation, so a larger id is newer.
- **Always advance each cursor** to the maximum fetched comment by `(created_at, id)` in that stream — including comments filtered out as the user's own — so the loop never re-processes them.
- For **notification**, drop comments authored by the user (`gh api user --jq .login`). If any remain → push-notify and print an in-session summary (author, file/line for review comments, a snippet, and the link).
- Non-blocking — continue to the scheduling step.

### 4. Nothing new

Continue to the scheduling step silently — no notification.

**Scheduling step (every non-terminal tick).** Persist the updated state file, then call `ScheduleWakeup` (interval → seconds) with a prompt that re-enters this skill and carries the current `watchId`, e.g. *"Run the co-watch tick from `<scratchpad>/co-watch-state.json` (watchId=`<watchId>`)."* The loop only stops via the state check (merge/close), the generation guard, or the user.

## Re-reviewing our own pushes

co-watch never commits or pushes on its own. The only way its worktree gains a commit is the user explicitly choosing co-review's direct-fix path and approving the commit/push. After such a user-approved push, advance `lastReviewedSha` to that commit so the next tick does not re-review work just authored and verified — the heartbeat then re-reviews only the *author's* commits.

## Cleanup on merge/close

When the state check sees `MERGED` or `CLOSED`, perform cleanup, then send **one** combined push notification for this terminal event (do not fire a separate push per sub-case). Stop the loop and do not reschedule.

1. **Detect position and find another checkout.** Resolve `worktreePath` and compare it to the session's `git rev-parse --show-toplevel`. If removal will need to run from outside the target, pick **any other worktree** of the same repo from `git worktree list --porcelain` (one whose path is not under `worktreePath`); if none is usable, fall back to instructing the user to run from any checkout of the same repo.
2. **Check the worktree is clean:** `git -C <worktreePath> status --porcelain`, then take exactly one branch:
   - **Dirty** → do NOT remove it. Print (in-session) that the worktree has uncommitted changes, plus the manual `git worktree remove` command for later.
   - **Clean and NOT inside the worktree** → run `git worktree remove <worktreePath>` (never `--force` unattended).
   - **Clean and inside the worktree** (git cannot remove a worktree you are currently in) → print the exact commands for the user to run:
     ```
     cd <other-checkout>
     git worktree remove <worktreePath>
     ```
   - **If removal fails** for any reason → print the failure and the exact manual commands.
3. **Send one push notification:** "PR #{pr} {merged|closed} — archive this session," including the cleanup outcome (removed / left dirty / remove manually). co-watch does not archive the session itself; that is the user's step.

## Notifications

Notify on all three event types (a new comment, a re-review result, and merge/close) via:

- **The `PushNotification` tool** — an OS push notification that fires even when the terminal isn't focused (this is a walk-away loop).
- **A terminal summary** — printed in-session.

Silent no-op ticks (nothing changed) produce no notification.

## Error handling

- A failing check on a tick (network blip, `gh` hiccup, Codex error) → notify the user that the tick errored and **keep the heartbeat alive** by completing the scheduling step (reschedule), rather than dying silently. (Codex failing specifically is non-fatal: re-review continues with Claude alone, same as co-review.)
- A tick that fails **before** re-review synthesis completes leaves `lastReviewedSha` and the comment cursors unchanged, so the next tick retries the same head/comments rather than skipping them.
- Never post to GitHub or commit unattended. Surfacing findings is in-session only.
