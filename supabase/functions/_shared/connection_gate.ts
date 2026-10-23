// Grant-level authorization for personal MCP calls (S10, S5).
//
// A verified token proves who the user is and which assistant holds it. It
// does not prove the user still allows that assistant in: every call resolves
// the token to its public.ai_connections row and requires status 'active',
// expires_at in the future and, per tool, the category in scope.categories.
// Nothing is cached, so Disconnect takes effect on the next call even while
// the access token itself is unexpired.
import type { VerifiedOAuthToken } from "./oauth_token.ts";

// Shared production-containment explanation. Transient failures keep their own
// retry messages; disabled personal access must not send clients into retries.
export const PERSONAL_ACCESS_DISABLED_MESSAGE =
  "Personal connections and snapshot sharing are not enabled. " +
  "Public product lookup is available without sign-in at https://mcp.pharmaguide.io/public. " +
  "That connector cannot read your supplement list, medications or health profile.";

export type ConnectionStatus = "active" | "revoked" | "expired";

export interface AiConnection {
  connection_id: string;
  user_id: string;
  client_id: string;
  session_id: string | null;
  scope: unknown;
  status: ConnectionStatus | string;
  created_at: string;
  expires_at: string | null;
  oauth_issuer?: string | null;
  consent_id?: string | null;
  revoked_at: string | null;
}

/// Service-role reads of public.ai_connections. Every method is filtered by
/// the verified user and client, never by a value the caller supplies.
export interface ConnectionRepository {
  findByConsent?(userId: string, clientId: string, issuer: string, consentId: string): Promise<AiConnection | null>;
  findBySession(
    userId: string,
    clientId: string,
    sessionId: string,
  ): Promise<AiConnection | null>;
  /// The most recently created row for (user, client), any status.
  findLatest(userId: string, clientId: string): Promise<AiConnection | null>;
  /// Atomically binds or validates against the live Auth session and returns
  /// the current connection. Null denies missing/older/wrong/revoked sessions.
  bindSession(connectionId: string, sessionId: string): Promise<AiConnection | null>;
}

export type GateResult =
  | { ok: true; connection: AiConnection }
  | { ok: false; status: 403; reason: string };

export const GATE_REASONS = {
  noConnection:
    "PharmaGuide has no approved connection for this assistant. Connect it again from PharmaGuide.",
  revoked:
    "This PharmaGuide connection was disconnected. Connect it again from PharmaGuide to continue.",
  expired:
    "This PharmaGuide connection has ended. Connect it again from PharmaGuide to continue.",
  otherSession:
    "This PharmaGuide connection belongs to a different sign-in. Connect this assistant again from PharmaGuide.",
  notInScope:
    "This PharmaGuide connection does not include that information.",
} as const;

function deny(reason: string): GateResult {
  return { ok: false, status: 403, reason };
}

/// Active and unexpired, or the reason it is not. Also used by
/// ai-share-snapshot before it stores a share for a connection.
export function evaluate(connection: AiConnection, now: Date): GateResult {
  if (connection.status === "revoked" || connection.revoked_at !== null) return deny(GATE_REASONS.revoked);
  if (connection.status !== "active") return deny(GATE_REASONS.expired);
  if (connection.expires_at === null) {
    return connection.oauth_issuer?.startsWith("https://") && connection.consent_id?.startsWith("app_consent_")
      ? {ok: true, connection} : deny(GATE_REASONS.expired);
  }
  const expiresAt = Date.parse(connection.expires_at);
  // An unparseable expiry is treated as already expired: fail closed.
  if (!Number.isFinite(expiresAt) || expiresAt <= now.getTime()) {
    return deny(GATE_REASONS.expired);
  }
  return { ok: true, connection };
}

export async function resolveConnection(
  token: VerifiedOAuthToken,
  repository: ConnectionRepository,
  now: Date = new Date(),
): Promise<GateResult> {
  if (token.provider === "workos") {
    const bound = await repository.findByConsent?.(token.sub, token.clientId, token.issuer, token.consentId);
    if (!bound) return deny(GATE_REASONS.noConnection);
    if (bound.user_id !== token.sub || bound.client_id !== token.clientId ||
      bound.oauth_issuer !== token.issuer || bound.consent_id !== token.consentId) {
      return deny(GATE_REASONS.otherSession);
    }
    return evaluate(bound, now);
  }
  const { sub, clientId, sessionId } = token;
  if (sessionId) {
    const bound = await repository.findBySession(sub, clientId, sessionId);
    if (bound) {
      const verdict = evaluate(bound, now);
      if (!verdict.ok) return verdict;
      const validated = await repository.bindSession(bound.connection_id, sessionId);
      return validated ? evaluate(validated, now) : deny(GATE_REASONS.otherSession);
    }
  }
  const latest = await repository.findLatest(sub, clientId);
  if (!latest) return deny(GATE_REASONS.noConnection);
  if (latest.session_id !== null) {
    // Bound to another session. Without a session claim, or with a different
    // one, this token cannot borrow that connection.
    return latest.status === "active"
      ? deny(GATE_REASONS.otherSession)
      : evaluate(latest, now);
  }
  const verdict = evaluate(latest, now);
  if (!verdict.ok) return verdict;
  // A token from before this consent must not claim a new unbound grant.
  // JWT iat has second precision; the database timestamp may include fractions.
  // The RPC also checks original Auth-session age, which refresh cannot reset.
  const approvedAt = Date.parse(latest.created_at);
  const issuedAt = token.claims.iat;
  if (!sessionId || !Number.isFinite(approvedAt) || typeof issuedAt !== "number" ||
      !Number.isFinite(issuedAt) || issuedAt < Math.floor(approvedAt / 1000)) {
    return deny(GATE_REASONS.otherSession);
  }
  // The service-only RPC checks Auth's original creation time and current
  // connection state atomically. Never return the cached pre-bind approval.
  const bound = await repository.bindSession(latest.connection_id, sessionId);
  return bound ? evaluate(bound, now) : deny(GATE_REASONS.otherSession);
}

/// The categories a connection grants. Anything that is not an object with a
/// string array `categories` grants nothing.
export function scopeCategories(scope: unknown): Set<string> {
  if (!scope || typeof scope !== "object" || Array.isArray(scope)) {
    return new Set();
  }
  const categories = (scope as { categories?: unknown }).categories;
  if (!Array.isArray(categories)) return new Set();
  return new Set(categories.filter((c): c is string => typeof c === "string"));
}

export function requireCategory(
  connection: AiConnection,
  category: string,
): GateResult {
  return scopeCategories(connection.scope).has(category)
    ? { ok: true, connection }
    : deny(GATE_REASONS.notInScope);
}
