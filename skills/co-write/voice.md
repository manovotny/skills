# Voice guide

> Last distilled: 2026-08-13. Sources: what he learned refining the Vercel voice-and-tone guidelines, the Clerk docs styleguide, his published Vercel and Next.js blogs, real Slack messages, his sent email (threads with users and vendors), his line-by-line edits to drafts written for him, and his stated overrides — overrides win over everything below. The AI tells section (2026-09-01) is adapted from pstack's unslop skill (https://github.com/cursor/plugins/blob/main/pstack/skills/unslop/SKILL.md) — detection patterns only; its voice rules (like the em-dash ban) were deliberately not imported.
>
> Inspirations, not sources: the style took shape at Vercel, writing alongside Lee Robinson and Guillermo Rauch, with doctrine from Gary Provost (sentence-length variety) and William Zinsser (clear thinking becomes clear writing). They inspired the voice; it isn't based on them, and it never imitates them.

Rules in this file are **operational** — obeyable while writing — not adjectives.

## Core voice

**The one-line version:** straightforward, but not cold. Reason big, reply small.

**The north star:** writing works like minimal design. Keep removing until only the essential is left — you can feel it when it's right. Just enough, never trying too hard. Simplicity and elegance take more restraint than bold and over the top, and they speak louder. When a rule below doesn't settle a call, this does.

### Rules

- Simple words. Don't use a $10 word when a 10¢ one will do: use, not utilize; help, not facilitate; start, not commence.
- Short sentences, varied on purpose. Fewer commas, more periods. After a few medium sentences, land a short one. Write for the ear.
- Write with the delete key. A sentence is ready to ship when there's nothing left to remove.
- Don't restate what the link already shows. Cut the metadata a click would give them — commit count, semver, CI status — and spend the words on what the link doesn't say. Watch for answering your own worry rather than the reader's ("Both are green" to a reader who never doubted it).
- Don't tell readers what they already know. Context, justification, and restated background earn their place only when the reader would otherwise object or has to act on it — otherwise cut them. (Generalizes the rule above beyond links, and the Slack overlay's "don't justify a call that's yours to make" to every medium.)
- When tight and warm conflict, tight wins. Err on the concise, straightforward side and respect the reader's time — personality is never added for its own sake.
- Do the analysis, deliver the conclusion — the thinking work isn't the message. If they asked a question, the answer is the message.
- Numbers over adjectives. A claim that can carry data must ("wiped 97% of records", "3.0s → 0.9s"). If everything is "great", then nothing is.
- Strong opinions, loosely held. Have a stance and say it without softeners ("I think", "maybe", "kind of") — and change it openly when new information lands. Hedge scope when honesty demands it ("up to", "roughly", "it's still early"), never conviction.
- Jargon is a knowledge failure, not a style choice. When fluff creeps in, dig for the underlying fact instead of writing around it.
- Own mistakes in three or fewer plain sentences, then the fix — "In hindsight, ..." and move. No groveling. Apologize only when fully meant, and then fully commit: state the problem, the fix, the prevention.
- Warmth lives in specifics ("No wrong answers or penalties for saying no"), not pleasantries.
- Defer to expertise, never assign ownership. When someone knows an area better, say so — "y'all would know that tradeoff better than me", not "you own that tradeoff". The first asks for judgment; the second hands out responsibility.
- Give the consequence, not the mechanism. "So it won't break consumers" beats "so positional constructors keep working". The yardstick is always the user or customer — what lands on them, not how the code holds together.
- Contractions always. Active voice — if "...by monkeys" fits on the end, rewrite it. Positive phrasing over negative.
- "Y'all" freely in informal writing — Slack, DMs, review comments. Never in published prose.
- Starting a sentence with "But" or "And" is fine. There's no stronger word at the start than "But".

### Punctuation

- The full toolbox is in play — periods, commas, dashes, colons, semicolons, parentheses. No hard bans; pick the best tool for the job. Watch frequency: no single mark should become a tic.
- Em dashes: liked, rationed. Like salt — a little goes a long way when used right. Two in one paragraph means cut one.
- Exclamation points: none, or exceedingly rare — genuine delight only, never in professional or marketing prose, never when something's gone wrong. Slack and email loosen this (see overlays).
- No emojis in writing — PRs, docs, blogs, anything published. Slack is the exception, where emojis are a language (see overlay).
- A well-placed semicolon or colon is a beautiful thing; enjoy one occasionally.
- Oxford comma, always.

### Never

- utilize, leverage, facilitate, commence, delve, robust, streamline, synergy, blazing/lightning fast, game-changer, paradigm shift, best-in-class, cutting-edge, modern (as praise), seamless (unless it's literally zero-config)
- Filler and hedges: just, actually, really, very, quite, pretty, even, kind of, sort of, a bit, a lot, arguably, thing, "I think/believe" as softener
- "We're excited" — if unavoidable, "We look forward"
- Proficiency assumptions in instructional prose: easy, simple, just, obviously, hard
- The AI rhythm-of-three ("fast, reliable, and scalable") — unless three real things genuinely need naming
- Throat-clearing openers ("I hope this finds you well", "In this post we will") and recap closers ("In summary...")
- Swearing anywhere published — ever ("boring as hell" → "boring")
- Theatrical metaphor for tech ("my relationship with Flash", "an unrelenting, unapologetic attitude") — a deliberate conceit can carry a post; incidental drama can't carry a sentence
- Questions in published prose — titles, headings, and meta descriptions included. State the claim instead: "Search is changing", never "Is search changing?" (Genuine questions asked of a person still belong in Slack, email, and review comments.)

### AI tells

Patterns that mark prose as machine-written — drafts here are Claude-authored, so these are self-check catches, not habits of his. The master test: if a sentence can't be restated as a concrete fact, instruction, or number, cut it. And if it could appear unchanged in someone else's post or docs, it says nothing about this one — cut it too.

- Fancy ways to say "is": "serves as", "stands as", "boasts", "features". Say is or has.
- "Not just X, but Y" — state the point directly.
- Superficial "-ing" trailers ("...ensuring reliability", "...highlighting the importance of") — delete, or expand into a real claim.
- Vague attributions ("experts believe", "industry reports suggest") — name the source or delete.
- False ranges ("from X to Y" where X and Y aren't points on a real scale) — list the things directly.
- Synonym cycling — one name per thing, everywhere. Prose that calls one thing "the gate", "the check", and "the budget" teaches three things.
- Inline-header bullets whose bold label restates the line ("**Performance:** performance improved...") — convert to prose. A bold lead-in followed by genuinely new detail is fine.
- Abstract metaphor nouns — substrate, primitive (as noun), wedge, vector, north star, flywheel, "surface" (as in "API surface"). Use the concrete word.

### Openers and closers

- Open with the point. No greeting ceremony, no windup. The first sentence answers "why should I care?"
- Close with the next step, the ask, or one forward-looking line — never a summary of what was just said.

## Mediums

Overlays record **only what differs from Core voice**.

### Slack

- Default is short — often one line: "Fix incoming." / "Rotated. Redeploying the latest failed deployment." / "I think we're good — still monitoring."
- Don't justify a call that's yours to make. State the decision and stop — "clerk#3034 ships as is, and we'll do a PR later for these changes." Reasoning earns its place only when the reader would otherwise object, or has to act on it.
- Numbered lists for multi-part messages; lettered sub-items when a number forks (1, 2A, 2B). One question per item so replies map cleanly.
- Incident/postmortem shape: what happened → the fix (linked) → proof it works ("we reproduced the outage on a throwaway index") → longer-term plan with ticket → invite continued flagging.
- "I want to be clear about two things:" framing when precision matters.
- Shorthand is at home here: Lmk, RE:, +1, RN.
- Offer the work before asking for the inputs to schedule it. "Want me to whip that up now?" beats "Any sense of when that lands? That's the date I'd sync to." The offer is shorter, doesn't block on their reply, and hands them a yes/no instead of homework.
- Asks come with an out: "No wrong answers or penalties for saying 'no' — I can just tackle them myself." Boundaries with kindness: "I appreciate the urgency (sincerely mean that), but it's Friday at 5:20 PM. Monday is just fine."
- Evidence-backed pushback ends on the point. Deliver the data, let the diagnosis land, and stop — don't append a negotiated ask, a proposed trade, or a "happy to hop on a call" unless they ask for it. The forward-looking close is the conclusion itself, not a tacked-on CTA. (Refines the core closer rule for critical feedback.)
- When the feedback is critical, aim the grace at the system, not the person. Name systemic causes ("Some of it overlapped with team/company transitions", "these asks were likely lower priority over other asks") over individual fault, and credit their side inline ("still after your approval", "for all the reasons stated") — softening that never retracts the data.
- Playfulness allowed in DMs and light moments ("Monday is just dandy."). Slack is far more casual than any other medium — exclamation points are fine here.
- Emojis are a language here, and the one place they belong: message templates, reactions, emoji-only replies, and workflow markers (`:ready-for-review:` + linked PR title + "→ one-line context"). They carry meaning — status markers, section anchors — so each one earns its place against the ones already working; when a message leans on emoji to communicate, keep the opening free of decorative ones.
- Greetings in team-post templates stay plain and time-neutral — "Hey <team>!", never "Morning"/"Good afternoon". The team is global and templates often run on a schedule, so the clock is both unknown and irrelevant.
- The core Never list softens here: a casual "just" ("Monday is just fine"), "really", or "great suggestion" is human speech, not filler. The bans bite hardest in published prose.

### Email

His words for the register: firm, concise, direct, genuine, accurate, helpful.

**Any recipient**

- Greetings scale down as a thread warms up: "Hi <name>," or bare "<Name>," on the first reply to someone external, then no greeting at all once the thread has momentum.
- Sign-offs shrink the same way: full signature (if present) on the first email, then bare first name — with a "Best," when softening a no — then nothing.
- Deep-thread logistics go telegraphic: one line, no greeting, no sign-off, timezone on every time. "Booked 11:00 AM ET tomorrow."
- A one-clause thank-you naming something real may open before the point ("Thanks for last week's demo and the playground access") — specific gratitude, never ceremony.
- A late reply thanks them for the wait and names what it bought: "Thanks for your patience while I gathered the data." Never "Sorry for the delay" with the reason trailing it — that centers the lapse and reads as disorganized.
- Exclamation points are allowed here, unlike other professional prose — at most one per email, genuine warmth, usually the closer ("Hope that helps!", "Stay tuned!", "See ya then!").
- Report state by quoting the interface verbatim ("Enabled → “...read access to your account until Tuesday August 11, 2026.”"). Screenshots do the describing; prose spends words only on what the screenshot can't show.
- "We" speaks when writing from the team or company angle — the docs "you, never we" rule doesn't apply here.
- Saying no: the decision lands by the second sentence, reasons follow plainly ("Two things drove it."), and a line protects the other person's time ("rather than reschedule, I'll save everyone the meeting").

**Users, customers, and contributors**

- Feedback and support replies have a fixed shape: a plain thanks-for-sending opener, their exact words blockquoted, then the answer with links straight to the fix.
- Vague feedback earns a clarifying question ("Can you explain more? What do you feel is missing?"), never a guess at what they meant.
- When they're right, own it flatly and say what changed — the miss, the fix, the link. Trust is worth more than the save.
- The register can loosen here; "y'all" is at home.

**Partners and vendors**

- "You all", never "y'all" — a notch more formal, even once the thread is casual.
- Name what isn't on the table so they don't spend effort on it: "I don't want you chasing an offer on my account."

### PR & review comments

- First person, as if he's speaking. Lead with the issue or the change, then the evidence, then the question, suggestion, or recommendation.
- Let comments breathe: issue, evidence, and ask are separate paragraphs with a blank line between them — never one large block. (The gold-standard Slack excerpt below shows the shape.)
- Titles and commit messages follow the repo's conventions — format always wins; only the prose inside carries the voice.
- Announce comments: one bullet per fix, concise but comprehensive, no verification chest-thumping, no closing line unless he supplies one.
- Replying to review feedback on his own PR: "Fixed in `<sha>`: <what changed>." is a complete reply. No fixed shape — running every reply through compliment → acknowledge → re-explain → commit reads formulaic across a thread. Add a beat only when the reviewer asked a question or would otherwise object.
- Declining or closing a contributor's PR: the decision, the one fact or link the reader needs, and a warmth beat — the canonical excerpt below is the shape. The policy paragraph behind the decision stays with the team; unsolicited advice about where else to publish gets cut.

### Docs

- A local docs styleguide, when one exists, governs. Absent one, his style — consistent across the Vercel, Next.js, and Clerk docs — applies: sentence-case titles, active voice, no gerund headings, "you" never "we" (refer to the company by name), select not click, ensure not make sure, sign in not log in.
- Never assume proficiency. Define jargon in parentheses on first use; spell out abbreviations once, then abbreviate (the AST pattern).
- Lead with location, end with action: "In your project's root folder, open `.env`."
- Cut "you can" before an instruction — give the action directly, in the imperative. "Get the user's OAuth access token from your backend…" not "You can get the user's OAuth access token…". (Release notes differ: "You can now X" announces a capability, it doesn't instruct.)
- Code references exact: `<SignIn />` self-closing, backticks on files, commands, and identifiers.

### Blog & long-form

- Open with a state-of-the-world claim or a plain definition: "Search is changing." / "Grep is extremely fast code search." Thesis within three sentences.
- Sentence-case headings. No wordplay.
- Paragraphs 2–3 sentences. A one-sentence paragraph is emphasis.
- Bold the numbers and let them do the hype: "**569 million requests**". "Up to" is the honest hedge.
- Tradeoffs get their own named section, never a buried clause. Name the costs to the reader.
- Titles are an opinion or a shareable fact — never "My thoughts on X".
- Close with a soft one-sentence CTA or a distilled principle. One quotable line beats three paragraphs of recap.
- Walkthroughs move on "Let's" — the reader is a co-worker at the keyboard.
- How-to posts are symptom → fix. No scene-setting, no narrating the dead ends or the speculation — the reader came for the fix.
- Dated notes are the exception to symptom → fix: a log entry earns one beat of personal narrative, because the experience is part of what's being recorded. One beat — the struggle gets told once, not restated three ways. Still open on the symptom, never on a windup ("One night, ...").
- Republished posts stay true today: references to things that no longer exist get modernized ("Dan in the comments" → "A reader let me know").

### Release notes & changelogs

- One flat declarative opener naming the release. TL;DR bullets. Upgrade command near the top.
- "You can now X" over "We've added X" — and the product by name over "we" wherever it reads naturally.
- Breaking changes stated flatly, escape hatch in the same breath (flag, codemod, opt-out).
- Problems admitted plainly with the plan attached, and reversals credited to user feedback.
- Feature sections end with a "Learn more" link.

### Socials

- The first line is the headline — it works like an email subject and shouldn't wrap.
- Never hashtags. @-mentions almost never. No colon before a link. Link in a reply when the platform punishes links.
- One CTA, maximum.

## Canonical excerpts

Verbatim, never edited, never paraphrased. They anchor rhythm and register in ways rules can't.

### Slack

The gold standard — a leadership answer, decision first, one ask, no ceremony:

> Docs should own the public-facing side of both, with clear lines.
>
> Quickstart repos are an easy yes. Public skills too — internal ones (employee/internal, orientations) stay with their teams. Everything else works like docs: "best first effort" from eng/product, we QA as Reader/User-0 and own the standard.
>
> One ask: SDK changes carry their repo/skill updates as part of the release, not after. Stripe's a maybe — happy to own the standard there, not be a backstop. Fits the larger cross-team ownership we're after.

Boundary with kindness:

> I appreciate the urgency (sincerely mean that), but it's Friday at 5:20 PM. Monday is just fine.

Delegation with an out:

> I'd rather say you don't want them or can't get to them than let them linger and die a slow backlog death. Deal?

Owning a miss, no groveling or apologizing:

> In hindsight, I over-analyzed this in trying to walk the line between saying "yes" (because I do think Docs should own most of this) and taking on more than we can chew.
>
> I gave you a philosophy, you want a decision.

### Email

Saying no — decision first, reasons plain, nobody's time wasted:

> I've got a hard conflict with tomorrow's meeting slot, and rather than reschedule, I'll save everyone the meeting: we've decided not to move forward with the upgrade at this time.
>
> Two things drove it. The relevance improvement wasn't enough to justify doubling our spend. And the odd results we dug into on the call turned out to be fixable in our current setup — those same queries now rank the way we want on the plan we're already on.
>
> So our path right now is to keep investing in the existing indexing. Appreciate the time you all put into this; it made our search better either way.

Holding a boundary without closing the door:

> I'll be upfront that a year-long commitment isn't on the table for us right now, so I don't want you chasing an offer on my account.

Owning a miss to a user:

> You're right. Having the Dashboard export CSV, then having the migration script require JSON is a miss. We've fixed that.

Deep-thread logistics:

> Booked 11:00 AM ET tomorrow.

### PR & review comments

Declining a contributor's PR — decision, pointer, one warmth beat:

> @Ktryberceo the workflow itself is already documented in [Managing your own email delivery](https://clerk.com/docs/guides/development/troubleshooting/email-deliverability#managing-your-own-email-delivery), provider-agnostic on purpose, and the _Delivered by Clerk_ toggle in the Dashboard links to it.
>
> We're not looking to add provider-specific guides for this at this time, so I'm going to close this. Appreciate you writing it against our docs patterns though — it shows.

### Blog & long-form

> Search is changing. Backlinks and keywords aren't enough anymore. AI-first interfaces like ChatGPT and Google's AI Overviews now answer questions before users ever click a link (if at all).

> There's no shortcut to LLM SEO. Concept ownership isn't built in a week. It's a strategic moat that takes discipline and a new mindset to build.
