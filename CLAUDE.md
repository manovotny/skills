# Working in this repo

## Editing skills — edit the working copy, never `~/.claude/skills/`

This repo's `skills/` directory is the **source of truth**. `setup.sh` creates symlinks
at `~/.claude/skills/<name>` that point into a checkout of this repo (often a *different*
checkout than the one you're working in — e.g. the main clone, not your worktree).

**Always edit `skills/<name>/...` in the working copy you're currently in.** Never edit
through `~/.claude/skills/...` — those paths resolve to whatever checkout the symlink
targets, so your changes land on the wrong branch (typically uncommitted edits on `main`
in another clone) instead of the branch you're working on here.

If a prompt or instruction hands you a `~/.claude/skills/...` path, translate it to the
matching `skills/...` path in this working copy before editing.

A `PreToolUse` hook in `.claude/settings.json` blocks edits to `~/.claude/skills/` as a
backstop, but the rule applies regardless of the hook.

## The audit and review prompts share dimensions — update both

Two prompts cover overlapping ground:

- `skills/co-review/review-prompt.md` — the **diff/PR** lens, read verbatim by both
  `co-review` and `co-fix`.
- `skills/co-audit/audit-prompt.md` — the **whole-project** lens, read by `co-audit`.

They are deliberately **not** one file: review gates a diff (severity bug/suggestion/nit,
output anchored to PR lines for GitHub posting) while audit hunts improvements across the
project (ranked by impact × effort). But they share a core set of improvement
**dimensions** — caching, query efficiency, error handling, framework-feature usage,
duplication, accessibility, plus the longstanding performance and security passes.

**When you add or materially change a shared dimension, change it in both files** — phrased
for each scope. In `review-prompt.md` keep it bounded to the diff and its immediate
neighborhood ("obvious or readily discoverable", "no whole-codebase archaeology"); in
`audit-prompt.md` it ranges over the whole project. **The differing wording is intentional
— do not "fix" it by merging the prompts.**

Some dimensions are **exclusive** and do not cross over: PR-only mechanics (CI status, base
staleness) stay in `review-prompt.md`; whole-project-only dimensions (dependency/bundle
health, platform features, SEO, CLI/library API design) stay in `audit-prompt.md`.

## co-write's voice guide is shared data — mind the path

`skills/co-write/voice.md` is the user's voice guide. It's data, not documentation:
co-pr, co-review, and co-fix read it (via `~/.claude/skills/co-write/voice.md`) when
writing outward-facing prose — PR bodies, review and announce comments. Renaming or
moving it means updating those references. The guide is normally maintained through
`/co-write learn`; manual edits follow the same rule as any skill edit (working copy,
never `~/.claude`). Voice never overrides format: commit-message format, code-comment
density/placement, and repo conventions win; only the prose inside them carries the voice.
