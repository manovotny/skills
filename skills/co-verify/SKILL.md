---
name: co-verify
description: Use when a project needs a scripted way to prove real app behavior — generates a project-local verify-<app> skill that launches the app, drives it like a user, and captures evidence; also maintains an existing one
---

# co-verify

Generate a **project-local verification skill** — a scripted, repeatable way to drive the real app the way a user does and capture proof: launch it, exercise a feature, observe the result, clean up. The generated skill lands in the target repo's project-skill directory (see "Where it lands") and is the durable artifact; co-verify is only the bootstrap and the maintainer.

Write the generated skill for its real reader: an agent that has never seen the app, reading it cold, mid-task. Every instruction must work without this conversation's context.

**Modes:**
- `/co-verify` — generate a verification skill for the current repo
- `/co-verify <app>` — same, but name the app/surface up front (for monorepos with several apps)
- `/co-verify update` — reconcile an existing verify skill and its feature map against the current app

**This is a solo utility** (no Codex loop). The peer review is step 4: the generated skill is proven by executing it, not by reading it.

## Step 1 — Interview the repo, not the user

Answer these from the codebase. Ask the user only what cannot be observed:

- **Surface.** What does a user actually touch? Web UI, CLI/TUI, API, desktop app, library. A repo can have several; pick the primary one (or the one named in the argument) and note the rest.
- **Run.** How does the app start locally? Prefer the repo's own documented dev command (package scripts, Makefile, README quickstart, `.claude/launch.json`). Note ports, env vars, seed data.
- **Auth.** How does an agent get past sign-in? A dev instance, seeded test user, bypass flag, or documented test credentials — name the exact mechanism. Never real user credentials. If no scripted path past auth exists, that's a finding to surface, not a gap to paper over.
- **Drive.** How can an agent interact programmatically? Existing harnesses first — Playwright/Cypress specs, expect scripts, curl-able endpoints. Only then a generic recipe: a scripted browser (Playwright/CDP) for web, a tmux/PTY session for CLI/TUI, plain HTTP for services. Claude's Browser pane works for the proof run, but the recipe written into the skill is the runtime-neutral one.
- **Observe.** What evidence can be captured? Screenshots, terminal transcripts, response bodies, logs, exit codes, DB state.
- **Isolate.** Can two instances run side by side (ports, data dirs, profiles)? If not, the generated skill must say so: refusing to double-drive a shared instance beats corrupting the user's session.

If the checkout doesn't build or start as-is, fix that first or report it precisely before generating — a skill written against a broken base teaches wrong steps.

## Step 2 — Generate the skill

**Follow the repo's project-skill convention.** If the repo already keeps skills in the agent-agnostic `.agents/skills/` (often indexed via a CLAUDE.md → AGENTS.md pointer chain), write there and hook the new skill into the same chain the existing ones use. Otherwise use `.claude/skills/`. A skill in `.agents/skills/` is read by any agent (Claude, Codex, and others), so keep its instructions runtime-neutral: real commands, selectors, and scripts any agent can run — name the underlying mechanism (Playwright, CDP, curl, tmux), not Claude-specific tool names.

Write `<skills-dir>/verify-<app>/SKILL.md` with YAML frontmatter (`name: verify-<app>`, and a `description` naming the app, the surface, and when to reach for it) and these sections, each grounded in what the interview actually found — no placeholders left:

- **Launch.** The exact command that starts the app for verification, and how to tell it's ready (a log line, a port answering, a prompt). Include teardown. For a short-lived CLI there's no server: launch means build once, then start each drive in its own isolated session.
- **Doctor.** One read-only check that answers "is this instance worth driving?" — process up, right version, port owned by us, auth valid. Run first whenever anything looks off.
- **Drive.** The harness recipe with real selectors, routes, and commands from this repo, not examples. Prefer stable handles (ARIA labels, data attributes, prompt strings, route paths) over coordinates.
- **Evidence.** What to capture for a proof and where it goes. State the standards: exercise the real user path, not internal setters or test-only endpoints; capture the action and the resulting state, not just the final screen; verify side effects (rows inserted, files written, webhooks fired) alongside what's visible.
- **Cleanup.** Tear down what the run created. Kill what you started, never by process name. Cleanup removes instances and scratch state, never the evidence — proof artifacts survive teardown, in a location the skill names.

Any helper script the skill ships is executable and its invocation shown in the skill body.

## Step 3 — Seed the feature map

Create `<skills-dir>/verify-<app>/features/README.md` (an index) plus one file per user-facing feature, identified from routes, commands, menus, or docs. Aim for the top 3–5 to start. Each file answers, from the user's point of view: what the feature is, how to reach it, how to drive it with the harness, and what observable end state proves it works.

The map is the repo's maintained verification source. A proof that drives one convenient entry point is incomplete when the map lists others.

## Step 4 — Prove it before handing it over

Run the generated skill's own instructions end to end once: launch, doctor, drive **one** mapped feature (one is enough — the map exists so later runs cover the rest), capture evidence, clean up. After cleanup, confirm the evidence still exists at the named location — a cleanup that eats the proof fails this step.

Fix what fails, and run the generated cleanup after every failed iteration too, so broken attempts don't strand processes and ports. **A generated skill that was never executed is a draft, not a deliverable.**

## Update mode

`/co-verify update` in a repo that already has a `verify-<app>` skill:

1. Re-run the step 1 interview cheaply: diff the feature map against current routes/commands/menus, and spot-check the Drive section's selectors and commands against the current code.
2. Fix what drifted: stale selectors, renamed commands, changed launch/ready signals, features added or removed.
3. Re-prove by driving one feature the update touched (step 4 rules apply).
4. Report what changed and what was re-proven.

## Where it lands

The generated skill is left as uncommitted files in the target repo — project skills are shared with anyone (and any agent) using the repo once committed, and that's the user's call. Offer the next step: commit it via `/co-pr` (team-shared), or add it to `.gitignore` (personal). Don't commit either way without being asked.

## Provenance

The interview → generate → feature map → prove shape is adapted from pstack's [`create-verification-skill`](https://github.com/cursor/plugins/blob/main/pstack/skills/create-verification-skill/SKILL.md) (MIT, by Lauren Tan), rewritten for this suite: solo instead of poteto-mode-routed, maintenance folded in as a mode instead of a second skill, and auth added as a first-class interview question.
