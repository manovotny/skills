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

## Review Loop

Announce: **"Starting agentic peer review. Round 1 of 4."**

**Step 1 — Send to Codex.** Write the plan to a temp file and pipe it to Codex. Use a Bash timeout of `600000` ms (Codex is slow — especially on the first round where it does its own investigation).

```bash
cat <<'CO_PLAN_EOF' | codex exec --dangerously-bypass-approvals-and-sandbox -
Here's a plan I have so far. Do your own investigation on how to best solve this problem and determine if there are any gaps or oversights in the current plan. Provide feedback on gaps and oversights, and do not execute the plan.

<plan>
[PLAN CONTENT HERE]
</plan>
CO_PLAN_EOF
```

If `codex exec` fails (non-zero exit, empty response, not installed), stop and tell the user what happened. Do not retry.

**Step 2 — Revise the plan.** Process Codex's feedback with this framing:

- Do not blindly accept feedback. You decide what is worth implementing.
- Keep changes that improve correctness, sequencing, scope, or risk handling.
- Reject overkill, premature abstraction, and out-of-scope suggestions.
- Add rejected items to a **Not Planned** section with brief rationale for each.

**Step 3 — Check termination.** (See Termination Rules below.) If not done, announce the next round number and send the revised plan back with the shorter follow-up prompt:

```bash
cat <<'CO_PLAN_EOF' | codex exec --dangerously-bypass-approvals-and-sandbox -
Updated plan:

<plan>
[REVISED PLAN CONTENT HERE]
</plan>
CO_PLAN_EOF
```

Repeat Steps 2-3 until terminated.

## Termination Rules

After each Codex response, check for a **satisfaction signal** — phrases like:
- "this is ready"
- "this is solid"
- "no remaining gaps"
- "complete enough to execute"
- "no remaining findings"
- "don't see any substantive gaps"

If Codex signals satisfaction — even with trailing nits — **exit the loop**. Fold trailing nits into the final self-review instead of looping again.

**Hard cap: 4 rounds.** If round 4 has no satisfaction signal, stop and ask the user for guidance. Do not continue indefinitely.

## Final Self-Review

Once the loop exits, do one cleanup pass:

- Remove anything overly defensive, pedantic, or overengineered for extreme corner cases not worth the complexity — bloat that agentic peer review introduced.
- Preserve important risk controls and sequencing. Only remove what does not earn its cost.
- Briefly note what you removed and why.

## Output

- Present a concise summary of meaningful changes made during review.
- Present the clean final plan in execution-ready form.
- Keep the **Not Planned** section when it has content.
- **Do not execute the plan.** The user decides when and how to execute.
