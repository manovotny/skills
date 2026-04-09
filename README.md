# ai

Personal collection of [Claude Code](https://claude.com/claude-code) skills built around collaborative workflows with [Codex CLI](https://github.com/openai/codex).

## The `co-` collection

The `co-` skills automate adversarial collaboration between Claude and Codex. Claude is the primary author and decision-maker; Codex is a peer reviewer whose feedback Claude filters with judgment. Each skill targets a specific stage of the development lifecycle.

| Skill | Purpose |
| --- | --- |
| [`/co-plan`](skills/co-plan/SKILL.md) | Iterative peer review of an implementation plan. Claude drafts, Codex reviews, Claude revises, repeat until Codex is satisfied — then a final pass strips overengineered bloat. |
| [`/co-review`](skills/co-review/SKILL.md) | Parallel PR review by Claude and Codex. Both review the diff simultaneously, Claude synthesizes findings into one issue list, then posts pending GitHub comments. Handles re-reviews when the author pushes changes. |
| [`/co-pr`](skills/co-pr/SKILL.md) | Create or update a GitHub pull request. Three modes: `/co-pr` (ready), `/co-pr draft`, `/co-pr update`. Handles staging, lint/format, commit, push, and PR description generation with content preservation. |
| [`/co-fix`](skills/co-fix/SKILL.md) | Agentic peer review-and-fix loop on a PR Claude authored. Codex reviews, Claude filters feedback (rejecting overkill), fixes the code, commits, iterates until Codex is satisfied. |

## Typical workflow

```
1. /co-plan         → refine an implementation plan with Codex
2. (work together)  → Claude implements, you iterate
3. /co-pr draft     → commit, push, create a draft PR
4. /co-fix          → Codex reviews Claude's code, Claude fixes
5. (your review)    → final iteration
6. (mark ready)     → PR ready for coworker review
7. /co-review       → use this to review someone else's PR
```

Each skill stands on its own. Use them in any order or combination that fits the task.

## Installation

### Requirements

- [Claude Code](https://claude.com/claude-code)
- [Codex CLI](https://github.com/openai/codex), authenticated, with model and reasoning configured in `~/.codex/config.toml`
- [GitHub CLI](https://cli.github.com/) (`gh`) for `co-pr`, `co-review`, and `co-fix`

Use the [`skills` CLI](https://skills.sh) to install. The skills target Claude Code specifically (`--agent claude-code`).

### Install all skills

```bash
npx skills add manovotny/ai -g --agent claude-code -y
```

### Install a single skill

```bash
npx skills add manovotny/ai -g --agent claude-code --skill co-plan -y
```

### Install a subset

```bash
npx skills add manovotny/ai -g --agent claude-code --skill co-plan co-review -y
```

The skills become available in your next Claude Code session as slash commands (`/co-plan`, `/co-review`, `/co-pr`, `/co-fix`).

## Skill design principles

- **Claude is the author and decision-maker.** Codex provides feedback, Claude filters it. Overkill, premature abstraction, and pedantry get rejected into a Dismissed list.
- **KISS, then iterate.** Skills start as single-file `SKILL.md`. Refactor only when complexity demands it.
- **Judgment over rigidity.** Where deterministic logic gets brittle (e.g., GitHub API errors), Claude adapts in the moment instead of failing.
- **Designed for [Superset](https://superset.sh) worktrees.** Each task lives in its own worktree, so dirty-state edge cases don't apply.

## License

MIT
