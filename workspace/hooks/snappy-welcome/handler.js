/**
 * Bintra snappy-welcome hook — fires a single <2s placeholder Telegram message
 * on the first inbound per conversation, before OpenClaw's LLM bootstrap runs.
 *
 * Event: message:received
 *
 * Hard rules:
 *  - NEVER log CUSTOMER_BOT_TOKEN. Not in console.log, not in thrown errors, not
 *    in request URLs written to any log. On failure we emit a short constant
 *    marker ("snappy-welcome: send failed") and nothing else.
 *  - Fire-and-forget. Any throw from this handler must not block the agent run.
 *    The caller (openclaw hook runtime) already catches errors, but we also
 *    catch locally so we control the log line.
 *  - One-shot per conversation. Gated by a zero-byte stamp file.
 *
 * Keep this file dependency-free (pure node:*) so it loads inside the OpenClaw
 * process without touching the package graph.
 */

import fs from "node:fs";
import path from "node:path";

// Intentionally phrased WITHOUT a greeting ("Hey", "Hi"). The Manager's first
// real reply opens with "Hey <name>", so prefacing with another greeting here
// produces a double-"Hey" sequence that reads robotic. Keep this line as a
// plain loading notification.
const PLACEHOLDER_TEXT = "just a moment while I load your setup…";

// /opt/bintra/workspace is the workspace root on droplets. We deliberately
// hard-code this rather than reading it off the event, because the workspaceDir
// is only reliably present on agent:bootstrap events, not on message:received.
// Same root as AGENTS.md references.
const STAMP_DIR = "/opt/bintra/workspace/state/snappy-welcome";

const TELEGRAM_SEND_TIMEOUT_MS = 2000;
const FAILURE_MARKER = "snappy-welcome: send failed";

/**
 * Atomic "has this conversation already fired?" check.
 *
 * We use `fs.openSync(path, "wx")` which fails with EEXIST if the file is
 * already there. If the create succeeds, we own the first fire for this
 * conversation. No race, no double-message.
 *
 * Returns true when we should proceed to send, false when already stamped.
 */
function claimFirstFire(conversationId) {
	try {
		fs.mkdirSync(STAMP_DIR, { recursive: true });
	} catch {
		// Can't create the stamp dir — fail closed (don't send), because without
		// the stamp we'd spam every inbound.
		return false;
	}

	// Sanitize: conversation ids are telegram chat ids (numeric). Keep only a
	// conservative charset so a malformed id can never escape the stamp dir.
	const safe = String(conversationId).replace(/[^A-Za-z0-9_-]/g, "_");
	if (!safe) return false;

	const stampPath = path.join(STAMP_DIR, `${safe}.stamp`);
	try {
		const fd = fs.openSync(stampPath, "wx");
		fs.closeSync(fd);
		return true;
	} catch (err) {
		// EEXIST = already fired. Anything else = filesystem problem; fail closed.
		return false;
	}
}

/**
 * POST to Telegram sendMessage. Wrapped in try/catch + AbortController.
 * Never throws. Never logs the token or full URL on failure.
 */
async function sendPlaceholder(botToken, chatId) {
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
					text: PLACEHOLDER_TEXT,
					disable_notification: false,
				}),
				signal: controller.signal,
			},
		);
		if (!res.ok) {
			// Deliberately no body read — response bodies can echo request params
			// including URL-shaped hints. Status code is safe on its own.
			console.warn(`${FAILURE_MARKER} (http ${res.status})`);
		}
	} catch {
		// err may be an AbortError, DNS error, TLS error. Any of their .message
		// fields can contain the hostname, which is fine — but we stay paranoid
		// and emit only the marker, never the error object.
		console.warn(FAILURE_MARKER);
	} finally {
		clearTimeout(timer);
	}
}

/**
 * Hook entrypoint. Signature matches OpenClaw's InternalHookHandler:
 *   (event: InternalHookEvent) => Promise<void>
 *
 * event.type === "message", event.action === "received"
 * event.context: { channelId, conversationId, from, content, ... }
 */
export default async function onMessageReceived(event) {
	try {
		if (!event || event.type !== "message" || event.action !== "received") {
			return;
		}
		const ctx = event.context;
		if (!ctx || typeof ctx !== "object") return;

		// Only Telegram. Other channels (e.g. discord) have their own latency
		// profile and their own chat_id conventions.
		if (ctx.channelId !== "telegram") return;

		const conversationId = ctx.conversationId;
		if (!conversationId || typeof conversationId !== "string") return;

		const botToken = process.env.CUSTOMER_BOT_TOKEN;
		if (!botToken) {
			// Don't log the missing-token as an error with any detail — just bail.
			// The agent will still run and reply the normal way.
			return;
		}

		if (!claimFirstFire(conversationId)) return;

		// Fire-and-forget. We deliberately do NOT await this from the caller's
		// perspective — but since the hook runner awaits the returned promise,
		// we still want the Telegram call to finish (or time out) before we
		// return, so that if something is misconfigured we at least see the
		// single marker log line. The 2s timeout guarantees we never stall the
		// agent turn.
		await sendPlaceholder(botToken, conversationId);
	} catch {
		// Absolute last-resort swallow. The hook runner already catches, but we
		// want to guarantee we never surface the token or URL through an
		// unhandled exception path.
		console.warn(FAILURE_MARKER);
	}
}
