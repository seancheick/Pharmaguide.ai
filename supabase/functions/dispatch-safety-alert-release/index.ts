import { createClient } from "npm:@supabase/supabase-js@2.110.7";

import { resolveSupabaseAdminKey } from "../_shared/supabase_server_keys.ts";
import {
  constantTimeEquals,
  parseReleaseDispatchRequest,
} from "../_shared/safety_alert_dispatch.ts";
import {
  buildSafetyAlertMessage,
  fcmAccessToken,
  sendFcmMessage,
  type FcmAccess,
  type FcmSendOutcome,
} from "../_shared/fcm_v1.ts";

const DISPATCH_SECRET_HEADER = "x-safety-alert-dispatch-secret";
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

  let access: FcmAccess;
  try {
    access = await fcmAccessToken();
  } catch {
    return json({ error: "Push transport unavailable" }, 503);
  }

  let sent = 0;
  let removed = 0;
  let failed = 0;
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

        let outcome: FcmSendOutcome;
        try {
          outcome = await sendFcmMessage(
            access,
            buildSafetyAlertMessage({
              token: row.fcm_token,
              alertId,
              revision,
            }),
          );
        } catch (sendError) {
          outcome = {
            delivered: false,
            invalidToken: false,
            retryable: true,
            detail: `network ${String(sendError)}`.slice(0, 200),
          };
        }
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
        } else if (outcome.invalidToken) {
          // Deleting the token cascades its pending delivery row away.
          await admin.from("device_push_tokens").delete().eq("id", row.id);
          removed++;
        } else {
          // Keep the delivery queued: record the failure and back-date the
          // claim so the next dispatch invocation reclaims it immediately.
          const { error: releaseError } = await admin.rpc(
            "release_safety_alert_push_delivery",
            {
              p_alert_id: alertId,
              p_revision: revision,
              p_device_push_token_id: row.id,
              p_error: outcome.detail,
            },
          );
          if (releaseError) {
            console.error(JSON.stringify({
              event: "safety_alert_release_failed",
              message: String(releaseError),
            }));
          }
          failed++;
        }
      }
    }
  }
  console.info(JSON.stringify({
    event: "safety_alert_dispatch",
    release_id: releaseId,
    sent,
    removed,
    failed,
  }));
  // Undelivered rows stay queued for the next invocation; the caller must see
  // the failure so its release pipeline halts instead of reporting success.
  const ok = failed === 0;
  return json({ ok, sent, removed, failed }, ok ? 200 : 502);
});
