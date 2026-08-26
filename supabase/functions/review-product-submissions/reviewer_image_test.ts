import { assertEquals, assertThrows } from "jsr:@std/assert@1.0.14";

import {
  detectReviewerImageContentType,
  parseReviewerImageUploadRequest,
} from "./reviewer_image.ts";

const submissionId = "018f4c79-7c7e-4c70-9d62-7fc3b9ce6a11";
const objectId = "118f4c79-7c7e-4c70-9d62-7fc3b9ce6a22";

Deno.test("reviewer crop inherits consent without a new attestation", () => {
  assertEquals(
    parseReviewerImageUploadRequest({
      action: "create_reviewer_image_upload",
      submission_id: submissionId,
      object_id: objectId,
      source_rights: "user_evidence_crop",
      rights_attested: false,
      source_photo_id: "218f4c79-7c7e-4c70-9d62-7fc3b9ce6a33",
    }).sourceRights,
    "user_evidence_crop",
  );
});

Deno.test("external picture sources require explicit rights attestation", () => {
  for (const sourceRights of [
    "operator_photo",
    "manufacturer_provided",
    "licensed",
  ]) {
    assertThrows(() =>
      parseReviewerImageUploadRequest({
        action: "create_reviewer_image_upload",
        submission_id: submissionId,
        object_id: objectId,
        source_rights: sourceRights,
        rights_attested: false,
      })
    );
    assertEquals(
      parseReviewerImageUploadRequest({
        action: "create_reviewer_image_upload",
        submission_id: submissionId,
        object_id: objectId,
        source_rights: sourceRights,
      rights_attested: true,
      source_photo_id: null,
      }).sourceRights,
      sourceRights,
    );
  }
});

Deno.test("reviewer image uploads reject unknown fields and invalid ids", () => {
  const valid = {
    action: "create_reviewer_image_upload",
    submission_id: submissionId,
    object_id: objectId,
    source_rights: "operator_photo",
        rights_attested: true,
        source_photo_id: null,
  };
  assertThrows(() => parseReviewerImageUploadRequest({ ...valid, extra: true }));
  assertThrows(() =>
    parseReviewerImageUploadRequest({ ...valid, object_id: "not-a-uuid" })
  );
});

Deno.test("reviewer image bytes are magic-number typed", () => {
  assertEquals(
    detectReviewerImageContentType(new Uint8Array([0xff, 0xd8, 0xff, 0xe0])),
    "image/jpeg",
  );
  assertEquals(
    detectReviewerImageContentType(
      new Uint8Array([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
    ),
    "image/png",
  );
  assertEquals(
    detectReviewerImageContentType(
      new Uint8Array([0x52, 0x49, 0x46, 0x46, 0, 0, 0, 0, 0x57, 0x45, 0x42, 0x50]),
    ),
    "image/webp",
  );
  assertEquals(detectReviewerImageContentType(new Uint8Array([1, 2, 3])), null);
});
