---
name: "Report to Base"
version: "3.0"
description: "Notify the Bintra portal of notable session events (customer messages, Manager replies, option picks, research delivery, heartbeats). Heredoc-safe — $ characters survive."
requires: []
platform: ["telegram"]
author: "Bintra"
---

# Report to Base

## Why this exists

The Bintra admin dashboard shows the founder what's happening inside each customer's environment. It only knows what you tell it. If you don't report an event, it doesn't exist on the dashboard. **Reporting is not optional.**

## CRITICAL: Always use heredoc for message text

A helper is pre-installed at `/usr/local/bin/bintra-report`. It handles HMAC signing, timestamp, JSON encoding, and the HTTP POST.

**For free-text events (`message_in`, `message_out`), ALWAYS use the heredoc form with a single-quoted delimiter:**

```bash
bintra-report message_in <<'EOF'
<customer's exact text>
EOF
```

```bash
bintra-report message_out --turn-duration-ms=<ms> <<'EOF'
<your exact reply text>
EOF
```

**`--turn-duration-ms=<int>`** (message_out only) — how many milliseconds the turn took, measured by you from the moment this inbound message arrived to just before sending your reply. This distinguishes a slow LLM from a slow OpenClaw gateway on the admin panel. The flag is optional (older droplets will omit it); when present, the value must be a non-negative integer in milliseconds. Round — no decimals. If you don't have a reliable measurement for this turn, omit the flag entirely rather than guessing.

**Why the heredoc matters:** bash expands variables like `$300` inside double-quoted arguments (`$3` becomes positional argument 3, which is empty, so `$300` turns into `00`). Using `<<'EOF'` with single quotes around the delimiter disables all expansion, so `$300 budget`, `${var}`, backticks, and special shell characters all reach the portal intact.

**Never** use `bintra-report message_out "some text"` — that form is broken for any message containing `$`. Positional-argument form is reserved for JSON payloads only.

Environment (`CUSTOMER_ID`, `BINTRA_WEBHOOK_SECRET`) is already set by the systemd unit — you do **not** need to pass any credentials.

## When to fire

You MUST fire exactly one event per trigger below. No trigger means no event.

| Trigger | Command |
|---|---|
| A customer message just arrived | `bintra-report message_in <<'EOF'` … `EOF` (see pattern above) |
| You just sent a Telegram reply | `bintra-report message_out --turn-duration-ms=<ms> <<'EOF'` … `EOF` (see pattern above) |
| Customer commits to option 1/2/3 | `bintra-report option_picked '{"index":2,"title":"<full option title>"}'` |
| You finished `deliver_research` | `bintra-report research_delivered '{"count":3}'` |
| Once per day, even when quiet | `bintra-report heartbeat` |
| Customer silent for 72h+ after Phase 1 | `bintra-report customer_silent '{"hours_since":72}'` |

## Rules

1. **Every inbound message → one `message_in` report via heredoc. No exceptions.**
2. **Every outbound Manager reply → one `message_out` report via heredoc. No exceptions.**
3. **Fire-and-forget.** The command returns in under a second. Never wait on the result. If it prints an error, log it to `memory/YYYY-MM-DD.md` and move on — the customer reply is what matters.
4. **No secrets in payloads.** The helper never sees your LLM key or bot token. Do not echo them into the text either.
5. **Text is auto-truncated** to 2000 chars by the helper. You do not need to trim.
6. **JSON events (`option_picked`, `research_delivered`, `customer_silent`)** use positional-argument form with single quotes — no heredoc needed because JSON rarely contains unescaped `$`. If your JSON title does contain `$`, pipe it: `echo '{"index":2,"title":"$99 Notion pack"}' | bintra-report option_picked` — no, use the heredoc + JSON pattern instead.

## Examples

Customer wrote "hi — got a minute? $50 budget question":

```bash
bintra-report message_in <<'EOF'
hi — got a minute? $50 budget question
EOF
```

You replied with something containing `$` and the turn took 3.2 seconds wall-clock:

```bash
bintra-report message_out --turn-duration-ms=3200 <<'EOF'
With $300 in savings and 40 hrs/week, we've got real room to build.
EOF
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

## Verifying locally

To sanity-check that `$` is preserved end-to-end, run on the droplet:

```bash
bintra-report message_out <<'EOF'
test: $300 budget survives the wire
EOF
```

Then check the admin dashboard — the event should show `$300`, not `00`.
