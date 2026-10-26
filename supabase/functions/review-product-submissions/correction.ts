const UUID =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const SHA256 = /^[0-9a-f]{64}$/;
const CATEGORIES = new Set([
  "front_identity",
  "supplement_facts",
  "ingredient_disclosure",
  "directions_warnings",
  "barcode",
  "lot_expiry",
]);
const CATEGORY_ORDER = [...CATEGORIES];

function exactKeys(body: Record<string, unknown>, allowed: Set<string>) {
  if (!Object.keys(body).every((key) => allowed.has(key))) {
    throw new Error("unknown field");
  }
}
function uuid(value: unknown, name: string): string {
  if (typeof value !== "string" || !UUID.test(value)) {
    throw new Error(`invalid ${name}`);
  }
  return value.toLowerCase();
}
function revision(value: unknown): number {
  if (!Number.isSafeInteger(value) || Number(value) < 1) {
    throw new Error("invalid revision");
  }
  return Number(value);
}
function hash(value: unknown): string {
  if (typeof value !== "string" || !SHA256.test(value)) {
    throw new Error("invalid hash");
  }
  return value;
}

export function parseReopenApprovalRequest(body: Record<string, unknown>) {
  exactKeys(
    body,
    new Set([
      "action",
      "submission_id",
      "expected_approval_revision",
      "expected_payload_sha256",
      "reason",
    ]),
  );
  const reason = typeof body.reason === "string" ? body.reason.trim() : "";
  if (reason.length < 5 || reason.length > 1000) {
    throw new Error("reason required");
  }
  return {
    submissionId: uuid(body.submission_id, "submission id"),
    expectedApprovalRevision: revision(body.expected_approval_revision),
    expectedPayloadSha256: hash(body.expected_payload_sha256),
    reason,
  };
}

export type ReviewerEvidencePhoto = {
  photo_id: string;
  seq: number;
  categories: string[];
  content_type: string;
  byte_size: number;
  content_sha256: string;
};

export function parseReviewerEvidenceRequest(body: Record<string, unknown>) {
  exactKeys(
    body,
    new Set([
      "action",
      "submission_id",
      "expected_approval_revision",
      "expected_payload_sha256",
      "request_key",
      "photos",
    ]),
  );
  if (
    !Array.isArray(body.photos) || body.photos.length < 1 ||
    body.photos.length > 8
  ) throw new Error("invalid photos");
  const photos: ReviewerEvidencePhoto[] = body.photos.map((raw, index) => {
    if (raw === null || typeof raw !== "object" || Array.isArray(raw)) {
      throw new Error("invalid photo");
    }
    const photo = raw as Record<string, unknown>;
    exactKeys(
      photo,
      new Set([
        "photo_id",
        "seq",
        "categories",
        "content_type",
        "byte_size",
        "content_sha256",
      ]),
    );
    if (!Number.isSafeInteger(photo.seq) || Number(photo.seq) !== index + 1) {
      throw new Error("invalid sequence");
    }
    if (
      !Array.isArray(photo.categories) || photo.categories.length < 1 ||
      new Set(photo.categories).size !== photo.categories.length ||
      !photo.categories.every((item) =>
        typeof item === "string" && CATEGORIES.has(item)
      )
    ) throw new Error("invalid categories");
    if (
      photo.content_type !== "image/jpeg" &&
      photo.content_type !== "image/png" && photo.content_type !== "image/webp"
    ) throw new Error("invalid content type");
    if (
      !Number.isSafeInteger(photo.byte_size) || Number(photo.byte_size) < 1 ||
      Number(photo.byte_size) > 20 * 1024 * 1024
    ) throw new Error("invalid byte size");
    return {
      photo_id: uuid(photo.photo_id, "photo id"),
      seq: Number(photo.seq),
      categories: [...photo.categories as string[]].sort(
        (left, right) =>
          CATEGORY_ORDER.indexOf(left) - CATEGORY_ORDER.indexOf(right),
      ),
      content_type: photo.content_type,
      byte_size: Number(photo.byte_size),
      content_sha256: hash(photo.content_sha256),
    };
  });
  return {
    submissionId: uuid(body.submission_id, "submission id"),
    expectedApprovalRevision: revision(body.expected_approval_revision),
    expectedPayloadSha256: hash(body.expected_payload_sha256),
    requestKey: uuid(body.request_key, "request key"),
    photos,
  };
}

export function parseFinalizeReviewerEvidenceRequest(
  body: Record<string, unknown>,
) {
  exactKeys(body, new Set(["action", "submission_id", "evidence_revision"]));
  return {
    submissionId: uuid(body.submission_id, "submission id"),
    evidenceRevision: revision(body.evidence_revision),
  };
}

export function correctionRecoveryMessage(
  action: string,
  error: unknown,
): string {
  const candidate = error as { code?: unknown; message?: unknown } | null;
  const code = typeof candidate?.code === "string" ? candidate.code : "";
  const message = typeof candidate?.message === "string"
    ? candidate.message.toLowerCase()
    : "";
  if (
    action === "finalize_reviewer_evidence_uploads" &&
    message.includes("bytes are incomplete")
  ) {
    return "Some replacement photos did not finish uploading. Retry with the same files.";
  }
  if (code === "23505" && message.includes("replay conflict")) {
    return "This upload does not match the pending attempt. Reselect the original files and panel descriptions.";
  }
  if (code === "55000" || code === "23505") {
    return "This submission changed while you were working. Reload it before continuing.";
  }
  return "Review action could not be completed";
}
