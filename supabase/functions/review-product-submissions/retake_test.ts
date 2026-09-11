import { assertEquals, assertThrows } from "jsr:@std/assert@1.0.14";
import { parseEvidenceRequest } from "./retake.ts";

const valid = {
  action: "request_evidence",
  submission_id: "3f2a1b4c-5d6e-4f70-8a9b-0c1d2e3f4a5b",
  reason: "photo_quality",
  panels: ["supplement_facts", "barcode"],
  expected_evidence_revision: 1,
  evidence_manifest_sha256: "a".repeat(64),
};

Deno.test("a well-formed request names the submission, reason, panels and evidence", () => {
  assertEquals(parseEvidenceRequest(valid), {
    submissionId: valid.submission_id,
    reason: "photo_quality",
    panels: ["supplement_facts", "barcode"],
    expectedEvidenceRevision: 1,
    evidenceManifestSha256: "a".repeat(64),
  });
});

Deno.test("only retake reasons can ask for new photos", () => {
  for (
    const reason of [
      "not_a_supplement",
      "already_in_catalog",
      "duplicate_submission",
      "product_identity_mismatch",
      "",
      null,
    ]
  ) {
    assertThrows(() => parseEvidenceRequest({ ...valid, reason }));
  }
});

Deno.test("a request names at least one known panel, each once", () => {
  for (
    const panels of [
      [],
      null,
      "supplement_facts",
      ["back_label"],
      ["barcode", "barcode"],
      [1],
    ]
  ) {
    assertThrows(() => parseEvidenceRequest({ ...valid, panels }));
  }
});

Deno.test("a request is bound to current evidence and carries nothing else", () => {
  assertThrows(() =>
    parseEvidenceRequest({ ...valid, evidence_manifest_sha256: "stale" })
  );
  assertThrows(() =>
    parseEvidenceRequest({ ...valid, expected_evidence_revision: 0 })
  );
  assertThrows(() => parseEvidenceRequest({ ...valid, submission_id: "x" }));
  assertThrows(() => parseEvidenceRequest({ ...valid, note: "free text" }));
});
