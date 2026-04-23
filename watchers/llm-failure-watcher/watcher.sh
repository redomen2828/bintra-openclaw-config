#!/usr/bin/env bash
# Bintra llm-failure-fallback-watcher
#
# Tails the openclaw.service journal for BYOK-key failures
# (auth / billing / rate-limit) and, when detected, asks the portal to
# generate a short Gemini-backed reply on Bintra's funded key, then
# forwards the reply to the customer on Telegram so Manager never goes
# fully mute.
#
# Pairs with /api/droplet/fallback/generate on the portal — that endpoint
# enforces a hard monthly budget, so this script cannot overspend even if
# the journal match loop goes wild.
#
# Hard rules (mirror credit-balance-watcher):
#  - NEVER log CUSTOMER_BOT_TOKEN or BINTRA_WEBHOOK_SECRET. Both land in
#    env; neither appears in stdout/stderr. No `set -x`.
#  - Fire-and-forget. Network errors must not kill the tail loop.
#  - Cooldown: 30 min per reason, kept in /run so it resets on reboot.
#  - No new dependencies — bash + curl + openssl + journalctl + python3
#    (all on the base Ubuntu 24.04 image the droplet boots from).

set -u
set +x

PORTAL_URL="${BINTRA_PORTAL_URL:-https://app.trybintra.com}"
FALLBACK_ENDPOINT="${PORTAL_URL}/api/droplet/fallback/generate"

CHAT_ID_FILE="/opt/bintra/workspace/state/primary-chat-id"
REPORT_BIN="/usr/local/bin/bintra-report"

# Reason-specific cooldown so a billing-failure cooldown doesn't mask a
# later auth-failure event (different problem, different guidance).
COOLDOWN_DIR="/run"
COOLDOWN_SECONDS=1800

# The journal emits several distinct error forms. Grep needs to match any
# of them — we classify the reason in Bash after the match.
MATCH_PATTERN='authentication_error|invalid_api_key|invalid x-api-key|HTTP 401|HTTP 403|credit balance is too low|insufficient_quota|billing_hard_limit_reached|HTTP 429|rate_limit_error|rate_limit_exceeded'

log() {
  printf 'llm-failure-watcher: %s\n' "$1"
}

classify_reason() {
  # $1 = the matched journal line. Decide which bucket to send to the
  # portal. Order matters — billing is checked before auth because an
  # Anthropic credit-exhaustion error body sometimes contains the word
  # "authentication" too.
  local line="$1"
  case "$line" in
    *credit\ balance\ is\ too\ low*|*insufficient_quota*|*billing_hard_limit_reached*)
      printf 'billing' ;;
    *HTTP\ 429*|*rate_limit_error*|*rate_limit_exceeded*)
      printf 'rate_limit' ;;
    *authentication_error*|*invalid_api_key*|*invalid\ x-api-key*|*HTTP\ 401*|*HTTP\ 403*)
      printf 'auth' ;;
    *)
      printf 'other' ;;
  esac
}

cooldown_file_for() {
  printf '%s/bintra-llm-fallback-%s' "$COOLDOWN_DIR" "$1"
}

cooldown_active() {
  local f="$1"
  if [ ! -f "$f" ]; then
    return 1
  fi
  local now mtime age
  now="$(date +%s 2>/dev/null || echo 0)"
  mtime="$(stat -c %Y "$f" 2>/dev/null || echo 0)"
  age=$(( now - mtime ))
  if [ "$age" -lt "$COOLDOWN_SECONDS" ]; then
    return 0
  fi
  return 1
}

touch_cooldown() {
  touch "$1" 2>/dev/null || true
}

read_chat_id() {
  if [ ! -s "$CHAT_ID_FILE" ]; then
    return 1
  fi
  local id
  id="$(tr -d ' \t\r\n' < "$CHAT_ID_FILE" 2>/dev/null || true)"
  if [ -z "$id" ]; then
    return 1
  fi
  printf '%s' "$id"
}

# ---- portal call ------------------------------------------------------------

request_fallback_reply() {
  # stdin-free HMAC signing. body is built manually (tiny, deterministic).
  local reason="$1"
  local ts body sig
  ts="$(date +%s)"
  # JSON assembled by hand so we don't need jq. user_id + secret are UUID
  # and hex respectively — no quoting risk.
  body=$(printf '{"user_id":"%s","reason":"%s","timestamp":%s}' \
    "$CUSTOMER_ID" "$reason" "$ts")
  sig=$(printf '%s.%s' "$ts" "$body" \
    | openssl dgst -sha256 -hmac "$BINTRA_WEBHOOK_SECRET" 2>/dev/null \
    | awk '{print $2}')
  if [ -z "$sig" ]; then
    log "HMAC signing failed"
    return 1
  fi

  # --max-time 30s: Gemini latency ~1s but include retry budget.
  curl -sS --max-time 30 \
    -X POST \
    -H "content-type: application/json" \
    -H "x-bintra-signature: ${sig}" \
    --data "$body" \
    "$FALLBACK_ENDPOINT" 2>/dev/null
}

extract_text_from_response() {
  # Use python3 — jq is optional, python3 is guaranteed on Ubuntu 24.04.
  python3 -c 'import sys,json
try:
    d=json.load(sys.stdin)
    if d.get("ok"):
        print(d.get("text","") or "")
    else:
        # Surface the code so the caller can decide whether to fall back
        # to a hardcoded string (e.g. monthly_cap_reached).
        print("__ERR__"+str(d.get("code","unknown")))
except Exception:
    print("__ERR__parse")' 2>/dev/null
}

send_telegram() {
  local chat_id="$1"
  local text="$2"
  # Swallow URL from any stdout/stderr capture — it contains the token.
  curl -sS --max-time 10 \
    -X POST \
    "https://api.telegram.org/bot${CUSTOMER_BOT_TOKEN}/sendMessage" \
    --data-urlencode "chat_id=${chat_id}" \
    --data-urlencode "text=${text}" \
    >/dev/null 2>&1 || true
}

hardcoded_fallback_text() {
  # Used when the portal endpoint itself is down or the monthly budget
  # is exhausted. Intentionally short and link-only — no LLM flair.
  local reason="$1"
  local lead
  case "$reason" in
    billing)
      lead="Your LLM API key is out of credits." ;;
    auth)
      lead="Your LLM API key was rejected as invalid." ;;
    rate_limit)
      lead="Your LLM provider is rate-limiting your account." ;;
    *)
      lead="Your LLM API key has a problem." ;;
  esac
  printf '%s Update it at https://app.trybintra.com/account/llm-key and your Manager will be back online in seconds.' "$lead"
}

report_llm_failure() {
  if [ ! -x "$REPORT_BIN" ]; then
    return 0
  fi
  local reason="$1"
  "$REPORT_BIN" llm_failure "$(printf '{"reason":"%s","provider":"%s","model":"%s","detected_by":"llm-failure-watcher"}' \
    "$reason" "${CUSTOMER_LLM_PROVIDER:-unknown}" "${CUSTOMER_LLM_MODEL:-unknown}")" \
    >/dev/null 2>&1 || true
}

# ---- main handler -----------------------------------------------------------

handle_match() {
  local line="$1"
  local reason
  reason="$(classify_reason "$line")"

  local cd_file
  cd_file="$(cooldown_file_for "$reason")"
  if cooldown_active "$cd_file"; then
    return 0
  fi

  if [ -z "${CUSTOMER_BOT_TOKEN:-}" ]; then
    log "no CUSTOMER_BOT_TOKEN; skipping"
    return 0
  fi
  if [ -z "${CUSTOMER_ID:-}" ] || [ -z "${BINTRA_WEBHOOK_SECRET:-}" ]; then
    log "missing CUSTOMER_ID or BINTRA_WEBHOOK_SECRET; skipping"
    return 0
  fi

  local chat_id
  if ! chat_id="$(read_chat_id)"; then
    log "no chat_id at $CHAT_ID_FILE yet; skipping"
    return 0
  fi

  # Emit telemetry FIRST so admin sees the failure even if the reply path
  # falls over.
  report_llm_failure "$reason"

  local response text
  response="$(request_fallback_reply "$reason")"
  text="$(printf '%s' "$response" | extract_text_from_response)"

  if [ -z "$text" ] || [[ "$text" == __ERR__* ]]; then
    log "portal fallback unavailable (${text:-empty}); using hardcoded text"
    text="$(hardcoded_fallback_text "$reason")"
  fi

  send_telegram "$chat_id" "$text"
  touch_cooldown "$cd_file"
  log "fallback reply dispatched (reason=${reason}, cooldown=${COOLDOWN_SECONDS}s)"
}

main() {
  log "tailing openclaw.service journal for LLM failures"
  # `-n 0` prevents journalctl -f from replaying the unit's most recent
  # lines on startup. Without this, a restart of the watcher would
  # re-fire fallbacks for historical errors (already-resolved incidents)
  # and spam the customer on Telegram. We only care about NEW failures
  # from here forward.
  journalctl -u openclaw.service -f -o cat -n 0 2>/dev/null \
    | grep --line-buffered -E "$MATCH_PATTERN" \
    | while IFS= read -r line; do
        handle_match "$line"
      done || true
}

main
