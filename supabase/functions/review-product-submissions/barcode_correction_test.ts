import { assertEquals, assertThrows } from "jsr:@std/assert@1.0.14";
import {
  barcodeCorrectionRefusal,
  parseBarcodeCorrection,
} from "./barcode_correction.ts";

const valid = {
  action: "correct_barcode",
  submission_id: "3f2a1b4c-5d6e-4f70-8a9b-0c1d2e3f4a5b",
  new_upc: "0067 1422",
  reason: "Bottle prints 0067 1422",
  expected_evidence_revision: 1,
  evidence_manifest_sha256: "a".repeat(64),
};

Deno.test("a well-formed correction names the submission, barcode, reason and evidence", () => {
  assertEquals(parseBarcodeCorrection(valid), {
    submissionId: valid.submission_id,
    newUpc: "0067 1422",
    reason: "Bottle prints 0067 1422",
    expectedEvidenceRevision: 1,
    evidenceManifestSha256: "a".repeat(64),
  });
});

Deno.test("the reason is trimmed and must say something", () => {
  assertEquals(
    parseBarcodeCorrection({ ...valid, reason: "  why  " }).reason,
    "why",
  );
  for (const reason of ["", "   ", undefined, 7, "x".repeat(501)]) {
    assertThrows(
      () => parseBarcodeCorrection({ ...valid, reason }),
      Error,
      "reason required",
    );
  }
});

Deno.test("a correction needs a barcode, a submission id and current evidence", () => {
  for (const new_upc of ["", "  ", undefined, 671422, "1".repeat(33)]) {
    assertThrows(
      () => parseBarcodeCorrection({ ...valid, new_upc }),
      Error,
      "barcode required",
    );
  }
  assertThrows(
    () => parseBarcodeCorrection({ ...valid, submission_id: "nope" }),
    Error,
    "invalid submission id",
  );
  assertThrows(
    () => parseBarcodeCorrection({ ...valid, evidence_manifest_sha256: "abc" }),
    Error,
    "current evidence revision and manifest required",
  );
});

Deno.test("unknown fields are refused, so a client cannot smuggle a reviewer id or status", () => {
  assertThrows(
    () => parseBarcodeCorrection({ ...valid, reviewer_id: "x" }),
    Error,
    "unknown field",
  );
});

Deno.test("only the database's curated refusals are reported, in the edge's own words", () => {
  assertEquals(
    barcodeCorrectionRefusal({ message: "valid barcode required" }),
    "That is not a valid barcode: the check digit does not match.",
  );
  assertEquals(
    barcodeCorrectionRefusal({
      message:
        'duplicate key value violates unique constraint "idx_product_submissions_user_open_upc"',
    }),
    "The owner already has an open submission for that barcode.",
  );
  assertEquals(
    barcodeCorrectionRefusal({
      message: "evidence revision changed since review",
    }),
    "The photos changed since you opened this. Reload the submission and try again.",
  );
  // Anything else stays behind the generic error.
  assertEquals(
    barcodeCorrectionRefusal({ message: "permission denied for table x" }),
    null,
  );
  assertEquals(barcodeCorrectionRefusal(new Error("boom")), null);
  assertEquals(barcodeCorrectionRefusal(null), null);
});

Deno.test("a submission that is not under review is refused in words", () => {
  assertEquals(
    barcodeCorrectionRefusal({
      message: "missing-product submission under review required",
    }),
    "Only a new-product submission under review can have its barcode corrected.",
  );
});
