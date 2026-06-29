---
name: co-audit
description: Use when auditing a whole project (or a path within it) for improvement opportunities — performance, caching, simplicity, consistency, security, and best practices — with agentic peer review
---

# co-audit

Proactive, whole-project improvement audit. Claude and Codex audit the project (or a scoped path) in parallel against a shared dimension taxonomy, Claude synthesizes both into one prioritized findings list, then offers to fix selected findings, write a report, or adjust.

**This is a whole-project audit, not a diff review.** For diff/PR work, use `/co-review` (others' PRs) or `/co-fix` (Claude's own code) — both are improvement-aware. For a deep security pass, use `/security-review`. co-audit cross-references these but does not invoke them.

**Do not make any changes until the user chooses an action.**

## Scope and focus

If the user passed an argument (e.g. `/co-audit performance src/api`), parse it loosely:

- a token or **multiword phrase** matching a known **dimension** → **dimension focus**. Recognize the dimension names from audit-prompt.md plus common aliases: `perf` → performance, `a11y` → accessibility, `deps` → dependencies, `docs` → documentation. Multiword dimensions (`error handling`, `best practices`) are matched as phrases, not split into separate tokens.
- a **path-like** token (contains `/`, `./`, `../`, or a file extension) → **path scope** if it resolves to an existing file/dir; if it looks path-like but doesn't exist (e.g. a typo like `src/apu`), stop and ask rather than auditing nothing.
- a bare token that resolves to an existing file/dir and is *not* also a dimension name → **path scope**.
- nothing recognized → full audit, whole project.
- **Collision** — a *bare* token (no path markers) matching both a known dimension and an existing file/dir (e.g. a directory literally named `security`): ask the user which they meant.
- an unrecognized token (neither a known dimension nor a resolvable path) → ask the user rather than guessing.

Scopes are **whole project** (default) or a **path**. There is no diff scope — diff/PR improvement work belongs to `/co-review` and `/co-fix`.

Examples: `/co-audit` · `/co-audit performance` · `/co-audit src/api` · `/co-audit security src/api`

## Audit prompt

Read [audit-prompt.md](audit-prompt.md) from this skill's directory (not repo cwd). Both Claude and Codex use this same prompt. Fill in `{SCOPE}` and `{FOCUS}` before use — e.g. `{SCOPE}` → "the whole project" or "the path `src/api`"; `{FOCUS}` → "all dimensions" or "performance".

## Flow

Announce the audit, naming the scope and any focus — e.g. **"Starting parallel audit of the whole project."** or **"Starting parallel audit of `src/api`, focused on performance."**

**Step 1 — Pre-audit context.** Gather context before auditing. The authoritative checklist is audit-prompt.md's "Pre-audit" section (Claude and Codex share it) — follow it there. In brief: read project context files (CLAUDE.md / AGENTS.md / CONTRIBUTING\* / STYLEGUIDE\*, one-hop pointer follow), detect project type / stack / framework / platform / package manager, and resolve scope and focus.

**Step 2 — Parallel audit.** Kick off Codex in the background with `run_in_background: true` and a timeout of `600000` ms:

```bash
cat <<'CO_AUDIT_EOF' | codex exec --dangerously-bypass-approvals-and-sandbox -
[AUDIT PROMPT WITH SCOPE AND FOCUS FILLED IN]
CO_AUDIT_EOF
```

**Capture the session ID** from Codex's output (`session id: <uuid>`) — Option 4 resumes this same session when the user re-scopes or re-ranks, so Codex keeps context instead of starting cold.

While Codex runs, Claude audits simultaneously using the same prompt. True parallel — do not wait for Codex before starting Claude's audit.

**Do not poll for Codex's status with sleep/cat loops.** Background tasks notify you on completion automatically — the Bash tool rejects leading `sleep` commands. Launch Codex, do Claude's audit in the meantime, and read the background task's output only once you receive the completion notification. If you must watch a condition, use the `Monitor` tool with an `until` loop, never chained sleeps.

If Codex fails (non-zero exit, empty response, timeout, not installed), continue with Claude's audit alone and tell the user Codex errored. Codex is additive — Claude's audit stands on its own.

**Step 3 — Synthesize & prioritize.** Once Codex finishes, merge both audits:

- Deduplicate overlapping findings.
- Apply Claude's judgment — reject overkill, premature abstraction, out-of-scope work, and low-value pedantry into a **Dismissed** section with a brief rationale each.
- Rank surviving findings by **impact × effort** — high-impact first; ties broken by lower effort.
- **Cap the list to the top findings and state what was dropped.** Big projects can produce dozens of findings per dimension; present the highest-impact ones and say how many more exist per dimension so the user can ask for more or re-scope. Never silently truncate.
- Tag each finding `[Direct fix ready]` or `[Needs input]` so the user knows which Claude can fix immediately.

**Step 4 — Present and prompt.**

```
Audit complete. N findings across M dimensions (top P shown).

1. Fix selected findings directly
2. Write the full report to a file
3. Fix some + report the rest
4. Let me adjust (re-scope, change focus, re-rank)
```

Do not make changes or write files until the user chooses.

**Step 5 — Act on the choice.**

### Option 1 — Fix selected findings directly

1. **Ask which findings to fix.** "Which findings should I fix directly? You can also pull items from the Dismissed list."
2. **Make the fixes locally.** Do NOT commit or push yet.
3. **Verify before showing them.** These are changes you authored, so confirm they hold up. Detect and run the repo's fast checks on the touched files — **formatter, linter, type check, and tests** — preferring what CI runs, then `package.json` scripts / `Makefile` / the ecosystem standard. Never hardcode commands.
   - Run format / lint / type check whenever the toolchain is present (fast, hermetic). Run tests when runnable; skip with a clear reason when they need infra/secrets or are slow.
   - Scope auto-format to the files you changed; never reformat the tree. Type check, not full build.
   - If a check fails, fix it before continuing.
4. **Summarize what changed**, one bullet per finding, and name what checks ran and what was skipped and why.
5. **Wait for approval.** Then **commit only when the user explicitly asks**, using a message matching the repo's style (`git log --oneline -20`); **push only when the user explicitly asks**. The default is to leave the fixes uncommitted for the user to review.

### Option 2 — Write the full report to a file

Write the complete findings list (including the Dismissed section) to `docs/audits/YYYY-MM-DD-audit.md` — create the directory if needed, or adjust to an existing docs convention. Use audit-prompt.md's output format, grouped by dimension and ranked by impact. Tell the user where it landed. Make no code changes.

### Option 3 — Fix some + report the rest

Combine Options 1 and 2: fix the findings the user selects (same verify → summarize → approve flow), and write the remaining findings to the report file.

### Option 4 — Let me adjust

Free-form. The user re-scopes, changes the dimension focus, asks to re-rank, or edits the findings. Re-run or re-synthesize as needed. When a re-scope or re-focus needs Codex again, **resume the captured session** (`codex exec resume <session_id> --dangerously-bypass-approvals-and-sandbox -`) and pass the prior findings + Dismissed list so Codex keeps context instead of starting cold.

## Findings cap

The presented list is capped to the highest-impact findings so large projects stay actionable — **default ~12, adjusted with judgment** for very large or very small audits. Always state what was held back (e.g. "showing top 12 of ~30; 8 more under Caching, 6 more under Consistency"). The full set goes in the report (Option 2) on request. This mirrors the co- family's no-silent-truncation rule.

## When to use which

| Tool | Scope | Job |
| --- | --- | --- |
| `co-audit` | Whole project / path | Proactive improvement audit across all dimensions. Local fix-or-report, never posts to GitHub. |
| `/co-review` | Diff / PR (others') | Full PR review with Codex; posts GitHub comments or makes fixes. |
| `/co-fix` | Diff / PR (Claude's own) | Self-review-and-fix loop with Codex. |
| `/code-review` | Current diff | Correctness bugs + targeted cleanup. |
| `/security-review` | Pending changes | Deep security pass. |
| `/simplify` | Changed code | Apply quality-only cleanups. |
