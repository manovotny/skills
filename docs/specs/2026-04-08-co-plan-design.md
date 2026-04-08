# co-plan Skill Design Spec

## Overview

A Claude Code skill (`/co-plan`) that automates agentic peer review of implementation plans. After the user and Claude collaboratively draft a plan, this skill sends it to Codex CLI for iterative peer review, processes the feedback, and performs a final cleanup pass to remove overengineered bloat.

This is the first skill in a `co-` prefix collection. Future skills (e.g., `/co-review` for PR review) will follow the same collaborative pattern.

## Scope

The skill covers steps 3-8 of the user's existing workflow:

- **In scope:** Codex review loop, plan revision, termination detection, final self-review, presenting clean plan
- **Out of scope:** Initial plan drafting (user + Claude do this collaboratively before invoking the skill), plan execution (user triggers this separately after approving the final plan)

## Skill Identity

```yaml
name: co-plan
description: Use when a plan draft is complete and ready for agentic peer review before execution
```

- **Installed to:** `~/.claude/skills/co-plan/SKILL.md` (Claude-only)
- **Trigger:** User types `/co-plan` after completing a plan draft
- **Precondition:** A plan must exist in the conversation context. If no plan is found, instruct the user to draft one first and exit.

## Architecture

Single-file skill (`SKILL.md`). No shell scripts, no separate prompt templates. Prompts are embedded inline — they're short (2-4 sentences each) and the simplicity outweighs the marginal benefit of external files. Can be refactored to separate templates later if prompts grow complex.

## File Structure

```
enshrined-flavor/
  skills/
    co-plan/
      SKILL.md
  docs/
    specs/
      2026-04-08-co-plan-design.md
  README.md
```

Installation: symlink or copy `skills/co-plan/` to `~/.claude/skills/co-plan/`.

## Review Loop Flow

### Step 1 — Gather the Plan

Read the current plan from conversation context. If in plan mode, the plan file path is available.

### Step 2 — Initial Codex Review

Send plan to Codex via stdin piping:

```bash
cat << 'PLAN_PROMPT' | codex exec --dangerously-bypass-approvals-and-sandbox -
Here's a plan I have so far. Do your own investigation on how to best solve this problem and determine if there are any gaps or oversights in the current plan. Provide feedback on gaps and oversights, and do not execute the plan.

[PLAN CONTENT]
PLAN_PROMPT
```

### Step 3 — Process Codex Feedback

Revise the plan with this framing:

- Do not blindly accept the feedback
- Decide what is worth implementing vs. what is overkill or out of scope
- Add rejected items to a "Not Planned" section with rationale explaining why

### Step 4 — Send Revision Back to Codex

Subsequent rounds use a shorter prompt:

```bash
cat << 'PLAN_PROMPT' | codex exec --dangerously-bypass-approvals-and-sandbox -
Updated plan:

[PLAN CONTENT]
PLAN_PROMPT
```

### Step 5 — Check Termination

After each Codex response, evaluate:

1. **Satisfaction signal detected** — phrases like "this is ready", "this is solid", "no remaining gaps", "complete enough to execute", "no remaining findings", "don't see any substantive gaps". If satisfied (even with trailing nits), exit loop and proceed to Step 6. Trailing nits are folded into the final self-review.
2. **Not satisfied** — return to Step 3 for another revision round.
3. **Hard cap at 4 rounds** — if Codex is not satisfied after 4 revisions, pause and ask the user what is going on. Something unexpected may need human judgment.

### Step 6 — Final Self-Review

Review the plan for anything that is overly defensive, pedantic, or overengineered for extreme corner cases that are not worth doing — bloat that agentic peer review introduced. Remove it. Note what was removed and why in a brief summary. Present the clean final plan.

## Codex Invocation Details

- **Command format:** stdin piping via heredoc (not CLI argument) to avoid shell escaping issues with large plans
- **Working directory:** Current working directory. Codex and Claude run side-by-side in the same repo worktree via Superset.
- **Model and reasoning:** Inherited from `~/.codex/config.toml` (currently `gpt-5.4`, reasoning `high`). No CLI flags needed.
- **Timeout:** 600 seconds (10 minutes) per invocation. Codex is slow, especially on initial review where it does its own investigation. 600s is the Bash tool maximum.
- **Error handling:** If `codex exec` fails (non-zero exit, empty response, Codex not installed/authenticated), stop the loop and tell the user what happened. Do not retry automatically.

## Termination Strategy

The skill uses semantic exit detection with a hard safety cap:

- **Semantic signals:** Parse Codex responses for satisfaction language. Codex has a pattern of saying "this is solid/ready/complete" while still listing minor nits. The satisfaction signal is the key — trailing nits get addressed in the final self-review, not by looping again.
- **Hard cap:** 4 rounds maximum. This is a safety net, not a target. Most reviews should converge in 2-3 rounds.
- **Escalation:** If the cap is hit, stop and ask the user. Don't silently proceed with a plan that Codex is still unhappy with.

## Not Planned

- **Automated plan drafting:** The initial draft phase is collaborative between user and Claude. Automating this removes the human judgment that makes plans good.
- **Codex model/reasoning overrides:** The skill inherits from Codex config. Users who want different settings can change their `~/.codex/config.toml`.
- **Hook-based automation (auto-trigger on ExitPlanMode):** The user wants to explicitly choose when to invoke peer review, not have it fire on every plan. Can be added later if desired.
- **Shell script for Codex invocation:** Premature abstraction for 2-4 sentence prompts. Refactor to separate files if prompts grow complex.
- **Shared installation with Codex agents:** This skill has Claude calling Codex — Codex reviewing its own output would be recursive. Claude-only installation.
