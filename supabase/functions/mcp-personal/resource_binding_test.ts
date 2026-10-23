import { createProductionHandler } from "./index.ts";
// Synthetic handler tests exercise audience checks and connection isolation.
// These are not proof of original requested-resource binding by the issuer.
// Production containment below denies all personal reads until S2 is repaired.
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

Deno.test("production containment denies previously issued personal tokens and keeps discovery", async () => {
  const h = await harness({ handlerFactory: createProductionHandler });
  const token = await sign(h.key, claimsFor(USER_A, CLAUDE));
  for (const name of ["get_my_supplements", "get_my_stack_snapshot"]) {
    const request = new Request(AUDIENCE, {
      method: "POST",
      headers: { "content-type": "application/json", authorization: `Bearer ${token}` },
      body: JSON.stringify({ jsonrpc: "2.0", id: 1, method: "tools/call", params: { name } }),
    });
    const response = await h.handler(request);
    assertEquals(response.status, 503, name);
    const message = (await body(response)).error.message;
    assertEquals(message.includes("Personal connections and snapshot sharing are not enabled"), true);
    assertEquals(message.includes("https://mcp.pharmaguide.io/public"), true);
    assertEquals(/try again|reconnect/i.test(message), false);
  }
  assertEquals(h.stacks.requestedUsers, [], "no personal read");
  assertEquals(h.log.entries, [], "no access log write");
  const metadata = await h.handler(new Request(`${AUDIENCE}/oauth-protected-resource`));
  assertEquals(metadata.status, 200);
  assertEquals((await body(metadata)).resource, AUDIENCE);
});

Deno.test("checked-in OAuth server config requires pre-registered clients", async () => {
  const config = await Deno.readTextFile(new URL("../../config.toml", import.meta.url));
  const oauth = config.split("[auth.oauth_server]")[1]?.split(/^\[/m)[0] ?? "";
  assertEquals(/^allow_dynamic_registration\s*=\s*false\s*$/m.test(oauth), true,
    "ADR-009 production config must not accept dynamic client registrations");
});
