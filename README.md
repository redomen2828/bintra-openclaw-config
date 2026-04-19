# bintra-openclaw-config

Per-customer OpenClaw configuration for Bintra's Manager agent.

## What this repo is

A template that gets cloned onto each customer's VPS at provisioning time. It contains:

- `workspace/` — the Manager agent's home (AGENTS.md, SOUL.md, skills/)
- `openclaw.json.template` — OpenClaw config with `{{PLACEHOLDER}}` values
- `research_results.template.json` — shape the Research Lab fills in
- `install.sh` — Ubuntu 24.04 installer, substitutes env vars and starts a systemd service

## How to provision a new customer (manual, for now)

1. Spin up a fresh Ubuntu 24.04 droplet.
2. SSH in as root.
3. Export the five required env vars (see `install.sh` header).
4. `curl -fsSL https://raw.githubusercontent.com/redomen2828/bintra-openclaw-config/main/install.sh | bash`
5. Ping the bot on Telegram — the Manager should respond.

The Bintra portal will automate this via `scripts/provision-customer.ts` (Phase 9).

## Research delivery

When the human research team finishes a brief, drop the filled-in JSON at:

```
/data/research/<CUSTOMER_ID>.json
```

The Manager checks this path at the start of every session.
