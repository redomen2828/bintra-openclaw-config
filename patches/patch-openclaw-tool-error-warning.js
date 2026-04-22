// Patches the installed openclaw package so `messages.suppressToolErrors: true`
// in openclaw.json actually suppresses tool-error warnings for MUTATING tools
// (Edit, Write, etc.) — not just exec-like ones.
//
// Upstream `resolveToolErrorWarningPolicy` checks `mutatingAction` BEFORE
// `suppressToolErrors`, so a failed Edit still emits
//   ⚠️ 📝 Edit: in /opt/bintra/workspace/IDENTITY.md failed
// to the customer's Telegram thread even when we've asked it to stay quiet.
// We reorder the checks so `suppressToolErrors` wins for mutating tools too.
//
// Idempotent — guarded by a marker comment.
// Fails loudly if the target function signature changes, so upgrades give us
// a clear signal to rebase this patch.

const fs = require("node:fs");
const path = require("node:path");

const dir = "/usr/lib/node_modules/openclaw/dist";
const marker = "// BINTRA_TOOL_ERROR_WARNING_PATCH_V1";

let entries;
try {
  entries = fs.readdirSync(dir);
} catch (err) {
  console.error(`[patch] cannot list ${dir}: ${err.message}`);
  process.exit(1);
}

const candidates = entries.filter(
  (name) => name.startsWith("pi-embedded-runner-") && name.endsWith(".js"),
);

if (candidates.length === 0) {
  console.error(
    "[patch] no pi-embedded-runner-*.js found in " +
      dir +
      " — openclaw bundle layout changed. Rebase patches/patch-openclaw-tool-error-warning.js.",
  );
  process.exit(1);
}

if (candidates.length > 1) {
  console.error(
    "[patch] multiple pi-embedded-runner-*.js candidates: " +
      candidates.join(", ") +
      ". Refusing to guess.",
  );
  process.exit(1);
}

const target = path.join(dir, candidates[0]);

let src;
try {
  src = fs.readFileSync(target, "utf8");
} catch (err) {
  console.error(`[patch] cannot read ${target}: ${err.message}`);
  process.exit(1);
}

if (src.includes(marker)) {
  console.log("[patch] tool-error-warning already applied to " + candidates[0]);
  process.exit(0);
}

const needle =
  "function resolveToolErrorWarningPolicy(params) {\n" +
  "\tconst normalizedToolName = normalizeOptionalLowercaseString(params.lastToolError.toolName) ?? \"\";\n" +
  "\tconst includeDetails = shouldIncludeToolErrorDetails(params);\n" +
  "\tif (params.suppressToolErrorWarnings) return {\n" +
  "\t\tshowWarning: false,\n" +
  "\t\tincludeDetails\n" +
  "\t};\n" +
  "\tif (isExecLikeToolName(params.lastToolError.toolName) && !includeDetails) return {\n" +
  "\t\tshowWarning: false,\n" +
  "\t\tincludeDetails\n" +
  "\t};\n" +
  "\tif (normalizedToolName === \"sessions_send\") return {\n" +
  "\t\tshowWarning: false,\n" +
  "\t\tincludeDetails\n" +
  "\t};\n" +
  "\tif (params.lastToolError.mutatingAction ?? isLikelyMutatingToolName(params.lastToolError.toolName)) return {\n" +
  "\t\tshowWarning: true,\n" +
  "\t\tincludeDetails\n" +
  "\t};\n" +
  "\tif (params.suppressToolErrors) return {\n" +
  "\t\tshowWarning: false,\n" +
  "\t\tincludeDetails\n" +
  "\t};\n" +
  "\treturn {\n" +
  "\t\tshowWarning: !params.hasUserFacingReply && !isRecoverableToolError(params.lastToolError.error),\n" +
  "\t\tincludeDetails\n" +
  "\t};\n" +
  "}";

if (!src.includes(needle)) {
  console.error(
    "[patch] resolveToolErrorWarningPolicy target not found in " +
      candidates[0] +
      " — openclaw bundle layout changed. " +
      "Rebase patches/patch-openclaw-tool-error-warning.js against the new version.",
  );
  process.exit(1);
}

const replacement =
  "function resolveToolErrorWarningPolicy(params) {\n" +
  "\t" + marker + "\n" +
  "\tconst normalizedToolName = normalizeOptionalLowercaseString(params.lastToolError.toolName) ?? \"\";\n" +
  "\tconst includeDetails = shouldIncludeToolErrorDetails(params);\n" +
  "\tif (params.suppressToolErrorWarnings) return {\n" +
  "\t\tshowWarning: false,\n" +
  "\t\tincludeDetails\n" +
  "\t};\n" +
  "\tif (params.suppressToolErrors) return {\n" +
  "\t\tshowWarning: false,\n" +
  "\t\tincludeDetails\n" +
  "\t};\n" +
  "\tif (isExecLikeToolName(params.lastToolError.toolName) && !includeDetails) return {\n" +
  "\t\tshowWarning: false,\n" +
  "\t\tincludeDetails\n" +
  "\t};\n" +
  "\tif (normalizedToolName === \"sessions_send\") return {\n" +
  "\t\tshowWarning: false,\n" +
  "\t\tincludeDetails\n" +
  "\t};\n" +
  "\tif (params.lastToolError.mutatingAction ?? isLikelyMutatingToolName(params.lastToolError.toolName)) return {\n" +
  "\t\tshowWarning: true,\n" +
  "\t\tincludeDetails\n" +
  "\t};\n" +
  "\treturn {\n" +
  "\t\tshowWarning: !params.hasUserFacingReply && !isRecoverableToolError(params.lastToolError.error),\n" +
  "\t\tincludeDetails\n" +
  "\t};\n" +
  "}";

fs.writeFileSync(target, src.replace(needle, replacement));
console.log("[patch] tool-error-warning applied to " + candidates[0]);
