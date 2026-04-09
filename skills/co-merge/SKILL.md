---
name: co-merge
description: Use when merging the default branch into the current branch to stay up to date and resolve conflicts
---

# co-merge

Merge the repository's default branch into the current branch, resolving any conflicts that come up. Handles lock file conflicts by accepting the default branch's version and reinstalling the current branch's dependency changes when needed.

**Scope:** Works on any branch, PR or not. A clean working tree is required.

## Preconditions

**Clean working tree required.** Run `git status --porcelain`. If there's any uncommitted work, stop and tell the user:

> Your working tree has uncommitted changes. Commit or stash them before running `/co-merge`.

Other checks:

- **Current branch** — `git rev-parse --abbrev-ref HEAD`
- **Default branch** — `gh repo view --json defaultBranchRef --jq .defaultBranchRef.name`. If `gh` fails (auth/remote/network), surface the actual error and stop. Don't fall back to hardcoded names.

## Flow

**Step 1 — Fetch from remote.**

```bash
git fetch origin
```

One fetch, then work from local refs. No further network calls until push.

**Step 2 — Fast-forward the current branch if remote is ahead.**

If `origin/{branch}` has commits that aren't in the local branch, fast-forward:

```bash
git merge --ff-only origin/{branch}
```

This picks up changes anyone else pushed to the branch (the user from another machine, a remote agent, etc.).

**Step 3 — Check if there's anything to merge.**

Compare the current branch against `origin/{default-branch}`. If the branch is already up to date with the default branch (no commits to merge in), stop and report:

```
Already up to date with `{default-branch}`.
```

Do not create empty merge commits.

**Step 4 — Merge the default branch.**

```bash
git merge origin/{default-branch}
```

If the merge completes cleanly, skip to Step 7.

If there are conflicts, proceed to Step 5.

**Step 5 — Handle conflicts.**

Run `git status --porcelain` (or `git diff --name-only --diff-filter=U`) to list conflicted files. Handle each category:

### Lock file conflicts

Detect by filename: `pnpm-lock.yaml`, `package-lock.json`, `yarn.lock`, `bun.lockb`, `bun.lock`, `npm-shrinkwrap.json`.

1. Accept the default branch's version:

   ```bash
   git checkout --theirs {lockfile}
   ```

2. Check if the branch has changes to the relevant manifest (typically `package.json`) vs the default branch:

   ```bash
   git diff origin/{default-branch}...HEAD -- package.json
   ```

3. If the manifest has branch-side changes, run the detected package manager's install command to reintegrate the branch's dependencies into the default branch's lock file. Detect the manager from the lock file name:

   - `pnpm-lock.yaml` → `pnpm install`
   - `package-lock.json` → `npm install`
   - `yarn.lock` → `yarn install`
   - `bun.lockb` or `bun.lock` → `bun install`
   - `npm-shrinkwrap.json` → `npm install`

4. If the manifest has no branch-side changes, skip the install — the default branch's lock file is correct as-is.

5. Stage the lock file (and anything the install touched): `git add {lockfile}` (plus any manifest or workspace files the install modified).

### Code and doc conflicts

Claude resolves with judgment. For each conflicted file:

- Read both sides of the conflict (`<<<<<<< HEAD`, `=======`, `>>>>>>> origin/{default-branch}`)
- Use conversation context, recent commit messages, and the file's purpose to decide the right resolution
- Common patterns:
  - Both sides added imports → combine both
  - Both sides edited different parts of the same function → keep both edits
  - Same line reworded differently → prefer the version that preserves meaning from both
  - Genuinely conflicting logic where both can't coexist → stop and ask the user
- Write the resolved file
- Stage it: `git add {file}`

**If a conflict is genuinely unclear**, stop and ask the user. Do not guess on conflicts where the right answer depends on intent Claude can't infer.

**Step 6 — Present resolution summary.**

Before committing the merge, show a summary so the user can see what Claude did. No approval gate — just visibility.

```
Merge summary:
- N files merged cleanly
- X conflicts resolved:
  - pnpm-lock.yaml: accepted main, reinstalled deps
  - src/foo.ts: combined imports from both sides
  - docs/bar.md: kept main's rewording, preserved branch's example block
```

If the user wants to abort at this point, they can run `git merge --abort` before Claude commits.

**Step 7 — Commit the merge.**

```bash
git commit --no-edit
```

Use git's default merge commit message. No co-author trailer on merge commits.

**Step 8 — Push.**

Detect upstream, fall back to `origin`:

```bash
if git rev-parse --abbrev-ref --symbolic-full-name @{upstream} >/dev/null 2>&1; then
  git push
else
  git push -u origin {branch}
fi
```

If push fails, surface the actual error. Note that the merge is already committed locally — the user can retry push manually.

## Output

On success:

```
Merged `{default-branch}` into `{branch}`. Pushed.

N commits merged. X conflicts resolved.

[PR URL if one exists]
```

Run `gh pr view --json url --jq .url` to check for an associated PR. If there is one, include the URL. If not, omit that line.

## Error Paths

- **Uncommitted changes** → "Commit or stash your changes first." Stop.
- **`gh repo view` fails** → surface the actual error. Stop.
- **Fetch fails** → surface the actual error. Stop.
- **Unresolvable conflict** → stop and ask the user. Don't guess. Don't commit.
- **Push fails** → surface the error, note that the merge is committed locally, suggest manual retry.
