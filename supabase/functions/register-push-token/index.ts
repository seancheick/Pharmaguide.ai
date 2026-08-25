import { createClient } from "npm:@supabase/supabase-js@2.110.7";

import {
  resolveSupabaseAdminKey,
  resolveSupabasePublicKey,
} from "../_shared/supabase_server_keys.ts";

const TOKEN_MAX_LENGTH = 4096;
const PLATFORMS = new Set(["ios", "android"]);

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json; charset=utf-8" },
  });
}

type PushTokenRequest =
  | { action: "register"; token: string; platform: string }
  | { action: "unregister"; token: string };

function parseRequest(value: unknown): PushTokenRequest {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new Error("invalid body");
  }
  const body = value as Record<string, unknown>;
  const token = typeof body.token === "string" ? body.token.trim() : "";
  if (!token || token.length > TOKEN_MAX_LENGTH) {
    throw new Error("invalid token registration");
  }
  if (body.action === "unregister") {
    if (Object.keys(body).length !== 2) throw new Error("invalid body");
    return { action: "unregister", token };
  }
  if (Object.keys(body).length !== 2 || !("token" in body) || !("platform" in body)) {
    throw new Error("invalid body");
  }
  const platform = typeof body.platform === "string" ? body.platform.trim() : "";
  if (!PLATFORMS.has(platform)) {
    throw new Error("invalid token registration");
  }
  return { action: "register", token, platform };
}

Deno.serve(async (request: Request): Promise<Response> => {
  if (request.method !== "POST") return json({ error: "Method not allowed" }, 405);
  const authorization = request.headers.get("authorization");
  if (!authorization?.startsWith("Bearer ")) {
    return json({ error: "Authentication required" }, 401);
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const publicKey = resolveSupabasePublicKey();
  const adminKey = resolveSupabaseAdminKey();
  if (!supabaseUrl || !publicKey || !adminKey) {
    return json({ error: "Push registration unavailable" }, 500);
  }

  const userClient = createClient(supabaseUrl, publicKey, {
    global: { headers: { Authorization: authorization } },
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data: authData, error: authError } = await userClient.auth.getUser();
  if (authError || !authData.user) return json({ error: "Authentication required" }, 401);

  let registration: PushTokenRequest;
  try {
    registration = parseRequest(await request.json());
  } catch {
    return json({ error: "Invalid request" }, 400);
  }

  const admin = createClient(supabaseUrl, adminKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  if (registration.action === "unregister") {
    // Sign-out teardown: only the caller's own row is removable, so a device
    // that already re-registered under another account deletes nothing.
    const { error } = await admin
      .from("device_push_tokens")
      .delete()
      .eq("user_id", authData.user.id)
      .eq("fcm_token", registration.token);
    if (error) {
      console.error(JSON.stringify({ event: "push_token_unregister_failed", code: error.code }));
      return json({ error: "Push registration unavailable" }, 503);
    }
    console.info(JSON.stringify({ event: "push_token_unregistered" }));
    return json({ ok: true });
  }
  // Conflict on the token itself intentionally moves a device from a prior
  // account at login. Direct client DML is revoked, so only this verified-JWT
  // route can make that transfer.
  const { error } = await admin.from("device_push_tokens").upsert(
    {
      user_id: authData.user.id,
      fcm_token: registration.token,
      platform: registration.platform,
      updated_at: new Date().toISOString(),
    },
    { onConflict: "fcm_token" },
  );
  if (error) {
    console.error(JSON.stringify({ event: "push_token_registration_failed", code: error.code }));
    return json({ error: "Push registration unavailable" }, 503);
  }
  console.info(JSON.stringify({ event: "push_token_registered", platform: registration.platform }));
  return json({ ok: true });
});
