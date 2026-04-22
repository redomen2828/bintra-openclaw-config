#!/usr/bin/env bash
# Bintra credit-balance-watcher
#
# Tails the openclaw.service journal and, when it sees an LLM
# insufficient-credits error, sends the customer a single Telegram alert
# (and fires a bintra-report telemetry event) telling them to top up.
#
# Hard rules (mirror snappy-welcome / research-ping discipline):
#  - NEVER log, echo, or write CUSTOMER_BOT_TOKEN. The curl URL is piped
#    straight to curl; no `set -x`, no stdout/stderr capture of the URL.
#  - Fire-and-forget. A failed curl or missing chat_id must NOT kill the
#    tail loop. We deliberately do not use `set -e`.
#  - Debounced: 1-hour cooldown via /run/bintra-credit-alert-cooldown. If
#    an out-of-credits state persists we do not re-spam the customer.
#  - No dependencies beyond coreutils + curl + journalctl (all on the
#    base Ubuntu 24.04 image).

set -u

# Re-exec in unset xtrace mode to be certain: if anything ever flipped -x
# globally we don't want to leak the bot token into the journal.
set +x

COOLDOWN_FILE="/run/bintra-credit-alert-cooldown"
COOLDOWN_SECONDS=3600
CHAT_ID_FILE="/opt/bintra/workspace/state/primary-chat-id"
REPORT_BIN="/usr/local/bin/bintra-report"

# journalctl's `--line-buffered` flag lives on grep, not journalctl — we
# stream `-f -o cat` from journalctl and pipe through a buffered grep so
# matches surface immediately rather than in 4KB chunks.
MATCH_PATTERN='credit balance is too low|insufficient_quota|billing_hard_limit_reached'

log() {
  # Tagged so `journalctl -u bintra-credit-watcher.service` is greppable.
  # NEVER include $CUSTOMER_BOT_TOKEN or the Telegram URL here.
  printf 'credit-balance-watcher: %s\n' "$1"
}

provider_label() {
  local raw="${CUSTOMER_LLM_PROVIDER:-}"
  if [ -z "$raw" ]; then
    printf 'LLM'
    return
  fi
  # Capitalise first letter; rest lowercase. "anthropic" -> "Anthropic".
  local first rest
  first="$(printf '%s' "$raw" | cut -c1 | tr '[:lower:]' '[:upper:]')"
  rest="$(printf '%s' "$raw" | cut -c2- | tr '[:upper:]' '[:lower:]')"
  printf '%s%s' "$first" "$rest"
}

billing_url_for() {
  case "${CUSTOMER_LLM_PROVIDER:-}" in
    anthropic) printf 'console.anthropic.com/settings/billing' ;;
    openai)    printf 'platform.openai.com/account/billing' ;;
    gemini)    printf 'aistudio.google.com/app/apikey' ;;
    *)         printf 'your provider'\''s billing page' ;;
  esac
}

cooldown_active() {
  if [ ! -f "$COOLDOWN_FILE" ]; then
    return 1
  fi
  local now mtime age
  now="$(date +%s 2>/dev/null || echo 0)"
  mtime="$(stat -c %Y "$COOLDOWN_FILE" 2>/dev/null || echo 0)"
  age=$(( now - mtime ))
  if [ "$age" -lt "$COOLDOWN_SECONDS" ]; then
    return 0
  fi
  return 1
}

touch_cooldown() {
  # /run is tmpfs on systemd — cleared on reboot, which is fine: after a
  # fresh boot it's correct to re-alert if the credit state is still bad.
  touch "$COOLDOWN_FILE" 2>/dev/null || true
}

read_chat_id() {
  if [ ! -s "$CHAT_ID_FILE" ]; then
    return 1
  fi
  # Strip whitespace/newline; reject anything that isn't a plausible
  # telegram numeric id (can be negative for group chats, but we only
  # serve 1:1 customer DMs so we take the first token as-is and let
  # Telegram validate).
  local id
  id="$(tr -d ' \t\r\n' < "$CHAT_ID_FILE" 2>/dev/null || true)"
  if [ -z "$id" ]; then
    return 1
  fi
  printf '%s' "$id"
}

send_alert() {
  local chat_id="$1"
  local provider
  provider="$(provider_label)"
  local billing
  billing="$(billing_url_for)"

  # Markdown v1 (not MarkdownV2) — simpler escaping; underscores inside
  # URLs don't need escaping and our provider names are safe.
  local message
  message="$(printf '⚠️ *Your Bintra Manager is blocked.*\n\nYour %s API account is out of credits. Top up at your provider'\''s billing page (for Anthropic: %s) and your Manager will start responding again immediately — no restart needed.' "$provider" "$billing")"

  # curl: -s silent, --max-time caps one attempt, no response echoed.
  # The URL contains the bot token — we pipe it to curl directly and
  # swallow stderr so nothing hits the journal.
  curl -sS --max-time 10 \
    -X POST \
    "https://api.telegram.org/bot${CUSTOMER_BOT_TOKEN}/sendMessage" \
    --data-urlencode "chat_id=${chat_id}" \
    --data-urlencode "text=${message}" \
    --data-urlencode "parse_mode=Markdown" \
    >/dev/null 2>&1 || true
}

report_telemetry() {
  if [ ! -x "$REPORT_BIN" ]; then
    return 0
  fi
  "$REPORT_BIN" customer_alert '{"kind":"insufficient_credits","debounce_hours":1}' >/dev/null 2>&1 || true
}

handle_match() {
  if cooldown_active; then
    return 0
  fi

  if [ -z "${CUSTOMER_BOT_TOKEN:-}" ]; then
    log "no CUSTOMER_BOT_TOKEN in env; skipping"
    return 0
  fi

  local chat_id
  if ! chat_id="$(read_chat_id)"; then
    log "no chat_id at $CHAT_ID_FILE yet; skipping alert"
    return 0
  fi

  send_alert "$chat_id"
  report_telemetry
  touch_cooldown
  log "alert dispatched (cooldown ${COOLDOWN_SECONDS}s)"
}

main() {
  log "tailing openclaw.service journal"
  # `journalctl -f -o cat` streams new log lines only (cat format drops
  # the metadata prefix). We pipe through a line-buffered egrep so the
  # shell `while read` below surfaces matches immediately.
  #
  # `|| true` on the pipeline so that a journalctl / grep restart doesn't
  # terminate the watcher — systemd `Restart=always` will bring us back,
  # but we also tolerate transient pipe closes within this run.
  journalctl -u openclaw.service -f -o cat 2>/dev/null \
    | grep --line-buffered -E "$MATCH_PATTERN" \
    | while IFS= read -r _line; do
        # Intentionally don't echo $_line anywhere; it may contain the
        # provider's error payload but we treat the match itself as the
        # signal and reconstruct our own alert text.
        handle_match
      done || true
}

main
