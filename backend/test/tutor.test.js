import assert from "node:assert/strict";
import { test } from "node:test";

import { parseAllowedEmails, supabaseTokenVerifier, AuthUnavailableError } from "../auth.js";
import { parseReply, requestTutorTurn, TutorError } from "../tutor.js";

test("parseReply reads JSON with a sentence before it", () => {
  const reply = parseReply(
    'Here you go: {"reply_rw":" Muraho ","reply_en":"Hello","was_correct":true,' +
      '"suggestions":[{"rw":"Yego","en":"Yes"},{"en":"no rw"},{"rw":"A"},{"rw":"B"},{"rw":"C"}]}',
  );
  assert.equal(reply.reply_rw, "Muraho");
  assert.equal(reply.was_correct, true);
  assert.equal(reply.feedback, "");
  assert.deepEqual(reply.suggestions.map((s) => s.rw), ["Yego", "A", "B"]);
});

test("parseReply rejects missing or empty replies", () => {
  assert.equal(parseReply("no json here"), null);
  assert.equal(parseReply('{"reply_rw":"  "}'), null);
  assert.equal(parseReply("{broken"), null);
});

const claudeResponse = (body, status = 200) => async () =>
  new Response(JSON.stringify(body), { status, headers: { "content-type": "application/json" } });

const turn = (fetchImpl) =>
  requestTutorTurn({ apiKey: "k", model: "m", level: "beginner", scenarioId: "greet", history: [], fetchImpl });

test("requestTutorTurn parses the text blocks and skips thinking", async () => {
  const reply = await turn(
    claudeResponse({
      stop_reason: "end_turn",
      content: [
        { type: "thinking", thinking: "" },
        { type: "text", text: '```json\n{"reply_rw":"Muraho","reply_en":"Hello"}\n```' },
      ],
    }),
  );
  assert.equal(reply.reply_rw, "Muraho");
});

test("requestTutorTurn maps failures to error codes", async () => {
  const code = (p) => p.then(() => null, (e) => (assert.ok(e instanceof TutorError), e.code));
  assert.equal(await code(turn(claudeResponse({ error: {} }, 429))), "rate_limited");
  assert.equal(await code(turn(claudeResponse({ error: {} }, 500))), "upstream_error");
  assert.equal(await code(turn(claudeResponse({ stop_reason: "refusal", content: [] }))), "refused");
  assert.equal(await code(turn(claudeResponse({ stop_reason: "max_tokens", content: [] }))), "bad_reply");
});

test("parseAllowedEmails trims, lowercases and drops blanks", () => {
  assert.deepEqual([...parseAllowedEmails(" A@x.com, ,b@Y.com,")], ["a@x.com", "b@y.com"]);
  assert.equal(parseAllowedEmails(undefined).size, 0);
});

test("supabaseTokenVerifier asks Supabase who the token belongs to", async () => {
  let seen;
  const verify = supabaseTokenVerifier({
    url: "https://ref.supabase.co",
    publishableKey: "pk",
    fetchImpl: async (url, init) => {
      seen = { url: String(url), headers: init.headers };
      return new Response(JSON.stringify({ id: "u1", email: "a@x.com" }), { status: 200 });
    },
  });
  assert.deepEqual(await verify("tok"), { id: "u1", email: "a@x.com" });
  assert.equal(seen.url, "https://ref.supabase.co/auth/v1/user");
  assert.equal(seen.headers.apikey, "pk");
  assert.equal(seen.headers.authorization, "Bearer tok");
});

test("supabaseTokenVerifier: invalid token -> null, outage -> AuthUnavailableError", async () => {
  const withStatus = (status) =>
    supabaseTokenVerifier({ url: "https://ref.supabase.co", publishableKey: "pk", fetchImpl: async () => new Response("{}", { status }) });
  assert.equal(await withStatus(401)("t"), null);
  assert.equal(await withStatus(403)("t"), null);
  await assert.rejects(withStatus(500)("t"), AuthUnavailableError);
  const offline = supabaseTokenVerifier({
    url: "https://ref.supabase.co",
    publishableKey: "pk",
    fetchImpl: async () => {
      throw new TypeError("fetch failed");
    },
  });
  await assert.rejects(offline("t"), AuthUnavailableError);
});
