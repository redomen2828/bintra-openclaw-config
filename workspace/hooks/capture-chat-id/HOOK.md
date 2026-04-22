---
name: capture-chat-id
description: "On every inbound Telegram message, idempotently write the customer's chat_id to /opt/bintra/workspace/state/primary-chat-id so out-of-band watchers (credit-balance-watcher, future dashboards) can send proactive alerts without depending on OpenClaw internals."
metadata:
  {
    "openclaw":
      {
        "emoji": "📌",
        "events": ["message:received"],
        "requires": {},
        "install": [{ "id": "workspace", "kind": "bundled", "label": "Bintra workspace hook" }],
      },
  }
---

# Capture Chat-Id Hook

## Why this exists

Several companion processes need to send proactive Telegram messages to
the customer (credit-balance-watcher alerts them when the LLM is out of
credits; future watchers may notify on long-running builds completing).
None of those live inside OpenClaw's process; they can't introspect
conversation state. We need a stable, on-disk rendezvous point: a single
file containing the customer's Telegram chat_id.

One droplet = one customer = one bot = one primary chat. The chat_id
never changes for a given customer+bot pair, so a single file written
once is sufficient.

## What it does

On `message:received`:

1. Only acts if `channelId === "telegram"`. Other channels have
   different id conventions.
2. Extracts `conversationId` from the hook context. OpenClaw encodes
   Telegram chat ids as `telegram:<numeric_id>`; we strip the prefix
   (and any other non-digit/minus characters) to get the raw id
   Telegram's sendMessage API wants.
3. Writes that raw id to `/opt/bintra/workspace/state/primary-chat-id`
   **only if the file does not already exist**. Idempotent — the
   chat_id never changes for a fixed customer+bot pair, so the first
   write is the only write. No races, no clobbers.
4. Never throws. Any filesystem error is swallowed; the Manager turn
   still runs normally.

## Why Option A (standalone hook) and not folded into snappy-welcome

`snappy-welcome` has a single tight job: fire a sub-2-second placeholder
message before the LLM bootstrap completes. Folding chat_id capture
into it couples two independent concerns and makes `snappy-welcome`'s
one-shot stamp ambiguous (is the stamp gating the placeholder, or the
chat_id write, or both?). A separate hook is clearer, and both run on
the same `message:received` event with negligible overhead.

## Consumer contract

`/opt/bintra/workspace/state/primary-chat-id` contains:
- a single line,
- a single Telegram chat id (integer, possibly negative),
- no trailing newline guaranteed, no leading whitespace,
- mode 0644 (readable by watcher processes running as root).

Consumers (e.g. `watchers/credit-balance-watcher/watcher.sh`) should
treat `stat $path` or `[ -s $path ]` as "we know who to message" and
skip-with-warning when missing.

## Wipe behaviour

`install.sh`'s customer-change wipe removes `workspace/state/` entirely,
so the first inbound from the new customer re-stamps correctly. That
matches the snappy-welcome wipe semantics.
