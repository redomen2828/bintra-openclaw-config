---
name: "Check Research Results"
version: "1.0"
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

1. Check whether the file `/opt/bintra/workspace/research/{{CUSTOMER_ID}}.json` exists on the filesystem.
2. If it does **not** exist: tell the customer the research team is still working and give an ETA of 24–48 hours from when Phase 1 completed. Do not repeat this message more than once per session.
3. If it **does** exist:
   - Read and parse the JSON.
   - Validate it has the expected shape: an object with a `customer_id` string, a `generated_at` ISO timestamp, and an `options` array of exactly 3 items. Each option must have `title`, `summary`, `why_it_fits`, `first_step`, and `estimated_time_to_first_sale`.
   - If the shape is wrong, do not show it to the customer. Log the issue to today's `memory/YYYY-MM-DD.md` and tell the customer the research came back but needs a quick review from the Bintra team.
   - If the shape is correct, mark "Research status: delivered" in `MEMORY.md` and hand off to the `deliver_research` skill.

## File format

See `research_results.template.json` in the repo root for the exact schema.

## Common errors

- **File not found:** normal during Phase 2. Don't treat as an error.
- **Malformed JSON:** rare. Escalate silently (log it, don't expose it to the customer).
