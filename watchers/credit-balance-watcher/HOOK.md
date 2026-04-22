# credit-balance-watcher

Long-lived companion process beside OpenClaw. Tails
`journalctl -u openclaw.service -f -o cat` and greps for the three LLM
out-of-credit error strings we've seen in the wild:

- `credit balance is too low` (Anthropic)
- `insufficient_quota` (OpenAI)
- `billing_hard_limit_reached` (OpenAI hard cap)

On a match, sends a single Markdown Telegram `sendMessage` to the
customer's primary chat telling them their Manager is blocked and
pointing them at their provider's billing page. Also fires a
`bintra-report customer_alert` event (fire-and-forget) so the admin
panel sees the outage.

## Why this exists

When a customer's provider account runs out of credits, OpenClaw keeps
accepting inbound Telegram messages but every LLM turn errors out. From
the customer's seat this looks identical to "the bot is broken" — they
keep typing, nothing comes back, and we silently lose them. A single
proactive alert with a concrete next step (top up here) converts that
silent failure into a solvable one.

We sit outside OpenClaw intentionally: we watch the journal rather than
patch the framework. Same discipline as the research-ping watcher — the
framework stays upstream-clean and our companion processes carry the
customer-facing glue.

## How it decides who to message

- Bot token: `CUSTOMER_BOT_TOKEN` from the systemd unit env. Never
  logged, never echoed, never written to any file from this watcher.
- Chat id: read from `/opt/bintra/workspace/state/primary-chat-id`,
  which the `capture-chat-id` hook writes on the customer's first
  inbound. If the file is missing (customer has not messaged yet), the
  watcher logs a single diagnostic line and skips — the alert will
  fire correctly once the customer has any message history.

## Debounce

A 1-hour cooldown via `/run/bintra-credit-alert-cooldown`. The file is
on tmpfs, so a reboot clears it (which is correct: after a restart it's
fine to re-alert if the credit state is still bad). During normal
operation the customer gets at most one alert per hour regardless of
how many failing LLM calls the Manager makes.

## The Telegram message

```
⚠️ *Your Bintra Manager is blocked.*

Your {Provider} API account is out of credits. Top up at your
provider's billing page (for Anthropic: console.anthropic.com/settings/billing)
and your Manager will start responding again immediately — no restart
needed.
```

`{Provider}` is `$CUSTOMER_LLM_PROVIDER` capitalised (`Anthropic`,
`Openai`, `Gemini`). If unset, falls back to "LLM". Provider-specific
billing URL is picked from a small map inside the script.

## Hard rules

- `set -u` but NEVER `set -e`. A single curl or grep failure must not
  kill the tail loop — systemd `Restart=always` is the outer safety
  net, but within one run we want robustness too.
- `set +x` at the top, defensively: if anyone ever flips xtrace
  globally we refuse to leak the bot token into the journal.
- curl output is sent to `/dev/null` with stderr swallowed. The URL
  containing the token is never printed, captured, or logged.
- Missing `CUSTOMER_BOT_TOKEN`, missing chat_id, Telegram 5xx,
  journalctl restart, systemd restart — all tolerated. Loop continues.

## Deployment

- **Droplet:** installed + started by `install.sh` as the
  `bintra-credit-watcher.service` systemd unit. Reads
  `CUSTOMER_BOT_TOKEN`, `CUSTOMER_LLM_PROVIDER`, `CUSTOMER_ID`,
  `BINTRA_WEBHOOK_SECRET` from unit env. `Requires=openclaw.service` +
  `After=openclaw.service` so the journal is available when we start
  tailing. `Restart=always` with `RestartSec=10`.
- **Local-dev Docker:** not wired up today. If we port it, spawn it
  the same way `local-dev/start.sh` runs the research-ping watcher.
