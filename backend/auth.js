// Checks the Supabase access token the app sends, and who it belongs to.
//
// Asking Supabase's /auth/v1/user endpoint works whichever way the project signs
// its tokens, honours sign-outs, and needs only the publishable key: no
// service_role key or JWT secret ever has to live on this server.

/** Supabase couldn't be reached, so we can't tell whether the token is valid. */
export class AuthUnavailableError extends Error {}

export function supabaseTokenVerifier({ url, publishableKey, fetchImpl = fetch }) {
  const endpoint = new URL("/auth/v1/user", url);
  return async function verify(token) {
    let res;
    try {
      res = await fetchImpl(endpoint, {
        headers: { apikey: publishableKey, authorization: `Bearer ${token}` },
        signal: AbortSignal.timeout(10_000),
      });
    } catch (err) {
      throw new AuthUnavailableError(err.message);
    }
    // 400/401/403 mean the token is malformed, expired or revoked.
    if (res.status === 400 || res.status === 401 || res.status === 403) return null;
    if (!res.ok) throw new AuthUnavailableError(`Supabase answered ${res.status}`);
    const user = await res.json();
    return { id: user.id, email: typeof user.email === "string" ? user.email : null };
  };
}

/** "a@x.com, B@y.com" -> Set { "a@x.com", "b@y.com" } */
export function parseAllowedEmails(value) {
  return new Set(
    String(value ?? "")
      .split(",")
      .map((e) => e.trim().toLowerCase())
      .filter(Boolean),
  );
}
