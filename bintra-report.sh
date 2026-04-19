#!/usr/bin/env bash
# bintra-report — one-command wrapper around the Bintra /api/droplet/report webhook.
# The Manager calls this after every inbound and outbound Telegram message so the
# admin dashboard stays in sync.
#
# Usage (safe for $ characters — ALWAYS use heredoc for message text):
#   bintra-report message_in <<'EOF'
#   hi manager — got a $100 question for you
#   EOF
#
#   bintra-report message_out <<'EOF'
#   With $300 in the bank we can build something solid.
#   EOF
#
#   bintra-report option_picked '{"index":2,"title":"Notion templates for coaches"}'
#   bintra-report research_delivered '{"count":3}'
#   bintra-report heartbeat
#   bintra-report customer_silent '{"hours_since":72}'
#
# The heredoc form with the single-quoted delimiter ('EOF') prevents bash from
# eating $VAR expansions inside the message text. NEVER pass free text as a
# quoted positional argument — bash will silently expand $0..$9 and corrupt the
# dashboard record. Positional-arg form is reserved for JSON payloads only.
#
# Reads env:
#   CUSTOMER_ID, BINTRA_WEBHOOK_SECRET   (set by systemd unit)
#   BINTRA_PORTAL_URL                    (optional, defaults to https://app.trybintra.com)
#
# Fire-and-forget: exits 0 on success, logs to stderr on failure, does not retry.
# Never blocks the Manager's reply loop.

set -u

EVENT_TYPE="${1:-}"
ARG_PAYLOAD="${2:-}"

if [ -z "$EVENT_TYPE" ]; then
  echo "bintra-report: missing event_type" >&2
  exit 2
fi

: "${CUSTOMER_ID:?bintra-report: CUSTOMER_ID not set}"
: "${BINTRA_WEBHOOK_SECRET:?bintra-report: BINTRA_WEBHOOK_SECRET not set}"
PORTAL_URL="${BINTRA_PORTAL_URL:-https://app.trybintra.com}"

# Input resolution order:
#   1. If positional $2 is a JSON object (starts with `{`), use it verbatim.
#   2. Else if stdin is not a TTY (caller piped / heredoc'd text), read stdin as free text.
#   3. Else if positional $2 is non-empty, use it as free text (LEGACY — $ may be corrupted).
#   4. Else payload is empty `{}`.
if [[ "$ARG_PAYLOAD" == \{* ]]; then
  PAYLOAD_JSON="$ARG_PAYLOAD"
elif [ ! -t 0 ]; then
  STDIN_TEXT="$(cat)"
  TRUNCATED="${STDIN_TEXT:0:2000}"
  PAYLOAD_JSON=$(jq -c -n --arg t "$TRUNCATED" '{text:$t, source:"telegram"}')
elif [ -n "$ARG_PAYLOAD" ]; then
  TRUNCATED="${ARG_PAYLOAD:0:2000}"
  PAYLOAD_JSON=$(jq -c -n --arg t "$TRUNCATED" '{text:$t, source:"telegram"}')
else
  PAYLOAD_JSON='{}'
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
