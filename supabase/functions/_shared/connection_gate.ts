// Grant-level authorization for personal MCP calls (S10, S5).
//
// A verified token proves who the user is and which assistant holds it. It
// does not prove the user still allows that assistant in: every call resolves
// the token to its public.ai_connections row and requires status 'active',
// expires_at in the future and, per tool, the category in scope.categories.
// Nothing is cached, so Disconnect takes effect on the next call even while
// the access token itself is unexpired.
import type { VerifiedOAuthToken } from "./oauth_token.ts";

export type ConnectionStatus = "active" | "revoked" | "expired";

export interface AiConnection {
  connection_id: string;
  user_id: string;
  client_id: string;
  session_id: string | null;
  scope: unknown;
  status: ConnectionStatus | string;
  created_at: string;
  expires_at: string;
  revoked_at: string | null;
}

/// Service-role reads of public.ai_connections. Every method is filtered by
/// the verified user and client, never by a value the caller supplies.
export interface ConnectionRepository {
  findBySession(
    userId: string,
    clientId: string,
    sessionId: string,
  ): Promise<AiConnection | null>;
  /// The most recently created row for (user, client), any status.
  findLatest(userId: string, clientId: string): Promise<AiConnection | null>;
  /// Binds the session to an unbound row; false when another session won.
  bindSession(connectionId: string, sessionId: string): Promise<boolean>;
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

function evaluate(connection: AiConnection, now: Date): GateResult {
  if (connection.status === "revoked") return deny(GATE_REASONS.revoked);
  if (connection.status !== "active") return deny(GATE_REASONS.expired);
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
  const { sub, clientId, sessionId } = token;
  if (sessionId) {
    const bound = await repository.findBySession(sub, clientId, sessionId);
    if (bound) return evaluate(bound, now);
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
  if (!verdict.ok || !sessionId) return verdict;
  // First call after approval: bind this session to the connection.
  if (await repository.bindSession(latest.connection_id, sessionId)) {
    return { ok: true, connection: { ...latest, session_id: sessionId } };
  }
  const winner = await repository.findBySession(sub, clientId, sessionId);
  return winner ? evaluate(winner, now) : deny(GATE_REASONS.otherSession);
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
