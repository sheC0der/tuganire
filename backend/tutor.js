// The one place that talks to Claude and turns its answer into a tutor reply.
import { buildSystemPrompt, buildTranscript } from "./prompt.js";

const MAX_TURNS = 40; // only the most recent turns are sent, to keep cost and latency down

/** A failed tutor turn. `code` is sent to the app as { error: code }. */
export class TutorError extends Error {
  constructor(code, detail) {
    super(detail ? `${code}: ${detail}` : code);
    this.code = code;
  }
}

export function cleanHistory(history) {
  return history
    .filter((h) => h && (h.role === "tutor" || h.role === "learner") && typeof h.text === "string")
    .map((h) => ({ role: h.role, text: h.text.slice(0, 1000) }))
    .slice(-MAX_TURNS);
}

/** Asks Claude for the tutor's next turn. Throws TutorError on failure. */
export async function requestTutorTurn({ apiKey, model, level, scenarioId, history, fetchImpl = fetch }) {
  const apiRes = await fetchImpl("https://api.anthropic.com/v1/messages", {
    method: "POST",
    headers: {
      "content-type": "application/json",
      "x-api-key": apiKey,
      "anthropic-version": "2023-06-01",
    },
    body: JSON.stringify({
      model,
      // Current Claude models think before answering and those tokens count against
      // max_tokens, so leave plenty of room or the JSON reply gets cut off.
      max_tokens: 16000,
      // Low effort keeps replies quick, which suits a back-and-forth conversation.
      output_config: { effort: "low" },
      system: buildSystemPrompt(level, scenarioId),
      messages: [{ role: "user", content: buildTranscript(cleanHistory(history)) }],
    }),
  });

  if (!apiRes.ok) {
    const detail = await apiRes.text();
    throw new TutorError(apiRes.status === 429 ? "rate_limited" : "upstream_error", `${apiRes.status} ${detail}`);
  }

  const data = await apiRes.json();
  if (data.stop_reason === "refusal") {
    throw new TutorError("refused", JSON.stringify(data.stop_details));
  }

  const text = (data.content || [])
    .filter((b) => b.type === "text")
    .map((b) => b.text)
    .join("")
    .replace(/```json|```/g, "")
    .trim();

  const reply = parseReply(text);
  if (!reply) {
    throw new TutorError("bad_reply", `stop_reason ${data.stop_reason}: ${text}`);
  }
  return reply;
}

export function parseReply(text) {
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
