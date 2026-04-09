# co-pr and co-fix Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the `/co-pr` and `/co-fix` Claude Code skills, install them, and clean up Codex's draft files.

**Architecture:** Two single-file skills. `/co-pr` handles create/draft/update modes inline. `/co-fix` reuses `../co-review/review-prompt.md` for the review prompt.

**Tech Stack:** Claude Code skill system, `gh` CLI, Codex CLI (for `/co-fix`)

---

### Task 1: Write skills/co-pr/SKILL.md

**Files:**
- Create: `skills/co-pr/SKILL.md`
- Reference: `skills/co-pr/SKILL-codex.md` (Codex's draft, for comparison)
- Reference: `docs/specs/2026-04-09-co-pr-design.md`

- [ ] **Step 1: Write the SKILL.md**

Write the file based on the spec. Key sections:
- YAML frontmatter with name and description (no workflow summary)
- Mode detection (create/draft/update)
- Shared pre-commit flow (stage, lint/format, re-stage, tests, commit, push)
- Create mode flow (precondition, pre-commit, template detection via `gh repo view`, body draft, title style, create, output)
- Update mode flow (precondition with state checks, pre-commit, read existing PR, drift detection with deterministic inputs, rewrite narrative with preservation rules, update via `gh pr edit --body-file -`, output)
- Always use `--body-file -` with heredoc, never inline `--body`
- Symlink exclusion as hard rule
- Push remote detection from upstream
- Repo style detection for commits and PR titles

Match the lean, scannable style of `co-plan/SKILL.md` and `co-review/SKILL.md`.

- [ ] **Step 2: Verify against spec**

Check that every spec requirement is covered: state checks, body-file heredoc, upstream detection, template detection, preservation rules, language scope.

- [ ] **Step 3: Word count check**

Run: `wc -w skills/co-pr/SKILL.md`
Target: under 1000 words. The skill is more complex than co-plan, so a higher budget is acceptable.

---

### Task 2: Write skills/co-fix/SKILL.md

**Files:**
- Create: `skills/co-fix/SKILL.md`
- Reference: `skills/co-fix/SKILL-codex.md` (Codex's draft)
- Reference: `docs/specs/2026-04-09-co-fix-design.md`

- [ ] **Step 1: Write the SKILL.md**

Key sections:
- YAML frontmatter
- Precondition with PR state checks (open/closed/merged/auth)
- Reference to `../co-review/review-prompt.md`
- Review-and-fix loop (announce, send to Codex with previous findings on rounds 2+, handle errors, judgment filter, fix code, pre-commit checks, commit and push, termination check)
- Critical: no amend after push
- Conditional PR description update (only when meaningful)
- Output format

Match the lean style of co-plan/co-review.

- [ ] **Step 2: Verify against spec**

Check coverage: round 2+ context passing, no-amend rule, state checks, conditional PR update, language scope.

- [ ] **Step 3: Word count check**

Run: `wc -w skills/co-fix/SKILL.md`
Target: under 800 words.

---

### Task 3: Commit both skills and specs

- [ ] **Step 1: Stage and commit**

```bash
git add skills/co-pr/SKILL.md skills/co-fix/SKILL.md docs/specs/2026-04-09-co-pr-design.md docs/specs/2026-04-09-co-fix-design.md docs/specs/2026-04-09-co-pr-co-fix-plan.md
git commit -m "feat: add co-pr and co-fix skills"
```

---

### Task 4: Install both skills

- [ ] **Step 1: Symlink to ~/.claude/skills/**

```bash
ln -sf /Users/manovotny/.superset/worktrees/ai/manovotny/enshrined-flavor/skills/co-pr ~/.claude/skills/co-pr
ln -sf /Users/manovotny/.superset/worktrees/ai/manovotny/enshrined-flavor/skills/co-fix ~/.claude/skills/co-fix
```

- [ ] **Step 2: Verify symlinks**

```bash
ls -la ~/.claude/skills/co-pr ~/.claude/skills/co-fix
```

---

### Task 5: Clean up Codex drafts

- [ ] **Step 1: Remove Codex versions**

```bash
rm skills/co-pr/SKILL-codex.md skills/co-fix/SKILL-codex.md
```

Codex's drafts are untracked, so no commit needed for the removal.
