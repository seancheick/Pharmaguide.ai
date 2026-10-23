// S1: only a verified OAuth client token reaches data, only its own user's
// rows are read, and the OAuth token is never forwarded to the database.
import { isOAuthClientToken, localJwks, TokenRejected, verifyOAuthAccessToken } from "../_shared/oauth_token.ts";
import { postgrestRepositories } from "./index.ts";
import {
  assert,
  assertEquals,
  body,
  callSupplements,
  CLAUDE,
  claimsFor,
  connection,
  harness,
  ISSUER,
  rpc,
  sign,
  signingKey,
  USER_A,
  USER_B,
} from "./test_support.ts";

async function expect401(response: Response, label: string): Promise<void> {
  assertEquals(response.status, 401, label);
  const challenge = response.headers.get("www-authenticate") ?? "";
  assert(
    challenge.startsWith("Bearer ") && challenge.includes('resource_metadata="'),
    `${label}: 401 must carry the RFC 9728 challenge, got "${challenge}"`,
  );
  const json = await body(response);
  assertEquals(json.error?.code, -32001, label);
}

Deno.test("401 without a token carries the resource_metadata challenge", async () => {
  const h = await harness();
  await expect401(await h.handler(rpc(null, "initialize")), "no token");
  assertEquals(h.log.entries.length, 0, "nothing logged");
  assertEquals(h.stacks.requestedUsers.length, 0, "nothing read");
});

Deno.test("protected resource metadata is served without a token", async () => {
  const h = await harness();
  const response = await h.handler(new Request(`${new URL(rpc(null, "x").url).origin}/functions/v1/mcp-personal/oauth-protected-resource`));
  assertEquals(response.status, 200, "metadata status");
  const json = await body(response);
  assertEquals(json.authorization_servers, [ISSUER], "authorization server");
});

Deno.test("a token signed by an unknown key is rejected", async () => {
  const h = await harness();
  const forger = await signingKey("project-key"); // same kid, different key
  await expect401(await h.handler(callSupplements(await sign(forger, claimsFor(USER_A, CLAUDE)))), "forged");
});

Deno.test("a tampered payload fails signature verification", async () => {
  const h = await harness();
  const token = await sign(h.key, claimsFor(USER_A, CLAUDE));
  const [header, , signature] = token.split(".");
  const payload = btoa(JSON.stringify(claimsFor(USER_B, CLAUDE))).replace(/=+$/, "")
    .replace(/\+/g, "-").replace(/\//g, "_");
  await expect401(await h.handler(callSupplements(`${header}.${payload}.${signature}`)), "tampered");
});

Deno.test("an expired token is rejected", async () => {
  const h = await harness();
  const claims = claimsFor(USER_A, CLAUDE);
  claims.exp = (claims.iat as number) + 30; // expired long before NOW
  await expect401(await h.handler(callSupplements(await sign(h.key, claims))), "expired");
});

Deno.test("the default Supabase audience is rejected", async () => {
  const h = await harness();
  const claims = { ...claimsFor(USER_A, CLAUDE), aud: "authenticated" };
  await expect401(await h.handler(callSupplements(await sign(h.key, claims))), "aud authenticated");
});

Deno.test("a token from another issuer is rejected", async () => {
  const h = await harness();
  const claims = { ...claimsFor(USER_A, CLAUDE), iss: "https://other-ref.supabase.co/auth/v1" };
  await expect401(await h.handler(callSupplements(await sign(h.key, claims))), "issuer");
});

Deno.test("an app session token without client_id is rejected", async () => {
  const h = await harness();
  await expect401(await h.handler(callSupplements(await sign(h.key, claimsFor(USER_A, null)))), "no client_id");
});

Deno.test("a token without sub or with another role is rejected", async () => {
  const h = await harness();
  const noSub = claimsFor(USER_A, CLAUDE);
  delete noSub.sub;
  await expect401(await h.handler(callSupplements(await sign(h.key, noSub))), "no sub");
  const serviceRole = { ...claimsFor(USER_A, CLAUDE), role: "service_role" };
  await expect401(await h.handler(callSupplements(await sign(h.key, serviceRole))), "service_role");
});

Deno.test("an HS256 token is refused even with valid-looking claims", async () => {
  const h = await harness();
  const secret = await crypto.subtle.generateKey({ name: "HMAC", hash: "SHA-256" }, true, ["sign"]);
  const { SignJWT } = await import("npm:jose@6.2.12");
  const token = await new SignJWT(claimsFor(USER_A, CLAUDE)).setProtectedHeader({ alg: "HS256", kid: "project-key" })
    .sign(secret);
  await expect401(await h.handler(callSupplements(token)), "HS256");
});

Deno.test("user A's token returns only user A's supplements", async () => {
  const h = await harness({
    connections: [
      connection({ user_id: USER_A, client_id: CLAUDE }),
      connection({ user_id: USER_B, client_id: CLAUDE }),
    ],
  });
  const responseA = await h.handler(callSupplements(await sign(h.key, claimsFor(USER_A, CLAUDE))));
  assertEquals(responseA.status, 200, "A status");
  const names = (await body(responseA)).result.structuredContent.data.supplements.map((s: { name: string }) => s.name);
  assertEquals(names, ["Magnesium Glycinate"], "A sees only A");
  assertEquals(h.stacks.requestedUsers, [USER_A], "read filtered by the verified sub");

  const responseB = await h.handler(callSupplements(await sign(h.key, claimsFor(USER_B, CLAUDE))));
  const namesB = (await body(responseB)).result.structuredContent.data.supplements.map((s: { name: string }) => s.name);
  assertEquals(namesB, ["User B Fish Oil"], "B sees only B");
});

Deno.test("a token for user A cannot use user B's connection", async () => {
  // Only B has a connection; A's valid token must not borrow it.
  const h = await harness({ connections: [connection({ user_id: USER_B, client_id: CLAUDE })] });
  const response = await h.handler(callSupplements(await sign(h.key, claimsFor(USER_A, CLAUDE))));
  assertEquals(response.status, 403, "no connection for A");
  assertEquals(h.stacks.requestedUsers.length, 0, "nothing read");
});

Deno.test("PostgREST reads use the service key and the verified sub, never the OAuth token", async () => {
  const seen: Array<{ url: string; authorization: string | null }> = [];
  const repos = postgrestRepositories("https://project-ref.supabase.co", "sb_secret_test", (input, init) => {
    seen.push({ url: input, authorization: new Headers(init?.headers).get("authorization") });
    return Promise.resolve(new Response("[]", { status: 200 }));
  });
  await repos.stacks.listActiveSupplements(USER_A, 201);
  await repos.connections.findLatest(USER_A, CLAUDE);
  await repos.connections.findBySession(USER_A, CLAUDE, "session-1");
  for (const { url, authorization } of seen) {
    assertEquals(authorization, "Bearer sb_secret_test", "service key only");
    assert(new URL(url).searchParams.get("user_id") === `eq.${USER_A}`, `user filter missing: ${url}`);
  }
  const stackUrl = new URL(seen[0].url);
  assertEquals(stackUrl.searchParams.get("deleted_at"), "is.null", "tombstones excluded");
  assertEquals(stackUrl.searchParams.get("type"), "eq.supplement", "supplements only");
  assertEquals(stackUrl.searchParams.get("select"), "name,dsld_id,ingredient_keys,added_at", "column allowlist");
});

Deno.test("user-JWT functions can recognise an OAuth client token", async () => {
  const key = await signingKey("k");
  assert(isOAuthClientToken(`Bearer ${await sign(key, claimsFor(USER_A, CLAUDE))}`), "client token");
  assert(!isOAuthClientToken(`Bearer ${await sign(key, claimsFor(USER_A, null))}`), "app session");
  assert(!isOAuthClientToken(null), "no header");
  assert(!isOAuthClientToken("Bearer not-a-jwt"), "garbage");
});


Deno.test("WorkOS checks signed claims before UserInfo and returns a consent identity", async () => {
  const key = await signingKey("workos");
  const issuer = "https://auth.example.com";
  const base: import("npm:jose@6.2.12").JWTPayload = { ...claimsFor(USER_A, CLAUDE), iss: issuer, sid: "app_consent_example", scope: "openid profile" };
  delete base.role;
  delete base.session_id;
  let calls = 0;
  let expectedToken = "";
  const config = {
    provider: "workos" as const, issuer, audience: base.aud as string,
    keys: localJwks({ keys: [key.jwk] }), now: () => new Date("2026-10-12T12:00:00Z"),
    allowedClientIds: [CLAUDE],
    userInfoFetch: (input: string | URL | Request, init?: RequestInit) => {
      calls++;
      assertEquals(String(input), `${issuer}/oauth2/userinfo`);
      assertEquals(init?.method, "POST");
      assertEquals(init?.redirect, "error");
      assertEquals(init?.cache, "no-store");
      assertEquals(new Headers(init?.headers).get("authorization"), `Bearer ${expectedToken}`);
      assert(init?.signal, "bounded request");
      return Promise.resolve(Response.json({ sub: USER_A }, { status: 201 }));
    },
  };
  expectedToken = await sign(key, base);
  const verified = await verifyOAuthAccessToken(expectedToken, config);
  assertEquals(verified.provider, "workos");
  assertEquals(verified.sessionId, undefined);
  assert("consentId" in verified, "provider identity");
  assertEquals(verified.consentId, "app_consent_example");
  assertEquals(calls, 1);
  const invalid: Record<string, unknown>[] = [
    { iss: "https://other.example.com" }, { aud: "elsewhere" },
    { aud: [base.aud, "elsewhere"] }, { aud: [base.aud] }, { client_id: "other" }, { client_id: "" },
    { sub: " " }, { sub: undefined }, { sid: undefined }, { sid: "session_wrong" }, { sid: "app_consent_" },
    { sid: "app_consent_" + "x".repeat(256) }, { scope: "profile" }, { scope: ["openid"] },
    { exp: 1 }, { exp: undefined }, { iat: undefined }, { iat: "1" },
    { iat: 9999999999 },
  ];
  for (const patch of invalid) {
    try {
      await verifyOAuthAccessToken(await sign(key, { ...base, ...patch } as import("npm:jose@6.2.12").JWTPayload), config);
      throw new Error(`accepted ${JSON.stringify(patch)}`);
    } catch (error) { assert(error instanceof TokenRejected, String(error)); }
  }
  for (const token of [null, "malformed", await sign(await signingKey("workos"), base)]) {
    try { await verifyOAuthAccessToken(token, config); throw new Error("accepted bad signature"); }
    catch (error) { assert(error instanceof TokenRejected, String(error)); }
  }
  assertEquals(calls, 1, "invalid local claims never reach UserInfo");
});

Deno.test("WorkOS UserInfo fails closed on revoked, redirected, mismatched, malformed and timed out responses", async () => {
  const key = await signingKey("workos");
  const claims = { ...claimsFor(USER_A, CLAUDE), iss: "https://auth.example.com", sid: "app_consent_example", scope: "openid" };
  const token = await sign(key, claims);
  const config = { provider: "workos" as const, issuer: claims.iss, audience: claims.aud as string,
    allowedClientIds: [CLAUDE], keys: localJwks({ keys: [key.jwk] }), now: () => new Date("2026-10-12T12:00:00Z"), userInfoTimeoutMs: 10 };
  const responses = [
    () => Promise.resolve(new Response("", { status: 401 })),
    () => Promise.resolve(new Response("", { status: 302 })),
    () => Promise.resolve(Response.json({ sub: USER_B })),
    () => Promise.resolve(new Response("not json")),
    () => Promise.resolve(Response.json(null)),
    () => Promise.reject(new TypeError("redirect refused")),
    (_input: string | URL | Request, init?: RequestInit) => new Promise<Response>((_resolve, reject) => {
      init?.signal?.addEventListener("abort", () => reject(new Error("aborted")), { once: true });
    }),
  ];
  for (const userInfoFetch of responses) {
    try { await verifyOAuthAccessToken(token, { ...config, userInfoFetch }); throw new Error("accepted UserInfo failure"); }
    catch (error) { assert(error instanceof TokenRejected, String(error)); }
  }
});


Deno.test("WorkOS rechecks the same token each request after consent revocation", async () => {
  const key = await signingKey("workos");
  const claims = { ...claimsFor(USER_A, CLAUDE), iss: "https://auth.example.com", sid: "app_consent_example", scope: "openid" };
  const token = await sign(key, claims);
  let calls = 0;
  const config = { provider: "workos" as const, issuer: claims.iss, audience: claims.aud as string,
    allowedClientIds: [CLAUDE], keys: localJwks({ keys: [key.jwk] }), now: () => new Date("2026-10-12T12:00:00Z"),
    userInfoFetch: () => Promise.resolve(++calls === 1 ? Response.json({ sub: USER_A }, { status: 201 }) : new Response(null, { status: 401 })) };
  await verifyOAuthAccessToken(token, config);
  try { await verifyOAuthAccessToken(token, config); throw new Error("cached revoked grant"); }
  catch (error) { assert(error instanceof TokenRejected, String(error)); }
  assertEquals(calls, 2);
});
