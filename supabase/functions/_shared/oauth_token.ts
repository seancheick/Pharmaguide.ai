// OAuth 2.1 access-token verification for the personal MCP server (S1, S2).
//
// Supabase Auth's OAuth server issues JWTs with role "authenticated", `sub`,
// `client_id` and `session_id`. The MCP server verifies every token itself and
// never forwards it to the database: the signature against the project's JWKS (asymmetric
// algorithms only), the exact issuer, expiry, the audience stamped by
// public.custom_access_token_hook, and the presence of `sub` and `client_id`.
// verifyAppSessionToken is the mirror image for ai-share-snapshot: the same
// signature core, but it requires the app's own session and refuses any
// token that carries `client_id`.
import {
  createLocalJWKSet,
  createRemoteJWKSet,
  errors,
  type JSONWebKeySet,
  type JWTPayload,
  jwtVerify,
  type JWTVerifyGetKey,
} from "npm:jose@6.2.12";

/// Asymmetric only. A symmetric (HS256) project secret is shared with every
/// Supabase service, so the personal MCP server refuses it outright.
export const ACCEPTED_ALGORITHMS = ["ES256", "RS256"];

export type TokenRejection =
  | "missing"
  | "malformed"
  | "invalid_signature"
  | "expired"
  | "wrong_issuer"
  | "wrong_audience"
  | "not_an_oauth_client_token"
  | "missing_subject"
  | "missing_session"
  | "wrong_role"
  | "userinfo_rejected"
  | "missing_scope"
  // App-session verification only (verifyAppSessionToken):
  | "assistant_token"
  | "anonymous_user";

export class TokenRejected extends Error {
  constructor(readonly reason: TokenRejection) {
    super(`access token rejected: ${reason}`);
  }
}

interface OAuthTokenBaseConfig {
  /// Exact `iss`, e.g. https://<ref>.supabase.co/auth/v1
  issuer: string;
  /// Exact `aud`: the personal MCP URL the token hook stamps.
  audience: string;
  keys: JWTVerifyGetKey;
  now?: () => Date;
}

export type OAuthTokenConfig = OAuthTokenBaseConfig & (
  | { provider?: "supabase" }
  | { provider: "workos"; allowedClientIds: readonly string[];
      userInfoFetch?: typeof fetch; userInfoTimeoutMs?: number }
);

export type VerifiedOAuthToken = VerifiedSupabaseOAuthToken | {
  provider: "workos";
  sub: string;
  clientId: string;
  consentId: string;
  issuer: string;
  sessionId?: never;
  claims: JWTPayload;
};

interface VerifiedSupabaseOAuthToken {
  provider?: "supabase";
  sub: string;
  clientId: string;
  sessionId: string;
  claims: JWTPayload;
}

export function remoteJwks(supabaseUrl: string, provider: "supabase" | "workos" = "supabase"): JWTVerifyGetKey {
  return createRemoteJWKSet(
    new URL(provider === "workos" ? "/oauth2/jwks" : "/auth/v1/.well-known/jwks.json", supabaseUrl),
  );
}

export function localJwks(jwks: JSONWebKeySet): JWTVerifyGetKey {
  return createLocalJWKSet(jwks);
}

/// The bearer credential, or null when the header is absent or not Bearer.
export function bearerToken(authorization: string | null): string | null {
  const match = /^Bearer\s+(\S+)\s*$/i.exec(authorization ?? "");
  return match ? match[1] : null;
}

function nonblankString(value: unknown, max = 255): string | null {
  return typeof value === "string" && value.trim() !== "" && value.length <= max
    ? value
    : null;
}

/// Signature (asymmetric JWKS), exact issuer, expiry, `sub` present and, when
/// given, the exact audience. The one verification core for both token kinds.
async function verifySignedClaims(
  token: string | null,
  config: { issuer: string; audience?: string; keys: JWTVerifyGetKey; now?: () => Date },
): Promise<JWTPayload> {
  if (!token) throw new TokenRejected("missing");
  try {
    const { payload } = await jwtVerify(token, config.keys, {
      algorithms: ACCEPTED_ALGORITHMS,
      issuer: config.issuer,
      audience: config.audience,
      requiredClaims: ["exp", "sub"],
      currentDate: config.now?.(),
    });
    return payload;
  } catch (error) {
    if (error instanceof errors.JWTExpired) throw new TokenRejected("expired");
    if (error instanceof errors.JWTClaimValidationFailed) {
      if (error.claim === "aud") throw new TokenRejected("wrong_audience");
      if (error.claim === "iss") throw new TokenRejected("wrong_issuer");
      if (error.claim === "sub") throw new TokenRejected("missing_subject");
      throw new TokenRejected("malformed");
    }
    if (
      error instanceof errors.JWSSignatureVerificationFailed ||
      error instanceof errors.JWKSNoMatchingKey ||
      error instanceof errors.JOSEAlgNotAllowed ||
      error instanceof errors.JWKSMultipleMatchingKeys
    ) {
      throw new TokenRejected("invalid_signature");
    }
    throw new TokenRejected("malformed");
  }
}

export async function verifyOAuthAccessToken(
  token: string | null,
  config: OAuthTokenConfig,
): Promise<VerifiedOAuthToken> {
  const claims = await verifySignedClaims(token, config);
  const sub = nonblankString(claims.sub);
  if (!sub) throw new TokenRejected("missing_subject");
  if (config.provider === "workos") {
    // The issuer is operator configuration, never token-controlled. Standalone
    // WorkOS uses the Supabase external user UUID as sub and consent ID as sid.
    let issuer: URL;
    try { issuer = new URL(config.issuer); } catch { throw new TokenRejected("wrong_issuer"); }
    if (issuer.protocol !== "https:" || issuer.username || issuer.password ||
      issuer.origin !== config.issuer) throw new TokenRejected("wrong_issuer");
    if (claims.aud !== config.audience) throw new TokenRejected("wrong_audience");
    const clientId = nonblankString(claims.client_id);
    if (!clientId || !config.allowedClientIds.includes(clientId)) {
      throw new TokenRejected("not_an_oauth_client_token");
    }
    const consentId = nonblankString(claims.sid);
    if (!consentId || !/^app_consent_[A-Za-z0-9_-]+$/.test(consentId)) {
      throw new TokenRejected("missing_session");
    }
    const now = Math.floor((config.now?.() ?? new Date()).getTime() / 1000);
    if (typeof claims.iat !== "number" || !Number.isFinite(claims.iat) ||
      claims.iat > now || claims.iat >= claims.exp!) throw new TokenRejected("malformed");
    if (typeof claims.scope !== "string" || !claims.scope.split(/\s+/).includes("openid")) {
      throw new TokenRejected("missing_scope");
    }
    // Live grant check on every request: reuse only this already-verified token.
    // Do not cache success: a revoked consent must stop existing access tokens.
    const requestedTimeout = config.userInfoTimeoutMs ?? 5000;
    if (!Number.isFinite(requestedTimeout) || requestedTimeout < 1 || requestedTimeout > 10000) {
      throw new TokenRejected("malformed");
    }
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), requestedTimeout);
    try {
      const response = await (config.userInfoFetch ?? fetch)(`${config.issuer}/oauth2/userinfo`, {
        method: "POST", redirect: "error", cache: "no-store", signal: controller.signal,
        headers: { authorization: `Bearer ${token}`, accept: "application/json" },
      });
      if (!response.ok) throw new TokenRejected("userinfo_rejected");
      const info = await response.json();
      if (!info || typeof info !== "object" || info.sub !== sub) {
        throw new TokenRejected("userinfo_rejected");
      }
    } catch {
      throw new TokenRejected("userinfo_rejected");
    } finally {
      clearTimeout(timer);
    }
    return { provider: "workos", sub, clientId, consentId, issuer: config.issuer, claims };
  }
  if (claims.role !== "authenticated") throw new TokenRejected("wrong_role");
  const clientId = nonblankString(claims.client_id);
  if (!clientId) throw new TokenRejected("not_an_oauth_client_token");
  const sessionId = nonblankString(claims.session_id);
  if (!sessionId) throw new TokenRejected("missing_session");
  if (typeof claims.iat !== "number" || !Number.isFinite(claims.iat)) {
    throw new TokenRejected("malformed");
  }
  return {
    sub,
    clientId,
    sessionId,
    claims,
  };
}

export interface AppSessionConfig {
  /// Exact `iss`, e.g. https://<ref>.supabase.co/auth/v1
  issuer: string;
  keys: JWTVerifyGetKey;
  now?: () => Date;
}

export interface VerifiedAppSession {
  sub: string;
  claims: JWTPayload;
}

/// The PharmaGuide app's own signed-in session (ai-share-snapshot). Refuses an
/// AI assistant's OAuth token (any `client_id`) before anything else, then
/// requires aud "authenticated", role "authenticated" and a non-anonymous user.
export async function verifyAppSessionToken(
  token: string | null,
  config: AppSessionConfig,
): Promise<VerifiedAppSession> {
  const claims = await verifySignedClaims(token, config);
  if (claims.client_id !== undefined && claims.client_id !== null) {
    throw new TokenRejected("assistant_token");
  }
  const audiences = Array.isArray(claims.aud) ? claims.aud : [claims.aud];
  if (!audiences.includes("authenticated")) throw new TokenRejected("wrong_audience");
  const sub = nonblankString(claims.sub);
  if (!sub) throw new TokenRejected("missing_subject");
  if (claims.role !== "authenticated") throw new TokenRejected("wrong_role");
  if (claims.is_anonymous === true) throw new TokenRejected("anonymous_user");
  return { sub, claims };
}

/// For user-JWT edge functions (delete-account, register-push-token): true
/// when the caller's token was issued to an OAuth client. Those functions
/// already have the token verified by the gateway and by auth.getUser(), so a
/// payload decode is enough to refuse it; a forged claim cannot pass them.
export function isOAuthClientToken(authorization: string | null): boolean {
  const token = bearerToken(authorization);
  const payload = token?.split(".")[1];
  if (!payload) return false;
  try {
    const base64 = payload.replace(/-/g, "+").replace(/_/g, "/");
    const padded = base64 + "=".repeat((4 - (base64.length % 4)) % 4);
    const claims = JSON.parse(atob(padded));
    return claims !== null && typeof claims === "object" &&
      claims.client_id !== undefined && claims.client_id !== null;
  } catch {
    return false;
  }
}
