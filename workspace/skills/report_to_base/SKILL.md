---
name: "Report to Base"
version: "1.0"
description: "Report notable session events (inbound/outbound messages, option picks, research delivery, heartbeats) back to the Bintra portal so the admin dashboard stays in sync."
requires: []
platform: ["telegram"]
author: "Bintra"
---

# Report to Base

## When to use

Invoke this skill whenever one of the following happens. Each invocation sends **one** event.

- **After every inbound customer message.** Event type: `message_in`. Payload should include the text (truncated to 2000 chars) and any relevant metadata (message id, timestamp).
- **After every outbound Manager reply you send on Telegram.** Event type: `message_out`. Same payload shape as `message_in`.
- **When the customer picks one of the three research options.** Event type: `option_picked`. Payload **must** include `{ "index": <1|2|3>, "title": "<full option title>" }`. Fire this once, at the moment they commit to a choice.
- **When you finish presenting research via `deliver_research`.** Event type: `research_delivered`. Payload can include the count of options delivered and their titles.
- **Once per 24 hours as a heartbeat.** Event type: `heartbeat`. Payload can be `{}` or include light session stats. This tells the admin dashboard the droplet is alive even when the customer is quiet.
- **When the customer has gone silent** (no inbound message for 72h+ after Phase 1). Event type: `customer_silent`. Fire once per silence spell, not repeatedly.

Never include the customer's API key, bot token, or any secret in the payload. Keep payloads small.

## How to use

The portal exposes a signed webhook at `https://app.trybintra.com/api/droplet/report`. You POST a JSON body and include an `X-Bintra-Signature` header that is the HMAC-SHA256 of `<timestamp>.<raw body>` using the shared secret from env var `BINTRA_WEBHOOK_SECRET`. The customer id is in env var `CUSTOMER_ID`.

### Request shape

```json
{
  "user_id": "<uuid from $CUSTOMER_ID>",
  "event_type": "message_in",
  "payload": { "text": "hi manager", "source": "telegram" },
  "timestamp": 1745078400
}
```

- `timestamp` is unix seconds. Must be within 5 minutes of server time or the portal rejects it.
- `event_type` must be one of: `message_in`, `message_out`, `option_picked`, `research_delivered`, `customer_silent`, `heartbeat`.
- `payload` is a JSON object. Keep it under a few KB.

### Bash / curl example

```bash
TIMESTAMP=$(date +%s)
BODY=$(jq -c -n \
  --arg uid "$CUSTOMER_ID" \
  --arg et "message_in" \
  --arg text "hi manager" \
  --argjson ts "$TIMESTAMP" \
  '{user_id:$uid, event_type:$et, payload:{text:$text, source:"telegram"}, timestamp:$ts}')

SIG=$(printf '%s.%s' "$TIMESTAMP" "$BODY" \
  | openssl dgst -sha256 -hmac "$BINTRA_WEBHOOK_SECRET" \
  | awk '{print $2}')

curl -sS -X POST https://app.trybintra.com/api/droplet/report \
  -H "Content-Type: application/json" \
  -H "X-Bintra-Signature: $SIG" \
  --data "$BODY"
```

The portal returns `{"ok": true}` on success. On failure you'll get a 4xx/5xx with `{"ok": false, "error": "..."}`. Do not retry on 4xx (bad signature, bad body, stale timestamp — fix it instead). You may retry once on 5xx.

## Rules

- **Fire and forget.** Never block the customer reply on the report. If the POST fails, log it to today's `memory/YYYY-MM-DD.md` and move on.
- **No secrets in payload.** Do not send `BINTRA_WEBHOOK_SECRET`, the LLM key, or the bot token.
- **Truncate long text.** Cap `text` fields at ~2000 chars. The admin view is a feed, not an archive.
- **Exact JSON bytes.** The signature is computed over the raw body string. If you re-serialize between signing and sending, the signature will mismatch. Sign the exact bytes you send.

## Common errors

- **401 Bad signature:** you hashed a different body than you sent, or `BINTRA_WEBHOOK_SECRET` is wrong. Verify the env var is set on the droplet and re-sign the exact body bytes.
- **400 Stale timestamp:** droplet clock drifted. Let it resync via `systemd-timesyncd` and retry.
- **403 Customer not provisioned:** the portal hasn't stored a webhook secret for this user yet. This means the provisioner ran without updating the DB — escalate to the Bintra team.
- **404 User not found:** `CUSTOMER_ID` doesn't match any portal user. Escalate.
