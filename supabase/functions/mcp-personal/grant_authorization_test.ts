// S10: a valid, unexpired token is not enough. The call must resolve to an
// active, unexpired connection whose scope grants the tool's category.
import { GATE_REASONS, scopeCategories } from "../_shared/connection_gate.ts";
import { RateLimiter } from "../_shared/rate_limiter.ts";
import {
  assert,
  assertEquals,
  body,
  callSupplements,
  CLAUDE,
  claimsFor,
  connection,
  harness,
  rpc,
  sign,
  USER_A,
} from "./test_support.ts";

async function expect403(response: Response, reason: string, label: string): Promise<void> {
  assertEquals(response.status, 403, label);
  assertEquals((await body(response)).error.message, reason, label);
}

Deno.test("a revoked connection gets 403 with a valid unexpired token", async () => {
  const h = await harness({
    connections: [connection({ status: "revoked", revoked_at: "2026-10-12T11:30:00Z" })],
  });
  await expect403(await h.handler(callSupplements(await sign(h.key, claimsFor(USER_A, CLAUDE)))), GATE_REASONS.revoked, "revoked");
  assertEquals(h.stacks.requestedUsers.length, 0, "nothing read");
});

Deno.test("an active row past expires_at gets 403", async () => {
  const h = await harness({ connections: [connection({ expires_at: "2026-10-12T11:59:59Z" })] });
  await expect403(await h.handler(callSupplements(await sign(h.key, claimsFor(USER_A, CLAUDE)))), GATE_REASONS.expired, "expired by time");
});

Deno.test("status expired and an unparseable expiry both fail closed", async () => {
  for (const row of [connection({ status: "expired" }), connection({ expires_at: "not a date" }), connection({ status: "paused" })]) {
    const h = await harness({ connections: [row] });
    await expect403(await h.handler(callSupplements(await sign(h.key, claimsFor(USER_A, CLAUDE)))), GATE_REASONS.expired, String(row.status));
  }
});

Deno.test("no connection at all gets 403 on every method", async () => {
  const h = await harness({ connections: [] });
  const token = await sign(h.key, claimsFor(USER_A, CLAUDE));
  for (const method of ["initialize", "tools/list", "tools/call"]) {
    await expect403(await h.handler(rpc(token, method)), GATE_REASONS.noConnection, method);
  }
});

Deno.test("scope without supplements denies the tool but not discovery", async () => {
  const h = await harness({ connections: [connection({ scope: { categories: ["catalog"] } })] });
  const token = await sign(h.key, claimsFor(USER_A, CLAUDE));
  assertEquals((await h.handler(rpc(token, "tools/list"))).status, 200, "tools/list");
  await expect403(await h.handler(callSupplements(token)), GATE_REASONS.notInScope, "tools/call");
  assertEquals(h.log.entries.length, 0, "denied calls are not logged as access");
});

Deno.test("malformed scopes grant nothing", () => {
  for (const scope of [{}, null, [], "supplements", { categories: "supplements" }, { categories: [1, null] }]) {
    assertEquals(scopeCategories(scope).size, 0, JSON.stringify(scope));
  }
  assert(scopeCategories({ categories: ["supplements"] }).has("supplements"), "valid scope");
});

Deno.test("the first call binds its session; another session is refused", async () => {
  const h = await harness();
  const first = await h.handler(callSupplements(await sign(h.key, claimsFor(USER_A, CLAUDE, "session-1"))));
  assertEquals(first.status, 200, "first session");
  assertEquals(h.connections.rows[0].session_id, "session-1", "bound");
  const again = await h.handler(callSupplements(await sign(h.key, claimsFor(USER_A, CLAUDE, "session-1"))));
  assertEquals(again.status, 200, "same session again");
  const other = await h.handler(callSupplements(await sign(h.key, claimsFor(USER_A, CLAUDE, "session-2"))));
  await expect403(other, GATE_REASONS.otherSession, "second session");
});

Deno.test("a superseded connection stays closed for its old session", async () => {
  const old = connection({ session_id: "session-old", status: "revoked", revoked_at: "2026-10-12T11:10:00Z", created_at: "2026-10-12T10:00:00Z" });
  const current = connection({ created_at: "2026-10-12T11:10:00Z" });
  const h = await harness({ connections: [old, current] });
  await expect403(await h.handler(callSupplements(await sign(h.key, claimsFor(USER_A, CLAUDE, "session-old")))), GATE_REASONS.revoked, "old session");
  const fresh = await h.handler(callSupplements(await sign(h.key, claimsFor(USER_A, CLAUDE, "session-new"))));
  assertEquals(fresh.status, 200, "new session binds the new connection");
  assertEquals(current.session_id, "session-new", "bound to the new row");
});

Deno.test("calls beyond the per-connection limit get 429", async () => {
  const h = await harness({ limiter: new RateLimiter(2, 0) });
  const token = await sign(h.key, claimsFor(USER_A, CLAUDE));
  assertEquals((await h.handler(callSupplements(token))).status, 200, "1");
  assertEquals((await h.handler(callSupplements(token))).status, 200, "2");
  const limited = await h.handler(callSupplements(token));
  assertEquals(limited.status, 429, "3");
  assertEquals(limited.headers.get("retry-after"), "60", "Retry-After");
});
