---
name: snappy-welcome
description: "Fire a single <2s placeholder Telegram message on the first inbound of a conversation, before OpenClaw's LLM bootstrap completes, so the customer isn't staring at 5–15s of silence on cold boot."
metadata:
  {
    "openclaw":
      {
        "emoji": "👋",
        "events": ["message:received"],
        "requires": { "env": ["CUSTOMER_BOT_TOKEN"] },
        "install": [{ "id": "workspace", "kind": "bundled", "label": "Bintra workspace hook" }],
      },
  }
---

# Snappy Welcome Hook

## Why this exists

On a fresh droplet, OpenClaw's first-turn agent bootstrap (read SOUL.md, AGENTS.md,
initial LLM call) takes 5–15s. During that window the customer sees silence after
their `/start`. Silence reads as "broken." On every customer we've shipped to so
far this has been the single worst first-impression issue.

This hook sends a **single** Telegram `sendMessage` the moment OpenClaw's channel
layer has received an inbound message, **before** the agent turn runs. Fire-and-
forget, <2s target. If it fails (network blip), the agent turn still runs — the
customer just sees the normal slower first reply.

## What it does

On `message:received`:

1. Extract `conversationId` + `channelId` from the hook context.
2. If `channelId !== "telegram"`, return (nothing to send on other channels).
3. Check for a per-conversation stamp file at
   `/opt/bintra/workspace/state/snappy-welcome/<conversationId>.stamp`.
   If present, return (already fired for this conversation).
4. Atomically create the stamp file (the create-then-check order means duplicate
   first-inbounds within the same millisecond still only fire once).
5. Read `CUSTOMER_BOT_TOKEN` from the process env (already set by the systemd
   unit — never logged, never echoed).
6. POST to `https://api.telegram.org/bot<token>/sendMessage` with the fixed
   placeholder copy and `conversationId` as `chat_id`. 2s abort timeout.
7. On any error: swallow. Never let a hook failure block OpenClaw. Never include
   the URL, token, or response body in any log line — only a short marker like
   `snappy-welcome: send failed`.

## Security

- **Token is never logged.** No `console.log(token)`, no `err.message` that
  could contain the request URL, no stack traces. Errors are caught and flattened
  to a constant marker string.
- **Token is read from `process.env.CUSTOMER_BOT_TOKEN` at call time.** It's not
  cached, not persisted, not written to any file other than the systemd unit and
  `~/.openclaw/openclaw.json` (both already chmod 600, same trust boundary).
- **No outbound logging of message content.** We only write a zero-byte stamp
  file — no payload, no sender, no chat id, no text — just the filename.

## One-shot semantics

The stamp file at
`/opt/bintra/workspace/state/snappy-welcome/<conversationId>.stamp` gates the
hook to exactly one fire per conversation. Repeat `/start`s inside the same
conversation are silent. If the workspace is wiped (new customer onto the same
droplet — see `install.sh` WIPE_STATE block), `workspace/state/` is removed, so
the next customer's first inbound re-fires, which is correct.

## Copy

Exactly this text, per SOUL.md tone — warm, direct, a little dry, no buzzwords,
no cheerleader voice:

```
Hey — good to see you. Your Manager is waking up now, hang tight for a moment.
```

No emoji, no punctuation embellishment, no version. The real agent reply follows
naturally a few seconds later.
