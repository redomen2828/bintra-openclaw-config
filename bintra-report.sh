#!/usr/bin/env bash
# bintra-report — one-command wrapper around the Bintra /api/droplet/report webhook.
# The Manager calls this after every inbound and outbound Telegram message so the
# admin dashboard stays in sync.
#
# Usage:
#   bintra-report message_in  "hi manager"
#   bintra-report message_out "Welcome — I'm the Manager..."
#   bintra-report option_picked '{"index":2,"title":"Notion templates for coaches"}'
#   bintra-report research_delivered '{"count":3}'
#   bintra-report heartbeat
#   bintra-report customer_silent '{"hours_since":72}'
#
# Reads env:
#   CUSTOMER_ID, BINTRA_WEBHOOK_SECRET   (set by systemd unit)
#   BINTRA_PORTAL_URL                    (optional, defaults to https://app.trybintra.com)
#
# Fire-and-forget: exits 0 on success, logs to stderr on failure, does not retry.
# Never blocks the Manager's reply loop.

set -u

EVENT_TYPE="${1:-}"
RAW_PAYLOAD="${2:-}"

if [ -z "$EVENT_TYPE" ]; then
  echo "bintra-report: missing event_type" >&2
  exit 2
fi

: "${CUSTOMER_ID:?bintra-report: CUSTOMER_ID not set}"
: "${BINTRA_WEBHOOK_SECRET:?bintra-report: BINTRA_WEBHOOK_SECRET not set}"
PORTAL_URL="${BINTRA_PORTAL_URL:-https://app.trybintra.com}"

# If the caller passed a JSON object (starts with `{`), use it as-is.
# Otherwise treat the argument as free text and wrap it as { "text": "<arg>" }.
# A missing second arg becomes `{}`.
if [ -z "$RAW_PAYLOAD" ]; then
  PAYLOAD_JSON='{}'
elif [[ "$RAW_PAYLOAD" == \{* ]]; then
  PAYLOAD_JSON="$RAW_PAYLOAD"
else
  # truncate to 2000 chars
  TRUNCATED="${RAW_PAYLOAD:0:2000}"
  PAYLOAD_JSON=$(jq -c -n --arg t "$TRUNCATED" '{text:$t, source:"telegram"}')
fi

TIMESTAMP=$(date +%s)
BODY=$(jq -c -n \
  --arg uid "$CUSTOMER_ID" \
  --arg et "$EVENT_TYPE" \
  --argjson p "$PAYLOAD_JSON" \
  --argjson ts "$TIMESTAMP" \
  '{user_id:$uid, event_type:$et, payload:$p, timestamp:$ts}')

SIG=$(printf '%s.%s' "$TIMESTAMP" "$BODY" \
  | openssl dgst -sha256 -hmac "$BINTRA_WEBHOOK_SECRET" \
  | awk '{print $2}')

RESPONSE=$(curl -sS -o /dev/null -w '%{http_code}' \
  -X POST "$PORTAL_URL/api/droplet/report" \
  -H "Content-Type: application/json" \
  -H "X-Bintra-Signature: $SIG" \
  --max-time 8 \
  --data "$BODY" 2>/dev/null) || true

if [ "${RESPONSE:-000}" != "200" ]; then
  echo "bintra-report: portal returned HTTP ${RESPONSE:-timeout} for event=$EVENT_TYPE" >&2
  exit 1
fi

exit 0
