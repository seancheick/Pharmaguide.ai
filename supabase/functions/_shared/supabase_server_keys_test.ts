import {
  resolveSupabaseAdminKey,
  resolveSupabasePublicKey,
} from "./supabase_server_keys.ts";

function environment(
  values: Record<string, string>,
): (name: string) => string | undefined {
  return (name) => values[name];
}

Deno.test("prefers a dedicated current secret key", () => {
  const key = resolveSupabaseAdminKey(
    environment({
      SUPABASE_SECRET_KEY: "sb_secret_dedicated",
      SUPABASE_SERVICE_ROLE_KEY: "legacy",
    }),
  );

  if (key !== "sb_secret_dedicated") {
    throw new Error(`unexpected admin key: ${key}`);
  }
});

Deno.test("supports the managed secret-key bundle", () => {
  const key = resolveSupabaseAdminKey(
    environment({
      SUPABASE_SECRET_KEYS: JSON.stringify({
        default: "sb_secret_default",
      }),
      SUPABASE_SERVICE_ROLE_KEY: "legacy",
    }),
  );

  if (key !== "sb_secret_default") {
    throw new Error(`unexpected admin key: ${key}`);
  }
});

Deno.test("retains legacy service-role compatibility", () => {
  const key = resolveSupabaseAdminKey(
    environment({ SUPABASE_SERVICE_ROLE_KEY: "legacy" }),
  );

  if (key !== "legacy") {
    throw new Error(`unexpected admin key: ${key}`);
  }
});

Deno.test("fails closed on a malformed managed secret bundle", () => {
  let rejected = false;
  try {
    resolveSupabaseAdminKey(
      environment({
        SUPABASE_SECRET_KEYS: "{malformed",
        SUPABASE_SERVICE_ROLE_KEY: "legacy",
      }),
    );
  } catch {
    rejected = true;
  }

  if (!rejected) {
    throw new Error("malformed secret-key bundle was accepted");
  }
});

Deno.test("prefers a current publishable key for user-token verification", () => {
  const key = resolveSupabasePublicKey(
    environment({
      SUPABASE_PUBLISHABLE_KEY: "sb_publishable_dedicated",
      SUPABASE_ANON_KEY: "legacy-anon",
    }),
  );

  if (key !== "sb_publishable_dedicated") {
    throw new Error(`unexpected public key: ${key}`);
  }
});

Deno.test("supports the managed publishable-key bundle", () => {
  const key = resolveSupabasePublicKey(
    environment({
      SUPABASE_PUBLISHABLE_KEYS: JSON.stringify({
        default: "sb_publishable_default",
      }),
      SUPABASE_ANON_KEY: "legacy-anon",
    }),
  );

  if (key !== "sb_publishable_default") {
    throw new Error(`unexpected public key: ${key}`);
  }
});
