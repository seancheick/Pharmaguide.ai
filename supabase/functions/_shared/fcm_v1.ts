// Shared FCM HTTP v1 sender.
//
// Extracted from dispatch-safety-alert-release so submission-review pushes
// reuse one credential/transport path. Callers own targeting and delivery
// bookkeeping; this module owns OAuth, the send call, and invalid-token
// classification.

import { GoogleAuth } from "npm:google-auth-library@9.15.1";

const FCM_SCOPE = "https://www.googleapis.com/auth/firebase.messaging";

// Generic-by-design copy: a push may surface on a lock screen, so it never
// carries product names, statuses, or any payload-derived text. The app
// fetches the verified state itself. Exported as constants so the
// safety-invariants suite can assert nothing is interpolated into them.
export const SUBMISSION_UPDATE_TITLE = "PharmaGuide";
export const SUBMISSION_UPDATE_BODY =
  "Your product submission has an update.";

export interface FcmAccess {
  token: string;
  projectId: string;
}

export interface FcmSendOutcome {
  delivered: boolean;
  invalidToken: boolean;
  // Transient transport failure (429/5xx): the delivery must stay queued so a
  // later dispatch retries it. Never true when invalidToken is true.
  retryable: boolean;
  // Short failure description for delivery bookkeeping; empty when delivered.
  detail: string;
}

export type ReadEnvironment = (name: string) => string | undefined;

export async function fcmAccessToken(
  readEnv: ReadEnvironment = Deno.env.get,
): Promise<FcmAccess> {
  const raw = readEnv("FCM_SERVICE_ACCOUNT_JSON");
  if (!raw) throw new Error("FCM service account is not configured");
  const credentials: unknown = JSON.parse(raw);
  if (
    !credentials || typeof credentials !== "object" ||
    Array.isArray(credentials)
  ) {
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

export async function sendFcmMessage(
  access: FcmAccess,
  message: Record<string, unknown>,
  fetcher: typeof fetch = fetch,
): Promise<FcmSendOutcome> {
  const response = await fetcher(
    `https://fcm.googleapis.com/v1/projects/${
      encodeURIComponent(access.projectId)
    }/messages:send`,
    {
      method: "POST",
      headers: {
        authorization: `Bearer ${access.token}`,
        "content-type": "application/json",
      },
      body: JSON.stringify({ message }),
    },
  );
  if (response.ok) {
    return { delivered: true, invalidToken: false, retryable: false, detail: "" };
  }
  const body = await response.text();
  const invalidToken = response.status === 404 && body.includes("UNREGISTERED");
  return {
    delivered: false,
    invalidToken,
    retryable: !invalidToken &&
      (response.status === 429 || response.status >= 500),
    detail: `HTTP ${response.status} ${body}`.slice(0, 200),
  };
}

export function buildSubmissionUpdateMessage({
  token,
  submissionId,
}: {
  token: string;
  submissionId: string;
}): Record<string, unknown> {
  return {
    token,
    notification: {
      title: SUBMISSION_UPDATE_TITLE,
      body: SUBMISSION_UPDATE_BODY,
    },
    data: {
      type: "submission_update",
      submission_id: submissionId,
    },
    android: { priority: "high" },
    apns: { headers: { "apns-priority": "10" } },
  };
}

export function buildSafetyAlertMessage({
  token,
  alertId,
  revision,
}: {
  token: string;
  alertId: string;
  revision: number;
}): Record<string, unknown> {
  return {
    token,
    notification: {
      title: "PharmaGuide safety update",
      body: "A product in your stack has a safety update.",
    },
    data: {
      type: "safety_alert",
      alert_id: alertId,
      revision: String(revision),
    },
    android: { priority: "high" },
    apns: { headers: { "apns-priority": "10" } },
  };
}
