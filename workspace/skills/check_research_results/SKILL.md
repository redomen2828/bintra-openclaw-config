---
name: "Check Research Results"
version: "2.0"
description: "Check whether the Bintra Research Lab has delivered product opportunities for this customer, and load them if so."
requires: []
platform: ["telegram"]
author: "Bintra"
---

# Check Research Results

## When to use

- At the start of any session after Phase 1 (Discovery) is complete.
- Any time the customer asks "is the research back yet?" or similar.
- Before invoking `deliver_research`.

## How to use

1. Look for the research file in these paths, in order. The FIRST hit wins:
   - `/opt/bintra/workspace/knowledge/bintra_research_*.json` — admin-dashboard upload flow (`push-knowledge.ts --from-db`). There should be exactly one match; if there are multiple, pick the newest by mtime.
   - `/opt/bintra/workspace/knowledge/research_results.json` — legacy admin-dashboard filename.
   - `/opt/bintra/workspace/research/{{CUSTOMER_ID}}.json` — legacy workspace path.
   - `/data/research/{{CUSTOMER_ID}}.json` — `push-research.ts` CLI flow.
2. If none of those exist: tell the customer the research team is still working and give an ETA of 24–48 hours from when Phase 1 completed. Do not repeat this message more than once per session.
3. If one exists:
   - Read and parse the JSON.
   - Validate it has the expected shape: an object with a `customer_id` string, a `generated_at` ISO timestamp, a `brief_summary` string, and an `options` array of exactly 3 items. Each option must have these string fields: `title`, `category`, `summary`, `why_it_fits`, `what_bintra_builds`, `what_customer_provides`, `time_to_product_ready`, `time_to_first_sale`. Each option must also have a numeric `price_usd` and numeric `customer_effort_hours`.
   - If the shape is wrong, do not show it to the customer. Log the issue to today's `memory/YYYY-MM-DD.md` and tell the customer the research came back but needs a quick review from the Bintra team.
   - If the shape is correct, mark "Research status: delivered" in `MEMORY.md`, record the source path you loaded it from, and hand off to the `deliver_research` skill.

## File format

See `research_results.template.json` in the config repo root for the exact schema. The schema is also documented in `src/lib/research-brief.ts` in the portal repo (this is what Claude gets told to produce).

## Common errors

- **File not found:** normal during Phase 2. Don't treat as an error.
- **Malformed JSON:** rare. Escalate silently (log it, don't expose it to the customer).
- **Schema drift:** if Claude produced an older shape (with `first_step` instead of `what_bintra_builds`), fall back to the old validation only if the customer_id matches — and flag it in `memory/YYYY-MM-DD.md` so the admin knows to re-run the brief.
