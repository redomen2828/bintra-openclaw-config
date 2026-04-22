# stage-progress watcher

Companion process beside OpenClaw. Watches the shared stamp directory
written by the Hermes builder container and forwards per-stage progress
lines to the customer on Telegram so they see the pipeline unfold in
real time (writer → reviewer → designer → landing → marketing → live).

## Why this exists

Hermes builds run in a sibling container with no Telegram gateway of its
own. Instead of wiring Telegram into the builder, we use a shared host
directory: the builder writes one stamp file per stage it finishes;
this watcher (running inside the OpenClaw Manager container) reads the
stamp and posts its contents to the customer via the Manager's existing
bot token. Same pattern as `research-ping`, generalised per-stage.

## Stamp conventions

- Directory (inside the container): `/opt/bintra/stamps/` — bind-mounted
  from the host at `local-dev-hermes-builder/shared/stamps/` so both
  containers see the same files.
- Filename: `{jobId}.{stage}.stamp` where
  `stage ∈ writing | review | design | landing | marketing | live`.
- File content: one-line human-readable message (e.g. `"✏️ Writer: 12
  templates drafted — next: QA review"`). Messages longer than 400
  chars are truncated before posting.

## Idempotency

On successful Telegram post the watcher writes a sibling `.sent` file
(`{jobId}.{stage}.sent`). Stamps with an existing `.sent` are never
re-posted even if the stamp file is touched. The builder can safely
re-drop a stamp on pipeline restart; the watcher will ignore it.

## Chat-id resolution

Same mechanism as `research-ping`: we read the single `.stamp` file in
`/opt/bintra/workspace/state/snappy-welcome/` (written once, the first
time the customer messages the bot). One droplet = one customer = one
welcome stamp. If the stamp isn't there yet, the watcher silently skips
and retries — it will start sending the moment the customer messages at
least once.

## Hard rules (mirror research-ping)

- Never log `CUSTOMER_BOT_TOKEN`. Failure log is the single constant
  marker `stage-progress: send failed`.
- Fire-and-forget. A Telegram API failure does not crash the loop.
- Zero dependencies (`node:*` only). No package graph to install.
- Graceful shutdown on `SIGTERM` / `SIGINT`.

## Deployment

- **Local-dev Docker:** started as a background process by
  `local-dev/start.sh` alongside `research-ping/watcher.js`, using the
  same `CUSTOMER_BOT_TOKEN` that's already exported.
- **Droplet:** when the swipe-file pipeline graduates beyond the local
  demo, add a `bintra-stage-progress.service` systemd unit mirroring
  `bintra-research-ping.service` (EnvironmentFile with the bot token,
  watchdog restart on failure).
