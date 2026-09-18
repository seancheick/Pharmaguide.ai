import { createClient } from "npm:@supabase/supabase-js@2.110.7";

import { resolveSupabaseAdminKey } from "../_shared/supabase_server_keys.ts";

import { parseClaimedNotifications } from "./claim.ts";
import { renderSubmissionNotificationEmail } from "./email.ts";

const CLAIM_LIMIT = 25;
const DEFAULT_FROM = "PharmaGuide Reviews <submissions@pharmaguide.io>";

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json; charset=utf-8" },
  });
}

// Matches cleanup-product-submissions/index.ts's constant-time compare —
// duplicated rather than shared, since both are small and independent.
function secretsMatch(left: string, right: string): boolean {
  const leftBytes = new TextEncoder().encode(left);
  const rightBytes = new TextEncoder().encode(right);
  if (leftBytes.length !== rightBytes.length) return false;
  let difference = 0;
  for (let index = 0; index < leftBytes.length; index++) {
    difference |= leftBytes[index] ^ rightBytes[index];
  }
  return difference === 0;
}

function audit(
  outcome: string,
  claimed: number,
  sent: number,
  failed: number,
): void {
  console.info(JSON.stringify({
    event: "product_submission_admin_notify",
    outcome,
    claimed_count: claimed,
    sent_count: sent,
    failed_count: failed,
  }));
}

async function sendViaResend(
  resendApiKey: string,
  from: string,
  to: string,
  submissionId: string,
  rendered: { subject: string; text: string; html: string },
): Promise<{ ok: true; id: string | null } | { ok: false; error: string }> {
  let response: Response;
  try {
    response = await fetch("https://api.resend.com/emails", {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${resendApiKey}`,
        "Content-Type": "application/json",
        // Prevents a retried drain (this run or a later one) from sending
        // the same submission's email twice if Resend already accepted it
        // but the response was lost before we recorded success.
        "Idempotency-Key": `new-product-submission/${submissionId}`,
      },
      body: JSON.stringify({
        from,
        to: [to],
        subject: rendered.subject,
        text: rendered.text,
        html: rendered.html,
      }),
    });
  } catch (error) {
    return { ok: false, error: `resend request failed: ${String(error)}` };
  }
  if (!response.ok) {
    let bodyText = "";
    try {
      bodyText = await response.text();
    } catch {
      // best-effort only
    }
    return {
      ok: false,
      error: `resend returned ${response.status}: ${bodyText.slice(0, 500)}`,
    };
  }
  let id: string | null = null;
  try {
    const parsed = await response.json();
    if (parsed && typeof parsed === "object" && typeof parsed.id === "string") {
      id = parsed.id;
    }
  } catch {
    // best-effort only; delivery already succeeded per the 2xx status
  }
  return { ok: true, id };
}

Deno.serve(async (request: Request): Promise<Response> => {
  if (request.method !== "POST") {
    return json({ error: "Method not allowed" }, 405);
  }

  const configuredSecret = Deno.env.get("PRODUCT_SUBMISSION_NOTIFY_SECRET");
  const suppliedSecret = request.headers.get("x-notify-secret") ?? "";
  if (
    !configuredSecret || !suppliedSecret ||
    !secretsMatch(configuredSecret, suppliedSecret)
  ) {
    audit("unauthorized", 0, 0, 0);
    return json({ error: "Authentication required" }, 401);
  }

  const resendApiKey = Deno.env.get("RESEND_API_KEY");
  const adminEmail = Deno.env.get("PRODUCT_SUBMISSION_ADMIN_EMAIL");
  const fromAddress = Deno.env.get("PRODUCT_SUBMISSION_NOTIFY_FROM") ??
    DEFAULT_FROM;
  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  let adminKey: string | undefined;
  try {
    adminKey = resolveSupabaseAdminKey();
  } catch {
    adminKey = undefined;
  }
  if (!resendApiKey || !adminEmail || !supabaseUrl || !adminKey) {
    audit("configuration_error", 0, 0, 0);
    return json({ error: "Notification service unavailable" }, 500);
  }

  const admin = createClient(supabaseUrl, adminKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  const { data: claimedRows, error: claimError } = await admin.rpc(
    "claim_admin_submission_notifications",
    { p_limit: CLAIM_LIMIT },
  );
  if (claimError) {
    audit("claim_failed", 0, 0, 0);
    return json({ error: "Notification service unavailable" }, 500);
  }

  let claimed;
  try {
    claimed = parseClaimedNotifications(claimedRows);
  } catch {
    audit("invalid_claim", 0, 0, 0);
    return json({ error: "Notification service unavailable" }, 500);
  }

  let sentCount = 0;
  let failedCount = 0;
  for (const notification of claimed) {
    const rendered = renderSubmissionNotificationEmail({
      submissionId: notification.submissionId,
      kind: notification.kind,
      normalizedUpc: notification.normalizedUpc,
      displayName: notification.displayName,
      submittedAt: notification.submittedAt,
      isResubmission: notification.isResubmission,
      photoCount: notification.photoCount,
      extractionConfidence: notification.extractionConfidence,
    });
    const result = await sendViaResend(
      resendApiKey,
      fromAddress,
      adminEmail,
      notification.submissionId,
      rendered,
    );
    if (result.ok) {
      sentCount++;
      await admin.rpc("record_admin_submission_notification_result", {
        p_notification_id: notification.notificationId,
        p_success: true,
        p_resend_email_id: result.id,
        p_error: null,
      });
    } else {
      failedCount++;
      console.error(JSON.stringify({
        event: "product_submission_admin_notify_send_failed",
        submission_id: notification.submissionId,
        message: result.error,
      }));
      await admin.rpc("record_admin_submission_notification_result", {
        p_notification_id: notification.notificationId,
        p_success: false,
        p_resend_email_id: null,
        p_error: result.error.slice(0, 500),
      });
    }
  }

  const outcome = failedCount === 0 ? "success" : "partial";
  audit(outcome, claimed.length, sentCount, failedCount);
  return json({
    claimed_count: claimed.length,
    sent_count: sentCount,
    failed_count: failedCount,
  });
});
