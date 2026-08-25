import {
  createClient,
  type SupabaseClient,
} from "npm:@supabase/supabase-js@2.110.7";

import {
  resolveSupabaseAdminKey,
  resolveSupabasePublicKey,
} from "../_shared/supabase_server_keys.ts";
import {
  buildSubmissionUpdateMessage,
  fcmAccessToken,
  sendFcmMessage,
} from "../_shared/fcm_v1.ts";
import { validateManualLabelV1 } from "./schema.ts";

// Supabase Edge Runtime keeps promises passed to EdgeRuntime.waitUntil alive
// after the response is returned; a bare floating promise may be killed.
declare const EdgeRuntime: {
  waitUntil(promise: Promise<unknown>): void;
} | undefined;

const PHOTO_BUCKET = "product-submission-photos";
const APPROVED_SCHEMA_VERSION = "manual_label_v1";
const APPROVED_PAYLOAD_MAX_BYTES = 512 * 1024;
const SIGNED_URL_TTL_SECONDS = 300;
const MAX_BODY_BYTES = 1_000_000;
const UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const ACTIONS = new Set(["list", "record_extraction", "transition"]);
const REVIEW_STATUSES = new Set([
  "submitted",
  "under_review",
  "approved",
  "rejected",
  "duplicate",
]);
const TRANSITION_STATUSES = new Set([
  "under_review",
  "approved",
  "rejected",
  "duplicate",
]);
const KINDS = new Set(["label_mismatch", "missing_product"]);
const REJECTED_RESOLUTION_CODES = new Set([
  "photo_quality",
  "missing_panel",
  "label_unreadable",
  "not_a_supplement",
  "other",
]);
const DUPLICATE_RESOLUTION_CODES = new Set([
  "already_in_catalog",
  "duplicate_submission",
]);
const RESOLVED_DSLD_PATTERN = /^([0-9]{1,30}|PG_SUB_[0-9A-F]{32})$/;
const STALE_PUSH_RETRY_MS = 2 * 60 * 1000;
const MAX_PUSH_BATCH = 20;
type JsonObject = Record<string, unknown>;

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json; charset=utf-8" },
  });
}

function audit(
  reviewerId: string,
  action: string,
  outcome: string,
  count = 0,
): void {
  console.info(JSON.stringify({
    event: "product_submission_review_access",
    reviewer_id: reviewerId,
    action,
    outcome,
    count,
  }));
}

function isObject(value: unknown): value is JsonObject {
  return value !== null && typeof value === "object" &&
    !Array.isArray(value);
}

function rejectUnknownKeys(
  value: JsonObject,
  allowed: ReadonlySet<string>,
): void {
  if (!Object.keys(value).every((key) => allowed.has(key))) {
    throw new Error("unknown field");
  }
}

function requiredString(
  value: unknown,
  name: string,
  maxLength = 200,
): string {
  if (
    typeof value !== "string" || value.trim().length === 0 ||
    value.length > maxLength
  ) {
    throw new Error(`invalid ${name}`);
  }
  return value.trim();
}

function requiredUuid(value: unknown, name: string): string {
  const normalized = requiredString(value, name, 36).toLowerCase();
  if (!UUID_PATTERN.test(normalized)) throw new Error(`invalid ${name}`);
  return normalized;
}

function validateApprovedPayload(value: unknown): JsonObject {
  return validateManualLabelV1(value);
}

function canonicalJson(value: unknown): string {
  if (
    value === null || typeof value === "boolean" ||
    typeof value === "string"
  ) {
    return JSON.stringify(value);
  }
  if (typeof value === "number") {
    if (!Number.isFinite(value)) throw new Error("non-finite number");
    return JSON.stringify(value);
  }
  if (Array.isArray(value)) {
    return `[${value.map(canonicalJson).join(",")}]`;
  }
  if (isObject(value)) {
    return `{${
      Object.keys(value).sort().map((key) =>
        `${JSON.stringify(key)}:${canonicalJson(value[key])}`
      ).join(",")
    }}`;
  }
  throw new Error("unsupported JSON value");
}

async function sha256Hex(value: string): Promise<string> {
  const digest = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(value),
  );
  return Array.from(new Uint8Array(digest))
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

async function sha256HexBytes(value: ArrayBuffer): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", value);
  return Array.from(new Uint8Array(digest))
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

async function parseBody(request: Request): Promise<JsonObject> {
  const text = await request.text();
  if (new TextEncoder().encode(text).byteLength > MAX_BODY_BYTES) {
    throw new Error("request too large");
  }
  const parsed: unknown = JSON.parse(text);
  if (!isObject(parsed)) throw new Error("invalid body");
  return parsed;
}

// Re-download private evidence through the Storage API and hash the bytes at
// the trusted reviewer boundary. The client-authored manifest and Storage
// metadata are useful upload guards, but neither proves byte identity because
// both originate with the uploader. Extraction and approval therefore bind to
// hashes recomputed here after the submission has become immutable.
async function verifySubmissionPhotoIntegrity(
  admin: SupabaseClient,
  submissionId: string,
): Promise<JsonObject> {
  const { data, error } = await admin
    .from("product_submission_photos")
    .select("photo_id,object_path,byte_size,content_sha256")
    .eq("submission_id", submissionId)
    .order("photo_id", { ascending: true });
  if (error) throw error;

  const verifiedHashes: JsonObject = {};
  for (const raw of (data ?? []) as unknown as JsonObject[]) {
    const photoId = requiredUuid(raw.photo_id, "photo id");
    const objectPath = requiredString(raw.object_path, "object path", 300);
    const expectedHash = requiredString(
      raw.content_sha256,
      "photo hash",
      64,
    );
    if (!/^[0-9a-f]{64}$/.test(expectedHash)) {
      throw new Error("invalid persisted photo hash");
    }
    const byteSize = Number(raw.byte_size);
    if (!Number.isSafeInteger(byteSize) || byteSize <= 0) {
      throw new Error("invalid persisted photo size");
    }

    const { data: blob, error: downloadError } = await admin.storage
      .from(PHOTO_BUCKET)
      .download(objectPath);
    if (downloadError || !blob) {
      throw downloadError ??
        new Error("photo download failed");
    }
    const bytes = await blob.arrayBuffer();
    if (bytes.byteLength !== byteSize) {
      throw new Error("photo byte size mismatch");
    }
    const actualHash = await sha256HexBytes(bytes);
    if (actualHash !== expectedHash) {
      throw new Error("photo content hash mismatch");
    }
    if (verifiedHashes[photoId] !== undefined) {
      throw new Error("duplicate persisted photo id");
    }
    verifiedHashes[photoId] = actualHash;
  }
  return verifiedHashes;
}

// Drain pending submission push deliveries: this submission's rows plus a
// bounded batch of stale pending rows from earlier failed sends. Delivery is
// at-least-once by design — the visible copy is generic, so a duplicate
// nudge is harmless, while a silently lost approval/rejection is not.
async function drainSubmissionPushDeliveries(
  admin: SupabaseClient,
  submissionId: string,
): Promise<void> {
  const staleBefore = new Date(Date.now() - STALE_PUSH_RETRY_MS).toISOString();
  const { data: pending, error: pendingError } = await admin
    .from("product_submission_push_deliveries")
    .select("id,submission_id,user_id,attempts")
    .is("sent_at", null)
    .or(`submission_id.eq.${submissionId},created_at.lt.${staleBefore}`)
    .order("created_at", { ascending: true })
    .limit(MAX_PUSH_BATCH);
  if (pendingError) throw pendingError;
  const rows = (pending ?? []) as unknown as JsonObject[];
  if (rows.length === 0) return;

  let access;
  try {
    access = await fcmAccessToken();
  } catch (credentialError) {
    // No transport: leave every row pending for a later drain.
    console.error(JSON.stringify({
      event: "product_submission_push_transport_unavailable",
      message: String(credentialError),
    }));
    return;
  }

  let sent = 0;
  let removedTokens = 0;
  for (const row of rows) {
    const deliveryId = row.id;
    const userId = typeof row.user_id === "string" ? row.user_id : null;
    const rowSubmissionId = typeof row.submission_id === "string"
      ? row.submission_id
      : submissionId;
    const attempts = Number(row.attempts ?? 0) + 1;
    let lastError: string | null = null;
    let delivered = false;
    try {
      if (!userId) throw new Error("delivery row missing user");
      const { data: tokens, error: tokenError } = await admin
        .from("device_push_tokens")
        .select("id,fcm_token")
        .eq("user_id", userId);
      if (tokenError) throw tokenError;
      const tokenRows = (tokens ?? []) as unknown as JsonObject[];
      // No registered device is a completed delivery: there is nothing to
      // send now, and the app refreshes state on open regardless.
      delivered = true;
      for (const tokenRow of tokenRows) {
        if (
          typeof tokenRow.fcm_token !== "string" ||
          typeof tokenRow.id !== "string"
        ) continue;
        const outcome = await sendFcmMessage(
          access,
          buildSubmissionUpdateMessage({
            token: tokenRow.fcm_token,
            submissionId: rowSubmissionId,
          }),
        );
        if (outcome.invalidToken) {
          await admin.from("device_push_tokens").delete().eq(
            "id",
            tokenRow.id,
          );
          removedTokens++;
        } else if (!outcome.delivered) {
          delivered = false;
          lastError = (outcome.detail || "fcm send failed").slice(0, 500);
        }
      }
    } catch (rowError) {
      delivered = false;
      lastError = String(rowError).slice(0, 500);
    }
    const { error: updateError } = await admin
      .from("product_submission_push_deliveries")
      .update(
        delivered
          ? { sent_at: new Date().toISOString(), attempts }
          : { attempts, last_error: lastError ?? "unknown" },
      )
      .eq("id", deliveryId);
    if (updateError) {
      console.error(JSON.stringify({
        event: "product_submission_push_bookkeeping_failed",
        message: String(updateError),
      }));
    }
    if (delivered) sent++;
  }
  console.info(JSON.stringify({
    event: "product_submission_push_drain",
    submission_id: submissionId,
    processed: rows.length,
    sent,
    removed_tokens: removedTokens,
  }));
}

Deno.serve(async (request: Request): Promise<Response> => {
  if (request.method !== "POST") {
    audit("unverified", "unknown", "method_not_allowed");
    return json({ error: "Method not allowed" }, 405);
  }

  const authorization = request.headers.get("authorization");
  if (!authorization?.startsWith("Bearer ")) {
    audit("unverified", "unknown", "missing_authentication");
    return json({ error: "Authentication required" }, 401);
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  let publicKey: string | undefined;
  try {
    publicKey = resolveSupabasePublicKey();
  } catch {
    publicKey = undefined;
  }
  if (!supabaseUrl || !publicKey) {
    audit("unverified", "unknown", "server_configuration_error");
    return json({ error: "Reviewer service unavailable" }, 500);
  }

  const userClient = createClient(supabaseUrl, publicKey, {
    global: { headers: { Authorization: authorization } },
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data: authData, error: authError } = await userClient.auth.getUser();
  if (authError || !authData.user) {
    audit("unverified", "unknown", "invalid_authentication");
    return json({ error: "Authentication required" }, 401);
  }

  const reviewerId = authData.user.id;
  const reviewerIds = new Set(
    (Deno.env.get("PRODUCT_SUBMISSION_REVIEWER_IDS") ?? "")
      .split(",")
      .map((value) => value.trim())
      .filter(Boolean),
  );
  if (!reviewerIds.has(reviewerId)) {
    audit(reviewerId, "unknown", "forbidden");
    return json({ error: "Reviewer access required" }, 403);
  }

  let adminKey: string | undefined;
  try {
    adminKey = resolveSupabaseAdminKey();
  } catch {
    adminKey = undefined;
  }
  if (!adminKey) {
    audit(reviewerId, "unknown", "server_configuration_error");
    return json({ error: "Reviewer service unavailable" }, 500);
  }
  const admin = createClient(supabaseUrl, adminKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  let body: JsonObject;
  let action = "unknown";
  try {
    body = await parseBody(request);
    action = requiredString(body.action, "action", 30);
    if (!ACTIONS.has(action)) throw new Error("invalid action");
  } catch {
    audit(reviewerId, action, "invalid_request");
    return json({ error: "Invalid request" }, 400);
  }

  try {
    if (action === "list") {
      rejectUnknownKeys(
        body,
        new Set(["action", "status", "kind", "limit", "submission_id"]),
      );
      const listSubmissionId = body.submission_id === undefined ||
          body.submission_id === null
        ? null
        : requiredUuid(body.submission_id, "submission id");
      const limit = body.limit ?? 50;
      if (
        !Number.isInteger(limit) ||
        !(Number(limit) >= 1 && Number(limit) <= 100)
      ) {
        throw new Error("invalid limit");
      }
      if (
        body.status !== undefined &&
        (typeof body.status !== "string" ||
          !REVIEW_STATUSES.has(body.status))
      ) {
        throw new Error("invalid status");
      }
      if (
        body.kind !== undefined &&
        (typeof body.kind !== "string" || !KINDS.has(body.kind))
      ) {
        throw new Error("invalid kind");
      }

      let query = admin
        .from("product_submissions")
        .select(
          "id,kind,normalized_upc,review_status,created_at,submitted_at," +
            "reviewed_at,promoted_catalog_version,promoted_at," +
            "declared_no_separate_ingredient_panel," +
            "resolution_code,resolution_detail,resolved_dsld_id," +
            "duplicate_of," +
            "product_submission_mismatch_details!" +
            "product_submission_mismatch_details_submission_id_fkey(" +
            "dsld_id,source_record_id," +
            "catalog_source_version,formula_fingerprint,mismatch_categories)",
        )
        .eq("upload_state", "ready")
        .order("submitted_at", { ascending: true })
        .order("id", { ascending: true })
        .limit(Number(limit));
      if (body.status) query = query.eq("review_status", body.status);
      if (body.kind) query = query.eq("kind", body.kind);
      if (listSubmissionId) query = query.eq("id", listSubmissionId);

      const { data: submissions, error: submissionsError } = await query;
      if (submissionsError) throw submissionsError;
      const submissionRows = (submissions ?? []) as unknown as JsonObject[];
      const ids = submissionRows.map((row) => row.id as string);
      const photosBySubmission = new Map<string, JsonObject[]>();
      if (ids.length > 0) {
        const { data: photos, error: photosError } = await admin
          .from("product_submission_photos")
          .select(
            "submission_id,photo_id,seq,categories,object_path,content_type," +
              "byte_size,content_sha256,created_at",
          )
          .in("submission_id", ids)
          .order("seq", { ascending: true });
        if (photosError) throw photosError;
        const photoRows = (photos ?? []) as unknown as JsonObject[];
        if (photoRows.length > 0) {
          const photoPaths = photoRows.map((row) => row.object_path as string);
          const { data: signed, error: signedError } = await admin.storage
            .from(PHOTO_BUCKET)
            .createSignedUrls(photoPaths, SIGNED_URL_TTL_SECONDS);
          if (signedError || !signed) throw signedError;
          const signedByPath = new Map(
            signed.map((item) => [item.path, item.signedUrl]),
          );
          for (const photo of photoRows) {
            const signedUrl = signedByPath.get(photo.object_path as string);
            if (!signedUrl) throw new Error("missing signed URL");
            const responsePhoto = {
              photo_id: photo.photo_id,
              seq: photo.seq,
              categories: photo.categories,
              content_type: photo.content_type,
              byte_size: photo.byte_size,
              content_sha256: photo.content_sha256,
              created_at: photo.created_at,
              signed_url: signedUrl,
              expires_in_seconds: SIGNED_URL_TTL_SECONDS,
            };
            photosBySubmission.set(photo.submission_id as string, [
              ...(photosBySubmission.get(photo.submission_id as string) ?? []),
              responsePhoto,
            ]);
          }
        }
      }
      const responseSubmissions = submissionRows.map((submission) => ({
        ...submission,
        photos: photosBySubmission.get(submission.id as string) ?? [],
      }));
      audit(reviewerId, action, "success", responseSubmissions.length);
      return json({ submissions: responseSubmissions });
    }

    if (action === "record_extraction") {
      rejectUnknownKeys(
        body,
        new Set(["action", "submission_id", "extraction"]),
      );
      const submissionId = requiredUuid(body.submission_id, "submission id");
      if (!isObject(body.extraction)) throw new Error("invalid extraction");
      const extraction = body.extraction;
      rejectUnknownKeys(
        extraction,
        new Set([
          "schema_version",
          "provider",
          "model",
          "prompt_version",
          "input_image_hashes",
          "draft_payload",
          "field_provenance",
          "confidence",
        ]),
      );
      if (
        !isObject(extraction.input_image_hashes) ||
        Object.keys(extraction.input_image_hashes).length === 0 ||
        !Object.values(extraction.input_image_hashes).every((value) =>
          typeof value === "string" && /^[0-9a-f]{64}$/.test(value)
        ) ||
        !isObject(extraction.draft_payload) ||
        !isObject(extraction.field_provenance)
      ) {
        throw new Error("invalid extraction payload");
      }
      const verifiedHashes = await verifySubmissionPhotoIntegrity(
        admin,
        submissionId,
      );
      if (
        canonicalJson(verifiedHashes) !==
          canonicalJson(extraction.input_image_hashes)
      ) {
        throw new Error("extraction image hashes do not match verified bytes");
      }
      const confidence = extraction.confidence;
      if (
        confidence !== null && confidence !== undefined &&
        (typeof confidence !== "number" ||
          !Number.isFinite(confidence) ||
          confidence < 0 || confidence > 1)
      ) {
        throw new Error("invalid confidence");
      }
      const { data, error } = await admin.rpc(
        "record_product_submission_extraction",
        {
          p_submission_id: submissionId,
          p_recorded_by: reviewerId,
          p_schema_version: requiredString(
            extraction.schema_version,
            "schema version",
            80,
          ),
          p_provider: requiredString(extraction.provider, "provider", 120),
          p_model: requiredString(extraction.model, "model", 120),
          p_prompt_version: requiredString(
            extraction.prompt_version,
            "prompt version",
            120,
          ),
          p_input_image_hashes: extraction.input_image_hashes,
          p_draft_payload: extraction.draft_payload,
          p_field_provenance: extraction.field_provenance,
          p_confidence: confidence ?? null,
        },
      );
      if (error || typeof data !== "number") throw error;
      audit(reviewerId, action, "success", 1);
      return json({ extraction_version: data });
    }

    rejectUnknownKeys(
      body,
      new Set([
        "action",
        "submission_id",
        "to_status",
        "review_notes",
        "approved_schema_version",
        "approved_payload",
        "duplicate_of",
        "resolution_code",
        "resolution_detail",
        "resolved_dsld_id",
      ]),
    );
    const submissionId = requiredUuid(body.submission_id, "submission id");
    const toStatus = requiredString(body.to_status, "status", 30);
    if (!TRANSITION_STATUSES.has(toStatus)) {
      throw new Error("invalid transition status");
    }
    const reviewNotes = body.review_notes === undefined ||
        body.review_notes === null
      ? null
      : requiredString(body.review_notes, "review notes", 2000);
    const duplicateOf = body.duplicate_of === undefined ||
        body.duplicate_of === null
      ? null
      : requiredUuid(body.duplicate_of, "duplicate id");
    // Shape validation only; the status-conditional resolution matrix is
    // enforced authoritatively inside review_product_submission.
    const resolutionCode = body.resolution_code === undefined ||
        body.resolution_code === null
      ? null
      : requiredString(body.resolution_code, "resolution code", 40);
    if (
      resolutionCode !== null &&
      !REJECTED_RESOLUTION_CODES.has(resolutionCode) &&
      !DUPLICATE_RESOLUTION_CODES.has(resolutionCode)
    ) {
      throw new Error("invalid resolution code");
    }
    const resolutionDetail = body.resolution_detail === undefined ||
        body.resolution_detail === null
      ? null
      : requiredString(body.resolution_detail, "resolution detail", 280);
    const resolvedDsldId = body.resolved_dsld_id === undefined ||
        body.resolved_dsld_id === null
      ? null
      : requiredString(body.resolved_dsld_id, "resolved product id", 40);
    if (
      resolvedDsldId !== null && !RESOLVED_DSLD_PATTERN.test(resolvedDsldId)
    ) {
      throw new Error("invalid resolved product id");
    }

    let schemaVersion: string | null = null;
    let approvedPayload: JsonObject | null = null;
    let approvedPayloadCanonical: string | null = null;
    let payloadHash: string | null = null;
    if (toStatus === "approved") {
      await verifySubmissionPhotoIntegrity(admin, submissionId);
      schemaVersion = requiredString(
        body.approved_schema_version,
        "approved schema version",
        80,
      );
      if (schemaVersion !== APPROVED_SCHEMA_VERSION) {
        throw new Error("unsupported approved schema version");
      }
      approvedPayload = validateApprovedPayload(body.approved_payload);
      approvedPayloadCanonical = canonicalJson(approvedPayload);
      if (
        new TextEncoder().encode(approvedPayloadCanonical).byteLength >
          APPROVED_PAYLOAD_MAX_BYTES
      ) {
        throw new Error("approved payload too large");
      }
      payloadHash = await sha256Hex(approvedPayloadCanonical);
    } else if (
      body.approved_schema_version !== undefined ||
      body.approved_payload !== undefined
    ) {
      throw new Error("approved payload not allowed");
    }

    const { data, error } = await admin.rpc("review_product_submission", {
      p_submission_id: submissionId,
      p_reviewer_id: reviewerId,
      p_to_status: toStatus,
      p_review_notes: reviewNotes,
      p_approved_schema_version: schemaVersion,
      p_approved_payload: approvedPayload,
      p_approved_payload_canonical: approvedPayloadCanonical,
      p_payload_sha256: payloadHash,
      p_duplicate_of: duplicateOf,
      p_resolution_code: resolutionCode,
      p_resolution_detail: resolutionDetail,
      p_resolved_dsld_id: resolvedDsldId,
    });
    if (error || data !== true) throw error;

    // The durable delivery row is already committed by the RPC. Draining it
    // must survive the response being returned, so it runs under
    // EdgeRuntime.waitUntil; a failed send stays pending and is retried by
    // the stale sweep on the next review action.
    const drain = drainSubmissionPushDeliveries(admin, submissionId)
      .catch((pushError) => {
        console.error(JSON.stringify({
          event: "product_submission_push_drain_failed",
          submission_id: submissionId,
          message: String(pushError),
        }));
      });
    if (typeof EdgeRuntime !== "undefined") {
      EdgeRuntime.waitUntil(drain);
    } else {
      await drain;
    }

    audit(reviewerId, action, "success", 1);
    return json({ updated: true, payload_sha256: payloadHash });
  } catch {
    audit(reviewerId, action, "backend_or_validation_error");
    return json({ error: "Review action could not be completed" }, 400);
  }
});
