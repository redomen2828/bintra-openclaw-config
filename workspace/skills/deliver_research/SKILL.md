---
name: "Deliver Research"
version: "1.0"
description: "Present the three product opportunities from the Research Lab to the customer on Telegram and drive them to a decision."
requires: ["check_research_results"]
platform: ["telegram"]
author: "Bintra"
---

# Deliver Research

## When to use

Only after `check_research_results` confirms a valid research file exists and has not yet been delivered.

## How to use

1. Open with a short framing message. Something like: "The research team came back. Three directions to choose from. I'll walk you through each, then you pick."

2. For each of the 3 options in `options[]`, send **one Telegram message per option** in this format (keep it tight, no markdown tables):

   ```
   Option N: <title>

   <summary in 1–2 sentences>

   Why it fits you: <why_it_fits in 1 sentence>

   First step: <first_step>

   Realistic time to first sale: <estimated_time_to_first_sale>
   ```

3. After all three, send a short prompt: "Which one pulls at you — 1, 2, or 3? Or want me to go deeper on any of them first?"

4. If they ask for depth on a specific option, answer using only what's in the research file plus general knowledge. Don't invent new facts about market size or competitors.

5. Once they pick, update `MEMORY.md`:
   - Set **Research status** to `chosen`
   - Add **Chosen direction** with the full option content copied in
   - Clear any Phase 2 waiting notes

6. Confirm their choice with a single message: "Good. Option N it is. Next session we start building. Between now and then: [first_step from the chosen option]."

## Rules

- Do **not** bias the customer toward a specific option unless they explicitly ask for your opinion. If they do ask, give one, briefly, and say it's your read.
- Do **not** deliver more than once. If research was already delivered (check `MEMORY.md`), refer back to the existing options instead of re-sending.
- Do **not** blend options. The customer picks one.

## Common errors

- **Customer wants a fourth option.** Tell them: the Research Lab gives three; if none fit, you'll go back to the team and re-brief. Confirm before doing so — a re-brief costs them another 24–48 hours.
- **Customer picks then changes their mind next session.** Update `MEMORY.md` to the new choice. No drama.
