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

If `voice.md` is missing, or its Core voice section has no rules yet, stop and say so — the only useful next step is `/co-write learn` with samples. Never improvise a voice from generic "sound casual" defaults: no guide, no voicing.

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

- ❌ "utilize" — Core voice: never-words
- ❌ closes with "Best regards" — Slack overlay: no sign-offs
- ✅ opener matches — straight in, no greeting

End with a verdict: **passes** / **passes with nits** / **doesn't sound like the user**.

## Self-check (draft and rewrite)

Before presenting any draft or rewrite, run check mode's comparison internally against `voice.md` and fix what fails. No announcement needed — just never present prose that would flunk check mode.

## Learn mode

`/co-write learn` with samples — pasted text, file paths, or links to messages/PRs the user wrote.

1. Confirm the samples are the user's own unedited writing (not Claude's, not group-edited). Ask if unsure — mixed sources dilute the voice.
2. Identify each sample's medium.
3. Distill **operational rules** — things a writer could obey while writing. Good: "starts bullets lowercase, no trailing periods". Bad: "concise and friendly".
4. Diff against the current guide:
   - New rules → Core voice if they show up across mediums, otherwise the medium's overlay.
   - Contradictions with existing rules → flag them and let the user pick which era of their voice wins; never silently overwrite.
   - Excerpt candidates → propose promoting a short, representative passage. Keep 2–4 per medium; when full, propose retiring the weakest.
5. Show the proposed `voice.md` changes as a diff. Apply only on the user's approval.
6. **Write to the real checkout, not the symlink.** `~/.claude/skills/co-write` is a symlink into a skills-repo checkout — resolve it (`readlink`) and edit the resolved path. Tell the user the change is an uncommitted edit in that checkout (name the branch it's on) so they can commit it like any other skill change.
