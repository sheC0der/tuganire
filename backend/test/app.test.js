import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { after, before, describe, test } from "node:test";

import { createApp } from "../app.js";
import { parseAllowedEmails } from "../auth.js";
import { TutorError } from "../tutor.js";

const REPLY = { reply_rw: "Muraho", reply_en: "Hello", feedback: "", corrected: "", was_correct: false, suggestions: [] };

const users = {
  "good-token": { id: "1", email: "Learner@Example.com" },
  "other-token": { id: "2", email: "stranger@example.com" },
};

async function verifyUser(token) {
  if (token === "down-token") throw new Error("Supabase unreachable");
  return users[token] ?? null;
}

let nextTurn = async () => REPLY;

function start(options) {
  const app = createApp({
    model: "test-model",
    allowedEmails: parseAllowedEmails("learner@example.com"),
    verifyUser,
    nextTurn: (args) => nextTurn(args),
    ...options,
  });
  return new Promise((resolve) => {
    const server = app.listen(0, () => resolve({ server, base: `http://127.0.0.1:${server.address().port}` }));
  });
}

const chatBody = JSON.stringify({ level: "beginner", scenarioId: "greet", history: [] });
const chat = (base, headers = {}, body = chatBody) =>
  fetch(`${base}/api/chat`, { method: "POST", headers: { "content-type": "application/json", ...headers }, body });

describe("production app with a web build", () => {
  let server, base, webDir;

  before(async () => {
    webDir = fs.mkdtempSync(path.join(os.tmpdir(), "tuganire-web-"));
    fs.writeFileSync(path.join(webDir, "index.html"), "<html>tuganire app</html>");
    fs.writeFileSync(path.join(webDir, "main.dart.js"), "console.log('app')");
    ({ server, base } = await start({ webDir, dev: false }));
  });
  after(() => {
    server.close();
    fs.rmSync(webDir, { recursive: true, force: true });
  });

  test("health endpoints", async () => {
    for (const p of ["/health", "/api/health"]) {
      const res = await fetch(base + p);
      assert.equal(res.status, 200);
      assert.deepEqual(await res.json(), { ok: true, model: "test-model" });
    }
  });

  test("serves the web app, its assets, and index.html for app routes", async () => {
    const root = await fetch(base + "/");
    assert.equal(await root.text(), "<html>tuganire app</html>");
    assert.equal(root.headers.get("cache-control"), "no-cache");

    const asset = await fetch(base + "/main.dart.js");
    assert.equal(await asset.text(), "console.log('app')");

    const route = await fetch(base + "/some/app/route", { headers: { accept: "text/html" } });
    assert.equal(route.status, 200);
    assert.equal(await route.text(), "<html>tuganire app</html>");
  });

  test("missing assets are 404, not index.html", async () => {
    const res = await fetch(base + "/missing.js");
    assert.equal(res.status, 404);
  });

  test("/api routes never fall through to index.html", async () => {
    for (const [method, p] of [
      ["GET", "/api"],
      ["GET", "/api/"],
      ["GET", "/api/nope"],
      ["GET", "/api/chat"],
      ["GET", "/API/Nope"],
      ["POST", "/api/nope"],
    ]) {
      const res = await fetch(base + p, { method, headers: { accept: "text/html" } });
      assert.equal(res.status, 404, `${method} ${p}`);
      assert.deepEqual(await res.json(), { error: "not_found" }, `${method} ${p}`);
    }
  });

  test("chat needs a bearer token", async () => {
    const res = await chat(base);
    assert.equal(res.status, 401);
    assert.deepEqual(await res.json(), { error: "unauthorized" });
  });

  test("chat rejects an invalid token with 401", async () => {
    const res = await chat(base, { authorization: "Bearer bad-token" });
    assert.equal(res.status, 401);
  });

  test("chat rejects a valid user who isn't in ALLOWED_EMAILS with 403", async () => {
    let called = false;
    nextTurn = async () => ((called = true), REPLY);
    const res = await chat(base, { authorization: "Bearer other-token" });
    assert.equal(res.status, 403);
    assert.deepEqual(await res.json(), { error: "forbidden" });
    assert.equal(called, false, "Claude must not be called");
  });

  test("chat answers 503, not 401, when the token can't be checked", async () => {
    const res = await chat(base, { authorization: "Bearer down-token" });
    assert.equal(res.status, 503);
    assert.deepEqual(await res.json(), { error: "auth_unavailable" });
  });

  test("chat returns the tutor reply for an allowed user (email case-insensitive)", async () => {
    let args;
    nextTurn = async (a) => ((args = a), REPLY);
    const res = await chat(base, { authorization: "Bearer good-token" });
    assert.equal(res.status, 200);
    assert.deepEqual(await res.json(), REPLY);
    assert.deepEqual(args, { level: "beginner", scenarioId: "greet", history: [] });
  });

  test("chat validates the level and situation", async () => {
    for (const scenarioId of ["constructor", "__proto__", "nope"]) {
      const body = JSON.stringify({ level: "beginner", scenarioId, history: [] });
      const res = await chat(base, { authorization: "Bearer good-token" }, body);
      assert.equal(res.status, 400, scenarioId);
    }
  });

  test("malformed JSON gets a JSON 400", async () => {
    const res = await chat(base, { authorization: "Bearer good-token" }, "{not json");
    assert.equal(res.status, 400);
    assert.deepEqual(await res.json(), { error: "bad_request" });
  });

  test("tutor errors are passed on as codes", async () => {
    nextTurn = async () => {
      throw new TutorError("rate_limited", "429");
    };
    const res = await chat(base, { authorization: "Bearer good-token" });
    assert.equal(res.status, 502);
    assert.deepEqual(await res.json(), { error: "rate_limited" });
  });

  test("no CORS headers in production", async () => {
    const res = await fetch(base + "/api/chat", { method: "OPTIONS", headers: { origin: "http://localhost:5000" } });
    assert.equal(res.headers.get("access-control-allow-origin"), null);
  });
});

describe("development app", () => {
  let server, base;
  before(async () => ({ server, base } = await start({ webDir: undefined, dev: true })));
  after(() => server.close());

  test("allows CORS from localhost only", async () => {
    const pre = await fetch(base + "/api/chat", {
      method: "OPTIONS",
      headers: { origin: "http://localhost:51234", "access-control-request-headers": "authorization" },
    });
    assert.equal(pre.status, 204);
    assert.equal(pre.headers.get("access-control-allow-origin"), "http://localhost:51234");
    assert.match(pre.headers.get("access-control-allow-headers"), /authorization/);

    const other = await fetch(base + "/api/health", { headers: { origin: "https://evil.example" } });
    assert.equal(other.headers.get("access-control-allow-origin"), null);
  });

  test("without a web build, non-API paths are 404", async () => {
    const res = await fetch(base + "/");
    assert.equal(res.status, 404);
  });
});
