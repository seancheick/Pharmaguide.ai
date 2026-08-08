const UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const MAX_REQUEST_BYTES = 1_024;

type JsonObject = Record<string, unknown>;

function isObject(value: unknown): value is JsonObject {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}

export async function parseReleaseDispatchRequest(request: Request): Promise<string> {
  const text = await request.text();
  if (new TextEncoder().encode(text).byteLength > MAX_REQUEST_BYTES) {
    throw new Error("request too large");
  }
  const body: unknown = JSON.parse(text);
  if (!isObject(body) || Object.keys(body).length !== 1 || !("release_id" in body)) {
    throw new Error("invalid request");
  }
  const releaseId = body.release_id;
  if (typeof releaseId !== "string" || !UUID_PATTERN.test(releaseId)) {
    throw new Error("invalid release id");
  }
  return releaseId.toLowerCase();
}

export async function constantTimeEquals(
  expected: string,
  actual: string | null,
): Promise<boolean> {
  if (actual === null) return false;
  const encode = new TextEncoder();
  const [expectedHash, actualHash] = await Promise.all([
    crypto.subtle.digest("SHA-256", encode.encode(expected)),
    crypto.subtle.digest("SHA-256", encode.encode(actual)),
  ]);
  const a = new Uint8Array(expectedHash);
  const b = new Uint8Array(actualHash);
  let difference = a.length ^ b.length;
  for (let index = 0; index < Math.max(a.length, b.length); index++) {
    difference |= (a[index] ?? 0) ^ (b[index] ?? 0);
  }
  return difference === 0;
}

export function buildSafetyAlertNotification({
  token,
  alertId,
  revision,
}: {
  token: string;
  alertId: string;
  revision: number;
}) {
  return {
    message: {
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
    },
  };
}
