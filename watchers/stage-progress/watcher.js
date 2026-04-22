#!/usr/bin/env node
/**
 * Bintra stage-progress watcher
 *
 * Companion to OpenClaw Manager. Watches the shared stamp directory
 * written by the Hermes builder container and forwards per-stage progress
 * lines to the customer on Telegram.
 *
 * Stamp filename convention:
 *   {jobId}.{stage}.stamp         — e.g. 8f0c-…-b.writing.stamp
 *   stage ∈ writing | review | design | landing | marketing | live
 * Stamp file content: a single-line human-readable message (≤ 200 chars).
 *
 * Idempotent — once a stamp is sent, a sibling {name}.sent file is written
 * and the stamp is never re-posted even if touched.
 *
 * Hard rules (mirror research-ping):
 *   - NEVER log CUSTOMER_BOT_TOKEN. Failure log is a single constant marker.
 *   - Fire-and-forget per stamp. Telegram errors must not kill the loop.
 *   - Zero dependencies — node:* only.
 *   - Graceful shutdown on SIGTERM.
 *
 * Chat-id resolution mirrors research-ping: we read the snappy-welcome
 * stamp dir to pull the customer's Telegram chat id. One droplet =
 * one customer, so the single stamp file there is always the right target.
 */

import fs from "node:fs";
import path from "node:path";

const STAMP_DIR = "/opt/bintra/stamps";
const WELCOME_STAMP_DIR = "/opt/bintra/workspace/state/snappy-welcome";
const POLL_INTERVAL_MS = 2000;
const TELEGRAM_SEND_TIMEOUT_MS = 5000;
const FAILURE_MARKER = "stage-progress: send failed";

// Valid stage suffixes. Stamps not matching this shape are ignored.
const VALID_STAGES = new Set([
  "writing",
  "review",
  "design",
  "landing",
  "marketing",
  "live",
]);

let shuttingDown = false;

function findChatId() {
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

function parseStampName(filename) {
  // "{jobId}.{stage}.stamp" — jobId is a uuid but we don't enforce shape.
  // Split on the last two dots so jobId can contain dots (defensive).
  if (!filename.endsWith(".stamp")) return null;
  const base = filename.slice(0, -".stamp".length);
  const lastDot = base.lastIndexOf(".");
  if (lastDot < 1) return null;
  const jobId = base.slice(0, lastDot);
  const stage = base.slice(lastDot + 1);
  if (!VALID_STAGES.has(stage)) return null;
  return { jobId, stage };
}

async function sendMessage(botToken, chatId, text) {
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
          text,
          disable_notification: false,
          disable_web_page_preview: false,
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

function listStamps() {
  try {
    return fs
      .readdirSync(STAMP_DIR)
      .filter((f) => f.endsWith(".stamp"))
      .map((f) => path.join(STAMP_DIR, f));
  } catch {
    return [];
  }
}

function sentPathFor(stampPath) {
  return stampPath.replace(/\.stamp$/, ".sent");
}

function markSent(stampPath) {
  try {
    fs.writeFileSync(sentPathFor(stampPath), "");
  } catch {
    /* noop */
  }
}

function alreadySent(stampPath) {
  try {
    return fs.existsSync(sentPathFor(stampPath));
  } catch {
    return false;
  }
}

async function tick() {
  const botToken = process.env.CUSTOMER_BOT_TOKEN;
  if (!botToken) return;

  const stamps = listStamps();
  if (stamps.length === 0) return;

  const chatId = findChatId();
  if (!chatId) return; // customer hasn't messaged yet — silent skip

  for (const stampPath of stamps) {
    if (alreadySent(stampPath)) continue;
    const parsed = parseStampName(path.basename(stampPath));
    if (!parsed) continue;

    let message = "";
    try {
      message = fs.readFileSync(stampPath, "utf8").trim();
    } catch {
      continue;
    }
    if (!message) continue;

    // Cap runaway payloads so a buggy upstream can't spam-bomb.
    if (message.length > 400) message = message.slice(0, 400);

    const ok = await sendMessage(botToken, chatId, message);
    if (ok) {
      markSent(stampPath);
      console.log(`stage-progress: sent ${parsed.stage} for ${parsed.jobId}`);
    }
  }
}

async function main() {
  console.log(
    `stage-progress: watching ${STAMP_DIR} (poll ${POLL_INTERVAL_MS}ms)`,
  );
  try {
    fs.mkdirSync(STAMP_DIR, { recursive: true });
  } catch {
    /* noop */
  }

  const onStop = (sig) => {
    console.log(`stage-progress: received ${sig}, shutting down`);
    shuttingDown = true;
  };
  process.on("SIGTERM", () => onStop("SIGTERM"));
  process.on("SIGINT", () => onStop("SIGINT"));

  while (!shuttingDown) {
    try {
      await tick();
    } catch {
      console.warn(FAILURE_MARKER);
    }
    await new Promise((r) => setTimeout(r, POLL_INTERVAL_MS));
  }
  console.log("stage-progress: exited cleanly");
}

main().catch(() => {
  console.warn(FAILURE_MARKER);
  process.exit(1);
});
