import { GoogleAuth } from "npm:google-auth-library@9.15.1";
import { createClient } from "npm:@supabase/supabase-js@2.110.7";

import { resolveSupabaseAdminKey } from "../_shared/supabase_server_keys.ts";
import {
  buildSafetyAlertNotification,
  constantTimeEquals,
  parseReleaseDispatchRequest,
} from "../_shared/safety_alert_dispatch.ts";

const DISPATCH_SECRET_HEADER = "x-safety-alert-dispatch-secret";
const FCM_SCOPE = "https://www.googleapis.com/auth/firebase.messaging";
const MAX_SCOPE_IDS = 200;

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json; charset=utf-8" },
  });
}

function chunks<T>(values: readonly T[], size: number): T[][] {
  const result: T[][] = [];
  for (let index = 0; index < values.length; index += size) {
    result.push(values.slice(index, index + size));
  }
  return result;
}

async function fcmAccessToken(): Promise<{ token: string; projectId: string }> {
  const raw = Deno.env.get("FCM_SERVICE_ACCOUNT_JSON");
  if (!raw) throw new Error("FCM service account is not configured");
  const credentials: unknown = JSON.parse(raw);
  if (!credentials || typeof credentials !== "object" || Array.isArray(credentials)) {
    throw new Error("FCM service account is malformed");
  }
  const projectId = (credentials as Record<string, unknown>).project_id;
  if (typeof projectId !== "string" || !projectId.trim()) {
    throw new Error("FCM service account has no project id");
  }
  const auth = new GoogleAuth({ credentials, scopes: [FCM_SCOPE] });
  const client = await auth.getClient();
  const token = await client.getAccessToken();
  if (!token.token) throw new Error("FCM access token unavailable");
  return { token: token.token, projectId };
}

async function sendFcm(
  accessToken: string,
  projectId: string,
  token: string,
  alertId: string,
  revision: number,
): Promise<{ delivered: boolean; invalidToken: boolean }> {
  const response = await fetch(
    `https://fcm.googleapis.com/v1/projects/${encodeURIComponent(projectId)}/messages:send`,
    {
      method: "POST",
      headers: {
        authorization: `Bearer ${accessToken}`,
        "content-type": "application/json",
      },
      body: JSON.stringify(
        buildSafetyAlertNotification({ token, alertId, revision }),
      ),
    },
  );
  if (response.ok) return { delivered: true, invalidToken: false };
  const body = await response.text();
  return {
    delivered: false,
    invalidToken: response.status === 404 && body.includes("UNREGISTERED"),
  };
}

Deno.serve(async (request: Request): Promise<Response> => {
  if (request.method !== "POST") return json({ error: "Method not allowed" }, 405);
  const expectedSecret = Deno.env.get("SAFETY_ALERT_DISPATCH_SECRET") ?? "";
  if (!expectedSecret || !await constantTimeEquals(expectedSecret, request.headers.get(DISPATCH_SECRET_HEADER))) {
    return json({ error: "Unauthorized" }, 401);
  }

  let releaseId: string;
  try {
    releaseId = await parseReleaseDispatchRequest(request);
  } catch {
    return json({ error: "Invalid request" }, 400);
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const adminKey = resolveSupabaseAdminKey();
  if (!supabaseUrl || !adminKey) return json({ error: "Dispatcher unavailable" }, 500);
  const admin = createClient(supabaseUrl, adminKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  const { data: release, error: releaseError } = await admin
    .from("safety_alert_releases")
    .select("feed_path,is_current")
    .eq("id", releaseId)
    .maybeSingle();
  if (releaseError || !release || release.is_current !== true) {
    return json({ error: "Unknown current release" }, 404);
  }
  const { data: blob, error: downloadError } = await admin.storage
    .from("pharmaguide")
    .download(release.feed_path);
  if (downloadError || !blob) return json({ error: "Release feed unavailable" }, 503);

  let alerts: Array<Record<string, unknown>>;
  try {
    const parsed = JSON.parse(await blob.text()) as { alerts?: unknown };
    if (!Array.isArray(parsed.alerts)) throw new Error("missing alerts");
    alerts = parsed.alerts.filter((alert): alert is Record<string, unknown> =>
      !!alert && typeof alert === "object" && !Array.isArray(alert)
    );
  } catch {
    return json({ error: "Release feed invalid" }, 500);
  }

  let accessToken: string;
  let projectId: string;
  try {
    ({ token: accessToken, projectId } = await fcmAccessToken());
  } catch {
    return json({ error: "Push transport unavailable" }, 503);
  }

  let sent = 0;
  let removed = 0;
  for (const alert of alerts) {
    const alertId = alert.alert_id;
    const revision = alert.revision;
    const resolved = alert.resolved_dsld_ids;
    if (
      typeof alertId !== "string" ||
      typeof revision !== "number" ||
      !Number.isInteger(revision) ||
      !Array.isArray(resolved)
    ) continue;
    const dsldIds = resolved.filter((value): value is string =>
      typeof value === "string" && value.trim().length > 0
    );
    const userIds = new Set<string>();
    for (const ids of chunks(dsldIds, MAX_SCOPE_IDS)) {
      const { data, error } = await admin.from("user_stacks").select("user_id").in("dsld_id", ids);
      if (error) return json({ error: "Target lookup failed" }, 503);
      for (const row of data ?? []) if (typeof row.user_id === "string") userIds.add(row.user_id);
    }
    for (const ids of chunks([...userIds], MAX_SCOPE_IDS)) {
      const { data, error } = await admin
        .from("device_push_tokens")
        .select("id,fcm_token")
        .in("user_id", ids);
      if (error) return json({ error: "Token lookup failed" }, 503);
      for (const row of data ?? []) {
        if (typeof row.fcm_token !== "string" || typeof row.id !== "string") continue;
        const { data: claimed, error: claimError } = await admin.rpc(
          "claim_safety_alert_push_delivery",
          {
            p_alert_id: alertId,
            p_revision: revision,
            p_device_push_token_id: row.id,
            p_release_id: releaseId,
          },
        );
        if (claimError) return json({ error: "Delivery claim failed" }, 503);
        if (claimed !== true) continue;

        const outcome = await sendFcm(accessToken, projectId, row.fcm_token, alertId, revision);
        if (outcome.delivered) {
          const { error: completionError } = await admin.rpc(
            "complete_safety_alert_push_delivery",
            {
              p_alert_id: alertId,
              p_revision: revision,
              p_device_push_token_id: row.id,
            },
          );
          if (completionError) return json({ error: "Delivery completion failed" }, 503);
          sent++;
        } else {
          await admin.rpc("release_safety_alert_push_delivery", {
            p_alert_id: alertId,
            p_revision: revision,
            p_device_push_token_id: row.id,
          });
        }
        if (outcome.invalidToken) {
          await admin.from("device_push_tokens").delete().eq("id", row.id);
          removed++;
        }
      }
    }
  }
  console.info(JSON.stringify({ event: "safety_alert_dispatch", release_id: releaseId, sent, removed }));
  return json({ ok: true, sent, removed });
});
