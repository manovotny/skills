# skills

Personal collection of [Claude Code](https://claude.com/claude-code) skills built around collaborative workflows with [Codex CLI](https://github.com/openai/codex).

## The `co-` collection

The `co-` skills automate collaborative development workflows. Most pair Claude with Codex for adversarial peer review — Claude is the primary author and decision-maker, Codex provides feedback, Claude filters it with judgment. A few are solo utilities that just handle mechanical git/GitHub work cleanly.

| Skill | Purpose |
| --- | --- |
| [`/co-audit`](skills/co-audit/SKILL.md) | Whole-project improvement audit. Claude and Codex audit the project (or a path) in parallel across performance, caching, simplicity, consistency, security, and more; Claude synthesizes one prioritized findings list, then fixes selected items or writes a report. No PR comments or GitHub posting; fixes stay local unless you explicitly ask to commit/push. |
| [`/co-clean`](skills/co-clean/SKILL.md) | Reclaim disk space from obsolete git worktrees and merged branches, across a folder of clones or a single repo. Classifies every worktree by merge status (including squash-merges via GitHub), removes the safe ones without touching uncommitted work, triages dirty checkouts (symlinks and agent artifacts vs real work), and compacts the largest repos with `git gc`. Discovers, reports, and confirms before deleting. |
| [`/co-fix`](skills/co-fix/SKILL.md) | Agentic peer review-and-fix loop on a PR Claude authored. Codex reviews, Claude filters feedback (rejecting overkill), fixes the code, commits, iterates until Codex is satisfied. |
| [`/co-merge`](skills/co-merge/SKILL.md) | Merge the default branch into the current branch and resolve conflicts. Accepts the default branch's lock file and reinstalls dependency changes when needed. Code conflicts are resolved with judgment. |
| [`/co-plan`](skills/co-plan/SKILL.md) | Iterative peer review of an implementation plan. Claude drafts, Codex reviews, Claude revises, repeat until Codex is satisfied — then a final pass strips overengineered bloat. |
| [`/co-pr`](skills/co-pr/SKILL.md) | Create or update a GitHub pull request. Three modes: `/co-pr` (ready), `/co-pr draft`, `/co-pr update`. Handles staging, lint/format, commit, push, and PR description generation with content preservation. |
| [`/co-review`](skills/co-review/SKILL.md) | Parallel PR review by Claude and Codex. Both review the diff simultaneously, Claude synthesizes findings into one issue list, then posts pending GitHub comments or makes direct fixes. Handles re-reviews when the author pushes changes. |
| [`/co-watch`](skills/co-watch/SKILL.md) | Watch a PR after review. A local self-rescheduling loop that notifies on new comments, re-runs `/co-review` when the author pushes commits, and cleans up the worktree when the PR merges or closes. Default 20m interval, overridable (`/co-watch 30m`). |

## Typical workflow

```
1. /co-plan         → refine an implementation plan with Codex
2. (work together)  → Claude implements, you iterate
3. /co-pr draft     → commit, push, create a draft PR
4. /co-fix          → Codex reviews Claude's code, Claude fixes
5. (your review)    → final iteration
6. /co-merge        → if the branch fell behind, merge the default branch in
7. (mark ready)     → PR ready for coworker review
8. /co-review       → use this to review someone else's PR
9. /co-watch        → after a review, keep watching for comments, commits, and merge
```

Each skill stands on its own. Use them in any order or combination that fits the task.

`/co-audit` sits outside this PR-centric flow — run it any time to audit the whole project (or a path) for improvements: `/co-audit`, `/co-audit performance`, or `/co-audit src/api`.

## Installation

### Requirements

- [Claude Code](https://claude.com/claude-code)
- [Codex CLI](https://github.com/openai/codex), authenticated, with model and reasoning configured in `~/.codex/config.toml`
- [GitHub CLI](https://cli.github.com/) (`gh`) for `co-pr`, `co-review`, `co-fix`, `co-merge`, `co-watch`, and `co-clean`

Use the [`skills` CLI](https://skills.sh) to install. The skills target Claude Code specifically (`--agent claude-code`).

### Install all skills

```bash
npx skills add manovotny/skills -g --agent claude-code -y
```

### Install a single skill

```bash
npx skills add manovotny/skills -g --agent claude-code --skill co-plan -y
```

### Install a subset

```bash
npx skills add manovotny/skills -g --agent claude-code --skill co-plan co-review -y
```

The skills become available in your next Claude Code session as slash commands (`/co-audit`, `/co-clean`, `/co-fix`, `/co-merge`, `/co-plan`, `/co-pr`, `/co-review`, `/co-watch`).

## Development

If you clone the repo to iterate on skills locally, run the setup script to symlink them into Claude Code:

```bash
git clone https://github.com/manovotny/skills.git
cd skills
./setup.sh
```

Re-run `./setup.sh` any time you add or remove a skill. It's idempotent — safe to run repeatedly. It only manages symlinks for skills in this repo and won't touch other skills you have installed.

## Skill design principles

- **Claude is the author and decision-maker.** Codex provides feedback, Claude filters it. Overkill, premature abstraction, and pedantry get rejected into a Dismissed list.
- **KISS, then iterate.** Skills start as single-file `SKILL.md`. Refactor only when complexity demands it.
- **Judgment over rigidity.** Where deterministic logic gets brittle (e.g., GitHub API errors), Claude adapts in the moment instead of failing.
- **Designed for [Superset](https://superset.sh) worktrees.** Each task lives in its own worktree, so dirty-state edge cases don't apply.

## License

MIT
