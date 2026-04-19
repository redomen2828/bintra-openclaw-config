---
name: "Report to Base"
version: "2.0"
description: "Notify the Bintra portal of notable session events (customer messages, Manager replies, option picks, research delivery, heartbeats). One command per event — fire-and-forget."
requires: []
platform: ["telegram"]
author: "Bintra"
---

# Report to Base

## Why this exists

The Bintra admin dashboard shows the founder what's happening inside each customer's environment. It only knows what you tell it. If you don't report an event, it doesn't exist on the dashboard. **Reporting is not optional.**

## The one command

A helper is pre-installed on this droplet at `/usr/local/bin/bintra-report`. It handles HMAC signing, timestamp, JSON encoding, and the HTTP POST.

```bash
bintra-report <event_type> "<text or JSON>"
```

Environment (`CUSTOMER_ID`, `BINTRA_WEBHOOK_SECRET`) is already set by the systemd unit — you do **not** need to pass any credentials.

## When to fire

You MUST fire exactly one event per trigger below. No trigger means no event.

| Trigger | Command |
|---|---|
| A customer message just arrived | `bintra-report message_in "<the customer's exact text>"` |
| You just sent a Telegram reply | `bintra-report message_out "<the exact text you replied with>"` |
| Customer commits to option 1/2/3 | `bintra-report option_picked '{"index":2,"title":"<full option title>"}'` |
| You finished `deliver_research` | `bintra-report research_delivered '{"count":3}'` |
| Once per day, even when quiet | `bintra-report heartbeat` |
| Customer silent for 72h+ after Phase 1 | `bintra-report customer_silent '{"hours_since":72}'` |

## Rules

1. **Every inbound message → one `message_in` report. No exceptions.**
2. **Every outbound Manager reply → one `message_out` report. No exceptions.**
3. **Fire-and-forget.** The command returns in under a second. Never wait on the result. If it prints an error, log it to `memory/YYYY-MM-DD.md` and move on — the customer reply is what matters.
4. **No secrets in payloads.** The helper never sees your LLM key or bot token. Do not echo them into the text argument either.
5. **Text is auto-truncated** to 2000 chars by the helper. You do not need to trim.
6. **Text argument** = bare string (helper wraps it as `{"text":"..."}` for you).
   **JSON argument** = must start with `{` (helper passes it through verbatim).

## Examples

Customer wrote "hi — got a minute?":
```bash
bintra-report message_in "hi — got a minute?"
```

You replied "Hey! Of course. How can I help you today?":
```bash
bintra-report message_out "Hey! Of course. How can I help you today?"
```

Customer picked option 2:
```bash
bintra-report option_picked '{"index":2,"title":"Notion templates for solo coaches"}'
```

## Troubleshooting

The helper prints `bintra-report: portal returned HTTP <code>` on failure.

- **HTTP 400 (stale timestamp)** — droplet clock drifted. `systemctl restart systemd-timesyncd` and retry.
- **HTTP 401 (bad signature)** — `BINTRA_WEBHOOK_SECRET` mismatch. Escalate to the Bintra team; do not guess.
- **HTTP 403 (not provisioned)** — portal has no webhook secret for this customer. Escalate.
- **HTTP 404 (user not found)** — `CUSTOMER_ID` is wrong. Escalate.
- **Timeout / network error** — log and continue. The customer's reply must not block on this.
