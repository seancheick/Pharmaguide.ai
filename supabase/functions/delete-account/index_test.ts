import { assert, assertEquals } from "jsr:@std/assert@1";
import { handleAccountDeletion } from "./index.ts";
const UID = "11111111-1111-4111-8111-111111111111";
function fixture(
  options: {
    lookupStatus?: number;
    deleteStatus?: number;
    externalId?: string;
    key?: boolean;
    barrierFailure?: boolean;
    providerThrows?: boolean;
    authDeleteStatus?: number;
  } = {},
) {
  const calls: string[] = [];
  const fetchFn: typeof fetch = async (input, init) => {
    const optionsInit = init as RequestInit | undefined;
    const url = new URL(input instanceof Request ? input.url : String(input));
    const method = optionsInit?.method ?? "GET";
    const path = url.pathname;
    calls.push(method + " " + path);
    const json = (data: unknown, status = 200) =>
      new Response(JSON.stringify(data), {
        status,
        headers: { "content-type": "application/json" },
      });
    if (path === "/auth/v1/user") {
      return json({ id: UID, aud: "authenticated", role: "authenticated" });
    }
    if (path.endsWith("/rpc/begin_ai_connection_revocation")) {
      assertEquals(JSON.parse(String(optionsInit?.body)), {
        p_user_id: UID,
        p_client_id: null,
      });
      return json(
        options.barrierFailure ? { error: "blocked" } : { generation: 3 },
      );
    }
    if (path.endsWith("/rpc/list_product_submission_objects_for_user")) {
      return json([]);
    }
    if (path.startsWith("/user_management/")) {
      assertEquals(url.origin, "https://api.workos.com");
      assertEquals(optionsInit?.redirect, "error");
      assert(optionsInit?.signal instanceof AbortSignal);
      if (options.providerThrows) {
        throw new DOMException("synthetic timeout", "TimeoutError");
      }
    }
    if (path === "/user_management/users/external_id/" + UID) {
      return json({
        id: "user_fixture",
        external_id: options.externalId ?? UID,
      }, options.lookupStatus ?? 200);
    }
    if (path === "/user_management/users/user_fixture") {
      return options.deleteStatus && options.deleteStatus !== 204
        ? json({ error: "provider" }, options.deleteStatus)
        : new Response(null, { status: 204 });
    }
    if (path === "/auth/v1/admin/users/" + UID) {
      return json({ id: UID }, options.authDeleteStatus ?? 200);
    }
    if (path === "/rest/v1/ai_connections") return json([]);
    throw Error("Unexpected mocked endpoint");
  };
  const env: Record<string, string> = {
    SUPABASE_URL: "https://project.invalid",
    SUPABASE_ANON_KEY: "anon-fixture",
    SUPABASE_SERVICE_ROLE_KEY: "service-fixture",
    ...(options.key === false ? {} : { WORKOS_API_KEY: "sk_fixture" }),
  };
  const handler = (request: Request) =>
    handleAccountDeletion(request, (n) => env[n], fetchFn);
  return {
    calls,
    run: () =>
      handler(
        new Request("https://project.invalid/delete", {
          method: "POST",
          headers: {
            authorization: "Bearer app-session",
            "content-type": "application/json",
          },
          body: JSON.stringify({ confirmation: "DELETE" }),
        }),
      ),
  };
}
Deno.test("account deletion blocks local grants before WorkOS cleanup and deletes auth last", async () => {
  const f = fixture();
  assertEquals((await f.run()).status, 200);
  const at = (s: string) => f.calls.findIndex((x) => x.includes(s));
  assert(at("begin_ai_connection_revocation") >= 0);
  assert(at("begin_ai_connection_revocation") < at("/user_management/"));
  assert(at("DELETE /user_management/") < at("/auth/v1/admin/"));
  assert(!f.calls.some((x) => x === "DELETE /rest/v1/ai_connections"));
});
Deno.test("provider failure preserves auth identity for retry without success", async () => {
  const f = fixture({ deleteStatus: 503 });
  assertEquals((await f.run()).status, 500);
  assert(!f.calls.some((x) => x.includes("/auth/v1/admin/")));
  assert(!f.calls.some((x) => x.includes("finish_ai_connection_revocation")));
});
Deno.test("external ID mismatch never deletes provider or app identity", async () => {
  const f = fixture({ externalId: "another-user" });
  assertEquals((await f.run()).status, 500);
  assert(!f.calls.some((x) => x.startsWith("DELETE ")));
});
Deno.test("missing WorkOS configuration fails closed after local barrier", async () => {
  const f = fixture({ key: false });
  assertEquals((await f.run()).status, 500);
  assert(f.calls.some((x) => x.includes("begin_ai_connection_revocation")));
  assert(!f.calls.some((x) => x.includes("/auth/v1/admin/")));
});
Deno.test("provider user already absent is idempotent cleanup", async () => {
  const f = fixture({ lookupStatus: 404 });
  assertEquals((await f.run()).status, 200);
  assert(f.calls.some((x) => x.includes("/auth/v1/admin/")));
});
Deno.test("local barrier error prevents provider and auth deletion", async () => {
  const f = fixture({ barrierFailure: true });
  assertEquals((await f.run()).status, 500);
  assert(
    !f.calls.some((x) =>
      x.includes("/user_management/") || x.includes("/auth/v1/admin/")
    ),
  );
});
Deno.test("provider redirect is rejected without deleting app identity", async () => {
  const f = fixture({ lookupStatus: 302 });
  assertEquals((await f.run()).status, 500);
  assert(!f.calls.some((x) => x.includes("/auth/v1/admin/")));
});
Deno.test("retry after provider failure completes without clearing barrier early", async () => {
  const options = { deleteStatus: 503 };
  const f = fixture(options);
  assertEquals((await f.run()).status, 500);
  options.deleteStatus = 204;
  assertEquals((await f.run()).status, 200);
  assertEquals(
    f.calls.filter((x) => x.includes("begin_ai_connection_revocation")).length,
    2,
  );
  assertEquals(f.calls.filter((x) => x.includes("/auth/v1/admin/")).length, 1);
});
Deno.test("provider unavailable at lookup preserves authenticated retry", async () => {
  const f = fixture({ lookupStatus: 503 });
  assertEquals((await f.run()).status, 500);
  assert(!f.calls.some((x) => x.startsWith("DELETE ")));
});
Deno.test("provider deletion already absent is idempotent", async () => {
  const f = fixture({ deleteStatus: 404 });
  assertEquals((await f.run()).status, 200);
});

Deno.test("provider timeout leaves authenticated retry and local barrier intact", async () => {
  const f = fixture({ providerThrows: true });
  assertEquals((await f.run()).status, 500);
  assert(!f.calls.some((x) => x.includes("/auth/v1/admin/")));
});
Deno.test("auth deletion failure retries already-removed provider safely", async () => {
  const options = { authDeleteStatus: 503, lookupStatus: 200 };
  const f = fixture(options);
  assertEquals((await f.run()).status, 500);
  options.authDeleteStatus = 200;
  options.lookupStatus = 404;
  assertEquals((await f.run()).status, 200);
  assertEquals(
    f.calls.filter((x) => x === "DELETE /user_management/users/user_fixture")
      .length,
    1,
  );
});
