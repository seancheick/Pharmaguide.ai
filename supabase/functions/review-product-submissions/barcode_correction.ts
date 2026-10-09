import { parseEvidenceBinding } from "./evidence.ts";

// A reviewer corrects the barcode an owner filed, bound to the evidence the
// reviewer is looking at. The database owns every rule (check digit, state,
// collisions); this only refuses shapes it would refuse anyway, before a round
// trip, and says which of the database's refusals a reviewer may be told.
export type BarcodeCorrection = {
  submissionId: string;
  newUpc: string;
  reason: string;
  expectedEvidenceRevision: number;
  evidenceManifestSha256: string;
};

const UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const ALLOWED_FIELDS = new Set([
  "action",
  "submission_id",
  "new_upc",
  "reason",
  "expected_evidence_revision",
  "evidence_manifest_sha256",
]);
const REASON_MAX_LENGTH = 500;
// A printed barcode has spaces ("0067 1422"); the database strips them.
const NEW_UPC_MAX_LENGTH = 32;

export function parseBarcodeCorrection(
  body: Record<string, unknown>,
): BarcodeCorrection {
  if (!Object.keys(body).every((key) => ALLOWED_FIELDS.has(key))) {
    throw new Error("unknown field");
  }
  const submissionId = body.submission_id;
  if (typeof submissionId !== "string" || !UUID_PATTERN.test(submissionId)) {
    throw new Error("invalid submission id");
  }
  const newUpc = body.new_upc;
  if (
    typeof newUpc !== "string" || newUpc.trim() === "" ||
    newUpc.length > NEW_UPC_MAX_LENGTH
  ) {
    throw new Error("barcode required");
  }
  const reason = typeof body.reason === "string" ? body.reason.trim() : "";
  if (reason === "" || reason.length > REASON_MAX_LENGTH) {
    throw new Error("barcode correction reason required");
  }
  return { submissionId, newUpc, reason, ...parseEvidenceBinding(body) };
}

// Refusals the console may show. The generic handler hides database text on
// purpose; these messages are written here, not taken from the database, so
// naming the cause of a correction that did not apply leaks nothing.
const REFUSALS: ReadonlyArray<readonly [RegExp, string]> = [
  [
    /valid barcode required/,
    "That is not a valid barcode: the check digit does not match.",
  ],
  [
    /barcode correction reason required/,
    "Say why the barcode is being corrected.",
  ],
  [/barcode unchanged/, "That is the barcode already on this submission."],
  [
    /missing-product submission under review required/,
    "Only a new-product submission under review can have its barcode corrected.",
  ],
  [
    /changed since review/,
    "The photos changed since you opened this. Reload the submission and try again.",
  ],
  [
    /idx_product_submissions_user_open_upc/,
    "The owner already has an open submission for that barcode.",
  ],
  [
    /another approved submission awaits promotion/,
    "Another approved submission for that barcode is waiting to be published.",
  ],
];

export function barcodeCorrectionRefusal(error: unknown): string | null {
  const message = typeof error === "object" && error !== null &&
      "message" in error
    ? String((error as { message: unknown }).message)
    : "";
  return REFUSALS.find(([pattern]) => pattern.test(message))?.[1] ?? null;
}
