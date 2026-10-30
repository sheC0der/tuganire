/** Longest text /api/tts accepts. The TTS service has the same limit. */
export const MAX_TTS_CHARS = 300;

export class TtsError extends Error {
  constructor(code, message) {
    super(message);
    this.code = code;
  }
}

/** Same text, same audio: trims and collapses whitespace so near-identical requests share a cache entry. */
export function normalizeTtsText(text) {
  return text.normalize("NFC").replace(/\s+/g, " ").trim();
}

/**
 * Calls the private TTS service (tts/ in this repo) with the shared secret.
 * The returned function resolves to { audio: Buffer, model: string }. On CPU,
 * MMS takes about as long to generate speech as to play it, hence the long timeout.
 */
export function ttsServiceClient({ url, secret, fetchImpl = fetch, timeoutMs = 25_000 }) {
  const endpoint = new URL("/synthesize", url);
  return async (text) => {
    let res;
    try {
      res = await fetchImpl(endpoint, {
        method: "POST",
        headers: { "content-type": "application/json", "x-tts-secret": secret },
        body: JSON.stringify({ text }),
        signal: AbortSignal.timeout(timeoutMs),
      });
    } catch (err) {
      throw new TtsError(err.name === "TimeoutError" ? "tts_timeout" : "tts_unreachable", err.message);
    }
    if (!res.ok) throw new TtsError("tts_failed", `TTS service answered ${res.status}`);
    return { audio: Buffer.from(await res.arrayBuffer()), model: res.headers.get("x-tts-model") ?? "" };
  };
}

/**
 * Wraps synthesize(text) with an in-memory cache of recent audio, up to maxBytes
 * in total, dropping the least recently used first. Requests for text that is
 * already being generated wait for that result instead of generating it again.
 */
export function cachedSynthesizer(synthesize, { maxBytes }) {
  const cache = new Map(); // insertion order doubles as recency order
  const pending = new Map();
  let bytes = 0;

  function remember(text, result) {
    const size = result.audio.length;
    if (size > maxBytes) return;
    cache.set(text, result);
    bytes += size;
    for (const [oldText, old] of cache) {
      if (bytes <= maxBytes) break;
      cache.delete(oldText);
      bytes -= old.audio.length;
    }
  }

  const cached = async (text) => {
    const hit = cache.get(text);
    if (hit) {
      cache.delete(text);
      cache.set(text, hit);
      return hit;
    }
    if (pending.has(text)) return pending.get(text);
    const job = synthesize(text)
      .then((result) => {
        remember(text, result);
        return result;
      })
      .finally(() => pending.delete(text));
    pending.set(text, job);
    return job;
  };
  cached.stats = () => ({ entries: cache.size, bytes });
  return cached;
}
