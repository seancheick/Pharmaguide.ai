import { createClient } from "npm:@supabase/supabase-js@2.110.7";

import {
  resolveSupabaseAdminKey,
  resolveSupabasePublicKey,
} from "../_shared/supabase_server_keys.ts";
import { removeStorageObjectsOrThrow } from "../_shared/verified_storage_removal.ts";

const DELETE_CONFIRMATION = "DELETE";
const PHOTO_BUCKET = "product-submission-photos";
const MAX_BODY_BYTES = 1024;
const MAX_OBJECTS_PER_DELETE = 1000;
const allowedBodyKeys = new Set(["confirmation"]);

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json; charset=utf-8" },
  });
}

function audit(outcome: string, objectCount = 0): void {
  console.info(
    JSON.stringify({
      event: "account_deletion",
      outcome,
      product_submission_object_count: objectCount,
    }),
  );
}

Deno.serve(async (request: Request): Promise<Response> => {
  if (request.method !== "POST") {
    audit("method_not_allowed");
    return json({ error: "Method not allowed" }, 405);
  }

  const authorization = request.headers.get("authorization");
  if (!authorization?.startsWith("Bearer ")) {
    audit("missing_authentication");
    return json({ error: "Authentication required" }, 401);
  }

  let body: Record<string, unknown>;
  try {
    const bodyText = await request.text();
    if (
      new TextEncoder().encode(bodyText).byteLength > MAX_BODY_BYTES
    ) {
      throw new Error("request too large");
    }
    const parsed: unknown = JSON.parse(bodyText);
    if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) {
      throw new Error("invalid body");
    }
    if (!Object.keys(parsed).every((key) => allowedBodyKeys.has(key))) {
      throw new Error("unknown field");
    }
    body = parsed as Record<string, unknown>;
  } catch {
    audit("invalid_request");
    return json({ error: "Invalid request" }, 400);
  }
  if (body.confirmation !== DELETE_CONFIRMATION) {
    audit("confirmation_required");
    return json({ error: "Type DELETE to confirm" }, 400);
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  let publicKey: string | undefined;
  let adminKey: string | undefined;
  try {
    publicKey = resolveSupabasePublicKey();
    adminKey = resolveSupabaseAdminKey();
  } catch {
    publicKey = undefined;
    adminKey = undefined;
  }
  if (!supabaseUrl || !publicKey || !adminKey) {
    audit("server_configuration_error");
    return json({ error: "Account deletion is unavailable" }, 500);
  }

  const userClient = createClient(supabaseUrl, publicKey, {
    global: { headers: { Authorization: authorization } },
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data: authData, error: authError } = await userClient.auth.getUser();
  if (authError || !authData.user) {
    audit("invalid_authentication");
    return json({ error: "Authentication required" }, 401);
  }

  const admin = createClient(supabaseUrl, adminKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  try {
    // Storage objects must be removed through the Storage API before auth user
    // deletion cascades the manifest rows. Deleting storage.objects with SQL
    // would orphan the underlying files.
    const { data: objectData, error: objectError } = await admin.rpc(
      "list_product_submission_objects_for_user",
      { p_user_id: authData.user.id },
    );
    if (objectError) throw objectError;
    const objectPaths = (objectData ?? [])
      .map((row: { object_path?: unknown }) => row.object_path)
      .filter((path: unknown): path is string =>
        typeof path === "string" && path.length > 0
      );

    for (
      let offset = 0;
      offset < objectPaths.length;
      offset += MAX_OBJECTS_PER_DELETE
    ) {
      const chunk = objectPaths.slice(offset, offset + MAX_OBJECTS_PER_DELETE);
      await removeStorageObjectsOrThrow(
        admin.storage.from(PHOTO_BUCKET),
        chunk,
      );
    }

    const { error: deleteError } = await admin.auth.admin.deleteUser(
      authData.user.id,
    );
    if (deleteError) throw deleteError;
    audit("success", objectPaths.length);
    return json({ deleted: true });
  } catch {
    audit("failed");
    return json(
      {
        error:
          "Account deletion could not be completed. No success was recorded.",
      },
      500,
    );
  }
});
