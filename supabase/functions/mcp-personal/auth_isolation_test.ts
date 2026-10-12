// S1: only a verified OAuth client token reaches data, only its own user's
// rows are read, and the OAuth token is never forwarded to the database.
import { isOAuthClientToken } from "../_shared/oauth_token.ts";
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
