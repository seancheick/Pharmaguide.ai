import { localJwks } from "../_shared/oauth_token.ts";
import { createProductionDependencies, createProductionHandler } from "./index.ts";
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
  signingKey,
  TEST_KEYRING_ENV,
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

Deno.test("personal discovery advertises required identity and durable refresh scopes", async () => {
  for (const factory of [undefined, createProductionHandler]) {
    const h = await harness(factory ? {handlerFactory: factory} : {});
    for (const suffix of ['/oauth-protected-resource', '/.well-known/oauth-protected-resource']) {
      const response = await h.handler(new Request(`${AUDIENCE}${suffix}`));
      assertEquals(response.status, 200);
      const metadata = await body(response);
      assertEquals(metadata.resource, AUDIENCE);
      assertEquals(metadata.scopes_supported, ['openid', 'offline_access']);
      assertEquals(response.headers.get('access-control-allow-origin'), '*');
    }
    assertEquals(h.stacks.requestedUsers, []);
    assertEquals(h.log.entries, []);
  }
});

Deno.test("production WorkOS configuration fails closed and never falls back to Supabase OAuth", async () => {
  const valid: Record<string, string> = {
    SUPABASE_URL: "https://project.supabase.co", SUPABASE_SECRET_KEY: "fixture-only",
    WORKOS_ISSUER: "https://issuer.authkit.app",
    MCP_PERSONAL_RESOURCE_URL: "https://mcp.pharmaguide.io/personal",
    MCP_PERSONAL_WEBSITE_URL: "https://pharmaguide.io/oauth/authorize",
    AI_CONNECTOR_TRUSTED_CLIENTS: JSON.stringify([{client_id: "client_fixture", name: "Codex", kind: "codex", redirect_uri: "http://127.0.0.1:12345/callback/fixture"}]),
    AI_SHARE_SNAPSHOT_KEY_V1: btoa("x".repeat(32)),
  };
  for (const key of Object.keys(valid)) {
    const env = {...valid}; delete env[key];
    let rejected = false;
    try { await createProductionDependencies(name => env[name]); } catch { rejected = true; }
    assertEquals(rejected, true, `missing ${key}`);
  }
  for (const [key, value] of [
    ["WORKOS_ISSUER", "http://issuer.authkit.app"],
    ["WORKOS_ISSUER", "https://issuer.authkit.app/path"],
    ["MCP_PERSONAL_RESOURCE_URL", "https://mcp.pharmaguide.io/personal?alternate=1"],
    ["MCP_PERSONAL_WEBSITE_URL", "https://user:password@pharmaguide.io/oauth/authorize"],
    ["AI_CONNECTOR_TRUSTED_CLIENTS", "[]"],
    ["AI_CONNECTOR_TRUSTED_CLIENTS", "malformed JSON"],
    ["AI_CONNECTOR_TRUSTED_CLIENTS", JSON.stringify([...JSON.parse(valid.AI_CONNECTOR_TRUSTED_CLIENTS), ...JSON.parse(valid.AI_CONNECTOR_TRUSTED_CLIENTS)])],
    ["AI_CONNECTOR_TRUSTED_CLIENTS", valid.AI_CONNECTOR_TRUSTED_CLIENTS.replace('"kind":"codex"', '"kind":"unknown"')],
    ["AI_CONNECTOR_TRUSTED_CLIENTS", valid.AI_CONNECTOR_TRUSTED_CLIENTS.replace("127.0.0.1", "attacker.example")],
    ["AI_SHARE_SNAPSHOT_KEY_V1", "not-a-key"],
  ]) {
    let rejected = false;
    try { await createProductionDependencies(name => ({...valid, [key]: value})[name]); } catch { rejected = true; }
    assertEquals(rejected, true, `invalid ${key}`);
  }
  const deps = await createProductionDependencies(name => valid[name]);
  assertEquals(deps.authorizationServer, valid.WORKOS_ISSUER);
  assertEquals(deps.resourceUrl, valid.MCP_PERSONAL_RESOURCE_URL);
  assertEquals(deps.setup?.websiteUrl, valid.MCP_PERSONAL_WEBSITE_URL);
  assertEquals(deps.keyring?.current, 1);
  const handler = createProductionHandler(deps);
  assertEquals((await handler(callSupplements("fixture"))).status, 503);
  const metadata = await handler(new Request(`${deps.resourceUrl}/oauth-protected-resource`));
  assertEquals((await body(metadata)).authorization_servers, [valid.WORKOS_ISSUER]);
});

Deno.test("production composition verifies pinned WorkOS grant and registers only trusted setup metadata", async () => {
  const key = await signingKey("production-wiring");
  const env: Record<string, string> = {
    SUPABASE_URL: "https://project.supabase.co", SUPABASE_SECRET_KEY: "fixture-only",
    WORKOS_ISSUER: "https://issuer.authkit.app", MCP_PERSONAL_RESOURCE_URL: AUDIENCE,
    MCP_PERSONAL_WEBSITE_URL: "https://pharmaguide.io/oauth/authorize",
    AI_CONNECTOR_TRUSTED_CLIENTS: JSON.stringify([{client_id: "client_fixture", name: "Reviewed Codex", kind: "codex", redirect_uri: "http://127.0.0.1:12345/callback/fixture"}]),
    ...TEST_KEYRING_ENV,
  };
  const calls: {url: string; init?: RequestInit}[] = [];
  let live = true;
  const request: typeof fetch = (input, init) => {
    const url = String(input); calls.push({url, init});
    if (url === `${env.WORKOS_ISSUER}/oauth2/userinfo`) {
      assertEquals((init as RequestInit)?.redirect, "error"); assertEquals((init as RequestInit)?.cache, "no-store");
      return Promise.resolve(Response.json(live ? {sub: USER_A} : {error: "revoked"}, {status: live ? 200 : 401}));
    }
    if (url.endsWith("/rpc/read_ai_connection_generation")) return Promise.resolve(Response.json(2));
    if (url.endsWith("/rpc/register_workos_ai_pairing")) return Promise.resolve(Response.json({authorization_id: "opaque-setup-reference"}));
    throw Error("Unexpected network call");
  };
  const deps = await createProductionDependencies(name => env[name], request, (issuer, provider) => {
    assertEquals(issuer, env.WORKOS_ISSUER); assertEquals(provider, "workos");
    return localJwks({keys: [key.jwk]});
  });
  const now = Math.floor(Date.now() / 1000);
  const claims = {iss: env.WORKOS_ISSUER, aud: AUDIENCE, sub: USER_A, client_id: "client_fixture", sid: "app_consent_fixture", iat: now - 1, exp: now + 600, scope: "openid"};
  const raw = await sign(key, claims);
  const token = await deps.verifyToken(raw);
  assertEquals(token.provider, "workos");
  if (token.provider !== "workos") throw Error("wrong verifier");
  const generation = await deps.setup!.generation(token.sub);
  assertEquals(await deps.setup!.register(token, generation), "opaque-setup-reference");
  const registration = JSON.parse(calls.at(-1)!.init!.body as string);
  assertEquals(registration.p_user_id, USER_A);
  assertEquals(registration.p_oauth_issuer, env.WORKOS_ISSUER);
  assertEquals(registration.p_consent_id, "app_consent_fixture");
  assertEquals(registration.p_expected_generation, 2);
  assertEquals(registration.p_client_name, "Reviewed Codex");
  assertEquals(registration.p_redirect_uri, "http://127.0.0.1:12345/callback/fixture");
  assertEquals(JSON.stringify(calls.slice(1)).includes(raw), false, "bearer never reaches database");
  for (const changed of [{aud: ATTACKER_AUDIENCE}, {iss: "https://other.authkit.app"}, {client_id: "client_other"}]) {
    const before = calls.length;
    let denied = false;
    try { await deps.verifyToken(await sign(key, {...claims, ...changed})); } catch { denied = true; }
    assertEquals(denied, true); assertEquals(calls.length, before, "reject before UserInfo or data access");
  }
  live = false;
  let denied = false;
  try { await deps.verifyToken(raw); } catch { denied = true; }
  assertEquals(denied, true, "same token fails after live consent revocation");
  assertEquals(calls.at(-1)!.url, `${env.WORKOS_ISSUER}/oauth2/userinfo`);
});
