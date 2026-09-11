import { parseEvidenceBinding } from "./evidence.ts";

// A reviewer asks the owner for new photos of named panels, bound to the
// evidence the reviewer is looking at. The database owns the rules; this
// only refuses shapes it would refuse anyway, before a round trip.
export type EvidenceRequest = {
  submissionId: string;
  reason: string;
  panels: string[];
  expectedEvidenceRevision: number;
  evidenceManifestSha256: string;
};

const UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const REASONS = new Set([
  "photo_quality",
  "missing_panel",
  "label_unreadable",
  "other",
]);
const PANELS = new Set([
  "front_identity",
  "supplement_facts",
  "ingredient_disclosure",
  "directions_warnings",
  "barcode",
  "lot_expiry",
]);
const ALLOWED_FIELDS = new Set([
  "action",
  "submission_id",
  "reason",
  "panels",
  "expected_evidence_revision",
  "evidence_manifest_sha256",
]);

export function parseEvidenceRequest(
  body: Record<string, unknown>,
): EvidenceRequest {
  if (!Object.keys(body).every((key) => ALLOWED_FIELDS.has(key))) {
    throw new Error("unknown field");
  }
  const submissionId = body.submission_id;
  if (typeof submissionId !== "string" || !UUID_PATTERN.test(submissionId)) {
    throw new Error("invalid submission id");
  }
  const reason = body.reason;
  if (typeof reason !== "string" || !REASONS.has(reason)) {
    throw new Error("invalid evidence request reason");
  }
  const panels = body.panels;
  if (
    !Array.isArray(panels) || panels.length === 0 ||
    !panels.every((panel) => typeof panel === "string" && PANELS.has(panel)) ||
    new Set(panels).size !== panels.length
  ) {
    throw new Error("invalid evidence request panels");
  }
  return {
    submissionId,
    reason,
    panels: panels as string[],
    ...parseEvidenceBinding(body),
  };
}
