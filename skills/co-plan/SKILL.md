---
name: co-plan
description: Use when a plan draft is complete and ready for agentic peer review before execution
---

# co-plan

Automate agentic peer review of a draft plan. This skill sends the plan to Codex CLI for iterative review, revises based on feedback, and performs a final cleanup pass before presenting the result.

**Do not use this skill to draft the initial plan or to execute the final plan.**

## Preconditions

- Locate the current plan in conversation context. If in plan mode, read the plan file.
- **If multiple plans exist in the conversation** (e.g., the user ran plan mode more than once in this session), use **only the most recent** one. Earlier plans are superseded and must not bleed into the current review.
- If no plan exists, tell the user to draft one first, then invoke `/co-plan` again. Stop here.

## Review loop

**Critical: Use a single stateful Codex session across all rounds.** Round 1 uses `codex exec` (fresh session). Rounds 2+ use `codex exec resume <session_id>` to continue the **same** session, so the "review only, do not execute" instruction from round 1 stays in context.

**Why this matters:** `codex exec` is stateless — each invocation is a brand new session with no memory of previous rounds. If you send "Updated plan: [PLAN]" as a fresh `codex exec` call, Codex has no context about "review only" and will execute the plan (we've tested this multiple times — it always does). `codex exec resume` preserves the session, making the rules stick.

Announce: **"Starting agentic peer review. Round 1 of 4."**

**Step 1 — Send the plan to Codex (round 1 only).** Fresh session, full instructions. Use a Bash timeout of `600000` ms (Codex is slow — especially on the first round where it does its own investigation).

```bash
cat <<'CO_PLAN_EOF' | codex exec --dangerously-bypass-approvals-and-sandbox -
Here's a plan I have so far. Do your own investigation on how to best solve this problem and determine if there are any gaps or oversights in the current plan. Provide feedback on gaps and oversights, and do not execute the plan.

<plan>
[PLAN CONTENT HERE]
</plan>
CO_PLAN_EOF
```

**Capture the session ID.** Codex prints `session id: <uuid>` near the top of its output (e.g., `session id: 019d7444-d6fd-7521-9a5d-796097ce68dd`). Extract and remember this UUID — you'll need it for every subsequent round.

If `codex exec` fails (non-zero exit, empty response, not installed), stop and tell the user what happened. Do not retry.

**Verify Codex did not execute the plan.** Before proceeding, run `git status --porcelain`. If Codex modified any files (it happens — it ignores "do not execute" instructions when given a fresh session with a plan), STOP the review loop immediately:

1. Run `git status` to see what changed.
2. Tell the user: "Codex executed the plan despite instructions. Stopping the review loop so you can decide how to handle the unreviewed changes."
3. Present options:
   - **1. Revert Codex's changes and re-run `/co-plan`** (`git restore` / `rm` the affected files)
   - **2. Exit `/co-plan` and manually verify Codex's implementation against the plan**
   - **3. Revert everything and start over**
4. Wait for the user's choice. Do not continue the loop automatically.

This should rarely happen with the `resume`-based flow, but we check every round as a safety net.

**Step 2 — Revise the plan.** Process Codex's feedback with this framing:

- Do not blindly accept feedback. You decide what is worth implementing.
- Keep changes that improve correctness, sequencing, scope, or risk handling.
- Reject overkill, premature abstraction, and out-of-scope suggestions.
- Add rejected items to a **Not Planned** section with brief rationale for each.

**Step 3 — Check termination.** (See Termination rules below.) If not done, announce the next round number and send the revised plan back using `codex exec resume` with the captured session ID:

```bash
cat <<'CO_PLAN_EOF' | codex exec resume <session_id> --dangerously-bypass-approvals-and-sandbox -
Updated plan:

<plan>
[REVISED PLAN CONTENT HERE]
</plan>
CO_PLAN_EOF
```

**The `<session_id>` must be the UUID captured from round 1's output.** Without it, Codex starts a fresh session and loses all prior context — including the "do not execute" instruction.

After each resumed round, run the same `git status --porcelain` safety check. If Codex went rogue anyway, stop and present the same options.

Repeat Steps 2-3 until terminated.

## Termination rules

After each Codex response, check for a **satisfaction signal** — phrases like:
- "this is ready"
- "this is solid"
- "no remaining gaps"
- "complete enough to execute"
- "no remaining findings"
- "don't see any substantive gaps"

If Codex signals satisfaction — even with trailing nits — **exit the loop**. Fold trailing nits into the final self-review instead of looping again.

**Hard cap: 4 rounds.** If round 4 has no satisfaction signal, stop and ask the user for guidance. Do not continue indefinitely.

## Final self-review

Once the loop exits, do one cleanup pass:

- Remove anything overly defensive, pedantic, or overengineered for extreme corner cases not worth the complexity — bloat that agentic peer review introduced.
- Preserve important risk controls and sequencing. Only remove what does not earn its cost.
- Briefly note what you removed and why.

## Output

- Present a concise summary of meaningful changes made during review.
- Present the clean final plan in execution-ready form.
- Keep the **Not Planned** section when it has content.
- **Do not execute the plan.** The user decides when and how to execute.
