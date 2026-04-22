#!/usr/bin/env node
/**
 * Bintra research-ping watcher
 *
 * Long-lived companion process beside OpenClaw. Watches the research drop
 * directory and sends a proactive Telegram nudge to the customer when a new
 * research file lands on disk.
 *
 * Hard rules (mirror snappy-welcome hook):
 *  - NEVER log CUSTOMER_BOT_TOKEN. Not in console, not in errors, not in URLs.
 *    On failure emit only the constant FAILURE_MARKER.
 *  - Once-per-research-file. Gated by a zero-byte stamp file. Double-ping is
 *    worse than a silent miss.
 *  - Fire-and-forget. An API failure must not crash the watcher loop.
 *  - If the customer has not yet messaged (no snappy-welcome stamp = no known
 *    chat_id), skip this cycle silently and retry next tick.
 *
 * Zero dependencies — node:* only, so this loads on any clean Node 24 runtime
 * without a package graph.
 */

import fs from "node:fs";
import path from "node:path";

const RESEARCH_DIR = "/data/research";
const WELCOME_STAMP_DIR = "/opt/bintra/workspace/state/snappy-welcome";
const PING_STAMP_DIR = "/opt/bintra/workspace/state/research-ping";
const POLL_INTERVAL_MS = 5000;
const TELEGRAM_SEND_TIMEOUT_MS = 5000;
const FAILURE_MARKER = "research-ping: send failed";

const PING_TEXT =
  "quick update — the research team just came back with three product options for you. want me to walk you through them?";

function findChatId() {
  // snappy-welcome writes stamp files named after the sanitized OpenClaw
  // conversationId, which for Telegram looks like `telegram_<numeric_id>` (the
  // colon in `telegram:NNN` gets sanitized to `_`). Telegram's sendMessage
  // API needs the raw numeric id, so we pull the trailing integer out.
  try {
    const files = fs
      .readdirSync(WELCOME_STAMP_DIR)
      .filter((f) => f.endsWith(".stamp"));
    if (files.length === 0) return null;
    const base = files[0].replace(/\.stamp$/, "");
    const match = base.match(/(-?\d+)$/);
    return match ? match[1] : null;
  } catch {
    return null;
  }
}

function stampPathFor(customerId) {
  const safe = String(customerId).replace(/[^A-Za-z0-9_.-]/g, "_");
  return path.join(PING_STAMP_DIR, `${safe}.stamp`);
}

function alreadyPinged(customerId) {
  return fs.existsSync(stampPathFor(customerId));
}

function markPinged(customerId) {
  try {
    fs.mkdirSync(PING_STAMP_DIR, { recursive: true });
    fs.writeFileSync(stampPathFor(customerId), "");
  } catch {
    /* noop */
  }
}

async function sendPing(botToken, chatId) {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), TELEGRAM_SEND_TIMEOUT_MS);
  try {
    const res = await fetch(
      `https://api.telegram.org/bot${botToken}/sendMessage`,
      {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({
          chat_id: chatId,
          text: PING_TEXT,
          disable_notification: false,
        }),
        signal: controller.signal,
      },
    );
    if (!res.ok) {
      console.warn(`${FAILURE_MARKER} (http ${res.status})`);
      return false;
    }
    return true;
  } catch {
    console.warn(FAILURE_MARKER);
    return false;
  } finally {
    clearTimeout(timer);
  }
}

function listResearchFiles() {
  try {
    return fs
      .readdirSync(RESEARCH_DIR)
      .filter((f) => f.endsWith(".json"))
      .map((f) => path.join(RESEARCH_DIR, f));
  } catch {
    return [];
  }
}

async function tick() {
  const botToken = process.env.CUSTOMER_BOT_TOKEN;
  if (!botToken) return;

  const files = listResearchFiles();
  if (files.length === 0) return;

  for (const filePath of files) {
    const customerId = path.basename(filePath, ".json");
    if (alreadyPinged(customerId)) continue;

    const chatId = findChatId();
    if (!chatId) continue;

    try {
      const raw = fs.readFileSync(filePath, "utf8");
      const json = JSON.parse(raw);
      if (!Array.isArray(json.options) || json.options.length === 0) continue;
    } catch {
      continue;
    }

    const ok = await sendPing(botToken, chatId);
    if (ok) {
      markPinged(customerId);
      console.log(`research-ping: sent for ${customerId}`);
    }
  }
}

async function main() {
  console.log(
    `research-ping: watching ${RESEARCH_DIR} (poll ${POLL_INTERVAL_MS}ms)`,
  );
  try {
    fs.mkdirSync(PING_STAMP_DIR, { recursive: true });
  } catch {
    /* noop */
  }
  while (true) {
    try {
      await tick();
    } catch {
      console.warn(FAILURE_MARKER);
    }
    await new Promise((r) => setTimeout(r, POLL_INTERVAL_MS));
  }
}

main().catch(() => {
  console.warn(FAILURE_MARKER);
  process.exit(1);
});
