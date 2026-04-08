# co-plan Skill Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Create the `/co-plan` Claude Code skill that automates agentic peer review of implementation plans via Codex CLI.

**Architecture:** Single-file skill (`SKILL.md`) with inline prompts and orchestration instructions. Installed to `~/.claude/skills/co-plan/` as a Claude-only skill.

**Tech Stack:** Claude Code skill system, Codex CLI (`codex exec`)

---

### Task 1: Write the SKILL.md

**Files:**
- Create: `skills/co-plan/SKILL.md`
- Reference: `skills/co-plan/SKILL-codex.md` (Codex's draft, for comparison)
- Reference: `docs/specs/2026-04-08-co-plan-design.md` (design spec)

- [ ] **Step 1: Write the skill file**

Write `skills/co-plan/SKILL.md` with the following content. This is the complete file — not a template.

The skill must cover these sections in order:

1. **YAML frontmatter** — `name: co-plan`, description focused on triggering conditions only (not workflow summary, per CSO best practices)
2. **Overview** — One-liner: what this skill does and when to use it. Precondition: a plan must already exist.
3. **Review Loop** — Numbered steps:
   - Step 1: Gather the plan from conversation context (plan file if in plan mode, or conversation)
   - Step 2: Send to Codex via stdin heredoc with initial review prompt. Timeout 600000ms. Include the exact prompt text.
   - Step 3: Process feedback — don't blindly accept, add rejected items to "Not Planned" section with rationale
   - Step 4: Send revised plan back with shorter follow-up prompt. Include the exact prompt text.
   - Step 5: Check termination — semantic signals or round cap
   - Step 6: Back to step 3 if not terminated
4. **Termination Rules** — Satisfaction signals list, trailing nits handling, 4-round hard cap, escalation to user
5. **Final Self-Review** — Strip overengineered bloat from agentic peer review, note what was removed and why
6. **Output** — Summary of changes, clean final plan, preserve Not Planned section, do not execute
7. **Notes** — Config inheritance, heredoc stdin piping rationale, Claude-only intent

Key differences from Codex's draft (`SKILL-codex.md`):
- Add explicit round counting with user-visible progress (e.g., "Round 1 of 4")
- Ensure the initial prompt and follow-up prompt match the user's exact wording from their workflow
- Make the "do not execute" instruction more prominent since Codex itself ignored it when we tested
- Add brief status updates between rounds so the user knows what's happening during long waits

- [ ] **Step 2: Verify word count**

Run: `wc -w skills/co-plan/SKILL.md`
Target: Under 500 words (per skill authoring guidelines for general skills)

- [ ] **Step 3: Compare against spec**

Read both `skills/co-plan/SKILL.md` and `docs/specs/2026-04-08-co-plan-design.md`. Verify every spec requirement has a corresponding section in the skill. Check:
- Precondition check present
- Both prompts (initial + follow-up) included with exact text
- Termination signals listed
- 4-round cap with user escalation
- Final self-review with bloat removal
- "Not Planned" section behavior
- Error handling for failed `codex exec`
- Timeout of 600000ms specified
- No model/reasoning override flags

- [ ] **Step 4: Commit**

```bash
git add skills/co-plan/SKILL.md
git commit -m "feat: add co-plan skill for agentic peer review of plans"
```

---

### Task 2: Install the skill

- [ ] **Step 1: Symlink to Claude Code skills directory**

```bash
ln -sf /Users/manovotny/.superset/worktrees/ai/manovotny/enshrined-flavor/skills/co-plan ~/.claude/skills/co-plan
```

Note: This symlink points to the worktree. For permanent installation, the user would point it at the main repo clone or install via `npx skills add`.

- [ ] **Step 2: Verify the skill is discoverable**

Start a new Claude Code session and check that `/co-plan` appears in the skill list. If it doesn't, verify the symlink target exists and `SKILL.md` is present.

---

### Task 3: Clean up

- [ ] **Step 1: Remove Codex's draft**

```bash
rm skills/co-plan/SKILL-codex.md
```

- [ ] **Step 2: Commit cleanup**

```bash
git add -A
git commit -m "chore: remove codex draft skill file"
```
