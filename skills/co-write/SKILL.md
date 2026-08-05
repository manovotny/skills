---
name: co-write
description: Use when writing, rewriting, or checking prose in the user's voice — Slack messages, emails, docs, blog posts, announcements — or when feeding new writing samples into the voice guide
---

# co-write

Make prose sound like the user. The voice lives in `voice.md` (same directory as this file) — distilled, operational rules plus canonical excerpts, split into a core voice and per-medium overlays. This file is the logic; `voice.md` is the data.

**Modes:**
- `/co-write <request>` — **draft** (default): write new prose in the user's voice
- `/co-write rewrite` — revoice existing text (pasted, or pointed at: a file, PR, message)
- `/co-write check` — critique a draft against the voice guide without rewriting
- `/co-write learn` — distill new samples into proposed voice-guide updates

Sibling skills (co-pr, co-review, co-fix) apply `voice.md` directly when writing outward-facing prose — they don't invoke this skill.

## Reading the voice guide

Every mode starts by reading `voice.md` from this skill's directory (resolve relative to this SKILL.md, not the project — the skill runs from any repo).

If `voice.md` is missing, or its Core voice section has no rules yet, write as Claude normally would and say so — the guide isn't seeded, and `/co-write learn` with samples is how to train it. Don't improvise a voice from generic "sound casual" defaults; just don't claim the output is voiced.

## Applying the voice

1. Identify the medium (Slack, PR & review comments, docs/blog, email, ...). If ambiguous, ask.
2. Apply Core voice rules, then layer the medium's overlay on top (overlays record only deviations from core).
3. Re-read the canonical excerpts for that medium before writing — they anchor rhythm and register in ways rules can't.
4. No overlay for the medium? Use core rules alone, and mention that samples for this medium would sharpen future output.

**Boundaries:**
- Format always wins over voice: commit-message format, code-comment density and placement, PR templates, repo naming and idiom. The prose *inside* a commit message or code comment carries the voice; the structure follows the repo.
- Code itself is never voiced.
- Voice never changes meaning — a rewrite that alters facts is a failed rewrite.

## Draft mode (default)

`/co-write <request>` — e.g. `/co-write a Slack announcement that the migration is done`.

1. Read `voice.md`; identify the medium.
2. Gather the facts from the conversation, or ask. Don't pad — part of the user's voice is what they *wouldn't* say.
3. Write the draft.
4. Run the self-check (below); fix violations before presenting.
5. Present the draft, noting anything you weren't sure about (register, missing facts, uncovered medium).

## Rewrite mode

`/co-write rewrite` with pasted text or a pointer.

1. Read `voice.md`; identify the medium from the text's destination — ask if unclear.
2. Revoice: preserve meaning, facts, and load-bearing structure (links, code blocks, @-mentions, lists that are genuinely lists). Change wording, rhythm, register.
3. Run the self-check; present the rewrite. On request, explain what changed and why.

## Check mode

`/co-write check` with a draft (pasted or pointed at).

Report, don't rewrite. Cite the specific rule or excerpt each violation conflicts with:

- × "utilize" — Core voice: never-words
- × closes with "Best regards" — Slack overlay: no sign-offs
- ✓ opener matches — straight in, no greeting

End with a verdict: **passes** / **passes with nits** / **doesn't sound like the user**.

## Self-check (draft and rewrite)

Before presenting any draft or rewrite, run check mode's comparison internally against `voice.md` and fix what fails. No announcement needed — just never present prose that would flunk check mode.

## Learn mode

`/co-write learn` with samples — pasted text, file paths, or links to messages/PRs the user wrote.

1. Confirm the samples are the user's own unedited writing (not Claude's, not group-edited). Ask if unsure — mixed sources dilute the voice.
2. Identify each sample's medium.
3. Distill **operational rules** — things a writer could obey while writing. Good: "starts bullets lowercase, no trailing periods". Bad: "concise and friendly".
   - Rules outlive jobs — state the pattern, not the instance. "Full signature (if present) on the first email", never the signature block spelled out; "'we' speaks from the team or company angle", never "'we' speaks for <employer>". Employer, product, and team names are provenance: they belong in the sources header, not inside a rule.
   - When a rule holds for some readers but not others, split the overlay by audience (users and contributors vs. partners and vendors), never by employer or product.
4. Diff against the current guide:
   - One data point is an edit, not a rule. A correction becomes a guide rule only when it recurs or the user says it generalizes — when in doubt, fix the instance and leave the guide alone.
   - New rules → Core voice if they show up across mediums, otherwise the medium's overlay.
   - Contradictions with existing rules → flag them and let the user pick which era of their voice wins; never silently overwrite.
   - Excerpt candidates → propose promoting a short, representative passage. Keep 2–4 per medium; when full, propose retiring the weakest.
5. Show the proposed `voice.md` changes as a diff. Apply only on the user's approval.
6. **Land the change as a PR, never as a loose edit.** Resolve `~/.claude/skills/co-write` (`readlink`) to find the skills-repo checkout; never write through the symlink.
   - Inside a checkout or worktree of that repo, on a non-default branch where this change belongs? Edit its working copy of `skills/co-write/voice.md`, then invoke co-pr on the current branch.
   - Anywhere else — including that repo on its default branch, or on a branch carrying unrelated work — leave the checkout as it sits: from it, fetch, `git worktree add` a fresh branch off the remote default branch — branch and worktree both named for the voice change — apply the approved diff in that worktree, and invoke co-pr from there to commit, push, and open the PR. Tell the user the worktree path so they can clean it up after merge (co-clean handles this).
   - Either way, tell the user the voice change takes effect when the PR merges and the symlink-target checkout picks it up — not at approval time.
