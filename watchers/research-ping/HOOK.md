# research-ping watcher

Long-lived companion process beside OpenClaw. Watches `/data/research/` and
sends a single warm Telegram nudge to the customer the moment a new research
file lands, so they don't have to message the bot first to discover their
options are ready.

## Why this exists

OpenClaw's Manager only wakes up in response to an incoming message. So on
droplets today, when the admin (or, post-Hermes, the Research Lab agent) drops
a research file on disk, nothing happens until the customer happens to message
again. For the customer-facing flow we need a proactive ping — same experience
a real co-founder would give: "hey, we've got something for you, come look."

This watcher is that ping.

## How it decides who to message

- The Telegram chat_id for this customer is picked up from the
  `snappy-welcome` stamp file (`/opt/bintra/workspace/state/snappy-welcome/`)
  which is written the first time the customer messages the bot. One droplet
  = one customer = one stamp. If the stamp doesn't exist yet, the watcher
  silently skips and retries — it will ping as soon as the customer has
  messaged at least once.
- The research file presence + its `options` array is the trigger signal.
- A one-shot guard stamp at `/opt/bintra/workspace/state/research-ping/<id>.stamp`
  prevents double-pinging if the research file is updated or touched.

## Hard rules (matches snappy-welcome discipline)

- Never log `CUSTOMER_BOT_TOKEN`. Failure log is a single constant marker
  (`research-ping: send failed`) with no detail.
- Fire-and-forget per file. Send failures don't crash the loop.
- Zero dependencies (node:* only). Loads on any clean Node 24 runtime without
  a package graph.

## Deployment

- **Droplet:** installed + started by `install.sh` as the
  `bintra-research-ping.service` systemd unit. EnvironmentFile carries
  `CUSTOMER_BOT_TOKEN` (mode 0600, root-only).
- **Local-dev Docker:** spawned as a background process by `local-dev/start.sh`
  before `exec openclaw gateway`. Uses the same `CUSTOMER_BOT_TOKEN` env var
  already exported for the snappy-welcome hook.
