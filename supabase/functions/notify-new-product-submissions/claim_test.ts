import { assertEquals, assertThrows } from "jsr:@std/assert@1";

import { parseClaimedNotifications } from "./claim.ts";

const validRow = {
  notification_id: 1,
  submission_id: "7dd4c1a0-1111-4a2b-9c3d-000000000001",
  kind: "missing_product",
  normalized_upc: "850025250001",
  display_name: "Seed DS-01 Daily Synbiotic",
  submitted_at: "2026-09-18T15:42:00Z",
  is_resubmission: false,
  photo_count: 4,
  extraction_confidence: null,
};

Deno.test("parses a full valid row", () => {
  const [parsed] = parseClaimedNotifications([validRow]);
  assertEquals(parsed.notificationId, 1);
  assertEquals(parsed.submissionId, validRow.submission_id);
  assertEquals(parsed.kind, "missing_product");
  assertEquals(parsed.photoCount, 4);
  assertEquals(parsed.extractionConfidence, null);
});

Deno.test("treats missing optional fields as null/false", () => {
  const [parsed] = parseClaimedNotifications([{
    notification_id: 2,
    submission_id: validRow.submission_id,
    kind: "label_mismatch",
    photo_count: 0,
  }]);
  assertEquals(parsed.normalizedUpc, null);
  assertEquals(parsed.displayName, null);
  assertEquals(parsed.submittedAt, null);
  assertEquals(parsed.isResubmission, false);
  assertEquals(parsed.extractionConfidence, null);
});

Deno.test("rejects a non-array payload", () => {
  assertThrows(() => parseClaimedNotifications({}));
});

Deno.test("rejects an unrecognized kind", () => {
  assertThrows(() =>
    parseClaimedNotifications([{ ...validRow, kind: "something_else" }])
  );
});

Deno.test("rejects a row missing notification_id", () => {
  const { notification_id: _drop, ...withoutId } = validRow;
  assertThrows(() => parseClaimedNotifications([withoutId]));
});

Deno.test("rejects a row missing photo_count", () => {
  const { photo_count: _drop, ...withoutCount } = validRow;
  assertThrows(() => parseClaimedNotifications([withoutCount]));
});
