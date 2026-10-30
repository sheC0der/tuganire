import assert from "node:assert/strict";
import { after, before, describe, test } from "node:test";

import { createApp } from "../app.js";
import { parseAllowedEmails } from "../auth.js";
import { MAX_TTS_CHARS, TtsError, cachedSynthesizer, ttsServiceClient } from "../tts.js";

const users = {
  "good-token": { id: "1", email: "learner@example.com" },
  "other-token": { id: "2", email: "stranger@example.com" },
};

function start(synthesizeSpeech) {
  const app = createApp({
    model: "test-model",
    allowedEmails: parseAllowedEmails("learner@example.com"),
    verifyUser: async (token) => users[token] ?? null,
    nextTurn: async () => ({}),
    synthesizeSpeech,
  });
  return new Promise((resolve) => {
    const server = app.listen(0, () => resolve({ server, base: `http://127.0.0.1:${server.address().port}` }));
  });
}

const tts = (base, text, token = "good-token") =>
  fetch(`${base}/api/tts`, {
    method: "POST",
    headers: { "content-type": "application/json", ...(token && { authorization: `Bearer ${token}` }) },
    body: JSON.stringify({ text }),
  });

describe("/api/tts", () => {
  let server, base;
  let synthesize;

  before(async () => ({ server, base } = await start((text) => synthesize(text))));
  after(() => server.close());

  test("needs a signed-in, allowed user", async () => {
    let called = false;
    synthesize = async () => ((called = true), { audio: Buffer.from("RIFF"), model: "m" });
    assert.equal((await tts(base, "Muraho", null)).status, 401);
    assert.equal((await tts(base, "Muraho", "bad-token")).status, 401);
    assert.equal((await tts(base, "Muraho", "other-token")).status, 403);
    assert.equal(called, false);
  });

  test("returns the audio with its voice model", async () => {
    let got;
    synthesize = async (text) => ((got = text), { audio: Buffer.from("RIFF-audio"), model: "facebook/mms-tts-kin" });
    const res = await tts(base, "  Muraho,\n  amakuru?  ");
    assert.equal(res.status, 200);
    assert.equal(res.headers.get("content-type"), "audio/wav");
    assert.equal(res.headers.get("x-tts-model"), "facebook/mms-tts-kin");
    assert.equal(Buffer.from(await res.arrayBuffer()).toString(), "RIFF-audio");
    assert.equal(got, "Muraho, amakuru?", "whitespace is normalised");
  });

  test("validates the text", async () => {
    assert.equal((await tts(base, "   ")).status, 400);
    assert.equal((await tts(base, 42)).status, 400);
    const long = await tts(base, "a".repeat(MAX_TTS_CHARS + 1));
    assert.equal(long.status, 413);
    assert.deepEqual(await long.json(), { error: "text_too_long" });
  });

  test("TTS service failures are 502 with a code", async () => {
    synthesize = async () => {
      throw new TtsError("tts_timeout", "slow");
    };
    const res = await tts(base, "Muraho");
    assert.equal(res.status, 502);
    assert.deepEqual(await res.json(), { error: "tts_timeout" });
  });
});

test("/api/tts without a TTS service is 503 tts_not_configured", async () => {
  const { server, base } = await start(undefined);
  try {
    const res = await tts(base, "Muraho");
    assert.equal(res.status, 503);
    assert.deepEqual(await res.json(), { error: "tts_not_configured" });
  } finally {
    server.close();
  }
});

describe("cachedSynthesizer", () => {
  const audioOf = (n) => ({ audio: Buffer.alloc(n), model: "m" });

  test("repeated text is served from memory", async () => {
    let calls = 0;
    const cached = cachedSynthesizer(async () => (calls++, audioOf(10)), { maxBytes: 100 });
    const first = await cached("Muraho");
    assert.equal(await cached("Muraho"), first);
    assert.equal(calls, 1);
  });

  test("concurrent requests for the same text share one call", async () => {
    let calls = 0;
    const cached = cachedSynthesizer(
      async () => (calls++, await new Promise((r) => setTimeout(r, 20)), audioOf(10)),
      { maxBytes: 100 },
    );
    await Promise.all([cached("Muraho"), cached("Muraho"), cached("Muraho")]);
    assert.equal(calls, 1);
  });

  test("drops the least recently used audio past the size limit", async () => {
    const calls = [];
    const cached = cachedSynthesizer(async (t) => (calls.push(t), audioOf(40)), { maxBytes: 100 });
    await cached("a");
    await cached("b");
    await cached("a"); // a is now the most recent
    await cached("c"); // 120 bytes: b goes
    assert.deepEqual(cached.stats(), { entries: 2, bytes: 80 });
    await cached("a");
    await cached("b");
    assert.deepEqual(calls, ["a", "b", "c", "b"]);
  });

  test("failures are not cached", async () => {
    let calls = 0;
    const cached = cachedSynthesizer(
      async () => {
        if (calls++ === 0) throw new TtsError("tts_failed", "x");
        return audioOf(10);
      },
      { maxBytes: 100 },
    );
    await assert.rejects(cached("Muraho"), TtsError);
    assert.equal((await cached("Muraho")).audio.length, 10);
  });
});

describe("ttsServiceClient", () => {
  test("posts the text with the shared secret", async () => {
    let request;
    const client = ttsServiceClient({
      url: "http://tts.railway.internal:8000",
      secret: "s3cret",
      fetchImpl: async (url, init) => {
        request = { url: String(url), ...init };
        return new Response(Buffer.from("RIFF"), { headers: { "x-tts-model": "facebook/mms-tts-kin" } });
      },
    });
    const { audio, model } = await client("Muraho");
    assert.equal(request.url, "http://tts.railway.internal:8000/synthesize");
    assert.equal(request.headers["x-tts-secret"], "s3cret");
    assert.deepEqual(JSON.parse(request.body), { text: "Muraho" });
    assert.equal(audio.toString(), "RIFF");
    assert.equal(model, "facebook/mms-tts-kin");
  });

  test("maps failures to codes", async () => {
    const failing = (fetchImpl) => ttsServiceClient({ url: "http://tts:8000", secret: "s", fetchImpl, timeoutMs: 20 })("x");
    await assert.rejects(failing(async () => new Response("no", { status: 401 })), { code: "tts_failed" });
    await assert.rejects(
      failing(async () => {
        throw new TypeError("fetch failed");
      }),
      { code: "tts_unreachable" },
    );
    await assert.rejects(
      failing((_url, { signal }) => new Promise((_, reject) => signal.addEventListener("abort", () => reject(signal.reason)))),
      { code: "tts_timeout" },
    );
  });
});
