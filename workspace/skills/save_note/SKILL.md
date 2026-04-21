---
name: "Save Note"
version: "1.0"
description: "Save a piece of research, a draft, or a working thought into the customer's notes folder so it persists across sessions and can be referenced later."
requires: []
platform: ["telegram"]
author: "Bintra"
---

# Save Note

The customer's notes folder lives at `/opt/bintra/workspace/customer_notes/`. Everything saved there persists across sessions and is listed at the start of every future session alongside `knowledge/`. This is where compounding knowledge lives — research you did, drafts you produced, hypotheses you formed.

## When to use

Save a note when any of these happen:

- **Customer asked you to research something substantive.** Example: "dig into Etsy pricing trends for handmade greeting cards" → save the research output as a note, not just a single reply.
- **You produced a draft the customer will want to refer back to.** Example: landing-page copy, email draft, product outline, brainstorm of angles.
- **You formed a working plan or hypothesis worth remembering next session.** Example: "based on her constraints, she's a better fit for Prompt Pack than Notion Template — here's why".
- **The customer shared something (a link, a competitor, a testimonial) that deserves a dedicated note rather than burying in today's log.**

## When NOT to use

- Trivial conversational replies. Not every message needs a note.
- Anything that belongs in `MEMORY.md` — that's the running customer profile (name, constraints, chosen direction). Notes are thinking artifacts; MEMORY is identity.
- Anything that belongs in today's `memory/YYYY-MM-DD.md` log — that's per-day event log (Q&A, status updates, flags). Notes are durable reference material worth reading weeks later.

Rule of thumb: if you'd be happy to re-read this file three weeks from now to refresh context, save it as a note. If it's a "what happened today" entry, it's a daily log.

## How to use

1. Pick a filename: `YYYY-MM-DD-<short-kebab-slug>.md`. The date is today; the slug is 2–5 kebab-case words describing the topic. Examples: `2026-04-21-etsy-pricing-research.md`, `2026-04-22-landing-page-draft-v1.md`, `2026-04-23-ads-budget-allocation-plan.md`.
2. Write the note as markdown. Free-form content. A short header telling future-you what this is (1–2 lines) is worth it.
3. Save at `/opt/bintra/workspace/customer_notes/<filename>`.
4. Mention briefly to the customer that you saved it, so they know it's durable: "Saved the research as a note — I'll have it ready next time you want to build on it."

## Session-start integration

Every session you list `/opt/bintra/workspace/customer_notes/` alongside `knowledge/`. You do not read every file — you scan filenames. If a filename looks relevant to the current conversation (customer brings up Etsy again → note file mentions Etsy), open and read that file before replying. This is how compound knowledge works: past work is always one `ls` + one `Read` away.

## Common errors

- **Overwriting an existing note.** If today you produce a v2 of something already saved, create a new file with `-v2` suffix rather than overwriting. History is cheap; lost work is expensive.
- **Saving secrets.** Never put API keys, bot tokens, or credentials into a note. If the customer shares a credential, redact before writing anywhere.
- **Saving everything.** Don't. Notes are for durable artifacts. If in doubt, don't save — the daily log is always there.
