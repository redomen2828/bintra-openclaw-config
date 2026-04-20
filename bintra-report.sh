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
#   bintra-report gateway_phase '{"phase":"ready"}'
#
# The heredoc form with the single-quoted delimiter ('EOF') prevents bash from
# eating $VAR expansions inside the message text. NEVER pass free text as a
# quoted positional argument — bash will silently expand $0..$9 and corrupt the
# dashboard record. Positional-arg form is reserved for JSON payloads only.
#
# Heartbeat enrichment (HARDENING 1.13):
#   On `heartbeat`, the helper automatically collects local gateway telemetry
#   and merges it into the payload so the admin panel can diagnose outages
#   without SSH. Collected fields (best-effort, silently omitted on failure):
#     - n_restarts      (int) : systemctl show openclaw.service NRestarts
#     - listener_count  (int) : number of processes bound to 127.0.0.1:18789
#     - phase           (str) : latest gateway phase ("ready"|"booting"|"crashed")
#   None of these are load-bearing for reporting — if collection fails, the
#   heartbeat still goes through with whatever subset succeeded.
#
# `gateway_phase` is called by the installer / systemd hooks on state changes
# (boot, ready, crashed) so the panel sees phase transitions as they happen,
# not only on the next heartbeat tick.
#
# Reads env:
#   CUSTOMER_ID, BINTRA_WEBHOOK_SECRET   (set by systemd unit)
#   BINTRA_PORTAL_URL                    (optional, defaults to https://app.trybintra.com)
#
# Fire-and-forget: exits 0 on success, logs to stderr on failure, does not retry.
# Never blocks the Manager's reply loop.

set -u

# Optional named flags (must come AFTER event_type, BEFORE the positional JSON
# or heredoc payload). Currently supported:
#   --turn-duration-ms=<int>   attaches turn_duration_ms to message_out payload
#                              (HARDENING 1.13 — separates slow-LLM from slow-OpenClaw).
EVENT_TYPE="${1:-}"
shift || true

TURN_DURATION_MS=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --turn-duration-ms=*)
      TURN_DURATION_MS="${1#--turn-duration-ms=}"
      shift
      ;;
    --turn-duration-ms)
      TURN_DURATION_MS="${2:-}"
      shift 2
      ;;
    *)
      break
      ;;
  esac
done

ARG_PAYLOAD="${1:-}"

if [ -z "$EVENT_TYPE" ]; then
  echo "bintra-report: missing event_type" >&2
  exit 2
fi

: "${CUSTOMER_ID:?bintra-report: CUSTOMER_ID not set}"
: "${BINTRA_WEBHOOK_SECRET:?bintra-report: BINTRA_WEBHOOK_SECRET not set}"
PORTAL_URL="${BINTRA_PORTAL_URL:-https://app.trybintra.com}"

# -----------------------------------------------------------------------------
# Heartbeat telemetry collectors (HARDENING 1.13).
#
# Each function prints a single value to stdout on success. On any failure
# (command not found, unit missing, permission denied, unexpected output) it
# prints nothing and returns 0. We intentionally swallow errors because the
# heartbeat itself is the important signal — we never want a broken collector
# to silence the heartbeat.
# -----------------------------------------------------------------------------

collect_n_restarts() {
  # `systemctl show --property=NRestarts` prints "NRestarts=<int>". If the
  # service is missing, the value comes out empty, not erroring. Tolerate both.
  local v
  v=$(systemctl show openclaw.service --property=NRestarts 2>/dev/null \
        | awk -F= '/^NRestarts=/ { print $2; exit }')
  if [[ "$v" =~ ^[0-9]+$ ]]; then
    printf '%s' "$v"
  fi
}

collect_listener_count() {
  # Number of processes listening on any interface on port 18789 (gateway).
  # `ss -ltnp` is the modern replacement for `netstat`; the `p` flag requires
  # root which the openclaw.service runs as, so this works in-unit.
  # We count *unique lines* that end in :18789 to avoid counting IPv4/IPv6
  # wildcard entries for the same process twice.
  local c
  if ! command -v ss >/dev/null 2>&1; then
    return 0
  fi
  c=$(ss -ltn 2>/dev/null | awk '$4 ~ /:18789$/' | wc -l | tr -d ' ')
  if [[ "$c" =~ ^[0-9]+$ ]]; then
    printf '%s' "$c"
  fi
}

collect_current_phase() {
  # Infer a phase string from systemd + gateway port state so the panel has
  # something useful even when the Manager hasn't emitted an explicit
  # gateway_phase yet. Priority: crashed > ready > booting > (nothing).
  local active
  active=$(systemctl is-active openclaw.service 2>/dev/null || true)
  local failed
  failed=$(systemctl is-failed openclaw.service 2>/dev/null || true)

  if [ "$failed" = "failed" ]; then
    printf 'crashed'
    return 0
  fi

  local listeners
  listeners=$(collect_listener_count)
  if [ "$active" = "active" ] && [ "${listeners:-0}" -ge 1 ]; then
    printf 'ready'
    return 0
  fi
  if [ "$active" = "activating" ] || [ "$active" = "active" ]; then
    printf 'booting'
    return 0
  fi
  # Unknown / inactive — leave empty so the panel shows "—" rather than lying.
}

build_heartbeat_payload() {
  # Merge collected telemetry into a single JSON object. Each field is
  # optional — jq `if . then ... else empty end` drops nulls so we never send
  # n_restarts=null or listener_count=null to the portal.
  local nr lc ph
  nr=$(collect_n_restarts)
  lc=$(collect_listener_count)
  ph=$(collect_current_phase)

  jq -c -n \
    --arg nr "$nr" \
    --arg lc "$lc" \
    --arg ph "$ph" \
    '
    {}
    | (if ($nr | length) > 0 then . + {n_restarts: ($nr | tonumber)} else . end)
    | (if ($lc | length) > 0 then . + {listener_count: ($lc | tonumber)} else . end)
    | (if ($ph | length) > 0 then . + {phase: $ph} else . end)
    '
}

# Input resolution order:
#   0. (heartbeat-only) auto-collect telemetry and merge with any JSON passed in.
#   1. If positional $2 is a JSON object (starts with `{`), use it verbatim.
#   2. Else if stdin is not a TTY (caller piped / heredoc'd text), read stdin as free text.
#   3. Else if positional $2 is non-empty, use it as free text (LEGACY — $ may be corrupted).
#   4. Else payload is empty `{}`.
if [ "$EVENT_TYPE" = "heartbeat" ]; then
  AUTO_HB=$(build_heartbeat_payload 2>/dev/null || printf '{}')
  if [ -z "$AUTO_HB" ]; then
    AUTO_HB='{}'
  fi
  if [[ "$ARG_PAYLOAD" == \{* ]]; then
    # Merge user-supplied JSON on top of auto-collected fields so callers can
    # override (useful for tests); user keys win.
    PAYLOAD_JSON=$(jq -c -n \
      --argjson a "$AUTO_HB" \
      --argjson b "$ARG_PAYLOAD" \
      '$a * $b')
  else
    PAYLOAD_JSON="$AUTO_HB"
  fi
elif [[ "$ARG_PAYLOAD" == \{* ]]; then
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

# If --turn-duration-ms was supplied and the value is a plain integer, merge
# it into the payload. Silently ignored for non-message_out events so callers
# can't accidentally decorate the wrong event type.
if [ "$EVENT_TYPE" = "message_out" ] && [[ "$TURN_DURATION_MS" =~ ^[0-9]+$ ]]; then
  PAYLOAD_JSON=$(jq -c -n \
    --argjson base "$PAYLOAD_JSON" \
    --argjson d "$TURN_DURATION_MS" \
    '$base + {turn_duration_ms: $d}')
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
