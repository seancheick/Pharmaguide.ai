import { assert, assertEquals } from "jsr:@std/assert@1";

import { handleReviewRequest } from "./index.ts";

function bearer(claims: Record<string, unknown>): string {
  const encode = (value: unknown) =>
    btoa(JSON.stringify(value)).replaceAll("+", "-").replaceAll("/", "_")
      .replaceAll("=", "");
  return `Bearer ${encode({ alg: "ES256" })}.${encode(claims)}.c2ln`;
}

async function callWith(authorization: string) {
  const originalFetch = globalThis.fetch;
  const requested: string[] = [];
  globalThis.fetch = (input: string | URL | Request) => {
    requested.push(String(input instanceof Request ? input.url : input));
    return Promise.resolve(
      Response.json({ message: "invalid token" }, { status: 401 }),
    );
  };
  Deno.env.set("SUPABASE_URL", "https://project.supabase.test");
  Deno.env.set("SUPABASE_ANON_KEY", "public-test-key");
  try {
    const response = await handleReviewRequest(
      new Request("https://edge.test/review", {
        method: "POST",
        headers: { authorization },
        body: JSON.stringify({ action: "list" }),
      }),
    );
    await response.body?.cancel();
    return { status: response.status, requested };
  } finally {
    globalThis.fetch = originalFetch;
  }
}

Deno.test({
  name: "an AI assistant token is refused before any network or admin use",
  sanitizeOps: false,
  sanitizeResources: false,
  fn: async () => {
    const { status, requested } = await callWith(
      bearer({
        sub: "reviewer",
        role: "authenticated",
        client_id: "assistant",
      }),
    );
    assertEquals(status, 403);
    assertEquals(requested, []);
  },
});

Deno.test({
  name: "an app session token still reaches user verification",
  sanitizeOps: false,
  sanitizeResources: false,
  fn: async () => {
    const { status, requested } = await callWith(
      bearer({ sub: "reviewer", role: "authenticated" }),
    );
    assertEquals(status, 401);
    assert(requested.some((url) => url.includes("/auth/v1/user")));
  },
});
