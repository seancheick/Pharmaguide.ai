// get_my_stack_snapshot (ADR-009 Phase 2): S10 gate, expiry, staleness, key
// versions, connection binding.
import { keyringFromEnv, sealSnapshotRow, type SnapshotRow } from "../_shared/snapshot_crypto.ts";
import { SNAPSHOT_NEXT_STEP, TOOLS } from "./index.ts";
import {
  assert,
  assertEquals,
  body,
  CHATGPT,
  claimsFor,
  CLAUDE,
  connection,
  harness,
  rpc,
  sign,
  TEST_KEYRING_ENV,
  USER_A,
  USER_B,
} from "./test_support.ts";

const PAYLOAD = "# PharmaGuide brief\n\n- Magnesium Glycinate\n- Warfarin 5 mg (medication)\n";
const SCOPE = {
  supplement_names: true,
  supplement_amounts: false,
  supplement_schedule: false,
  medication_names: true,
  medication_schedule: false,
  profile: false,
  findings: true,
};

async function sealed(
  connectionId: string,
  userId: string,
  overrides: Partial<{ payload: string; generatedAt: Date; expiresAt: Date; env: Record<string, string> }> = {},
): Promise<SnapshotRow> {
  const keyring = await keyringFromEnv((n) => (overrides.env ?? TEST_KEYRING_ENV)[n]);
  return await sealSnapshotRow(keyring, {
    snapshotId: crypto.randomUUID(),
    connectionId,
    userId,
    format: "pharmaguide-brief-markdown/v1",
    scope: SCOPE,
    stackRevision: "rev-1",
    payload: overrides.payload ?? PAYLOAD,
    generatedAt: overrides.generatedAt ?? new Date("2026-10-12T10:00:00Z"),
    expiresAt: overrides.expiresAt ?? new Date("2026-10-13T10:00:00Z"),
  });
}

function callSnapshot(token: string | null): Request {
  return rpc(token, "tools/call", { name: "get_my_stack_snapshot", arguments: {} });
}

Deno.test("tools/list offers get_my_stack_snapshot as read-only", () => {
  const tool = TOOLS.find((t) => t.name === "get_my_stack_snapshot");
  assert(tool, "tool listed");
  assertEquals(tool!.annotations.readOnlyHint, true);
});

Deno.test("returns the decrypted share with scope, times and a fresh stale flag", async () => {
  const live = connection();
  const h = await harness({ connections: [live] });
  h.snapshots.rows.push(await sealed(live.connection_id, USER_A));
  h.snapshots.stackUpdates[USER_A] = ["2026-10-12T09:00:00Z"]; // before generated_at
  const token = await sign(h.key, claimsFor(USER_A, CLAUDE));
  const response = await h.handler(callSnapshot(token));
  assertEquals(response.status, 200);
  const result = (await body(response)).result;
  assertEquals(result.isError, false);
  const out = result.structuredContent;
  assertEquals(out.data.found, true);
  assertEquals(out.data.payload, PAYLOAD);
  assertEquals(out.data.format, "pharmaguide-brief-markdown/v1");
  assertEquals(out.data.scope, SCOPE);
  assertEquals(out.data.generated_at, "2026-10-12T10:00:00.000Z");
  assertEquals(out.data.expires_at, "2026-10-13T10:00:00.000Z");
  assertEquals(out.data.stale, false);
  assertEquals(out.next_step, SNAPSHOT_NEXT_STEP);
  assert(SNAPSHOT_NEXT_STEP.includes("medications") && SNAPSHOT_NEXT_STEP.includes("profile"),
    "next_step says medication and profile changes are not detected");
  assertEquals(h.log.entries, [{ connectionId: live.connection_id, tool: "get_my_stack_snapshot" }]);
});

Deno.test("stale is true when a stack row changed after the share was generated", async () => {
  const live = connection();
  const h = await harness({ connections: [live] });
  h.snapshots.rows.push(await sealed(live.connection_id, USER_A));
  h.snapshots.stackUpdates[USER_A] = ["2026-10-12T09:00:00Z", "2026-10-12T11:30:00Z"];
  h.snapshots.stackUpdates[USER_B] = ["2026-10-12T11:59:00Z"];
  const token = await sign(h.key, claimsFor(USER_A, CLAUDE));
  const out = (await body(await h.handler(callSnapshot(token)))).result.structuredContent;
  assertEquals(out.data.stale, true);
  assertEquals(h.snapshots.staleChecks, [{ userId: USER_A, since: "2026-10-12T10:00:00.000Z" }],
    "staleness is read for the verified user only");
});

Deno.test("an expired share is not found, with a plain reason and no payload", async () => {
  const live = connection();
  const h = await harness({ connections: [live] });
  h.snapshots.rows.push(await sealed(live.connection_id, USER_A, { expiresAt: new Date("2026-10-12T11:59:59Z") }));
  const token = await sign(h.key, claimsFor(USER_A, CLAUDE));
  const text = await (await h.handler(callSnapshot(token))).text();
  const out = JSON.parse(text).result.structuredContent;
  assertEquals(out.data.found, false);
  assert(typeof out.data.reason === "string" && out.data.reason.includes("expired"), "says it expired");
  assert(!text.includes("Warfarin"), "no payload");
});

Deno.test("no share for this connection is not found", async () => {
  const h = await harness();
  const token = await sign(h.key, claimsFor(USER_A, CLAUDE));
  const out = (await body(await h.handler(callSnapshot(token)))).result.structuredContent;
  assertEquals(out.data.found, false);
});

Deno.test("an unknown key version is an error that never leaks ciphertext or payload", async () => {
  const live = connection();
  const h = await harness({ connections: [live] });
  const v2Key = btoa(String.fromCharCode(...new Uint8Array(32).fill(7)));
  const row = await sealed(live.connection_id, USER_A, {
    env: { ...TEST_KEYRING_ENV, AI_SHARE_SNAPSHOT_KEY_V2: v2Key },
  });
  assertEquals(row.key_version, 2);
  h.snapshots.rows.push(row);
  const token = await sign(h.key, claimsFor(USER_A, CLAUDE));
  const text = await (await h.handler(callSnapshot(token))).text();
  const result = JSON.parse(text).result;
  assertEquals(result.isError, true);
  assert(!text.includes(row.ciphertext.slice(2, 18)), "no ciphertext");
  assert(!text.includes("Warfarin"), "no payload");
});

Deno.test("a tampered ciphertext is an error, not garbage", async () => {
  const live = connection();
  const h = await harness({ connections: [live] });
  const row = await sealed(live.connection_id, USER_A);
  const last = row.ciphertext.slice(-2) === "00" ? "01" : "00";
  h.snapshots.rows.push({ ...row, ciphertext: row.ciphertext.slice(0, -2) + last });
  const token = await sign(h.key, claimsFor(USER_A, CLAUDE));
  const result = (await body(await h.handler(callSnapshot(token)))).result;
  assertEquals(result.isError, true);
});

Deno.test("a revoked connection is refused before any snapshot read", async () => {
  const revoked = connection({ status: "revoked", revoked_at: "2026-10-12T11:30:00Z" });
  const h = await harness({ connections: [revoked] });
  h.snapshots.rows.push(await sealed(revoked.connection_id, USER_A));
  const token = await sign(h.key, claimsFor(USER_A, CLAUDE));
  const response = await h.handler(callSnapshot(token));
  assertEquals(response.status, 403);
  assertEquals(h.snapshots.reads, [], "no snapshot read");
  assert(!(await response.text()).includes("Warfarin"), "no payload");
});

Deno.test("connection X never reads connection Y's share (same user, other assistant)", async () => {
  const claude = connection({ client_id: CLAUDE });
  const chatgpt = connection({ client_id: CHATGPT });
  const h = await harness({ connections: [claude, chatgpt] });
  h.snapshots.rows.push(await sealed(chatgpt.connection_id, USER_A));
  const token = await sign(h.key, claimsFor(USER_A, CLAUDE));
  const text = await (await h.handler(callSnapshot(token))).text();
  assertEquals(JSON.parse(text).result.structuredContent.data.found, false);
  assert(!text.includes("Warfarin"), "the other assistant's share stays unread");
  assertEquals(h.snapshots.reads, [{ connectionId: claude.connection_id, userId: USER_A }]);
});

Deno.test("a share row moved under another connection does not decrypt", async () => {
  const live = connection();
  const h = await harness({ connections: [live] });
  const foreign = await sealed(crypto.randomUUID(), USER_A);
  h.snapshots.rows.push({ ...foreign, connection_id: live.connection_id });
  const token = await sign(h.key, claimsFor(USER_A, CLAUDE));
  const result = (await body(await h.handler(callSnapshot(token)))).result;
  assertEquals(result.isError, true);
});
