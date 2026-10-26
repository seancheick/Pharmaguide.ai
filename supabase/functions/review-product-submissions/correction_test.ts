import { assertEquals, assertThrows } from "jsr:@std/assert@1";
import {
  correctionRecoveryMessage,
  parseReopenApprovalRequest,
  parseReviewerEvidenceRequest,
} from "./correction.ts";

const submissionId = "018f4c79-7c7e-4c70-9d62-7fc3b9ce6a11";
const hash = "a".repeat(64);

Deno.test("reopen approval requires an exact revision hash and reason", () => {
  assertEquals(
    parseReopenApprovalRequest({
      action: "reopen_approval",
      submission_id: submissionId,
      expected_approval_revision: 2,
      expected_payload_sha256: hash,
      reason: "The serving size was transcribed incorrectly.",
    }),
    {
      submissionId,
      expectedApprovalRevision: 2,
      expectedPayloadSha256: hash,
      reason: "The serving size was transcribed incorrectly.",
    },
  );
  assertThrows(() =>
    parseReopenApprovalRequest({
      action: "reopen_approval",
      submission_id: submissionId,
      expected_approval_revision: 2,
      expected_payload_sha256: hash,
      reason: " ",
    })
  );
});

Deno.test("reviewer replacement manifest is bounded and exact", () => {
  const parsed = parseReviewerEvidenceRequest({
    action: "create_reviewer_evidence_uploads",
    submission_id: submissionId,
    expected_approval_revision: 1,
    expected_payload_sha256: hash,
    request_key: "20000000-0000-4000-8000-000000000001",
    photos: [{
      photo_id: "30000000-0000-4000-8000-000000000001",
      seq: 1,
      categories: [
        "front_identity",
        "supplement_facts",
        "ingredient_disclosure",
        "barcode",
      ],
      content_type: "image/jpeg",
      byte_size: 1234,
      content_sha256: "b".repeat(64),
    }],
  });
  assertEquals(parsed.photos.length, 1);
  assertThrows(() =>
    parseReviewerEvidenceRequest({
      ...parsed,
      action: "create_reviewer_evidence_uploads",
      photos: [{ ...parsed.photos[0], categories: ["unknown"] }],
    } as unknown as Record<string, unknown>)
  );
});

Deno.test("correction failures return safe actionable recovery copy", () => {
  assertEquals(
    correctionRecoveryMessage("finalize_reviewer_evidence_uploads", {
      code: "55000",
      message: "reviewer evidence bytes are incomplete",
    }),
    "Some replacement photos did not finish uploading. Retry with the same files.",
  );
  assertEquals(
    correctionRecoveryMessage("create_reviewer_evidence_uploads", {
      code: "23505",
      message: "reviewer evidence replay conflict",
    }),
    "This upload does not match the pending attempt. Reselect the original files and panel descriptions.",
  );
  assertEquals(
    correctionRecoveryMessage("reopen_approval", {
      code: "55000",
      message: "approval changed",
    }),
    "This submission changed while you were working. Reload it before continuing.",
  );
});
