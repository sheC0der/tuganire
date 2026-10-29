import "dotenv/config";
import express from "express";
import { LEVELS, SCENARIOS, buildSystemPrompt, buildTranscript } from "./prompt.js";

const API_KEY = process.env.ANTHROPIC_API_KEY;
const MODEL = process.env.CLAUDE_MODEL || "claude-sonnet-5-5";
const PORT = Number(process.env.PORT || 8787);
const APP_TOKEN = process.env.APP_TOKEN || "";
const MAX_TURNS = 40; // only the most recent turns are sent, to keep cost and latency down

if (!API_KEY) {
  console.error("Missing ANTHROPIC_API_KEY. Copy .env.example to .env and add your key.");
  process.exit(1);
}

const app = express();
app.use(express.json({ limit: "64kb" }));

app.get("/health", (_req, res) => res.json({ ok: true, model: MODEL }));

app.post("/chat", async (req, res) => {
  if (APP_TOKEN && req.get("x-app-token") !== APP_TOKEN) {
    return res.status(401).json({ error: "unauthorized" });
  }

  const { level, scenarioId, history } = req.body ?? {};
  // Object.hasOwn so keys like "constructor" or "__proto__" don't pass as valid ids.
  if (!Object.hasOwn(LEVELS, level) || !Object.hasOwn(SCENARIOS, scenarioId) || !Array.isArray(history)) {
    return res.status(400).json({ error: "bad_request" });
  }

  const cleanHistory = history
    .filter((h) => h && (h.role === "tutor" || h.role === "learner") && typeof h.text === "string")
    .map((h) => ({ role: h.role, text: h.text.slice(0, 1000) }))
    .slice(-MAX_TURNS);

  try {
    const apiRes = await fetch("https://api.anthropic.com/v1/messages", {
      method: "POST",
      headers: {
        "content-type": "application/json",
        "x-api-key": API_KEY,
        "anthropic-version": "2023-06-01",
      },
      body: JSON.stringify({
        model: MODEL,
        // Current Claude models think before answering and those tokens count against
        // max_tokens, so leave plenty of room or the JSON reply gets cut off.
        max_tokens: 16000,
        // Low effort keeps replies quick, which suits a back-and-forth conversation.
        output_config: { effort: "low" },
        system: buildSystemPrompt(level, scenarioId),
        messages: [{ role: "user", content: buildTranscript(cleanHistory) }],
      }),
    });

    if (!apiRes.ok) {
      const detail = await apiRes.text();
      console.error("Claude API error", apiRes.status, detail);
      const code = apiRes.status === 429 ? "rate_limited" : "upstream_error";
      return res.status(502).json({ error: code });
    }

    const data = await apiRes.json();
    if (data.stop_reason === "refusal") {
      console.error("Claude declined to reply", data.stop_details);
      return res.status(502).json({ error: "refused" });
    }
    const text = (data.content || [])
      .filter((b) => b.type === "text")
      .map((b) => b.text)
      .join("")
      .replace(/```json|```/g, "")
      .trim();

    const reply = parseReply(text);
    if (!reply) {
      console.error("Could not parse tutor reply (stop_reason %s):", data.stop_reason, text);
      return res.status(502).json({ error: "bad_reply" });
    }
    return res.json(reply);
  } catch (err) {
    console.error(err);
    return res.status(500).json({ error: "server_error" });
  }
});

function parseReply(text) {
  // Claude sometimes adds a sentence before the JSON, so grab the outermost object.
  const start = text.indexOf("{");
  const end = text.lastIndexOf("}");
  if (start === -1 || end === -1) return null;
  try {
    const j = JSON.parse(text.slice(start, end + 1));
    if (typeof j.reply_rw !== "string" || !j.reply_rw.trim()) return null;
    return {
      reply_rw: j.reply_rw.trim(),
      reply_en: String(j.reply_en ?? "").trim(),
      feedback: String(j.feedback ?? "").trim(),
      corrected: String(j.corrected ?? "").trim(),
      was_correct: j.was_correct === true,
      suggestions: Array.isArray(j.suggestions)
        ? j.suggestions
            .filter((s) => s && typeof s.rw === "string")
            .slice(0, 3)
            .map((s) => ({ rw: s.rw.trim(), en: String(s.en ?? "").trim() }))
        : [],
    };
  } catch {
    return null;
  }
}

app.listen(PORT, "0.0.0.0", () => {
  console.log(`Tuganire backend listening on http://0.0.0.0:${PORT} using ${MODEL}`);
});
