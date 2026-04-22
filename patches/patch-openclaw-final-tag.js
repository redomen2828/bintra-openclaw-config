// Patches the installed openclaw package so its user-facing sanitizer also
// strips trailing unclosed `<final` / `</final` fragments. The upstream regex
// requires a closing `>`, so a truncated model output like
//   ...Framer, or maybe something else?</
// leaks through untouched and shows up in Telegram.
//
// Idempotent — guarded by a marker comment.
// Fails loudly if the target function signature changes, so upgrades give us
// a clear signal to rebase this patch.

const fs = require("node:fs");
const path = require("node:path");

// openclaw's bundler appends a content hash to each chunk, e.g.
// sanitize-user-facing-text-CMGLMaCD.js. The hash rolls on every upstream
// release, so hard-coding it breaks the patch on every openclaw upgrade.
// Discover the chunk by its stable prefix instead — same approach as
// patch-openclaw-tool-error-warning.js.
const dir = "/usr/lib/node_modules/openclaw/dist";
const marker = "// BINTRA_FINAL_TAG_PATCH_V1";

let entries;
try {
  entries = fs.readdirSync(dir);
} catch (err) {
  console.error(`[patch] cannot list ${dir}: ${err.message}`);
  process.exit(1);
}

const candidates = entries.filter(
  (name) => name.startsWith("sanitize-user-facing-text-") && name.endsWith(".js"),
);

if (candidates.length === 0) {
  console.error(
    "[patch] no sanitize-user-facing-text-*.js found in " +
      dir +
      " — openclaw bundle layout changed. Rebase patches/patch-openclaw-final-tag.js.",
  );
  process.exit(1);
}

if (candidates.length > 1) {
  console.error(
    "[patch] multiple sanitize-user-facing-text-*.js candidates: " +
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
  console.log("[patch] already applied");
  process.exit(0);
}

const needle =
  "function stripFinalTagsFromText(text) {\n" +
  "\tconst normalized = coerceText(text);\n" +
  "\tif (!normalized) return normalized;\n" +
  "\treturn normalized.replace(FINAL_TAG_RE, \"\");\n" +
  "}";

if (!src.includes(needle)) {
  console.error(
    "[patch] stripFinalTagsFromText target not found — openclaw bundle layout changed. " +
      "Rebase patches/patch-openclaw-final-tag.js against the new version.",
  );
  process.exit(1);
}

const replacement =
  "function stripFinalTagsFromText(text) {\n" +
  "\t" + marker + "\n" +
  "\tconst normalized = coerceText(text);\n" +
  "\tif (!normalized) return normalized;\n" +
  "\treturn normalized\n" +
  "\t\t.replace(FINAL_TAG_RE, \"\")\n" +
  "\t\t.replace(/<\\s*\\/?\\s*final\\b[^>]*$/i, \"\")\n" +
  "\t\t.replace(/<\\s*\\/?\\s*$/, \"\")\n" +
  "\t\t.replace(/\\s+$/, \"\");\n" +
  "}";

fs.writeFileSync(target, src.replace(needle, replacement));
console.log("[patch] applied");
