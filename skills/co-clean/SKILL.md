---
name: co-clean
description: Use when reclaiming disk space from obsolete git worktrees and merged branches, across a folder of cloned repos or a single repo — especially after heavy AI-agent / worktree workflows leave many stale checkouts behind
---

# co-clean

Reclaim disk space trapped in obsolete git worktrees and merged branches. AI agents and worktree-based workflows (Claude Code, Superset, Conductor, and tool-managed feature stacks) leave behind dozens of checkouts — each with its own `node_modules` — long after their branches merged. This finds the safe-to-remove ones, removes them, deletes their merged branches, and compacts the repos.

**Scope:** Run from a directory containing many cloned repos (cleans all of them) or from inside a single repo (cleans just that one). Worktrees are found via `git worktree list` regardless of where on disk they live — the working directory of the checkout does not have to be next to the repo.

## The prime directive

**Discover everything → classify everything → report the complete plan → confirm once → then delete.** Every removal candidate — merged, squash-merged, and dirty-but-disposable alike — must appear in the report the user approves. Never delete anything that wasn't in the plan they saw. Cleanup is destructive and mostly irreversible.

**Two rules decide what stays, and both must pass to remove:**

1. **Merged** — the work is provably in the default branch, OR its PR is merged on GitHub *and the worktree's HEAD is exactly what merged*.
2. **Pushed** — nothing local-only, and no local commits beyond what's on the remote.

> If it's unmerged **or** unpushed (local-only, or ahead of the remote), leave it. Full stop.

You never run a separate "is it pushed?" check — the removal gates guarantee it: an ancestor of `origin/<default>` is on the remote, and a squash-merge is only eligible when the local HEAD matches the merged PR's head commit. Everything else is left. In particular, **a branch with no PR that isn't an ancestor is treated as local-only and kept** — clean working tree or not.

**A single "dirty" flag is not a reason to keep a worktree** — but neither is a clean `git status` a reason to remove one. Git's dirty check has blind spots (ignored files, collapsed untracked directories). Classify by *what's actually on disk*, not by exit codes.

## Preconditions

- **`gh` authenticated** — `gh auth status`. Required: co-clean uses it to resolve each repo's slug and default branch (Step 1) and to detect and verify squash-merges (Step 4). If `gh` is unavailable or a repo won't resolve, that repo can't be classified safely — skip it and say so, rather than guessing.
- **Never use `cd` to enter a repo for read commands.** Use `git -C <repo> …` and `gh -R <owner/repo> …`. Entering a repo directory can trigger shell/`direnv`/`corepack` hooks that print banners into your captured output and corrupt parsing.

## Flow

Steps 1–5 are **discovery** — no deletions until the user approves in Step 6. The one state change they make is a `git fetch` per repo (Step 3), needed to classify against current history.

### Step 1 — Enumerate repos and their worktrees

Resolve the set of repos to scan:

- **Parent-folder scan:** each subdirectory whose `.git` is a *directory* is a repo. A `.git` *file* marks a linked worktree, not a top-level repo — skip it here (its worktrees are reached through its own repo).
- **Invoked inside a single repo or linked worktree** (its `.git` may be a file): resolve the one shared repo and scan that:

  ```bash
  repo=$(dirname "$(git -C . rev-parse --path-format=absolute --git-common-dir)")
  ```

For each repo, list worktrees and resolve its GitHub slug + default branch **once**, from the remote URL — no regex (BSD and GNU `sed` differ; `+?` is invalid on macOS). Fail closed (skip the repo) if resolution fails:

```bash
git -C "$repo" worktree list --porcelain
read -r owner_repo def < <(gh repo view "$(git -C "$repo" remote get-url origin)" \
  --json nameWithOwner,defaultBranchRef --jq '"\(.nameWithOwner) \(.defaultBranchRef.name)"')
```

Parse `worktree`/`HEAD`/`branch`/`detached`/`prunable` records. Git guarantees the **first record is the main worktree** — identify it that way and skip it (you only clean *linked* worktrees). Don't identify the main worktree by comparing paths.

### Step 2 — Measure where the disk actually is

`du -sh` the worktree container directories so you can prioritize and report a real number later. Common homes: `~/.claude/worktrees`, `~/.superset/worktrees`, `~/conductor/workspaces`, in-repo `.claude/worktrees`, and tool-managed feature dirs. **`du` over `node_modules` is slow — give it a long timeout or run it in the background.**

### Step 3 — Classify by merge status

**Fetch first, and fail closed.** A stale remote-tracking ref can *mis*classify — after a force-rewrite of the default branch, a removed commit still looks like an ancestor and reads MERGED, which would delete the only local copy of that work. So refresh the default ref before any destructive classification, and if the fetch fails, leave the whole repo untouched:

Fetch with an **explicit destination refspec** so `origin/$def` actually advances — a narrow `remote.origin.fetch` mapping can otherwise leave it stale while only `FETCH_HEAD` moves:

```bash
git -C "$repo" fetch origin "+refs/heads/$def:refs/remotes/origin/$def" \
  || { echo "fetch failed — skipping $repo"; continue; }
git -C "$repo" merge-base --is-ancestor "$head" "origin/$def"   # true = provably merged
```

`--is-ancestor` is **conservative**: true only for real merges, never a false positive. Squash-merged branches read as UNMERGED here — Step 4 catches those. Bucket each worktree: `PRUNABLE` (temp dir gone) · `MERGED` (ancestor) · `UNMERGED` (else).

> zsh gotcha: `status` is a read-only variable. Name your loop variable something else (`st`).

### Step 4 — Resolve UNMERGED against GitHub (catch squash-merges, verify the commit)

Most "unmerged" worktrees from tool/PR-review workflows are actually **squash-merged**. But a merged PR with a given branch name does **not**, by itself, prove *this* worktree is safe — the branch may have been reused, gained local commits after the merge, or had its merged content later dropped by a force-rewrite of the default. Verify the *merge is still on the default branch* and the checkout matches it. Use the `owner_repo` resolved in Step 1 and normalize the porcelain branch ref:

```bash
branch=${branch_ref#refs/heads/}                       # porcelain gives refs/heads/<name>
read -r pr_state pr_merged pr_oid pr_mergeoid < <(gh -R "$owner_repo" pr list --head "$branch" --state all \
  --json state,mergedAt,headRefOid,mergeCommit \
  --jq '.[0] | "\(.state) \(.mergedAt) \(.headRefOid) \(.mergeCommit.oid // "")"')
```

Eligible for removal only when **all** hold: `mergedAt` is set, `pr_oid` == the worktree's HEAD sha, and the PR's `mergeCommit` is still reachable from the freshly-fetched default branch (`git -C "$repo" merge-base --is-ancestor "$pr_mergeoid" "origin/$def"`). Then the checkout is exactly what merged, and that merge is still on the default branch.

- **OID differs** → the local branch diverged from what merged (reused name, or commits added after). **Keep and ask** — `-D` would destroy those commits.
- **`mergeCommit` empty, or not an ancestor of the default** → can't prove the work is still on the default branch (unavailable merge OID, or a post-merge force-rewrite). **Keep and ask** — fail closed. This also handles feature-stack PRs correctly: a merge into a parent branch becomes eligible only once that stack reaches the default.
- **OPEN** → leave. **CLOSED without merge** → unmerged, leave. **No PR** → possibly local-only, leave.

Detached-HEAD worktrees have no branch to look up. You *may* try to tie the commit to a merged PR (`gh -R "$owner_repo" pr list --search "$head" --state merged`), but if it doesn't cleanly resolve, **leave them**.

### Step 5 — Inventory dirty worktrees (look before you keep — or trash)

For every MERGED / eligible-squash-merged worktree, inventory what's actually on disk *before* deciding — `git worktree remove` without `--force` refuses tracked/untracked changes, but it will happily delete **ignored** files, and default status **collapses untracked directories**. Enumerate fully, NUL-safe:

```bash
git -C "$wt" status -z --porcelain=v1 --untracked-files=all --ignored=matching
```

`--ignored=matching` lists ignored *roots and patterns* (so a huge `node_modules` doesn't flood or truncate the output the way full `--ignored` would), while `--untracked-files=all` expands untracked directories so a real file can't hide inside one. `-z` keeps odd paths parseable.

Status alone won't reveal a **clean** initialized submodule, so check explicitly — any initialized entry (or a failure of this command) means keep-and-ask:

```bash
git -C "$wt" submodule status    # any populated entry → keep and ask
```

**The burden of proof is on "disposable."** A worktree is force-removable only if it has **zero tracked edits** AND every untracked *and every ignored* path is affirmatively throwaway. If even one path is something you can't confidently call throwaway, **keep the worktree and ask** — untracked/ignored + removal is unrecoverable (no reflog, no undo). Don't default an unclassified path to disposable.

| On-disk state | Verdict |
|---|---|
| Tracked modifications/additions/**deletions** (`M`/`A`/`D`) to real files | **KEEP** — genuine uncommitted work |
| Untracked **symlink** (usually → another clone in the same parent folder) | disposable — zero real data; removal deletes only the link, never the target |
| Untracked/ignored `.claude/*` local config (`settings.local.json`, `launch.json`) | disposable — the user commits these if they want them |
| Untracked agent-process artifacts (`docs/superpowers/*`, stray specs / plans / notes) | disposable — not committed by rule; confirm the *pattern*, don't assume |
| Ignored build output (`node_modules`, `.next`, `.turbo`, `dist/`, `build/`, `.DS_Store`) | disposable |
| Ignored **data/secrets** (`.env*`, credentials, local databases, dumps) | **KEEP and ask** — ignored ≠ worthless; these never come back |
| Untracked **real** files/dirs — actual docs, code, data reports, or results | **KEEP** — a deliverable, not an artifact |
| Worktree has **initialized submodules** | **KEEP and ask** — superproject status can hide submodule-local changes, and removal needs `--force`; don't force past an unread submodule |
| Any untracked/ignored path you can't confidently place above | **KEEP and ask** — don't guess |

**Watch the lookalike.** A process artifact and a deliverable can share the `.md` extension: `docs/superpowers/plan.md` is throwaway, but a benchmark report, an analysis write-up, or anything under a `results/`/`analysis/` path is real work. The **path and content decide, not the extension** — open every file you can't classify on sight (check them all, not just one).

**The disposable rows are examples, not a closed list.** The principle: things that are *throwaway by convention* look like data to a filesystem scan but carry no value. New tools invent new throwaway patterns; judge by "would the user ever commit or miss this?" and generalize.

### Step 6 — Report the complete plan and confirm (the one gate)

Show the user the whole plan in one place: total reclaimable disk, the biggest wins, and — grouped — every worktree that will be **pruned**, **removed** (clean merged), **force-removed** (dirty-but-disposable, with the reason), and every branch that will be deleted. Call out anything headed to keep-and-ask. **Get one go-ahead covering all of it before deleting anything.** Use `AskUserQuestion` for scope. Nothing below this line runs until they approve.

### Step 7 — Execute removals

**Revalidate immediately before each removal.** The confirmation in Step 6 can sit for a while, and the worktrees this skill targets are often still live — an agent may commit or drop a file, or the remote default may be force-rewritten, between the plan and the delete. Just before removing each one, re-fetch the default (`+refs/heads/$def:refs/remotes/origin/$def`) and re-check *everything* that made it eligible against current state:

- HEAD still equals the planned SHA.
- A fresh Step 5 inventory + `submodule status` is still clean-or-disposable.
- **Merge proof re-run against the just-fetched default** — for ancestor-merges, `merge-base --is-ancestor "$planned_sha" "origin/$def"`; for squash-merges, the `mergeCommit` is still an ancestor of `origin/$def` and the OID still matches. Don't lean on Step 3's earlier classification, and don't lean on `branch -d` to catch it (it checks the upstream or local HEAD, not `origin/$def`).
- Before `branch -D`, the branch ref still equals the approved SHA.

**If anything changed or any recheck command fails, skip that worktree** and report that it needs a new plan and confirmation — never delete against a stale snapshot.

```bash
git -C "$repo" worktree prune                    # PRUNABLE: temp dirs already gone
git -C "$repo" worktree remove "$wt"             # clean merged: no --force
git -C "$repo" worktree remove --force "$wt"     # dirty-but-disposable only (Step 5 cleared it)
```

Then delete the branch:

- **Ancestor-merged** (Step 3): `git -C "$repo" branch -d "$branch"` — the *safe* delete; it succeeds because the branch is merged. If it ever refuses, stop and recheck rather than escalating.
- **Squash-merged** (Step 4, OID verified): `-d` refuses (not an ancestor), so use `git -C "$repo" branch -D "$branch"` — but only for a branch whose merged-PR head commit you confirmed equals its HEAD, via a **repo-scoped** `gh -R "$owner_repo"` lookup. Branch names collide across repos; an unscoped or unverified match can force-delete unmerged work.
- **Detached HEAD**: no branch to delete.

**These operations are slow** (deleting tens of GB of `node_modules`) and will time out a foreground call. Run the removal loop in the background and make it **idempotent** (skip paths already logged) so you can resume after a timeout. Don't run two removal loops against the *same* repo concurrently — you'll hit an index lock.

**Corrupt worktree** (its `.git` link was partially deleted, so `git worktree remove` errors with "validation failed"): try `git -C "$repo" worktree repair "$wt"` first, then re-inventory it through Step 5. Only `rm -rf` the directory once Step 5 confirms it's disposable — corrupt metadata doesn't mean the directory is empty of real files.

### Step 8 — Compact the repos with gc

Deleting branches leaves unreachable objects behind. Reclaim them **after** all removals:

```bash
du -sh "$repo/.git"                # measure to pick targets
git -C "$repo" gc --prune=now      # only when the repo is idle
```

Run gc on the repos you removed branches from; if that's many, prioritize the **5–10 largest by `.git` size**. Be precise about what `--prune=now` does: a deleted branch's reflog is gone too, so its now-unreachable commits are **permanently** dropped here (intended — you proved them merged, but it is not recoverable afterward). And `--prune=now` **risks corruption if another process writes to the repo concurrently** — only run it when nothing else is touching that repo. If you want a safety window, plain `git gc` keeps the default grace period. The payoff is modest when branches were merged (their commits still live in the default branch) — the real disk was in the worktree checkouts.

### Step 9 — Report reclaimed disk

Re-measure the containers and `.git` dirs from Steps 2/8. Report a before/after table and a grand total. State plainly what was **kept and why** (real uncommitted work, open PRs, diverged/local-only branches, ignored data, unverifiable detached HEADs) so the user can trust nothing valuable was touched.

## Output

```
Reclaimed ~<N> GB.

Removed <count> worktrees + branches:
- <count> stale refs pruned
- <count> provably-merged
- <count> squash-merged (GitHub-verified, HEAD matched)
- <count> dirty-but-disposable (symlinks / local config / agent artifacts)

Kept <count> (untouched): <real uncommitted work>, <open PRs>, <diverged/local-only>, <ignored data>, <unverifiable detached HEADs>.

git gc reclaimed ~<N> MB across the <count> largest repos.
```

## Error paths

- **`gh` unavailable / unauthenticated, or slug/default resolution fails** → skip that repo (fail closed). Report that it couldn't be classified and was left untouched. Don't guess.
- **`git fetch` fails for a repo** → skip the whole repo. A stale ref can misclassify, so never classify destructively against one.
- **Squash-merge PR found but HEAD OID doesn't match, or its `mergeCommit` isn't an ancestor of the fetched default** → the local branch diverged, or the merge is no longer on the default branch; keep and ask. Never `-D` on a name match alone.
- **`worktree remove` reports uncommitted/untracked changes** → expected; it went to Step 5 triage. Never blanket `--force`.
- **Removal loop times out** → resume the idempotent background loop; it skips already-processed paths.
- **"validation failed, cannot remove working tree"** → try `git worktree repair`; if that fails, triage the dir (Step 5) and confirm before any `rm -rf`.
- **Genuinely ambiguous dirty/ignored path** → keep the worktree, name the file that gave you pause, and ask. Never force-remove on a hunch.
