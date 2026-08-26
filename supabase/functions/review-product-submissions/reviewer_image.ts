type JsonObject = Record<string, unknown>;

export type ReviewerImageRights =
  | "user_evidence_crop"
  | "operator_photo"
  | "manufacturer_provided"
  | "licensed";

export type ReviewerImageUploadRequest = {
  submissionId: string;
  objectId: string;
  sourceRights: ReviewerImageRights;
  rightsAttested: boolean;
  sourcePhotoId: string | null;
};

const UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const RIGHTS = new Set<ReviewerImageRights>([
  "user_evidence_crop",
  "operator_photo",
  "manufacturer_provided",
  "licensed",
]);
const ALLOWED_FIELDS = new Set([
  "action",
  "submission_id",
  "object_id",
  "source_rights",
  "rights_attested",
  "source_photo_id",
]);

function uuid(value: unknown, name: string): string {
  if (typeof value !== "string" || !UUID_PATTERN.test(value)) {
    throw new Error(`invalid ${name}`);
  }
  return value.toLowerCase();
}

export function parseReviewerImageUploadRequest(
  value: unknown,
): ReviewerImageUploadRequest {
  if (value === null || typeof value !== "object" || Array.isArray(value)) {
    throw new Error("invalid reviewer image request");
  }
  const body = value as JsonObject;
  if (Object.keys(body).some((key) => !ALLOWED_FIELDS.has(key))) {
    throw new Error("unknown reviewer image field");
  }
  if (body.action !== "create_reviewer_image_upload") {
    throw new Error("invalid reviewer image action");
  }
  if (typeof body.source_rights !== "string" || !RIGHTS.has(
    body.source_rights as ReviewerImageRights,
  )) {
    throw new Error("invalid image rights");
  }
  if (typeof body.rights_attested !== "boolean") {
    throw new Error("invalid rights attestation");
  }
  const sourceRights = body.source_rights as ReviewerImageRights;
  const sourcePhotoId = body.source_photo_id === undefined ||
      body.source_photo_id === null
    ? null
    : uuid(body.source_photo_id, "source photo id");
  if (sourceRights === "user_evidence_crop") {
    if (body.rights_attested) {
      throw new Error("inherited consent must not fabricate an attestation");
    }
    if (sourcePhotoId === null) throw new Error("source photo required");
  } else if (!body.rights_attested) {
    throw new Error("image rights attestation required");
  } else if (sourcePhotoId !== null) {
    throw new Error("source photo is not allowed");
  }
  return {
    submissionId: uuid(body.submission_id, "submission id"),
    objectId: uuid(body.object_id, "object id"),
    sourceRights,
    rightsAttested: body.rights_attested,
    sourcePhotoId,
  };
}

export function detectReviewerImageContentType(
  bytes: Uint8Array,
): "image/jpeg" | "image/png" | "image/webp" | null {
  if (bytes.length >= 3 && bytes[0] === 0xff && bytes[1] === 0xd8 && bytes[2] === 0xff) {
    return "image/jpeg";
  }
  if (
    bytes.length >= 8 && bytes[0] === 0x89 && bytes[1] === 0x50 &&
    bytes[2] === 0x4e && bytes[3] === 0x47 && bytes[4] === 0x0d &&
    bytes[5] === 0x0a && bytes[6] === 0x1a && bytes[7] === 0x0a
  ) {
    return "image/png";
  }
  if (
    bytes.length >= 12 && bytes[0] === 0x52 && bytes[1] === 0x49 &&
    bytes[2] === 0x46 && bytes[3] === 0x46 && bytes[8] === 0x57 &&
    bytes[9] === 0x45 && bytes[10] === 0x42 && bytes[11] === 0x50
  ) {
    return "image/webp";
  }
  return null;
}
