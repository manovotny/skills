---
name: co-clean
description: Use when reclaiming disk space from obsolete git worktrees and merged branches, across a folder of cloned repos or a single repo — especially after heavy AI-agent / worktree workflows leave many stale checkouts behind
---

# co-clean

Reclaim disk space trapped in obsolete git worktrees and merged branches. AI agents and worktree-based workflows (Claude Code, Superset, Conductor, and tool-managed feature stacks) leave behind dozens of checkouts — each with its own `node_modules` — long after their branches merged. This finds the safe-to-remove ones, removes them, deletes their merged branches, trims regenerable build output from the ones it keeps, and compacts the repos. It can also clear the developer caches this workflow piles up (stale package-manager stores, build caches) as a separately approved step.

**Scope:** Run from a directory containing many cloned repos (cleans all of them) or from inside a single repo (cleans just that one). Worktrees are found via `git worktree list` regardless of where on disk they live — the working directory of the checkout does not have to be next to the repo — plus a sweep of the usual worktree folders for orphaned checkouts git no longer lists (Step 1). Application data under `~/Library/Application Support` (Slack, Notion, desktop-app VMs) is out of scope; never touch it.

## The prime directive

**Discover everything → classify everything → report the complete plan → confirm once → then delete.** Every removal candidate — merged, squash-merged, and dirty-but-disposable alike — must appear in the report the user approves. Never delete anything that wasn't in the plan they saw. Cleanup is destructive and mostly irreversible.

**Two rules decide what stays, and both must pass to remove:**

1. **Merged** — the work is provably in the default branch, OR its PR is merged on GitHub *and the worktree's HEAD is exactly what merged*.
2. **Pushed** — nothing local-only, and no local commits beyond what's on the remote.

> If it's unmerged **or** unpushed (local-only, or ahead of the remote), leave it. Full stop.

You never run a separate "is it pushed?" check — the removal gates guarantee it: an ancestor of `origin/<default>` is on the remote, and a squash-merge is only eligible when the local HEAD matches the merged PR's head commit. Everything else is left. In particular, **a branch with no PR that isn't an ancestor is treated as local-only and kept** — clean working tree or not.

**One opt-in exception: idle review checkouts of open PRs** (Step 4). They fail rule 1 but are fully recoverable with `gh pr checkout`. They're offered as their own group, off by default, and removed only when the user explicitly opts that group in.

**A single "dirty" flag is not a reason to keep a worktree** — but neither is a clean `git status` a reason to remove one. Git's dirty check has blind spots (ignored files, collapsed untracked directories). Classify by *what's actually on disk*, not by exit codes.

## Preconditions

- **`gh` authenticated** — `gh auth status`. Required: co-clean uses it to resolve each repo's slug and default branch (Step 1) and to detect and verify squash-merges (Step 4). If `gh` is unavailable or a repo won't resolve, that repo can't be classified safely — skip it and say so, rather than guessing.
- **Write for the shell you're actually in.** On macOS that's usually zsh, and the background loop in Step 7 often runs under `/bin/bash` 3.2. Each has traps that fail silently. Run *every* loop as a `bash` script, including one-off checks like Step 9's idle test, since an inline loop pasted into zsh hits the traps below:
  - **zsh reads `$var:x` as a history modifier.** `"+refs/heads/$def:refs/remotes/origin/$def"` expands `$def:r` (strip extension), so `main` becomes `mainefs/remotes/…` and every fetch fails. Always brace a variable followed by a colon: `${def}:`.
  - **zsh doesn't word-split unquoted variables.** `set -- $line` or `for x in $list` gets one word, not many. Parse with `read -r a b c <<< "$line"` or `awk`.
  - **`status` is read-only in zsh.** Name loop variables something else (`st`).
  - **macOS `/bin/bash` is 3.2.** No associative arrays (`declare -A`), no `mapfile`. Track per-repo state with marker files or plain lists.
  - **`IFS=$'\t' read` collapses empty fields.** Tab is IFS whitespace, so `a<TAB><TAB>c` reads as two fields and every later column shifts. Plan rows with empty columns (no branch, no untracked files) then misparse silently. Read through a non-whitespace delimiter: `tr '\t' '\037' < plan.tsv | while IFS=$'\037' read -r …`.
- **Never use `cd` to enter a repo for read commands.** Use `git -C <repo> …` and `gh -R <owner/repo> …`. Entering a repo directory can trigger shell/`direnv`/`corepack` hooks that print banners into your captured output and corrupt parsing.

## Flow

Steps 1–5 are **discovery** — no deletions until the user approves in Step 6. The only state changes they make are `git fetch`es (the default branch in Step 3, PR heads in Step 4), needed to classify against current history.

### Step 1 — Enumerate repos and their worktrees

Resolve the set of repos to scan:

- **Parent-folder scan:** each subdirectory whose `.git` is a *directory* is a repo. A `.git` *file* marks a linked worktree, not a top-level repo — skip it here (its worktrees are reached through its own repo). Also descend one level into subdirectories that aren't repos themselves: grouping folders like `!personal/` or `work/` hold repos too. One run missed a 47-worktree repo this way. Skip symlinks at both levels (`[ -L "$d" ] && continue`): a repo can contain a link to itself (`clerk_go/clerk_go -> .`), and following it counts the repo twice.
- **No `origin` remote** → there's no GitHub repo to verify against, so skip the repo and list it as unclassified in the plan, like a `gh` resolution failure.
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

**Then sweep for orphans.** A checkout whose admin directory (`<repo>/.git/worktrees/<name>`) was deleted — by `worktree prune` after a move, a crashed tool, or a manual cleanup — no longer appears in `git worktree list` and won't be marked `prunable`. Its directory, `node_modules` and all, stays on disk invisibly. Walk the worktree folders two levels deep (tools nest them as `<container>/<repo>/<name>`): Step 2's list, plus the scan root and its grouping folders, where hand-made sibling worktrees (`skills-<topic>/`) and ad-hoc checkouts live, and flag any directory whose `.git` file points at a missing gitdir. Run it under `bash`; in zsh an unmatched glob aborts the loop:

```bash
for d in "$container"/*/ "$container"/*/*/; do
  d=${d%/}; [ -f "$d/.git" ] || continue
  gd=$(sed -n 's/^gitdir: //p' "$d/.git")
  [ -n "$gd" ] && [ ! -e "$gd" ] && echo "ORPHAN $d -> $gd"
done
```

An orphan has no git metadata left to prove anything, so it can't be classified as MERGED. Its committed history is fine (it lives in the shared repo), but its working-tree files are unknown. Inventory it against the shared repo instead (file mtimes don't help: checkout writes every file after the `.git` link):

```bash
git --git-dir="$repo/.git" --work-tree="$d" ls-files --others --exclude-standard |
  while read -r p; do git -C "$repo" log --all --oneline -1 -- "$p" | grep -q . || echo "NO HISTORY: $p"; done
git --git-dir="$repo/.git" --work-tree="$d" ls-files --others --ignored --exclude-standard --directory
```

The first lists files the main checkout's index doesn't have. Any of them with history somewhere in the repo came from a commit; one with **no history** is real uncommitted work, so keep and ask. The second lists ignored roots for the same Step 5 judgment as any worktree. Both only read; `ls-files` doesn't write the main index. Report every orphan in the plan as its own group. Remove it only with explicit approval, via `rm -rf`, never `git worktree remove` (git doesn't know it).

**Say what the inventory can't see.** Edits to *tracked* files in an orphan are undetectable: without its HEAD there's nothing to diff against, and a diff against the default branch is all branch noise (one orphan showed 1,721 changed files). State that in the plan next to the orphan's age, so the user decides knowing it.

Save both `ls-files` outputs at plan time, and re-run and compare them byte-for-byte before the `rm -rf`, the same as the Step 7 snapshot for worktrees.

Empty per-repo folders left in a container (`~/.claude/worktrees/<repo>/` after its last worktree went) hold no data. Note the count; `rmdir` them only if the user wants the tidy-up.

### Step 2 — Measure where the disk actually is

`du -sh` the worktree container directories so you can prioritize and report a real number later. Common homes: `~/.claude/worktrees`, `~/.superset/worktrees`, `~/conductor/workspaces`, in-repo `.claude/worktrees`, and tool-managed feature dirs. **`du` over `node_modules` is slow — give it a long timeout or run it in the background.**

Treat `du` totals as an **upper bound**, not a promise. pnpm (and some other package managers) hard-link `node_modules` from a shared store, so `du` counts bytes that won't come back when a checkout is deleted. One run measured ~73 GB of worktrees and freed ~32 GB. Record `df -h /` now too, so Step 11 can report what was actually freed. Also measure the developer caches Step 10 covers (`pnpm store path` and its sibling version folders, `go env GOCACHE`, `~/Library/Caches/ms-playwright`). Old pnpm store versions are often the reason a worktree cleanup frees far less than `du` predicted: the checkouts were hard-linked to a store nobody prunes.

### Step 3 — Classify by merge status

**Fetch first, and fail closed.** A stale remote-tracking ref can *mis*classify — after a force-rewrite of the default branch, a removed commit still looks like an ancestor and reads MERGED, which would delete the only local copy of that work. So refresh the default ref before any destructive classification, and if the fetch fails, leave the whole repo untouched:

Fetch with an **explicit destination refspec** so `origin/$def` actually advances — a narrow `remote.origin.fetch` mapping can otherwise leave it stale while only `FETCH_HEAD` moves:

```bash
git -C "$repo" fetch origin "+refs/heads/${def}:refs/remotes/origin/${def}" \
  || { echo "fetch failed — skipping $repo"; continue; }
git -C "$repo" merge-base --is-ancestor "$head" "origin/$def"   # true = provably merged
```

`--is-ancestor` is **conservative**: true only for real merges, never a false positive. Squash-merged branches read as UNMERGED here — Step 4 catches those. Bucket each worktree: `PRUNABLE` (temp dir gone) · `MERGED` (ancestor) · `UNMERGED` (else).

### Step 4 — Resolve UNMERGED against GitHub (catch squash-merges, verify the commit)

Most "unmerged" worktrees from tool/PR-review workflows are actually **squash-merged**. But a merged PR with a given branch name does **not**, by itself, prove *this* worktree is safe — the branch may have been reused, gained local commits after the merge, or had its merged content later dropped by a force-rewrite of the default. Verify the *merge is still on the default branch* and the checkout matches it. Use the `owner_repo` resolved in Step 1 and normalize the porcelain branch ref:

```bash
branch=${branch_ref#refs/heads/}                       # porcelain gives refs/heads/<name>
read -r pr_state pr_merged pr_oid pr_mergeoid < <(gh -R "$owner_repo" pr list --head "$branch" --state all \
  --json state,mergedAt,headRefOid,mergeCommit \
  --jq '.[0] // empty | "\(.state) \(.mergedAt) \(.headRefOid) \(.mergeCommit.oid // "")"')
```

Eligible for removal only when **all** hold: `mergedAt` is set, `pr_oid` == the worktree's HEAD sha, and the PR's `mergeCommit` is still reachable from the freshly-fetched default branch (`git -C "$repo" merge-base --is-ancestor "$pr_mergeoid" "origin/$def"`). Then the checkout is exactly what merged, and that merge is still on the default branch.

- **OID differs** → first check whether the local copy is just *behind* what merged. Review checkouts are often taken before the author's last push. Fetch the PR head and test ancestry:

  ```bash
  git -C "$repo" fetch origin "pull/${pr_num}/head" </dev/null
  git -C "$repo" merge-base --is-ancestor "$head" "$pr_oid"   # true = local has nothing the PR lacks
  ```

  True means every local commit is in the merged PR, so treat it exactly like an OID match (still subject to the `mergeCommit` check below). False means the local branch diverged (reused name, or commits added after). **Keep and ask** — `-D` would destroy those commits.
- **`mergeCommit` empty, or not an ancestor of the default** → can't prove the work is still on the default branch (unavailable merge OID, or a post-merge force-rewrite). **Keep and ask** — fail closed. This also handles feature-stack PRs correctly: a merge into a parent branch becomes eligible only once that stack reaches the default.
- **Stacked PR** (`baseRefName` isn't the default) → follow the chain: look up the PR whose head is that base (`gh -R "$owner_repo" pr list --head "$base" --state all`) and repeat until you reach the default or an unmerged link. If the parent was squash-merged, the child's merge commit never becomes an ancestor of the default, so it stays keep-and-ask. Show the chain when you ask (`#3161 → typedoc-ddf9afc → #3356 merged to main`, or `#3117 → #3111 still open`), which lets the user decide in one glance.
- **OPEN** → leave. **CLOSED without merge** → unmerged, leave.
- **PR number from the name isn't in this repo** → `gh pr view` fails or returns another repo's PR (a `pr-3365-review` worktree in a repo that has no #3365). Report it as "no matching PR in this repo", not as diverged.
- **No PR by branch name** → don't conclude "no PR" yet. Local names often don't match the PR's head branch: `git fetch origin pull/479/head:pr-479-review`, `gh pr checkout` with a custom name, a renamed branch, or a fork. Fall back to the commit search used for detached HEADs below, and also try a PR number embedded in the name (`pr-479-…` → `gh -R "$owner_repo" pr view 479`). Report what you find, e.g. "open PR #479, local copy behind its head", which tells the user far more than "no PR". Only call a branch local-only when both searches come back empty, and leave it either way unless it passes the same squash-merge proof.

**Detached-HEAD worktrees** have no branch to look up, but PR-review checkouts are usually the exact head commit of a PR, so they're worth resolving. Search by SHA across all states (an open PR feeds the opt-in review group below) and hold a merged result to the **same proof as a squash-merge**:

```bash
gh -R "$owner_repo" pr list --search "$head" --state all --json number,state </dev/null
```

For each hit, `gh pr view` it for `headRefOid` and `mergeCommit`. Eligible only when a PR's `headRefOid` equals HEAD, or HEAD is an ancestor of it (fetch `pull/<n>/head` first, as above), and its `mergeCommit` is an ancestor of the fetched `origin/$def`. A search hit alone proves nothing; the SHA may only appear in a comment. No such PR, or no reachable merge commit → **leave it**. There's no branch to delete afterward.

**Opt-in group: idle review checkouts of open PRs.** Reviewing teammates' PRs leaves a checkout per PR, and while the PR is open the rules above keep it — often the biggest bucket by size. Offer one as removable *only if the user opts the group in* at Step 6, and only when all hold:

- The PR was opened by **someone else** (`author.login` differs from `gh api user --jq .login`). The user's own open PRs are work in progress, not review copies, so they stay kept.
- The PR is **OPEN** and HEAD equals or is an ancestor of its current `headRefOid` (fetched as above), so every local commit is on GitHub.
- The branch has no commits beyond its upstream (`git rev-list --count @{u}..HEAD` is 0, or there's no upstream and the ancestry check passed).
- Step 5's inventory comes back disposable, exactly as for a merged worktree.
- No agent session activity in the last **7 days** (Step 5's session check, with a longer window).

Report each with its PR number and author so the user can see these are review copies, not their own work in progress, and note that `gh pr checkout <n>` restores it. Delete the local branch with `-D` only for these approved entries; its commits are all on the PR head.

> Quoting trap: a jq filter inside a double-quoted shell string needs every inner `"` escaped, including the `// ""` fallback. Get it wrong and the fallback glues onto the OID (`<sha>-`), which then fails `merge-base`. Fail-closed, but it silently disqualifies every candidate. Print the parsed fields once before trusting them.

### Step 5 — Inventory dirty worktrees (look before you keep — or trash)

For every MERGED / eligible-squash-merged worktree, inventory what's actually on disk *before* deciding — `git worktree remove` without `--force` refuses tracked/untracked changes, but it will happily delete **ignored** files, and default status **collapses untracked directories**. Enumerate fully, NUL-safe:

```bash
git -C "$wt" status -z --porcelain=v1 --untracked-files=all --ignored=matching
```

Count entries, not NUL fields: a rename or copy (`R`/`C`) entry carries a second NUL-terminated path, so splitting on NUL alone misreads that path as its own entry.

`--ignored=matching` lists ignored *roots and patterns* (so a huge `node_modules` doesn't flood or truncate the output the way full `--ignored` would), while `--untracked-files=all` expands untracked directories so a real file can't hide inside one. `-z` keeps odd paths parseable.

**A file-pattern ignore rule lists every match.** `--ignored=matching` collapses ignored *directories* to one line, but a rule like `apps/*/icons/**/*.tsx` matches files, so each one prints (one dashboard checkout printed hundreds of generated icons). Group these by the rule that ignores them, `git -C "$wt" check-ignore -v <path>`, and judge the rule once.

**An ignored root is one line, but it can hide anything.** `!! bin/` says nothing about what's inside `bin/`. So never filter the inventory by directory *name* to keep output short. A name filter broad enough to be convenient (`bin`, `tmp`, `out`, `local`, `vendor`, `.cache`, `.vercel`) is broad enough to hide `bin/creds.json` or a `vercel env pull` result. Only a short allowlist of roots whose contents are regenerable by definition may go unopened: `node_modules/`, `.next/`, `.turbo/`, `dist/`, `.swc/`, `.DS_Store`, `*.tsbuildinfo`, `next-env.d.ts`. Every other ignored root gets opened (`find "$wt/<root>" -maxdepth 2 -type f | head`) before it's called disposable. Compare it against the same path in the main checkout when there is one.

Status alone won't reveal a **clean** initialized submodule, so check explicitly — any initialized entry (or a failure of this command) means keep-and-ask:

```bash
git -C "$wt" submodule status    # any populated entry → keep and ask
```

**The burden of proof is on "disposable."** A worktree is removable only if it has **zero tracked edits** AND every untracked *and every ignored* path is affirmatively throwaway. If even one path is something you can't confidently call throwaway, **keep the worktree and ask** — untracked/ignored + removal is unrecoverable (no reflog, no undo). Don't default an unclassified path to disposable.

**Disposable ≠ needs `--force`.** Plain `git worktree remove` already deletes ignored files; it only refuses on tracked edits or untracked files. So split the disposable set by *what kind* of extra files it has:

- **Ignored-only** (every non-clean status line is `!!`) → plain `remove`. In practice this is most of them: `node_modules`, build output, identical `.env` copies.
- **Has untracked disposables** (`??` symlinks, agent artifacts) → `remove --force`, the only case that needs it.

| On-disk state | Verdict |
|---|---|
| Tracked modifications/additions/**deletions** (`M`/`A`/`D`) to real files | **KEEP** — genuine uncommitted work |
| Untracked **symlink** (usually → another clone in the same parent folder) | disposable — zero real data; removal deletes only the link, never the target |
| Untracked/ignored `.claude/*` local config (`settings.local.json`, `launch.json`) | disposable — the user commits these if they want them |
| Untracked agent-process artifacts (`docs/superpowers/*`, stray specs / plans / notes) | disposable — not committed by rule; confirm the *pattern*, don't assume |
| Ignored build output on the allowlist above (`node_modules`, `.next`, `.turbo`, `dist/`, `.DS_Store`) | disposable |
| Any other ignored directory (`build/`, `bin/`, `target/`, `tmp/`, `.vercel/`, …) | disposable only after opening it and finding regenerable output, such as compiled binaries or a `.vercel/project.json` link. Env or credential files inside → the secrets rows below |
| Ignored `.env*` that is **byte-identical** (`cmp -s`) to the same file in the repo's main checkout | disposable — a copy survives in the main checkout, so nothing is lost |
| Ignored **data/secrets** (`.env*` that differs or has no main-checkout copy, credentials, local databases, dumps) | **KEEP and ask** — ignored ≠ worthless; these never come back. When asking, show only the *key names* that differ (`cut -d= -f1`), never values |
| Untracked **real** files/dirs — actual docs, code, data reports, or results | **KEEP** — a deliverable, not an artifact |
| Worktree has **initialized submodules** | **KEEP and ask** — superproject status can hide submodule-local changes, and removal needs `--force`; don't force past an unread submodule |
| Any untracked/ignored path you can't confidently place above | **KEEP and ask** — don't guess |

**Watch the lookalike.** A process artifact and a deliverable can share the `.md` extension: `docs/superpowers/plan.md` is throwaway, but a benchmark report, an analysis write-up, or anything under a `results/`/`analysis/` path is real work. The **path and content decide, not the extension** — open every file you can't classify on sight (check them all, not just one).

**The disposable rows are examples, not a closed list.** The principle: things that are *throwaway by convention* look like data to a filesystem scan but carry no value. New tools invent new throwaway patterns; judge by "would the user ever commit or miss this?" and generalize.

**Check for agent sessions attached to each candidate.** A worktree can be merged and clean but still be some session's working directory. Removing it doesn't lose committed work, but the session gets moved to a fresh worktree on its next turn and loses its ignored files: installed deps, local env, build caches. Claude Code keeps one folder per working directory under `~/.claude/projects/`, named by the absolute path with every non-alphanumeric character replaced by `-`:

```bash
proj=~/.claude/projects/$(printf '%s' "$wt" | sed 's/[^A-Za-z0-9]/-/g')
last=$(ls -t "$proj"/*.jsonl 2>/dev/null | head -1)   # newest transcript, if any
```

**Group leftover agent worktrees.** Claude Code creates worktrees for subagents run with worktree isolation (directories `agent-<hex>`, branches `worktree-agent-<hex>`) and for `claude --worktree` sessions (branches `worktree-<name>`). When the agent ends with uncommitted edits, the worktree stays. Its result was usually applied elsewhere, but not always. They still fail the tracked-edits rule, so they stay keep-and-ask. List them as their own group with `git -C "$wt" diff --stat` and the creation date, rather than mixing them in with the user's real work, so the user can clear them in one decision.

No transcript doesn't mean idle: worktrees made by hand or by other tools never get one. Fall back to the worktree's reflog, `$(git -C "$wt" rev-parse --git-dir)/logs/HEAD`, which moves on every commit and checkout. With no reflog either (it can be disabled or missing), use the mtime of that git dir's `HEAD` file, which is written at checkout. If none of the three exists, call the activity unknown and keep and ask. **Never use the index mtime**: `git status` refreshes it, so your own Step 5 inventory makes every worktree look active.

Activity in the last 24 hours means a session may be live. Keep it and ask. Older activity is fine to remove, but name the session's last-active date in the plan so the user isn't surprised when a session reports that its worktree was recycled. Other tools (Superset, Conductor) track workspaces their own way; if one of them owns the worktree's container directory, ask rather than assume it's idle.

### Step 6 — Report the complete plan and confirm (the one gate)

Show the user the whole plan in one place: total reclaimable disk, the biggest wins, and — grouped — every worktree that will be **pruned**, **removed** (clean, or ignored-only extras), **force-removed** (untracked-but-disposable, with the reason), and every branch that will be deleted. Report the size as the Step 2 `du` upper bound. Call out anything headed to keep-and-ask. Also list, as separate groups with their own sizes: orphaned checkouts (Step 1), the opt-in review-checkout group (Step 4), agent worktrees (Step 5), build output to trim from kept worktrees (Step 8), gc (Step 9), and developer caches (Step 10). The opt-in groups, gc, and the cache group each need their own yes; approving the main plan doesn't approve them.

**Show every ignored and untracked root that will be deleted**, aggregated across the plan with a count and what it is (`10 × .vercel/ (project.json link only)`, `3 × local/bin/ (compiled Go tools)`). Allowlisted build output can collapse to one line. The user approves what's actually on disk, not a category label. A root you didn't list is a root they didn't approve. **Get one go-ahead covering all of it before deleting anything.** Use `AskUserQuestion` for scope. Nothing below this line runs until they approve.

### Step 7 — Execute removals

**Revalidate immediately before each removal.** The confirmation in Step 6 can sit for a while, and the worktrees this skill targets are often still live — an agent may commit or drop a file, or the remote default may be force-rewritten, between the plan and the delete. Just before removing each one, re-fetch the default (`+refs/heads/${def}:refs/remotes/origin/${def}`) and re-check *everything* that made it eligible against current state:

- HEAD still equals the planned SHA.
- A fresh Step 5 inventory **matches the snapshot the user approved**, and `submodule status` still shows nothing initialized. Make this mechanical: at plan time, save each worktree's sorted `status -z --porcelain=v1 --untracked-files=all --ignored=matching` output to a file keyed by a hash of its path, and at removal time compare the fresh output byte-for-byte. Any difference, even a new ignored file, means skip. Re-judging by eye at delete time is how a new `.env` slips through.
- **Merge proof re-run against the just-fetched default** — for ancestor-merges, `merge-base --is-ancestor "$planned_sha" "origin/$def"`; for squash-merges, the `mergeCommit` is still an ancestor of `origin/$def` and HEAD still equals (or is an ancestor of) the merged head. For opt-in review checkouts, the PR is still open or merged and HEAD is still an ancestor of its freshly fetched head. Don't lean on Step 3's earlier classification, and don't lean on `branch -d` to catch it (it checks the upstream or local HEAD, not `origin/$def`).
- Before `branch -D`, the branch ref still equals the approved SHA.

**If anything changed or any recheck command fails, skip that worktree** and report that it needs a new plan and confirmation — never delete against a stale snapshot.

```bash
git -C "$repo" worktree prune                    # PRUNABLE: temp dirs already gone
git -C "$repo" worktree remove "$wt"             # clean or ignored-only extras: no --force
git -C "$repo" worktree remove --force "$wt"     # untracked-but-disposable only (Step 5 cleared it)
```

Then delete the branch:

- **Ancestor-merged** (Step 3): `git -C "$repo" branch -d "$branch"` — the *safe* delete; it succeeds because the branch is merged. If it ever refuses, stop and recheck rather than escalating.
- **Squash-merged** (Step 4, OID verified): `-d` refuses (not an ancestor), so use `git -C "$repo" branch -D "$branch"` — but only for a branch whose HEAD you confirmed equals, or is an ancestor of, its merged PR's head commit, via a **repo-scoped** `gh -R "$owner_repo"` lookup. Branch names collide across repos; an unscoped or unverified match can force-delete unmerged work.
- **Detached HEAD**: no branch to delete.

**These operations are slow** (deleting tens of GB of `node_modules`) and will time out a foreground call. Run the removal loop in the background and make it **idempotent** (skip paths already logged) so you can resume after a timeout. Write it as a script file run with `bash`, not inline zsh, and keep it 3.2-safe (see Preconditions). Log one `<outcome>\t<path>` line per worktree, skips included, and check the log with an exact match on the path column (`awk -F'\t' -v p="$wt" '$2 == p'`), never `grep -F "$wt"`: a prefix match treats `foo` as done once `foo-bar` is logged. The final summary is then a `cut -f1 | sort | uniq -c`, and a rerun never retries a worktree that needs a new plan. Redirect stdin from `/dev/null` on `gh` and `git fetch` calls inside a `while read` loop so they can't swallow the plan file. Don't run two removal loops against the *same* repo concurrently — you'll hit an index lock.

**Corrupt worktree** (its `.git` link was partially deleted, so `git worktree remove` errors with "validation failed"): try `git -C "$repo" worktree repair "$wt"` first, then re-inventory it through Step 5. Only `rm -rf` the directory once Step 5 confirms it's disposable — corrupt metadata doesn't mean the directory is empty of real files.

### Step 8 — Trim build output from kept worktrees

A kept worktree can still be mostly regenerable bytes: one Next.js checkout carried a 7 GB `.next` cache, and kept worktrees in one repo held ~17 GB of `.next` between them. Removing the worktree isn't allowed, but clearing its build output is safe once nothing's using it.

For each kept worktree, take the **ignored roots** from its Step 5 inventory (`!!` lines) and select only the build caches: `.next/`, `.turbo/`, `.swc/`, `dist/`, `*.tsbuildinfo`. Skip `node_modules/`: with pnpm it's mostly hard links into the store (little comes back), and deleting it leaves the checkout unusable until a reinstall. Trim only worktrees with no session activity in the last 24 hours and no running process inside (`lsof -a -d cwd -Fn 2>/dev/null | grep -F "n$wt"`), since a dev server writes to `.next` live.

Liveness can change after the plan, so re-run the session and `lsof` checks just before trimming each worktree, and skip it if either now shows activity. Then confirm each path is still listed as ignored (`git -C "$wt" check-ignore -q "$path"`) and has no tracked files under it (`git -C "$wt" ls-files "$path"` is empty). Then `rm -rf` it. Put it in the same background loop and log as Step 7.

### Step 9 — Compact the repos with gc (optional, separately approved)

Offer this as its own opt-in line in the plan, not a default. Once the deleted branches are merged, their commits still live in the default branch, so there's little to reclaim. In one run, gc across 8 repos changed disk use by +3 MB: repacking grew the largest `.git` more than pruning shrank the rest.

If the user opts in, deleting branches leaves unreachable objects behind. Reclaim them **after** all removals:

```bash
du -sh "$repo/.git"                # measure to pick targets
git -C "$repo" gc --prune=now      # only when the repo is idle
```

Run gc on the repos you removed branches from; if that's many, prioritize the **5–10 largest by `.git` size**. Be precise about what `--prune=now` does: a deleted branch's reflog is gone too, so its now-unreachable commits are **permanently** dropped here (intended — you proved them merged, but it is not recoverable afterward). And `--prune=now` **risks corruption if another process writes to the repo concurrently** — only run it when nothing else is touching that repo. A repo is idle when no process has its main checkout or any of its worktrees as its working directory (`lsof -a -d cwd -Fn`), and no transcript for any of those paths changed in the last hour. For a repo that isn't idle, use plain `git gc`, which keeps the default grace period, or skip it. The payoff is modest when branches were merged (their commits still live in the default branch) — the real disk was in the worktree checkouts.

### Step 10 — Clear developer caches (separately approved)

Worktree-heavy workflows pile up caches outside any repo. These are regenerable, but clearing them costs download/rebuild time, so they get their own line in the plan and their own yes. Run this **after** Step 7, so stores no longer have checkouts linking into them.

- **pnpm.** Each store folder belongs to a range of pnpm majors: `v3` is pnpm 7–9, `v10` is pnpm 10, `v11` is pnpm 11. `pnpm store path` shows only the global pnpm's store, but corepack runs whatever major each repo pins, so a folder that looks stale may still be in daily use. Collect the pins first, across every repo under the scan root (not just the ones with worktrees):

  ```bash
  grep -ho '"packageManager": *"pnpm@[0-9]*' */package.json */*/package.json 2>/dev/null | sort | uniq -c
  ```

  A store folder with no pinning repo is safe to delete: existing `node_modules` keep working (hard-linked files survive while any link remains), and only a future install with that major would re-download. For a store still in use, **`pnpm store prune` is close to a delete, not a safe trim.** It removes every package not referenced by a project the store still tracks, and in one run it emptied an 18 GB store with 35 repos pinned to it. Existing `node_modules` keep working (the hard links survive), but the next install in every one of those repos re-downloads. Offer it per store with that cost stated, run it with the store's own major (`npx pnpm@10 store prune`), and let the user decide. Leaving an in-use store alone is a fine answer.
- **Go.** `go clean -cache` clears `go env GOCACHE` (often 20 GB+). It refills on the next build.
- **Playwright.** `~/Library/Caches/ms-playwright` keeps every browser revision ever installed. Report old revisions; leave the newest of each browser.
- **npm.** `~/.npm/_cacache` grows without bound (19 GB in one run). `npm cache clean --force` clears it; npm re-downloads on the next install.
- **bun.** `bun pm cache rm` fails outside a project ("No package.json"), even with `-g`. Run it from a throwaway directory with a `{}` `package.json`, or remove the folder that `bun pm cache` prints.
- **pnpm metadata.** `~/Library/Caches/pnpm` holds registry metadata, not packages, and is safe to remove.
- **Others found in Step 2** (Yarn, CocoaPods, Cypress, Homebrew): report sizes and the tool's own clean command (`yarn cache clean`, `brew cleanup`). Use the tool's command over `rm` wherever one exists.

Never touch `~/Library/Application Support` or app caches that hold user data or sign-in state.

### Step 11 — Report reclaimed disk

Re-measure the containers, `.git` dirs and caches from Steps 2/9/10, and lead with the `df -h /` free-space delta against Step 2. That's the number the user feels; the `du` sum overstates it whenever store hard links are involved. Report a before/after table and a grand total. State plainly what was **kept and why** (real uncommitted work, open PRs, diverged/local-only branches, ignored data, unverifiable detached HEADs) so the user can trust nothing valuable was touched.

## Output

```
Reclaimed ~<N> GB.

Removed <count> worktrees + branches:
- <count> stale refs pruned
- <count> provably-merged
- <count> squash-merged (GitHub-verified, HEAD matched)
- <count> with ignored-only extras (build output / identical .env copies)
- <count> force-removed, untracked-but-disposable (symlinks / agent artifacts)
- <count> idle review checkouts of open PRs (opt-in; `gh pr checkout` restores)

Kept <count> (untouched): <real uncommitted work>, <open PRs>, <diverged/local-only>, <ignored data>, <unverifiable detached HEADs>, <live agent sessions>.

Trimmed ~<N> GB of build output from <count> kept worktrees.
Removed <count> orphaned checkouts (approved individually).
Cleared ~<N> GB of developer caches: <pnpm stale stores / go build / …>.
Partly cleared: <cache> <before> → <after> (<why it didn't fully clear>).

git gc changed .git size by <±N> MB across <count> repos (or: gc not run).
```

## Error paths

- **`gh` unavailable / unauthenticated, or slug/default resolution fails** → skip that repo (fail closed). Report that it couldn't be classified and was left untouched. Don't guess.
- **Repo has no `origin` remote** → skip it and list it as unclassified. There's nothing on GitHub to prove a merge against.
- **`git fetch` fails for a repo** → skip the whole repo. A stale ref can misclassify, so never classify destructively against one.
- **Squash-merge PR found but HEAD OID doesn't match, or its `mergeCommit` isn't an ancestor of the fetched default** → the local branch diverged, or the merge is no longer on the default branch; keep and ask. Never `-D` on a name match alone.
- **`worktree remove` reports uncommitted/untracked changes** → expected; it went to Step 5 triage. Never blanket `--force`.
- **Removal loop times out** → resume the idempotent background loop; it skips already-processed paths.
- **"validation failed, cannot remove working tree"** → try `git worktree repair`; if that fails, triage the dir (Step 5) and confirm before any `rm -rf`.
- **Orphaned checkout (gitdir missing)** → no git proof is possible; inventory it from the filesystem, list it on its own, and `rm -rf` only with explicit approval.
- **Genuinely ambiguous dirty/ignored path** → keep the worktree, name the file that gave you pause, and ask. Never force-remove on a hunch.
