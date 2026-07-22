---
name: co-clean
description: Use when reclaiming disk space from obsolete git worktrees and merged branches, across a folder of cloned repos or a single repo — especially after heavy AI-agent / worktree workflows leave many stale checkouts behind
---

# co-clean

Reclaim disk space trapped in obsolete git worktrees and merged branches. AI agents and worktree-based workflows (Claude Code, Superset, Conductor, and tool-managed feature stacks) leave behind dozens of checkouts — each with its own `node_modules` — long after their branches merged. This finds the safe-to-remove ones, removes them, deletes their merged branches, and compacts the repos.

**Scope:** Run from a directory containing many cloned repos (cleans all of them) or from inside a single repo (cleans just that one). Worktrees are found via `git worktree list` regardless of where on disk they live — the working directory of the checkout does not have to be next to the repo.

## The prime directive

**Discover → classify → report → confirm → then delete.** Never remove anything before showing the user the plan and getting a go-ahead. Cleanup is destructive and mostly irreversible.

**Two rules decide what stays, and both must pass to remove:**

1. **Merged** — the work is provably in the default branch (see classification), OR its PR is merged on GitHub.
2. **Pushed** — nothing local-only. If it isn't on a remote, leave it.

> If it's unmerged **or** unpushed (local-only), leave it. Full stop.

You never run a separate "is it pushed?" check — the removal gates already guarantee it: an ancestor of `origin/<default>` is on the remote, and a branch with a merged PR was pushed to open it. Everything else is left. In particular, **a branch with no PR that isn't an ancestor is treated as local-only and kept** — clean working tree or not, since it may hold unpushed commits.

**A single "dirty" flag is not a reason to keep a worktree.** Git will refuse to remove a worktree with uncommitted or untracked changes — but "dirty" is often noise, not work. Always look at *what* is dirty before deciding (see [Triaging dirty worktrees](#step-7--triage-dirty-skips-look-before-you-keep)).

## Preconditions

- **`gh` authenticated** — `gh auth status`. Needed to detect squash-merged PRs (the merge test alone can't see them). If `gh` is unavailable, say so and skip the squash-merge phase rather than guessing.
- **Never use `cd` to enter a repo for read commands.** Use `git -C <repo> …` and `gh -R <owner/repo> …`. Entering a repo directory can trigger shell/`direnv`/`corepack` hooks that print banners into your captured output and corrupt parsing.

## Flow

### Step 1 — Enumerate repos and their worktrees

Find every git repo (a dir with a `.git` file or directory). For each, list worktrees in parseable form:

```bash
git -C "$repo" worktree list --porcelain
```

Parse `worktree`/`HEAD`/`branch`/`detached`/`prunable` records. **Skip the main worktree** (its path equals the repo root) — you only clean *linked* worktrees.

### Step 2 — Measure where the disk actually is

`du -sh` the worktree container directories so you can prioritize and report a real number later. Common homes: `~/.claude/worktrees`, `~/.superset/worktrees`, `~/conductor/workspaces`, in-repo `.claude/worktrees`, and tool-managed feature dirs. **`du` over `node_modules` is slow — give it a long timeout or run it in the background.**

### Step 3 — Classify every worktree

For each linked worktree, determine its default branch and whether its HEAD is merged:

```bash
def=$(git -C "$repo" symbolic-ref --quiet refs/remotes/origin/HEAD 2>/dev/null | sed 's#refs/remotes/origin/##')
# fallback if origin/HEAD isn't set: gh repo view --json defaultBranchRef --jq .defaultBranchRef.name
# provably merged = HEAD is an ancestor of the (remote) default branch
git -C "$repo" merge-base --is-ancestor "$head" "origin/$def"
```

`--is-ancestor` is **conservative**: it is true only for real merges, never a false positive. Squash-merged branches will read as UNMERGED here — Step 6 catches those via GitHub.

Classification reads the *local* `origin/<default>` ref. Running `git fetch` first makes it current, but **skipping the fetch is safe**: a stale ref can only misread a merged branch as UNMERGED (which Step 6 then resolves via GitHub) — it never causes a wrong removal. Fetching every repo is slow, so treat it as optional.

Bucket each worktree: `PRUNABLE` (temp dir already gone) · `MERGED` (ancestor of default) · `UNMERGED` (everything else, pending the GitHub check).

> zsh gotcha: `status` is a read-only variable. Name your loop variable something else (`st`).

### Step 4 — Report and confirm (the gate)

Show the user: total reclaimable disk, the biggest wins, and the counts per bucket. Offer scope options (merged-only / merged + GitHub-check unmerged / a single big feature). **Wait for a go-ahead before deleting anything.** Use `AskUserQuestion` for scope.

### Step 5 — Prune stale refs, then remove merged worktrees

```bash
git -C "$repo" worktree prune            # clears PRUNABLE refs (real dirs already gone)
git -C "$repo" worktree remove "$wt"     # NO --force — see below
```

**Remove without `--force`.** That makes git your safety net: it refuses any worktree with uncommitted or untracked changes, which drop into the "dirty skip" pile for Step 7 instead of being destroyed. Log removed vs skipped.

**Deleting the branch after its worktree is gone:**

- **Ancestor-merged** (Step 3): `git -C "$repo" branch -d "$branch"` — the *safe* delete. It succeeds precisely because the branch is merged; if it ever refuses, that's a signal to stop and recheck, not to escalate.
- **Squash-merged** (confirmed in Step 6): `-d` will refuse (the branch isn't an ancestor), so use `git -C "$repo" branch -D "$branch"`. Only ever `-D` a branch whose merged PR you confirmed with a **repo-scoped** `gh -R "$owner_repo" --head "$branch"` lookup — branch names collide across repos, so an unscoped match can point at a different repo's PR and force-delete unmerged work.
- **Detached HEAD**: no branch to delete.

**These operations are slow** (deleting tens of GB of `node_modules`) and will time out a foreground call. Run the removal loop in the background and make it **idempotent** (skip paths already logged) so you can resume after a timeout. Don't run two removal loops against the *same* repo concurrently — you'll hit an index lock.

### Step 6 — Check "unmerged" against GitHub (catch squash-merges)

Most "unmerged" worktrees from tool/PR-review workflows are actually **squash-merged** — real merges the ancestor test can't see. For each unmerged worktree that has a branch:

```bash
owner_repo=$(git -C "$repo" config --get remote.origin.url | sed -E 's#.*[:/]([^/]+/[^/]+)(\.git)?$#\1#')
gh pr list -R "$owner_repo" --head "$branch" --state all --json state,mergedAt --limit 1
```

- `mergedAt` non-null → **PR merged** → eligible for removal (Steps 5/7 rules still apply).
- state `OPEN` → leave. state `CLOSED` without merge → **unmerged, leave it** (honors the prime directive). No PR at all → possibly local-only → leave.

Detached-HEAD worktrees have no branch to look up. You *may* try to tie the checked-out commit to a PR (`gh -R "$owner_repo" pr list --search "$head" --state merged`), but if that doesn't cleanly resolve, **leave them** — an unverifiable detached HEAD is not worth the risk.

### Step 7 — Triage dirty skips (look before you keep)

The worktrees git refused in Step 5/6 are dirty — but "dirty" ≠ "has work." Inspect each with `git -C "$wt" status --porcelain` and judge by *what* is dirty.

**The burden of proof is on "disposable."** A worktree is force-removable only if it has **zero tracked edits** AND you can *affirmatively* classify **every** untracked entry as throwaway. If even one entry is something you can't confidently call throwaway, **keep the worktree and ask** — because untracked + `--force` is unrecoverable (no reflog, no undo). Do not default an unclassified file to disposable.

| Dirty state | Verdict |
|---|---|
| Tracked modifications/additions/**deletions** (`M`/`A`/`D`) to real files | **KEEP** — genuine uncommitted work |
| Untracked **symlink** (usually → another clone in the same parent folder) | disposable — zero real data; removing the worktree deletes only the link, never the target |
| Untracked `.claude/*` local config (`settings.local.json`, `launch.json`) | disposable — the user commits these if they want to keep them |
| Untracked agent-process artifacts (`docs/superpowers/*`, stray specs / plans / brainstorm notes) | disposable — not committed by rule; confirm the *pattern*, don't assume |
| Untracked build output (`node_modules`, `.next`, `.turbo`, `dist/`, `build/`, `.DS_Store`) | disposable |
| Untracked **real** files/dirs — actual docs, code, data reports, or results | **KEEP** — a deliverable, not an artifact |
| Untracked file you can't confidently place in a row above | **KEEP and ask** — don't guess |

**Watch the lookalike.** A process artifact and a deliverable can share the `.md` extension: `docs/superpowers/plan.md` is throwaway, but a benchmark report, an analysis write-up, or anything under a `results/` or `analysis/` path is real work. The **path and content decide, not the extension** — open every untracked file you can't classify on sight (there may be several; check them all, not just one).

**The disposable rows are examples, not a closed list.** The principle is: untracked things that are *throwaway by convention* — machine-local config, agent-process artifacts, symlinks, build output, etc. — look like work to git's dirty check but carry no committed value. Generalize it. New tools invent new throwaway patterns; judge by "would the user ever commit this?" rather than matching these three literally. Conversely, don't over-apply — a lone untracked `.md` might be a real research deliverable, so open it before deciding. When a worktree is disposable on every count, remove it with `git worktree remove --force` and delete its branch. **When in doubt, keep it and ask the user** — name the specific file that made you hesitate.

Handle a corrupt worktree (its `.git` was partially deleted in an earlier timeout, so `git worktree remove` errors with "validation failed") by `rm -rf` on the directory, then `git -C "$repo" worktree prune`.

### Step 8 — Compact the repos with gc

Deleting branches leaves unreachable objects behind. Reclaim them:

```bash
git -C "$repo" gc --prune=now
```

Run gc on the repos you removed branches from. If that's many, prioritize the **5–10 largest by `.git` size** (`du -sh "$repo/.git"`, sort, take the top) — that's where compaction pays off. `--prune=now` drops the now-unreachable objects while keeping reflog-reachable history, so it won't nuke your recovery net. The payoff is modest when branches were merged (their commits still live in the default branch) — that's expected; the real disk was in the worktree checkouts.

### Step 9 — Report reclaimed disk

Re-measure the containers and `.git` dirs from Steps 2/8. Report a before/after table and a grand total. State plainly what was **kept and why** (real uncommitted work, open PRs, unverifiable state) so the user can trust nothing valuable was touched.

## Output

```
Reclaimed ~<N> GB.

Removed <count> worktrees + branches:
- <count> stale refs pruned
- <count> provably-merged
- <count> squash-merged (via GitHub)
- <count> dirty-but-disposable (symlinks / local config / agent artifacts)

Kept <count> (untouched): <real uncommitted work>, <open PRs>, <no-PR/local-only>, <unverifiable detached HEADs>.

git gc reclaimed ~<N> MB across the <count> largest repos.
```

## Error paths

- **`gh` unavailable / unauthenticated** → skip Step 6, report that squash-merged worktrees couldn't be detected and were left. Don't guess merge state.
- **`worktree remove` reports uncommitted/untracked changes** → expected; route to Step 7 triage. Never blanket `--force`.
- **Removal loop times out** → resume the idempotent background loop; it skips already-processed paths.
- **"validation failed, cannot remove working tree"** → the worktree is corrupt; `rm -rf` the dir and `git worktree prune`.
- **Genuinely ambiguous dirty worktree** → keep it, name the file that gave you pause, and ask the user. Never force-remove on a hunch.
