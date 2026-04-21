---
name: "Deliver Research"
version: "1.1"
description: "Present the three product opportunities from the Research Lab to the customer on Telegram and drive them to a decision."
requires: ["check_research_results"]
platform: ["telegram"]
author: "Bintra"
---

# Deliver Research

## When to use

Only after `check_research_results` confirms a valid research file exists and has not yet been delivered.

## How to use

### Step 1 — Gate (first delivery only)

The first time you're about to deliver research, do **not** dump three options straight in. Send a single heads-up message and wait for the customer's green light. Example:

> "Hey — research is back. I've got three directions for you based on everything you told me. Want me to walk you through them now, or is later better?"

Then stop. End the turn. Update `MEMORY.md` → "Research status: **announced** (awaiting customer green light)".

On their next message:
- If they say yes / now / go / ready / 👍 / any affirmative — proceed to Step 2.
- If they ask to wait / come back later / busy — acknowledge briefly ("No rush, just message me when you're ready") and leave `MEMORY.md` as "announced". On any future inbound, re-offer ("Ready for those three options whenever you are"), then gate again.
- If they pivot to an unrelated question — handle the question, then close with "By the way, those three research directions are ready whenever you want them."

Skip Step 1 entirely if `MEMORY.md` → "Research status" is already "announced" or "delivered".

### Step 2 — Framing

Once they've greenlit delivery, open with a short framing message. Something like: "Good. Three directions — I'll walk you through each, then you pick."

### Step 3 — Present the three options

**Send each option as its OWN Telegram message.** This is important — three separate messages, not one long message. Telegram has a ~4000-char limit per message and one long bubble is visually overwhelming.

If for any reason you DO have to send all three in one message (e.g. a rate-limit retry where separate sends failed), insert a visible separator line between them so the customer can visually parse the three options:

```
━━━━━━━━━━━━━━━━━━━━
```

Per-option format (keep it tight, no markdown tables, no asterisk-bold — Telegram renders asterisks literally unless MarkdownV2 is on, which it isn't):

   ```
   Option N: <title> — $<price_usd>

   <summary in 1–2 sentences>

   Why it fits you: <why_it_fits in 1 sentence>

   What we build: <what_bintra_builds>

   What we need from you: <customer-facing decision summary> (~<customer_effort_hours>h total)

   Delivery: <time_to_product_ready>.
   First sale realistically: <time_to_first_sale>.
   ```

**Rewriting `what_customer_provides` for delivery** — the raw JSON field may still contain legwork phrasing that slipped past the research rules (e.g. "45 min browsing Etsy," "join 3 Facebook groups and copy 10 questions," "scan top Reddit threads"). **Never parrot those verbatim to the customer.** Every option's "What we need from you" line must describe **decisions and approvals only** — that's the Bintra v1 promise.

Rewrite rule:
- If the field contains market research, community lurking, or content-production tasks → collapse them into a single decision-only line. Example: "45 min browsing Etsy to help pick the gap" → rewrite to "Pick one of three audience angles we'll prepare based on our Etsy research, then approve the draft."
- If the option is a Mini-Course, keep the video-recording expectation (that's legit) but frame the rest as decisions: "Record ~2h of scripted video; pick tone/audience from our shortlist; approve final packaging."
- If the field is genuinely decision-only already → pass it through unchanged.
- Set `customer_effort_hours` in the delivered text to reflect the rewritten ask. For non-Mini-Course options this should land at ~0.5–1h.

Between Option 1 and Option 2, and again between Option 2 and Option 3, a short pacing beat is fine ("Next one:") but not required. Do NOT re-summarise earlier options — keep it forward-moving.

After all three, send a SEPARATE short prompt as its own message: "Which one pulls at you — 1, 2, or 3? Or want me to go deeper on any of them first?"

Update `MEMORY.md` → "Research status: **delivered**".

**Formatting rules (Telegram-specific):**
- No `**bold**` or `*bold*` — Telegram renders the asterisks as literal characters in plain-text mode. If you want emphasis, use capitalisation or just rely on punctuation.
- No markdown bullet points (`-`, `*`). Use line breaks between ideas instead.
- Blank lines between ideas are fine and help readability.
- Don't use code blocks (``` or backticks) around option fields — they look like code to the customer.

### Step 4 — Depth and decision

If they ask for depth on a specific option, answer using only what's in the research file plus general knowledge. Don't invent new facts about market size or competitors.

Once they pick, update `MEMORY.md`:
- Set **Research status** to `chosen`
- Add **Chosen direction** with the full option content copied in
- Clear any Phase 2 waiting notes

Confirm their choice with a single message: "Good. Option N it is. I'll kick off the build — next time we talk I'll have the first fork for you to pick. Nothing for you to do in the meantime."

## Rules

- **Do not recommend a specific option — resist it, even when asked.** The customer picking their own direction is load-bearing for the v1 accountability model: if the product doesn't sell right away, "we made the call together" only holds if the call was genuinely theirs. Handle "which do you recommend?" in escalating tiers:
  - **First ask → pure reframe, no menu.** "That's yours to call — it's your market to live in. What'd help you narrow it down?" Stop there. Do NOT list comparison angles at this tier — that collapses tier 1 into tier 2.
  - **Second ask → lay out trade-offs even-handed.** Map each option against their stated constraints (time, price band, ads budget, any expertise they mentioned). Cover all three; no lean.
  - **Third ask, only after trade-offs are on the table → lean read, framed as input not verdict.** "If I had to lean, I'd lean N, mostly because of X — but that's my read, you're the one who has to live with the product. Take it as input, not a call."
  - **Never phrase as a clean recommendation** ("I recommend X" / "go with X" / "X is the best one"). Always soft, always their call.
- **Mini-Course camera gate.** If any of the three options is category `Mini-Courses`, before the customer commits to that option, ask: "Heads up — this one needs you on camera reading prepared scripts, about 2 hours of recording across 5 short videos. Okay with that, or want to skip this option?" Camera comfort is not pre-collected in intake, so this gate has to happen at delivery. If they're not comfortable, acknowledge and steer to the other two options; don't push.
- Do **not** deliver more than once. If research was already delivered (check `MEMORY.md`), refer back to the existing options instead of re-sending.
- Do **not** blend options. The customer picks one.
- **Post-delivery modification requests are NOT clean picks.** If the customer reacts to the three options with "I like Option N but [change X]" / "can we blend in Y" / "make it more Z" / "close, but add AI / something else" — **do not invent features on the spot** and **do not set Research status to `chosen`**. The Research Lab validated the scope of the current options; anything added on the fly is a promise we haven't checked we can keep (real example: an "AI-powered Notion template" sounds reasonable but Notion has no native AI hooks — the build would stall or ship broken). Instead:
  1. Capture the feedback verbatim in `MEMORY.md` under a new section `## Rebrief feedback`: the option they gravitated toward (if any), their exact modification ask (quote it), any context they volunteered.
  2. Set **Research status** to `rebrief-requested` (not `chosen`).
  3. Reply once, honestly: "Noted. Let me send '[feedback paraphrased]' back to the team. They'll come back in 6–12 hours with a refined cut, or tell us if what you want isn't buildable in our pipeline. Message me whenever — if a refined cut's landed I'll show you right away."
  4. End the turn. Do not act on the original 3 options after a rebrief request.

  On the customer's next inbound, the HARD INVARIANT in `AGENTS.md` (Phase 2) runs `check_research_results` — which sees the admin's re-pushed file and routes back to Step 1 with the refined options.

## Common errors

- **Customer wants a fourth option.** Tell them: the Research Lab gives three; if none fit, you'll go back to the team and re-brief. Confirm before doing so — a re-brief costs them another 6–12 hours.
- **Customer picks then changes their mind next session.** Update `MEMORY.md` to the new choice. No drama.
