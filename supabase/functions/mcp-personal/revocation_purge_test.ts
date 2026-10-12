// S5: Disconnect and expiry take effect on the next call, and account
// deletion leaves no connection or log rows behind.
//
// Covered elsewhere or on staging:
//   - Cascades are exercised in SQL by scripts/test_ai_connector_rls.sh
//     (deleting the auth user removes ai_connections and mcp_access_log rows).
//   - revokeGrant ending refresh tokens, and the website Disconnect route
//     marking the row revoked, are staging checks (README "Gate").
//   - Snapshot purge belongs to Phase 2 (ai_share_snapshots does not exist yet).
import { GATE_REASONS } from "../_shared/connection_gate.ts";
import { assert, assertEquals, body, callSupplements, CLAUDE, claimsFor, harness, NOW, sign, USER_A } from "./test_support.ts";

const functionsDir = new URL("../", import.meta.url);
const migrationsDir = new URL("../../migrations/", import.meta.url);

Deno.test("a still-unexpired token loses access right after Disconnect", async () => {
  const h = await harness();
  const token = await sign(h.key, claimsFor(USER_A, CLAUDE));
  assertEquals((await h.handler(callSupplements(token))).status, 200, "before");

  // What the website Disconnect route does: status revoked, revoked_at set.
  const row = h.connections.rows[0];
  row.status = "revoked";
  row.revoked_at = NOW.toISOString();

  const after = await h.handler(callSupplements(token));
  assertEquals(after.status, 403, "after");
  assertEquals((await body(after)).error.message, GATE_REASONS.revoked, "reason");
  assertEquals(h.stacks.requestedUsers.length, 1, "only the call before Disconnect read data");
});

Deno.test("a connection that expires mid-session closes on the next call", async () => {
  const h = await harness();
  const token = await sign(h.key, claimsFor(USER_A, CLAUDE));
  assertEquals((await h.handler(callSupplements(token))).status, 200, "before");
  h.connections.rows[0].expires_at = new Date(NOW.getTime() - 1).toISOString();
  assertEquals((await h.handler(callSupplements(token))).status, 403, "after expiry");
});

Deno.test("delete-account removes the user's ai_connections before deleting the user", async () => {
  const source = await Deno.readTextFile(new URL("delete-account/index.ts", functionsDir));
  const purge = source.indexOf('.from("ai_connections")');
  const deleteUser = source.indexOf("auth.admin.deleteUser(");
  assert(purge > 0, "delete-account must delete ai_connections rows");
  assert(purge < deleteUser, "connections are purged before the auth user is deleted");
});

Deno.test("user-JWT functions refuse OAuth client tokens", async () => {
  for (const fn of ["delete-account", "register-push-token"]) {
    const source = await Deno.readTextFile(new URL(`${fn}/index.ts`, functionsDir));
    assert(source.includes("isOAuthClientToken(authorization)"), `${fn} must refuse OAuth client tokens`);
  }
});

Deno.test("connections and their log rows cascade from the auth user", async () => {
  const sql = await Deno.readTextFile(new URL("20261012120100_ai_connections.sql", migrationsDir));
  assert(/user_id uuid NOT NULL REFERENCES auth\.users\(id\) ON DELETE CASCADE/.test(sql), "ai_connections cascade");
  assert(
    /connection_id uuid NOT NULL REFERENCES public\.ai_connections\(connection_id\) ON DELETE CASCADE/.test(sql),
    "mcp_access_log cascade",
  );
});
