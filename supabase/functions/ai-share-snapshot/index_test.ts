// ai-share-snapshot: the phone's consented share (ADR-009 Phase 2).
// Tokens are app session JWTs signed with a per-run RSA key and verified
// against an injected JWKS; the store is an in-memory fake of the
// service-role PostgREST calls.
import type { JWTPayload } from "npm:jose@6.2.12";

import type { AiConnection } from "../_shared/connection_gate.ts";
import { localJwks, verifyAppSessionToken } from "../_shared/oauth_token.ts";
import { RateLimiter } from "../_shared/rate_limiter.ts";
import {
  decryptSnapshot,
  fromPgBytea,
  type Keyring,
  keyringFromEnv,
  SnapshotKeyError,
  toPgBytea,
} from "../_shared/snapshot_crypto.ts";
import {
  assert,
  assertEquals,
  CLAUDE,
  claimsFor,
  harness,
  rpc,
  connection,
  ISSUER,
  NOW,
  sign,
  type SigningKey,
  signingKey,
  USER_A,
  USER_B,
} from "../mcp-personal/test_support.ts";
import { createHandler, createProductionHandler, normalizeScope, SCOPE_KEYS, type ShareStore, type SnapshotRow } from "./index.ts";

const KEY_V1 = btoa(String.fromCharCode(...new Uint8Array(32).map((_, i) => i + 1)));
const KEY_V2 = btoa(String.fromCharCode(...new Uint8Array(32).map((_, i) => 200 - i)));
const URL_ = "https://project-ref.supabase.co/functions/v1/ai-share-snapshot";
const PAYLOAD = "# PharmaGuide brief\n\n- Magnesium Glycinate\n- Warfarin 5 mg (medication)\n";
const HOUR = 3_600_000;
const FULL_SCOPE = {
  supplement_names: true,
  supplement_amounts: true,
  supplement_schedule: false,
  medication_names: true,
  medication_schedule: false,
  profile: false,
  findings: true,
};

function sessionClaims(user: string, extra: JWTPayload = {}): JWTPayload {
  const iat = Math.floor(NOW.getTime() / 1000) - 60;
  return {
    iss: ISSUER,
    aud: "authenticated",
    sub: user,
    role: "authenticated",
    session_id: `app-session-${user}`,
    is_anonymous: false,
    iat,
    exp: iat + 3600,
    ...extra,
  };
}

class FakeStore implements ShareStore {
  rows = new Map<string, SnapshotRow>();
  deletes: Array<{ connectionId: string | null; userId: string }> = [];
  constructor(public connections: AiConnection[]) {}
  findConnection(connectionId: string, userId: string) {
    return Promise.resolve(
      this.connections.find((c) => c.connection_id === connectionId && c.user_id === userId) ?? null,
    );
  }
  upsert(row: SnapshotRow) {
    this.rows.set(row.connection_id, row);
    return Promise.resolve();
  }
  deleteForConnection(connectionId: string, userId: string) {
    this.deletes.push({ connectionId, userId });
    const row = this.rows.get(connectionId);
    if (row && row.user_id === userId) this.rows.delete(connectionId);
    return Promise.resolve();
  }
  deleteAllForUser(userId: string) {
    this.deletes.push({ connectionId: null, userId });
    for (const [id, row] of this.rows) if (row.user_id === userId) this.rows.delete(id);
    return Promise.resolve();
  }
}

interface Setup {
  handler: (request: Request) => Promise<Response>;
  key: SigningKey;
  store: FakeStore;
  keyring: Keyring;
  live: AiConnection;
}

async function setup(connections?: AiConnection[], limiter = new RateLimiter(1000, 0), handlerFactory = createHandler): Promise<Setup> {
  const key = await signingKey("project-key");
  const keys = localJwks({ keys: [key.jwk] });
  const live = connection({ expires_at: "2026-12-31T00:00:00Z" });
  const store = new FakeStore(connections ?? [live]);
  const keyring = await keyringFromEnv((name) => ({ AI_SHARE_SNAPSHOT_KEY_V1: KEY_V1 } as Record<string, string>)[name]);
  const handler = handlerFactory({
    verifySession: (token) => verifyAppSessionToken(token, { issuer: ISSUER, keys, now: () => NOW }),
    store,
    keyring,
    limiter,
    now: () => NOW,
  });
  return { handler, key, store, keyring, live };
}

function request(method: string, token: string | null, body: unknown): Request {
  const headers: Record<string, string> = { "content-type": "application/json" };
  if (token !== null) headers.authorization = `Bearer ${token}`;
  const payload = method === "GET" ? undefined : typeof body === "string" ? body : JSON.stringify(body);
  return new Request(URL_, { method, headers, body: payload });
}

function share(connectionId: string, overrides: Record<string, unknown> = {}) {
  return {
    connection_id: connectionId,
    scope: FULL_SCOPE,
    stack_revision: "rev-7",
    generated_at: NOW.toISOString(),
    ttl_hours: 24,
    format: "pharmaguide-brief-markdown/v1",
    payload: PAYLOAD,
    ...overrides,
  };
}

async function appToken(s: Setup, user = USER_A, extra: JWTPayload = {}) {
  return await sign(s.key, sessionClaims(user, extra));
}

/// Runs `fn` with console output captured, so a test can prove nothing it
/// logs carries the payload.
async function captureLogs<T>(fn: () => Promise<T>): Promise<{ value: T; logs: string }> {
  const lines: string[] = [];
  const saved = { log: console.log, info: console.info, warn: console.warn, error: console.error };
  for (const level of ["log", "info", "warn", "error"] as const) {
    console[level] = (...args: unknown[]) => lines.push(args.map(String).join(" "));
  }
  try {
    return { value: await fn(), logs: lines.join("\n") };
  } finally {
    Object.assign(console, saved);
  }
}

Deno.test("an AI assistant's OAuth token (client_id claim) is refused with 403", async () => {
  const s = await setup();
  const token = await sign(s.key, sessionClaims(USER_A, { client_id: CLAUDE }));
  const response = await s.handler(request("POST", token, share(s.live.connection_id)));
  assertEquals(response.status, 403);
  assertEquals(s.store.rows.size, 0, "nothing stored");
  const del = await s.handler(request("DELETE", token, { all: true }));
  assertEquals(del.status, 403, "delete refused too");
  assertEquals(s.store.deletes.length, 0);
});

Deno.test("no token, a token from another key, or an expired token is 401", async () => {
  const s = await setup();
  assertEquals((await s.handler(request("POST", null, share(s.live.connection_id)))).status, 401);
  const stranger = await signingKey("stranger");
  const forged = await sign(stranger, sessionClaims(USER_A));
  assertEquals((await s.handler(request("POST", forged, share(s.live.connection_id)))).status, 401);
  const old = await sign(s.key, sessionClaims(USER_A, { exp: Math.floor(NOW.getTime() / 1000) - 10 }));
  assertEquals((await s.handler(request("POST", old, share(s.live.connection_id)))).status, 401);
  assertEquals((await s.handler(request("POST", "not-a-jwt", share(s.live.connection_id)))).status, 401);
  assertEquals(s.store.rows.size, 0);
});

Deno.test("anon-key and anonymous (guest) sessions are refused", async () => {
  const s = await setup();
  const anonKey = await sign(s.key, { iss: ISSUER, role: "anon", iat: 1, exp: 4_000_000_000 });
  assertEquals((await s.handler(request("POST", anonKey, share(s.live.connection_id)))).status, 401);
  const guest = await appToken(s, USER_A, { is_anonymous: true });
  assertEquals((await s.handler(request("POST", guest, share(s.live.connection_id)))).status, 403);
  assertEquals(s.store.rows.size, 0);
});

Deno.test("another user's connection is not found", async () => {
  const s = await setup();
  const response = await s.handler(request("POST", await appToken(s, USER_B), share(s.live.connection_id)));
  assertEquals(response.status, 404);
  assertEquals(s.store.rows.size, 0);
});

Deno.test("a revoked or lapsed connection is refused with 403", async () => {
  const revoked = connection({ status: "revoked", revoked_at: "2026-10-12T11:30:00Z" });
  const lapsed = connection({ expires_at: "2026-10-12T11:59:00Z" });
  const marked = connection({ status: "expired" });
  const s = await setup([revoked, lapsed, marked]);
  const token = await appToken(s);
  for (const c of [revoked, lapsed, marked]) {
    assertEquals((await s.handler(request("POST", token, share(c.connection_id)))).status, 403, c.status);
  }
  assertEquals(s.store.rows.size, 0);
});

Deno.test("ttl_hours is clamped to 24..720 and never outlives the connection", async () => {
  const s = await setup();
  const token = await appToken(s);
  const cases: Array<[unknown, number]> = [[1, 24], [24, 24], [48, 48], [10_000, 720], [undefined, 24]];
  for (const [ttl, hours] of cases) {
    const response = await s.handler(request("POST", token, share(s.live.connection_id, { ttl_hours: ttl })));
    assertEquals(response.status, 201, `ttl ${ttl}`);
    const body = await response.json();
    assertEquals(body.expires_at, new Date(NOW.getTime() + hours * HOUR).toISOString(), `ttl ${ttl}`);
  }
  const short = connection({ expires_at: "2026-10-13T11:00:00Z" });
  const s2 = await setup([short]);
  const body = await (await s2.handler(request("POST", await appToken(s2), share(short.connection_id, { ttl_hours: 720 })))).json();
  assertEquals(body.expires_at, "2026-10-13T11:00:00.000Z", "clamped to the connection's own expiry");
  assertEquals((await s.handler(request("POST", token, share(s.live.connection_id, { ttl_hours: "48" })))).status, 400);
});

Deno.test("the stored row is AES-GCM ciphertext that round-trips, bound to its connection", async () => {
  const s = await setup();
  const { value: response, logs } = await captureLogs(async () =>
    await s.handler(request("POST", await appToken(s), share(s.live.connection_id)))
  );
  assertEquals(response.status, 201);
  const text = await response.text();
  const body = JSON.parse(text);
  assert(typeof body.snapshot_id === "string" && body.snapshot_id.length === 36, "snapshot id returned");
  assert(!text.includes("Magnesium") && !text.includes("Warfarin"), "response never echoes the payload");
  assert(!logs.includes("Magnesium") && !logs.includes("Warfarin"), "logs never carry the payload");

  const row = s.store.rows.get(s.live.connection_id)!;
  assert(!JSON.stringify(row).includes("Warfarin"), "no plaintext in the stored row");
  assertEquals(row.user_id, USER_A);
  assertEquals(row.format, "pharmaguide-brief-markdown/v1");
  assertEquals(row.scope, FULL_SCOPE);
  assertEquals(row.stack_revision, "rev-7");
  assertEquals(row.key_version, 1);
  assertEquals(row.generated_at, NOW.toISOString());
  assertEquals(fromPgBytea(row.nonce).length, 12, "96-bit nonce");

  const sealed = { ciphertext: fromPgBytea(row.ciphertext), nonce: fromPgBytea(row.nonce), keyVersion: row.key_version };
  const plain = await decryptSnapshot(s.keyring, sealed, { connectionId: s.live.connection_id, userId: USER_A });
  assertEquals(plain, PAYLOAD);

  let refused = false;
  try {
    await decryptSnapshot(s.keyring, sealed, { connectionId: crypto.randomUUID(), userId: USER_A });
  } catch {
    refused = true;
  }
  assert(refused, "a ciphertext moved to another connection does not decrypt");
});

Deno.test("re-sharing replaces the connection's single snapshot with a fresh nonce", async () => {
  const s = await setup();
  const token = await appToken(s);
  await s.handler(request("POST", token, share(s.live.connection_id)));
  const first = s.store.rows.get(s.live.connection_id)!;
  await s.handler(request("POST", token, share(s.live.connection_id, { payload: "# Updated" })));
  assertEquals(s.store.rows.size, 1);
  const second = s.store.rows.get(s.live.connection_id)!;
  assert(second.nonce !== first.nonce, "nonce never reused");
  assert(second.snapshot_id !== first.snapshot_id, "a re-share is a new snapshot");
});

Deno.test("format, scope and payload are validated", async () => {
  const s = await setup();
  const token = await appToken(s);
  const bad: Array<[Record<string, unknown>, number]> = [
    [{ format: "text/plain" }, 400],
    [{ scope: { ...FULL_SCOPE, conditions: true } }, 400],
    [{ scope: { ...FULL_SCOPE, profile: "yes" } }, 400],
    [{ scope: [] }, 400],
    [{ payload: "" }, 400],
    [{ payload: 42 }, 400],
    [{ connection_id: "not-a-uuid" }, 400],
    [{ stack_revision: "x".repeat(129) }, 400],
    [{ payload: "a".repeat(64 * 1024 + 1) }, 413],
  ];
  for (const [override, status] of bad) {
    const response = await s.handler(request("POST", token, share(s.live.connection_id, override)));
    assertEquals(response.status, status, JSON.stringify(override).slice(0, 60));
  }
  assertEquals((await s.handler(request("POST", token, "{not json"))).status, 400);
  const exact = await s.handler(request("POST", token, share(s.live.connection_id, { payload: "a".repeat(64 * 1024) })));
  assertEquals(exact.status, 201, "64 KB exactly is allowed");
  const partial = await s.handler(request("POST", token, share(s.live.connection_id, { scope: { supplement_names: true } })));
  assertEquals(partial.status, 201);
  assertEquals(s.store.rows.get(s.live.connection_id)!.scope, {
    supplement_names: true,
    supplement_amounts: false,
    supplement_schedule: false,
    medication_names: false,
    medication_schedule: false,
    profile: false,
    findings: false,
  }, "missing categories are stored as not shared");
});

Deno.test("DELETE removes one connection's snapshot or all of the user's", async () => {
  const s = await setup();
  const token = await appToken(s);
  await s.handler(request("POST", token, share(s.live.connection_id)));
  const one = await s.handler(request("DELETE", token, { connection_id: s.live.connection_id }));
  assertEquals(one.status, 204);
  assertEquals(s.store.rows.size, 0);
  assertEquals(s.store.deletes[0], { connectionId: s.live.connection_id, userId: USER_A });
  const all = await s.handler(request("DELETE", token, { all: true }));
  assertEquals(all.status, 204);
  assertEquals(s.store.deletes[1], { connectionId: null, userId: USER_A }, "all = only the caller's own rows");
  for (const body of [{}, { all: false }, { all: true, connection_id: s.live.connection_id }, { connection_id: "x" }]) {
    assertEquals((await s.handler(request("DELETE", token, body))).status, 400, JSON.stringify(body));
  }
  assertEquals((await s.handler(request("GET", token, ""))).status, 405);
});

Deno.test("keyring: the newest configured version encrypts; an unknown version never decrypts", async () => {
  const both = await keyringFromEnv((n) => ({ AI_SHARE_SNAPSHOT_KEY_V1: KEY_V1, AI_SHARE_SNAPSHOT_KEY_V2: KEY_V2 } as Record<string, string>)[n]);
  assertEquals(both.current, 2);
  const onlyV1 = await keyringFromEnv((n) => ({ AI_SHARE_SNAPSHOT_KEY_V1: KEY_V1 } as Record<string, string>)[n]);
  let error: unknown;
  try {
    await decryptSnapshot(onlyV1, { ciphertext: new Uint8Array(32), nonce: new Uint8Array(12), keyVersion: 2 }, {
      connectionId: "c",
      userId: "u",
    });
  } catch (e) {
    error = e;
  }
  assert(error instanceof SnapshotKeyError, "unknown key version is a key error");
  let missing: unknown;
  try {
    await keyringFromEnv(() => undefined);
  } catch (e) {
    missing = e;
  }
  assert(missing instanceof SnapshotKeyError, "no key configured fails closed");
  let short: unknown;
  try {
    await keyringFromEnv((n) => (n === "AI_SHARE_SNAPSHOT_KEY_V1" ? btoa("too short") : undefined));
  } catch (e) {
    short = e;
  }
  assert(short instanceof SnapshotKeyError, "a key that is not 32 bytes fails closed");
  assertEquals(toPgBytea(new Uint8Array([0, 15, 255])), "\\x000fff");
  assertEquals(Array.from(fromPgBytea("\\x000fff")), [0, 15, 255]);
});

Deno.test("writes are rate limited per user", async () => {
  const s = await setup(undefined, new RateLimiter(2, 0));
  const token = await appToken(s);
  assertEquals((await s.handler(request("POST", token, share(s.live.connection_id)))).status, 201);
  assertEquals((await s.handler(request("DELETE", token, { all: true }))).status, 204);
  const limited = await s.handler(request("POST", token, share(s.live.connection_id)));
  assertEquals(limited.status, 429);
  assertEquals(limited.headers.get("retry-after"), "60");
});

Deno.test("delayed upload preserves report generation time and detects intervening supplement changes", async () => {
  const s = await setup();
  const generatedAt = "2026-10-12T11:00:00.000Z";
  const response = await s.handler(request("POST", await appToken(s), share(s.live.connection_id, {
    generated_at: generatedAt,
  })));
  assertEquals(response.status, 201);
  const row = s.store.rows.get(s.live.connection_id)!;
  assertEquals(row.generated_at, generatedAt, "upload receipt time must not replace report creation");
  assertEquals(row.expires_at, new Date(NOW.getTime() + 24 * HOUR).toISOString(), "TTL still begins at upload");
  const personal = await harness({ connections: [s.live] });
  personal.snapshots.rows.push(row);
  personal.snapshots.stackUpdates[USER_A] = ["2026-10-12T11:30:00.000Z"];
  const token = await sign(personal.key, claimsFor(USER_A, CLAUDE));
  const read = await personal.handler(rpc(token, "tools/call", { name: "get_my_stack_snapshot" }));
  assertEquals((await read.json()).result.structuredContent.data.stale, true);
});

Deno.test("a snapshot requires an explicit valid generation timestamp no later than receipt", async () => {
  const s = await setup();
  const token = await appToken(s);
  for (const generated_at of [undefined, null, "not a date", "2026-10-12", "2026-10-12T12:00:01.000Z", 12]) {
    const response = await s.handler(request("POST", token, share(s.live.connection_id, { generated_at })));
    assertEquals(response.status, 400, `invalid generation time ${generated_at}`);
  }
  assertEquals(s.store.rows.size, 0);
});

Deno.test("production containment denies new snapshots but preserves authenticated purge", async () => {
  const s = await setup(undefined, undefined, createProductionHandler);
  const token = await appToken(s);
  const upload = await s.handler(request("POST", token, share(s.live.connection_id)));
  assertEquals(upload.status, 503);
  const message = (await upload.json()).error;
  assertEquals(message.includes("Personal connections and snapshot sharing are not enabled"), true);
  assertEquals(message.includes("https://mcp.pharmaguide.io/public"), true);
  assertEquals(/try again|reconnect/i.test(message), false);
  assertEquals(s.store.rows.size, 0, "no sensitive snapshot stored");
  const denied = await s.handler(request("DELETE", null, { all: true }));
  assertEquals(denied.status, 401, "purge still requires app authentication");
  const deleted = await s.handler(request("DELETE", token, { connection_id: s.live.connection_id }));
  assertEquals(deleted.status, 204);
  const signedOut = await s.handler(request("DELETE", token, { all: true }));
  assertEquals(signedOut.status, 204);
  assertEquals(s.store.deletes, [
    { connectionId: s.live.connection_id, userId: USER_A },
    { connectionId: null, userId: USER_A },
  ]);
});

Deno.test("enabled production preserves authenticated scoped upload and revocation", async () => {
  const s = await setup(undefined, undefined, deps => createProductionHandler(deps, true));
  assertEquals((await s.handler(request("POST", null, share(s.live.connection_id)))).status, 401);
  assertEquals(s.store.rows.size, 0);
  const token = await appToken(s);
  assertEquals((await s.handler(request("POST", token, share(s.live.connection_id)))).status, 201);
  assertEquals(s.store.rows.size, 1);
  s.live.status = "revoked";
  assertEquals((await s.handler(request("POST", token, share(s.live.connection_id)))).status, 403);
  assertEquals((await s.handler(request("DELETE", token, {connection_id: s.live.connection_id}))).status, 204);
  assertEquals(s.store.rows.size, 0);
});

Deno.test("durable WorkOS connection does not make its shared snapshot permanent", async () => {
  const c = connection({expires_at: null, oauth_issuer: "https://issuer.authkit.app", consent_id: "app_consent_durable"});
  const s = await setup([c]);
  const response = await s.handler(request("POST", await appToken(s), share(c.connection_id, {ttl_hours: 48})));
  assertEquals(response.status, 201);
  assertEquals((await response.json()).expires_at, new Date(NOW.getTime() + 48 * HOUR).toISOString());
  c.status = "revoked";
  assertEquals((await s.handler(request("POST", await appToken(s), share(c.connection_id)))).status, 403);
});

Deno.test("snapshot scope wire keys match the actual Dart serializer", async () => {
  const source = await Deno.readTextFile(new URL("../../../lib/services/sharing/ai_share_scope.dart", import.meta.url));
  const serializer = source.split("Map<String, bool> toJson() => {")[1]?.split("};")[0];
  assert(typeof serializer === "string", "Dart wire serializer must be inspected when its shape changes");
  const keys = [...serializer.matchAll(/'([a-z_]+)':/g)].map(match => match[1]).sort();
  assertEquals(keys, [...SCOPE_KEYS].sort());
  const scope = Object.fromEntries(keys.map(key => [key, key !== "supplement_schedule"]));
  const normalized = normalizeScope(scope);
  for (const key of keys) assertEquals(normalized[key], scope[key]);
  for (const invalid of [{supplementNames: true}, {supplement_schedule: true}]) {
    let rejected = false;
    try { normalizeScope(invalid); } catch { rejected = true; }
    assert(rejected, "wrong wire format and retired supplement free-text dose must be refused");
  }
});
