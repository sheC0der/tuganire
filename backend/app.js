import fs from "node:fs";
import path from "node:path";
import express from "express";

import { LEVELS, SCENARIOS } from "./prompt.js";
import { TutorError } from "./tutor.js";

/**
 * Builds the server: the JSON API under /api, plus the Flutter web build served
 * from the same origin.
 *
 * - verifyUser(token) resolves to { id, email }, or null for an invalid token,
 *   and throws if the token can't be checked right now.
 * - nextTurn({ level, scenarioId, history }) resolves to the tutor's reply.
 */
export function createApp({ verifyUser, allowedEmails, nextTurn, model, webDir, dev = false }) {
  const app = express();
  app.disable("x-powered-by");

  const health = (_req, res) => res.json({ ok: true, model });
  app.get("/health", health);

  const api = express.Router();
  // The web app is served from this origin, so CORS is only needed when developing
  // with `flutter run -d chrome`, which serves the app from its own localhost port.
  if (dev) api.use(devCors);
  api.use(express.json({ limit: "64kb" }));
  api.get("/health", health);

  api.post("/chat", requireUser(verifyUser, allowedEmails), async (req, res) => {
    const { level, scenarioId, history } = req.body ?? {};
    // Object.hasOwn so keys like "constructor" or "__proto__" don't pass as valid ids.
    if (!Object.hasOwn(LEVELS, level) || !Object.hasOwn(SCENARIOS, scenarioId) || !Array.isArray(history)) {
      return res.status(400).json({ error: "bad_request" });
    }
    try {
      return res.json(await nextTurn({ level, scenarioId, history }));
    } catch (err) {
      if (err instanceof TutorError) {
        console.error("Tutor turn failed:", err.message);
        return res.status(502).json({ error: err.code });
      }
      console.error(err);
      return res.status(500).json({ error: "server_error" });
    }
  });

  // Anything else under /api is a JSON 404, never the web app's index.html.
  api.use((_req, res) => res.status(404).json({ error: "not_found" }));
  // Express recognises an error handler by its four parameters, so keep _next.
  api.use((err, _req, res, _next) => {
    const status = err.status >= 400 && err.status < 500 ? err.status : 500;
    if (status === 500) console.error(err);
    res.status(status).json({ error: status === 500 ? "server_error" : "bad_request" });
  });
  app.use("/api", api);

  const index = webDir && path.join(webDir, "index.html");
  if (index && fs.existsSync(index)) {
    // Flutter's web file names aren't content-hashed, so make browsers revalidate
    // (cheap thanks to ETags) instead of running a stale app after a deploy.
    const noCache = (res) => res.setHeader("Cache-Control", "no-cache");
    app.use(express.static(webDir, { setHeaders: noCache }));
    // App routes (paths without a file extension) get index.html; missing assets stay 404.
    app.use((req, res, next) => {
      if ((req.method !== "GET" && req.method !== "HEAD") || path.extname(req.path) || !req.accepts("html")) {
        return next();
      }
      noCache(res);
      res.sendFile(index);
    });
  } else if (webDir) {
    console.warn(`No web build at ${webDir}; serving the API only.`);
  }

  return app;
}

function requireUser(verifyUser, allowedEmails) {
  return async (req, res, next) => {
    const match = /^Bearer\s+(\S+)$/i.exec(req.get("authorization") ?? "");
    if (!match) return res.status(401).json({ error: "unauthorized" });

    let user;
    try {
      user = await verifyUser(match[1]);
    } catch (err) {
      // Not a 401: the token may be fine, and the app signs the user out on 401.
      console.error("Could not verify token:", err.message);
      return res.status(503).json({ error: "auth_unavailable" });
    }
    if (!user) return res.status(401).json({ error: "unauthorized" });
    if (!user.email || !allowedEmails.has(user.email.toLowerCase())) {
      return res.status(403).json({ error: "forbidden" });
    }
    req.user = user;
    next();
  };
}

const LOCAL_ORIGIN = /^https?:\/\/(localhost|127\.0\.0\.1|\[::1\])(:\d+)?$/;

function devCors(req, res, next) {
  const origin = req.get("origin");
  if (origin && LOCAL_ORIGIN.test(origin)) {
    res.set({
      "access-control-allow-origin": origin,
      "access-control-allow-headers": "authorization, content-type",
      "access-control-allow-methods": "GET, POST, OPTIONS",
    });
    res.vary("Origin");
    if (req.method === "OPTIONS") return res.sendStatus(204);
  }
  next();
}
