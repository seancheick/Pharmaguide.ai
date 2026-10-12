// S2: a token minted for another MCP resource on the same authorization
// server is never accepted here, and one connection never reads through
// another.
//
// Staging checks that a unit test cannot make (README "Gate"):
//   - Register a second (attacker) MCP resource and client against the staging
//     authorization server, complete the flow with resource=<attacker URL>, and
//     replay the access token here: expect 401.
//   - Repeat after a refresh_token grant, and with a DCR-registered client:
//     the hook must stamp aud on refreshed tokens too, expect 401 for the
//     attacker audience and 200 only for this server's audience.
//   - Confirm supabase/auth#2610 status: if Auth starts honouring `resource`,
//     re-run this list before relying on it.
import {
  assertEquals,
  ATTACKER_AUDIENCE,
  AUDIENCE,
  body,
  callSupplements,
  CHATGPT,
  CLAUDE,
  claimsFor,
  connection,
  harness,
  sign,
  USER_A,
} from "./test_support.ts";

Deno.test("a token stamped for an attacker resource is rejected", async () => {
  const h = await harness();
  const claims = { ...claimsFor(USER_A, CLAUDE), aud: ATTACKER_AUDIENCE };
  const response = await h.handler(callSupplements(await sign(h.key, claims)));
  assertEquals(response.status, 401, "attacker audience");
  assertEquals(h.log.entries.length, 0, "nothing logged");
});

Deno.test("an audience that only starts with this server's URL is rejected", async () => {
  const h = await harness();
  for (const aud of [`${AUDIENCE}-evil`, `${AUDIENCE}/../mcp-public`, AUDIENCE.toUpperCase()]) {
    const response = await h.handler(callSupplements(await sign(h.key, { ...claimsFor(USER_A, CLAUDE), aud })));
    assertEquals(response.status, 401, aud);
  }
});

Deno.test("only this server's audience is accepted", async () => {
  const h = await harness();
  const response = await h.handler(callSupplements(await sign(h.key, claimsFor(USER_A, CLAUDE))));
  assertEquals(response.status, 200, "own audience");
});

Deno.test("connection X never reads through connection Y", async () => {
  // Same user, two assistants: supplements granted to Claude only.
  const h = await harness({
    connections: [
      connection({ client_id: CLAUDE, scope: { categories: ["supplements"] } }),
      connection({ client_id: CHATGPT, scope: { categories: [] } }),
    ],
  });
  const chatgpt = await h.handler(callSupplements(await sign(h.key, claimsFor(USER_A, CHATGPT))));
  assertEquals(chatgpt.status, 403, "ChatGPT's connection grants nothing");
  assertEquals(h.stacks.requestedUsers.length, 0, "no read through Claude's grant");

  const claude = await h.handler(callSupplements(await sign(h.key, claimsFor(USER_A, CLAUDE))));
  assertEquals(claude.status, 200, "Claude's own grant");
  const logged = h.log.entries.map((e) => e.connectionId);
  assertEquals(logged, [h.connections.rows[0].connection_id], "logged against Claude's connection only");
});

Deno.test("a session bound to connection X cannot be used for connection Y's client", async () => {
  const x = connection({ client_id: CLAUDE, session_id: "session-x" });
  const h = await harness({ connections: [x, connection({ client_id: CHATGPT, session_id: "session-y" })] });
  // A token for ChatGPT that carries Claude's session id finds no ChatGPT row
  // for that session and ChatGPT's own row is bound to another session.
  const response = await h.handler(callSupplements(await sign(h.key, claimsFor(USER_A, CHATGPT, "session-x"))));
  assertEquals(response.status, 403, "cross-connection session");
  assertEquals((await body(response)).error.code, -32003, "gate error");
});
