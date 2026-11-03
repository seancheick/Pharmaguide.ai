const UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const MAX_REQUEST_BYTES = 1_024;

type JsonObject = Record<string, unknown>;

function isObject(value: unknown): value is JsonObject {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}

// Events the server can target from a product alone. Anything else, such as an
// interaction rule that matches on the device against medications the server
// never sees, is left for the app to find when it refreshes the feed.
const PUSHABLE_EVENT_TYPES = new Set(["ingredient_ban", "product_recall"]);

export function isPushableEventType(eventType: unknown): boolean {
  return typeof eventType === "string" && PUSHABLE_EVENT_TYPES.has(eventType);
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
