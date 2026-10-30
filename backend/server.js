import "dotenv/config";
import path from "node:path";
import { fileURLToPath } from "node:url";

import { createApp } from "./app.js";
import { parseAllowedEmails, supabaseTokenVerifier } from "./auth.js";
import { cachedSynthesizer, ttsServiceClient } from "./tts.js";
import { requestTutorTurn } from "./tutor.js";

const REQUIRED = ["ANTHROPIC_API_KEY", "SUPABASE_URL", "SUPABASE_PUBLISHABLE_KEY", "ALLOWED_EMAILS"];
const missing = REQUIRED.filter((name) => !process.env[name]?.trim());
if (missing.length) {
  console.error(
    `Missing ${missing.join(", ")}. Locally, copy .env.example to .env and fill it in; on Railway, set them as service variables.`,
  );
  process.exit(1);
}

const API_KEY = process.env.ANTHROPIC_API_KEY;
const MODEL = process.env.CLAUDE_MODEL || "claude-sonnet-5-5";
const PORT = Number(process.env.PORT || 8787); // Railway sets PORT
const allowedEmails = parseAllowedEmails(process.env.ALLOWED_EMAILS);
if (!allowedEmails.size) {
  console.error("ALLOWED_EMAILS has no email addresses in it. Use a comma-separated list.");
  process.exit(1);
}

// Kinyarwanda read aloud is optional: without a TTS service the app uses the device's voice.
const TTS_URL = process.env.TTS_URL?.trim();
const TTS_SHARED_SECRET = process.env.TTS_SHARED_SECRET?.trim();
if (Boolean(TTS_URL) !== Boolean(TTS_SHARED_SECRET)) {
  console.error("Set both TTS_URL and TTS_SHARED_SECRET, or neither.");
  process.exit(1);
}
const TTS_CACHE_MB = Number(process.env.TTS_CACHE_MB || 50);
const synthesizeSpeech =
  TTS_URL &&
  cachedSynthesizer(ttsServiceClient({ url: TTS_URL, secret: TTS_SHARED_SECRET }), {
    maxBytes: TTS_CACHE_MB * 1024 * 1024,
  });

const here = path.dirname(fileURLToPath(import.meta.url));

const app = createApp({
  model: MODEL,
  allowedEmails,
  verifyUser: supabaseTokenVerifier({
    url: process.env.SUPABASE_URL,
    publishableKey: process.env.SUPABASE_PUBLISHABLE_KEY,
  }),
  nextTurn: ({ level, scenarioId, history }) =>
    requestTutorTurn({ apiKey: API_KEY, model: MODEL, level, scenarioId, history }),
  synthesizeSpeech,
  // The Docker image copies the Flutter web build here. Locally, point WEB_DIR at
  // ../build/web after `flutter build web`, or leave it and use `flutter run -d chrome`.
  webDir: path.resolve(here, process.env.WEB_DIR || "public"),
  dev: process.env.NODE_ENV !== "production",
});

app.listen(PORT, () => {
  console.log(`Tuganire backend listening on port ${PORT} using ${MODEL}`);
  console.log(TTS_URL ? `Kinyarwanda read aloud via ${TTS_URL}` : "No TTS_URL: the app will use device voices.");
});
