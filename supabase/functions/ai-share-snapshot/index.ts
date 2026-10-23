// ai-share-snapshot: stores or deletes the user's consented share for one AI
// connection (ADR-009 Phase 2). Called by the PharmaGuide app with its own
// signed-in session, never with an assistant's OAuth token.
//
//   POST   { connection_id, scope, stack_revision, generated_at, ttl_hours, format, payload }
//            -> 201 { snapshot_id, expires_at }
//   DELETE { connection_id } | { all: true } -> 204
//
// The payload is the brief the user previewed on the phone, already limited
// to the chosen scope; the server never widens or re-derives it. It is
// encrypted with AES-256-GCM (_shared/snapshot_crypto.ts) and only the
// ciphertext is stored, one row per connection. The payload is never logged
// and never returned.
import { type AiConnection, evaluate, PERSONAL_ACCESS_DISABLED_MESSAGE } from "../_shared/connection_gate.ts";
import {
  bearerToken,
  remoteJwks,
  TokenRejected,
  type VerifiedAppSession,
  verifyAppSessionToken,
} from "../_shared/oauth_token.ts";
import { RateLimiter } from "../_shared/rate_limiter.ts";
import {
  type Keyring,
  keyringFromEnv,
  MAX_PAYLOAD_BYTES,
  SNAPSHOT_FORMAT,
  sealSnapshotRow,
  type SnapshotRow,
} from "../_shared/snapshot_crypto.ts";
import { resolveSupabaseAdminKey } from "../_shared/supabase_server_keys.ts";

export type { SnapshotRow };

/// The app's AiShareScope categories. Missing keys mean "not shared".
export const SCOPE_KEYS = [
  "supplementNames",
  "supplementAmounts",
  "supplementSchedule",
  "medicationNames",
  "medicationSchedule",
  "profile",
  "findings",
] as const;

export const TTL_HOURS = { min: 24, max: 720, default: 24 } as const;
const MAX_BODY_BYTES = MAX_PAYLOAD_BYTES + 4 * 1024;
const MAX_STACK_REVISION = 128;
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const HOUR_MS = 3_600_000;

/// Service-role access, always filtered by the verified user.
export interface ShareStore {
  findConnection(connectionId: string, userId: string): Promise<AiConnection | null>;
  /// Insert or replace the connection's single snapshot.
  upsert(row: SnapshotRow): Promise<void>;
  deleteForConnection(connectionId: string, userId: string): Promise<void>;
  deleteAllForUser(userId: string): Promise<void>;
}

export interface ShareDeps {
  verifySession: (token: string | null) => Promise<VerifiedAppSession>;
  store: ShareStore;
  keyring: Keyring;
  limiter?: RateLimiter;
  now?: () => Date;
}

function json(body: unknown, status: number, extra: Record<string, string> = {}): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json; charset=utf-8", "cache-control": "no-store", ...extra },
  });
}

function audit(outcome: string): void {
  // Outcome only: never the payload, scope, ids or token.
  console.info(JSON.stringify({ event: "ai_share_snapshot", outcome }));
}

class BadRequest extends Error {
  constructor(readonly status = 400) {
    super("bad request");
  }
}

export function clampTtlHours(value: unknown): number {
  if (value === undefined || value === null) return TTL_HOURS.default;
  if (typeof value !== "number" || !Number.isFinite(value)) throw new BadRequest();
  return Math.min(TTL_HOURS.max, Math.max(TTL_HOURS.min, Math.round(value)));
}

export function normalizeScope(value: unknown): Record<string, boolean> {
  if (!value || typeof value !== "object" || Array.isArray(value)) throw new BadRequest();
  const input = value as Record<string, unknown>;
  for (const key of Object.keys(input)) {
    if (!(SCOPE_KEYS as readonly string[]).includes(key)) throw new BadRequest();
    if (typeof input[key] !== "boolean") throw new BadRequest();
  }
  return Object.fromEntries(SCOPE_KEYS.map((key) => [key, input[key] === true]));
}

function parseBody(text: string): Record<string, unknown> {
  if (new TextEncoder().encode(text).length > MAX_BODY_BYTES) throw new BadRequest(413);
  let parsed: unknown;
  try {
    parsed = JSON.parse(text);
  } catch {
    throw new BadRequest();
  }
  if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) throw new BadRequest();
  return parsed as Record<string, unknown>;
}

const MESSAGES = {
  unauthorized: "Sign in to PharmaGuide to share with an assistant.",
  assistantToken: "Sharing is available only from the PharmaGuide app.",
  guest: "Create a PharmaGuide account to share with an assistant.",
  notFound: "PharmaGuide could not find that assistant connection.",
  rateLimited: "Too many share requests. Try again in a minute.",
  invalid: "Invalid share request.",
  tooLarge: "This share is too large.",
  unavailable: "Sharing is unavailable right now. Try again shortly.",
} as const;

export function createHandler(deps: ShareDeps): (request: Request) => Promise<Response> {
  const now = deps.now ?? (() => new Date());
  const limiter = deps.limiter ?? new RateLimiter(10, 10 / 60_000);

  async function handle(request: Request): Promise<Response> {
    if (request.method !== "POST" && request.method !== "DELETE") {
      return json({ error: "Method not allowed" }, 405, { Allow: "POST, DELETE" });
    }
    let session: VerifiedAppSession;
    try {
      session = await deps.verifySession(bearerToken(request.headers.get("authorization")));
    } catch (error) {
      if (!(error instanceof TokenRejected)) throw error;
      if (error.reason === "assistant_token") {
        audit("assistant_token_refused");
        return json({ error: MESSAGES.assistantToken }, 403);
      }
      if (error.reason === "anonymous_user") {
        audit("guest_refused");
        return json({ error: MESSAGES.guest }, 403);
      }
      audit("unauthorized");
      return json({ error: MESSAGES.unauthorized }, 401);
    }
    if (!limiter.take(session.sub)) {
      audit("rate_limited");
      return json({ error: MESSAGES.rateLimited }, 429, { "Retry-After": "60" });
    }

    let body: Record<string, unknown>;
    try {
      body = parseBody(await request.text());
    } catch (error) {
      const status = error instanceof BadRequest ? error.status : 400;
      return json({ error: status === 413 ? MESSAGES.tooLarge : MESSAGES.invalid }, status);
    }

    if (request.method === "DELETE") {
      const keys = Object.keys(body);
      if (keys.length === 1 && body.all === true) {
        await deps.store.deleteAllForUser(session.sub);
        audit("deleted_all");
        return new Response(null, { status: 204 });
      }
      if (keys.length === 1 && typeof body.connection_id === "string" && UUID.test(body.connection_id)) {
        await deps.store.deleteForConnection(body.connection_id, session.sub);
        audit("deleted_one");
        return new Response(null, { status: 204 });
      }
      return json({ error: MESSAGES.invalid }, 400);
    }

    let connectionId: string;
    let scope: Record<string, boolean>;
    let ttlHours: number;
    let stackRevision: string | null;
    let payload: string;
    let generatedAt: Date;
    try {
      if (typeof body.connection_id !== "string" || !UUID.test(body.connection_id)) throw new BadRequest();
      connectionId = body.connection_id.toLowerCase();
      if (body.format !== SNAPSHOT_FORMAT) throw new BadRequest();
      scope = normalizeScope(body.scope);
      // Use the report's generation time, not upload receipt time: a change
      // between preview and upload must still make the shared report stale.
      if (typeof body.generated_at !== "string" ||
          !/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,6})?Z$/.test(body.generated_at)) {
        throw new BadRequest();
      }
      generatedAt = new Date(body.generated_at);
      if (!Number.isFinite(generatedAt.getTime()) || generatedAt.getTime() > now().getTime()) {
        throw new BadRequest();
      }
      ttlHours = clampTtlHours(body.ttl_hours);
      if (body.stack_revision === undefined || body.stack_revision === null) {
        stackRevision = null;
      } else if (typeof body.stack_revision === "string" && body.stack_revision.length <= MAX_STACK_REVISION) {
        stackRevision = body.stack_revision;
      } else {
        throw new BadRequest();
      }
      if (typeof body.payload !== "string" || body.payload.trim() === "") throw new BadRequest();
      if (new TextEncoder().encode(body.payload).length > MAX_PAYLOAD_BYTES) throw new BadRequest(413);
      payload = body.payload;
    } catch (error) {
      const status = error instanceof BadRequest ? error.status : 400;
      audit(status === 413 ? "too_large" : "invalid");
      return json({ error: status === 413 ? MESSAGES.tooLarge : MESSAGES.invalid }, status);
    }

    // Another user's connection reads exactly like a missing one.
    const connection = await deps.store.findConnection(connectionId, session.sub);
    if (!connection) {
      audit("connection_not_found");
      return json({ error: MESSAGES.notFound }, 404);
    }
    const at = now();
    const live = evaluate(connection, at);
    if (!live.ok) {
      audit("connection_not_active");
      return json({ error: live.reason }, 403);
    }

    // A share never outlives its connection.
    const expiresAt = new Date(
      Math.min(at.getTime() + ttlHours * HOUR_MS, Date.parse(connection.expires_at)),
    );
    const row = await sealSnapshotRow(deps.keyring, {
      snapshotId: crypto.randomUUID(),
      connectionId: connection.connection_id,
      userId: session.sub,
      format: SNAPSHOT_FORMAT,
      scope,
      stackRevision,
      payload,
      generatedAt,
      expiresAt,
    });
    await deps.store.upsert(row);
    audit("stored");
    return json({ snapshot_id: row.snapshot_id, expires_at: row.expires_at }, 201);
  }

  return async (request: Request): Promise<Response> => {
    try {
      return await handle(request);
    } catch {
      audit("failed");
      return json({ error: MESSAGES.unavailable }, 503);
    }
  };
}

// ---------------------------------------------------------------------------
// Service-role PostgREST store (production wiring)
// ---------------------------------------------------------------------------

export type FetchLike = (input: string, init?: RequestInit) => Promise<Response>;

export function postgrestShareStore(
  supabaseUrl: string,
  serviceKey: string,
  fetchFn: FetchLike = (input, init) => fetch(input, init),
): ShareStore {
  const base = `${supabaseUrl.replace(/\/$/, "")}/rest/v1`;
  const headers = {
    apikey: serviceKey,
    Authorization: `Bearer ${serviceKey}`,
    "content-type": "application/json",
  };
  async function call(path: string, params: Record<string, string>, init: RequestInit = {}): Promise<string> {
    const response = await fetchFn(`${base}/${path}?${new URLSearchParams(params)}`, {
      ...init,
      headers: { ...headers, ...(init.headers ?? {}) },
    });
    // Status only: a PostgREST error body could echo submitted values.
    if (!response.ok) throw new Error(`postgrest ${path} ${response.status}`);
    return await response.text();
  }
  return {
    async findConnection(connectionId, userId) {
      const text = await call("ai_connections", {
        select: "connection_id,user_id,client_id,session_id,scope,status,created_at,expires_at,revoked_at",
        connection_id: `eq.${connectionId}`,
        user_id: `eq.${userId}`,
        limit: "1",
      });
      return (text ? JSON.parse(text) as AiConnection[] : [])[0] ?? null;
    },
    async upsert(row) {
      await call("ai_share_snapshots", { on_conflict: "connection_id" }, {
        method: "POST",
        headers: { Prefer: "resolution=merge-duplicates,return=minimal" },
        body: JSON.stringify(row),
      });
    },
    async deleteForConnection(connectionId, userId) {
      await call("ai_share_snapshots", { connection_id: `eq.${connectionId}`, user_id: `eq.${userId}` }, {
        method: "DELETE",
        headers: { Prefer: "return=minimal" },
      });
    },
    async deleteAllForUser(userId) {
      await call("ai_share_snapshots", { user_id: `eq.${userId}` }, {
        method: "DELETE",
        headers: { Prefer: "return=minimal" },
      });
    },
  };
}

// Do not collect new sensitive snapshots while personal reads are contained
// for ADR-009 S2. Keep the existing authenticated deletion/sign-out path live.
export function createProductionHandler(deps: ShareDeps): (request: Request) => Promise<Response> {
  const handler = createHandler(deps);
  return (request) => request.method === "POST"
    ? Promise.resolve(json({ error: PERSONAL_ACCESS_DISABLED_MESSAGE }, 503))
    : handler(request);
}

if (import.meta.main) {
  const supabaseUrl = Deno.env.get("SUPABASE_URL")?.trim();
  let serviceKey: string | undefined;
  let keyring: Keyring | undefined;
  try {
    serviceKey = resolveSupabaseAdminKey();
    keyring = await keyringFromEnv((name) => Deno.env.get(name));
  } catch {
    serviceKey = undefined;
  }
  if (!supabaseUrl || !serviceKey || !keyring) {
    // Fail closed: without keys nothing is stored.
    Deno.serve(() => json({ error: MESSAGES.unavailable }, 503));
  } else {
    const issuer = `${supabaseUrl.replace(/\/$/, "")}/auth/v1`;
    const keys = remoteJwks(supabaseUrl);
    Deno.serve(createProductionHandler({
      verifySession: (token) => verifyAppSessionToken(token, { issuer, keys }),
      store: postgrestShareStore(supabaseUrl, serviceKey),
      keyring,
    }));
  }
}
