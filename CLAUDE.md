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
