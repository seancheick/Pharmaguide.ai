// Shared fixtures for the mcp-personal tests (not a test file itself).
// Tokens are signed with an RSA key generated per test run and verified
// against an injected local JWKS; repositories are in-memory fakes of the
// service-role reads.
import { exportJWK, type JWTPayload, SignJWT } from "npm:jose@6.2.12";

import type { AiConnection, ConnectionRepository } from "../_shared/connection_gate.ts";
import { localJwks, verifyOAuthAccessToken } from "../_shared/oauth_token.ts";
import { RateLimiter } from "../_shared/rate_limiter.ts";
import { keyringFromEnv, type SnapshotRow } from "../_shared/snapshot_crypto.ts";
import {
  type AccessLog,
  createHandler,
  type SnapshotRepository,
  type StackRepository,
  type StackRow,
} from "./index.ts";

export const ISSUER = "https://project-ref.supabase.co/auth/v1";
export const AUDIENCE = "https://project-ref.supabase.co/functions/v1/mcp-personal";
export const ATTACKER_AUDIENCE = "https://attacker.example/mcp";
export const NOW = new Date("2026-10-12T12:00:00Z");
export const USER_A = "00000000-0000-0000-0000-00000000000a";
export const USER_B = "00000000-0000-0000-0000-00000000000b";
export const CLAUDE = "client-claude";
export const CHATGPT = "client-chatgpt";
/// A fixed 32-byte test key (bytes 1..32). Never a real secret.
export const TEST_KEYRING_ENV: Record<string, string> = {
  AI_SHARE_SNAPSHOT_KEY_V1: btoa(String.fromCharCode(...Array.from({ length: 32 }, (_, i) => i + 1))),
};

export function assert(condition: unknown, message: string): asserts condition {
  if (!condition) throw new Error(message);
}

export function assertEquals(actual: unknown, expected: unknown, message = ""): void {
  const a = JSON.stringify(actual);
  const e = JSON.stringify(expected);
  if (a !== e) throw new Error(`${message} expected ${e}, got ${a}`);
}

export interface SigningKey {
  privateKey: CryptoKey;
  kid: string;
  jwk: JsonWebKey & { kid: string; alg: string; use: string };
}

export async function signingKey(kid: string): Promise<SigningKey> {
  const pair = await crypto.subtle.generateKey(
    {
      name: "RSASSA-PKCS1-v1_5",
      modulusLength: 2048,
      publicExponent: new Uint8Array([1, 0, 1]),
      hash: "SHA-256",
    },
    true,
    ["sign", "verify"],
  );
  const jwk = { ...(await exportJWK(pair.publicKey)), kid, alg: "RS256", use: "sig" };
  return { privateKey: pair.privateKey, kid, jwk };
}

export function claimsFor(user: string, client: string | null, session = `session-${user}-${client}`): JWTPayload {
  const issuedAt = Math.floor(NOW.getTime() / 1000) - 60;
  const claims: JWTPayload = {
    iss: ISSUER,
    aud: AUDIENCE,
    sub: user,
    role: "authenticated",
    session_id: session,
    iat: issuedAt,
    exp: issuedAt + 3600,
  };
  if (client !== null) claims.client_id = client;
  return claims;
}

export async function sign(key: SigningKey, claims: JWTPayload, alg = "RS256"): Promise<string> {
  return await new SignJWT(claims).setProtectedHeader({ alg, kid: key.kid, typ: "JWT" })
    .sign(key.privateKey);
}

export function connection(overrides: Partial<AiConnection> = {}): AiConnection {
  return {
    connection_id: crypto.randomUUID(),
    user_id: USER_A,
    client_id: CLAUDE,
    session_id: null,
    scope: { categories: ["supplements"] },
    status: "active",
    created_at: "2026-10-12T11:00:00Z",
    expires_at: "2026-10-13T11:00:00Z",
    revoked_at: null,
    ...overrides,
  };
}

/// In-memory ai_connections with the same filters as the PostgREST repository.
export class FakeConnections implements ConnectionRepository {
  constructor(public rows: AiConnection[] = []) {}
  findBySession(userId: string, clientId: string, sessionId: string) {
    return Promise.resolve(
      this.rows.find((r) => r.user_id === userId && r.client_id === clientId && r.session_id === sessionId) ??
        null,
    );
  }
  findLatest(userId: string, clientId: string) {
    const matches = this.rows.filter((r) => r.user_id === userId && r.client_id === clientId)
      .sort((a, b) => b.created_at.localeCompare(a.created_at));
    return Promise.resolve(matches[0] ?? null);
  }
  bindSession(connectionId: string, sessionId: string) {
    const row = this.rows.find((r) => r.connection_id === connectionId && (r.session_id === null || r.session_id === sessionId));
    if (!row || row.status !== "active" || row.revoked_at !== null || (row.expires_at === null || Date.parse(row.expires_at) <= NOW.getTime())) return Promise.resolve(null);
    row.session_id = sessionId;
    return Promise.resolve({ ...row });
  }
}

/// In-memory user_stacks keyed by owner; records which user each read asked for.
export class FakeStacks implements StackRepository {
  readonly requestedUsers: string[] = [];
  constructor(readonly byUser: Record<string, StackRow[]>) {}
  listActiveSupplements(userId: string, limit: number) {
    this.requestedUsers.push(userId);
    return Promise.resolve((this.byUser[userId] ?? []).slice(0, limit));
  }
}

/// In-memory ai_share_snapshots and user_stacks.client_updated_at, with the
/// same filters as the PostgREST repository; records every read.
export class FakeSnapshots implements SnapshotRepository {
  rows: SnapshotRow[] = [];
  stackUpdates: Record<string, string[]> = {};
  readonly reads: Array<{ connectionId: string; userId: string }> = [];
  readonly staleChecks: Array<{ userId: string; since: string }> = [];
  findForConnection(connectionId: string, userId: string) {
    this.reads.push({ connectionId, userId });
    return Promise.resolve(
      this.rows.find((r) => r.connection_id === connectionId && r.user_id === userId) ?? null,
    );
  }
  stackChangedSince(userId: string, since: string) {
    this.staleChecks.push({ userId, since });
    const cutoff = Date.parse(since);
    return Promise.resolve((this.stackUpdates[userId] ?? []).some((at) => Date.parse(at) > cutoff));
  }
}

export class FakeLog implements AccessLog {
  readonly entries: Array<{ connectionId: string; tool: string }> = [];
  fail = false;
  record(connectionId: string, tool: string) {
    if (this.fail) return Promise.reject(new Error("log down"));
    this.entries.push({ connectionId, tool });
    return Promise.resolve();
  }
}

export interface Harness {
  handler: (request: Request) => Promise<Response>;
  key: SigningKey;
  connections: FakeConnections;
  stacks: FakeStacks;
  snapshots: FakeSnapshots;
  log: FakeLog;
}

export async function harness(
  options: {
    connections?: AiConnection[];
    stacks?: Record<string, StackRow[]>;
    extraKeys?: SigningKey[];
    limiter?: RateLimiter;
    handlerFactory?: typeof createHandler;
  } = {},
): Promise<Harness> {
  const key = await signingKey("project-key");
  const jwks = localJwks({ keys: [key.jwk, ...(options.extraKeys ?? []).map((k) => k.jwk)] });
  const connections = new FakeConnections(options.connections ?? [connection()]);
  const stacks = new FakeStacks(options.stacks ?? {
    [USER_A]: [{ name: "Magnesium Glycinate", dsld_id: "1001", ingredient_keys: '["magnesium"]', added_at: "2026-10-01T09:00:00Z" }],
    [USER_B]: [{ name: "User B Fish Oil", dsld_id: "2002", ingredient_keys: '["epa","dha"]', added_at: "2026-10-02T09:00:00Z" }],
  });
  const log = new FakeLog();
  const snapshots = new FakeSnapshots();
  const keyring = await keyringFromEnv((name) => TEST_KEYRING_ENV[name]);
  const handler = (options.handlerFactory ?? createHandler)({
    verifyToken: (token) => verifyOAuthAccessToken(token, { issuer: ISSUER, audience: AUDIENCE, keys: jwks, now: () => NOW }),
    connections,
    stacks,
    snapshots,
    keyring,
    accessLog: log,
    resourceUrl: AUDIENCE,
    authorizationServer: ISSUER,
    limiter: options.limiter,
    now: () => NOW,
  });
  return { handler, key, connections, stacks, snapshots, log };
}

export function rpc(token: string | null, method: string, params: Record<string, unknown> = {}): Request {
  const headers: Record<string, string> = { "content-type": "application/json" };
  if (token !== null) headers.authorization = `Bearer ${token}`;
  return new Request(AUDIENCE, {
    method: "POST",
    headers,
    body: JSON.stringify({ jsonrpc: "2.0", id: 1, method, params }),
  });
}

export function callSupplements(token: string | null): Request {
  return rpc(token, "tools/call", { name: "get_my_supplements", arguments: {} });
}

export async function body(response: Response): Promise<Record<string, any>> {
  return await response.json();
}
