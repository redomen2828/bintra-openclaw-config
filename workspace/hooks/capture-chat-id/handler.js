/**
 * Bintra capture-chat-id hook — on the first inbound Telegram message
 * per customer, write the raw numeric chat_id to
 *   /opt/bintra/workspace/state/primary-chat-id
 *
 * This file is the rendezvous point for out-of-band companion processes
 * (credit-balance-watcher, future alerters) that need to send proactive
 * Telegram messages without reaching into OpenClaw internals.
 *
 * Hard rules:
 *  - Idempotent. We only write if the file does not already exist. The
 *    chat_id never changes for a fixed customer+bot pair, so the first
 *    write is the only write.
 *  - Never throws. All errors swallowed. Hook runner already catches,
 *    but we're defensive anyway — a crash here must never block the
 *    Manager turn.
 *  - No dependencies beyond node:* so this loads cleanly in the
 *    OpenClaw process.
 *  - No logging of message content, user identity, or anything other
 *    than a constant success/failure marker.
 */

import fs from "node:fs";
import path from "node:path";

const STATE_DIR = "/opt/bintra/workspace/state";
const CHAT_ID_FILE = path.join(STATE_DIR, "primary-chat-id");
const FAILURE_MARKER = "capture-chat-id: write failed";

/**
 * OpenClaw encodes Telegram conversation ids as `telegram:<numeric_id>`
 * (sometimes sanitized elsewhere to `telegram_<numeric_id>`). Telegram's
 * sendMessage API needs the raw integer. Pull the trailing signed
 * integer out of whatever form arrives.
 *
 * Accepts: `telegram:123`, `telegram_123`, `telegram:-100123`, `123`.
 * Rejects: empty / non-matching strings.
 */
function extractChatId(conversationId) {
	if (!conversationId || typeof conversationId !== "string") return null;
	const match = conversationId.match(/(-?\d+)$/);
	return match ? match[1] : null;
}

export default async function onMessageReceived(event) {
	try {
		if (!event || event.type !== "message" || event.action !== "received") {
			return;
		}
		const ctx = event.context;
		if (!ctx || typeof ctx !== "object") return;
		if (ctx.channelId !== "telegram") return;

		// Fast path: file already exists, nothing to do. This is the hot
		// case on every inbound after the first.
		try {
			if (fs.existsSync(CHAT_ID_FILE)) return;
		} catch {
			/* fall through */
		}

		const chatId = extractChatId(ctx.conversationId);
		if (!chatId) return;

		try {
			fs.mkdirSync(STATE_DIR, { recursive: true });
		} catch {
			console.warn(FAILURE_MARKER);
			return;
		}

		// "wx" flag: fail if file exists. Wins the race if two inbounds
		// land in the same millisecond — first write wins, second throws
		// EEXIST which we swallow.
		try {
			const fd = fs.openSync(CHAT_ID_FILE, "wx");
			fs.writeSync(fd, chatId);
			fs.closeSync(fd);
		} catch (err) {
			// EEXIST = someone else won the race; that's fine. Any other
			// errno = real filesystem problem; log the marker and move on.
			if (err && err.code !== "EEXIST") {
				console.warn(FAILURE_MARKER);
			}
		}
	} catch {
		console.warn(FAILURE_MARKER);
	}
}
