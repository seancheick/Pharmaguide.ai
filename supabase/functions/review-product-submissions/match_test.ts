import { assertEquals, assertThrows } from "jsr:@std/assert@1.0.14";

import { parseRecordMatchRequest } from "./match.ts";

const submissionId = "018f4c79-7c7e-4c70-9d62-7fc3b9ce6a11";
const indexBuiltAt = "2026-08-25T16:20:30.123Z";

Deno.test("match checks require the evidence revision actually reviewed", () => {
  assertThrows(() =>
    parseRecordMatchRequest({
      action: "record_match",
      submission_id: submissionId,
      outcome: "no_match_verified",
      canonical_gtin14: "00050428381397",
      index_built_at: indexBuiltAt,
    })
  );
});

Deno.test("record_match accepts a fresh exact no-match check", () => {
  assertEquals(
    parseRecordMatchRequest({
      action: "record_match",
      submission_id: submissionId,
      expected_evidence_revision: 1,
      evidence_manifest_sha256: "a".repeat(64),
      outcome: "no_match_verified",
      canonical_gtin14: "00050428381397",
      index_built_at: indexBuiltAt,
    }),
    {
      submissionId,
      expectedEvidenceRevision: 1,
      evidenceManifestSha256: "a".repeat(64),
      outcome: "no_match_verified",
      canonicalGtin14: "00050428381397",
      indexBuiltAt,
      matchedDsldId: null,
      candidateDsldIds: [],
      reason: null,
    },
  );
});

Deno.test("record_match validates each outcome-specific shape", () => {
  for (const outcome of ["catalog_match", "dsld_match"] as const) {
    const parsed = parseRecordMatchRequest({
      action: "record_match",
      submission_id: submissionId,
      expected_evidence_revision: 1,
      evidence_manifest_sha256: "a".repeat(64),
      outcome,
      canonical_gtin14: "04006381333931",
      index_built_at: indexBuiltAt,
      matched_dsld_id: "12345",
    });
    assertEquals(parsed.outcome, outcome);
    assertEquals(parsed.matchedDsldId, "12345");
  }

  const ambiguous = parseRecordMatchRequest({
    action: "record_match",
    submission_id: submissionId,
    expected_evidence_revision: 1,
    evidence_manifest_sha256: "a".repeat(64),
    outcome: "identity_ambiguous",
    canonical_gtin14: "00000096385074",
    index_built_at: indexBuiltAt,
    candidate_dsld_ids: ["123", "456"],
  });
  assertEquals(ambiguous.candidateDsldIds, ["123", "456"]);

  const override = parseRecordMatchRequest({
    action: "record_match",
    submission_id: submissionId,
    expected_evidence_revision: 1,
    evidence_manifest_sha256: "a".repeat(64),
    outcome: "not_this_product",
    canonical_gtin14: "00016000275447",
    index_built_at: indexBuiltAt,
    matched_dsld_id: "PG_SUB_0123456789ABCDEF0123456789ABCDEF",
    reason: "The reviewed label is a different product despite the reused UPC.",
  });
  assertEquals(
    override.reason,
    "The reviewed label is a different product despite the reused UPC.",
  );
});

Deno.test("record_match fails closed on malformed identity evidence", () => {
  const base = {
    action: "record_match",
    submission_id: submissionId,
    expected_evidence_revision: 1,
    evidence_manifest_sha256: "a".repeat(64),
    outcome: "no_match_verified",
    canonical_gtin14: "00050428381397",
    index_built_at: indexBuiltAt,
  };
  assertThrows(() => parseRecordMatchRequest({ ...base, extra: true }));
  assertThrows(() =>
    parseRecordMatchRequest({ ...base, canonical_gtin14: "050428381397" })
  );
  assertThrows(() =>
    parseRecordMatchRequest({ ...base, canonical_gtin14: "00050428381398" })
  );
  assertThrows(() =>
    parseRecordMatchRequest({ ...base, index_built_at: "not-a-time" })
  );
  assertThrows(() =>
    parseRecordMatchRequest({ ...base, matched_dsld_id: "123" })
  );
  assertThrows(() =>
    parseRecordMatchRequest({
      ...base,
      outcome: "identity_ambiguous",
      candidate_dsld_ids: ["123"],
    })
  );
  assertThrows(() =>
    parseRecordMatchRequest({
      ...base,
      outcome: "not_this_product",
      matched_dsld_id: "123",
    })
  );
});

Deno.test("label review requires explicit complete candidate decision and retains null GTIN", () => {
  const request = {
    action: "record_match",
    submission_id: submissionId,
    expected_evidence_revision: 1,
    evidence_manifest_sha256: "a".repeat(64),
    outcome: "new_product_verified",
    canonical_gtin14: null,
    index_built_at: indexBuiltAt,
    identity_method: "label_review",
    candidate_review_complete: true,
    index_revision: "catalog:fixture",
    identifier_decision: {
      code_type: "amazon_fnsku",
      issuer: "Amazon",
      verified_gtin: null,
      package: "60 capsules",
      reason: "Compared complete label and candidate formulations",
    },
  };
  assertEquals(parseRecordMatchRequest(request).canonicalGtin14, null);
  assertThrows(() =>
    parseRecordMatchRequest({ ...request, candidate_review_complete: false })
  );
  assertThrows(() =>
    parseRecordMatchRequest({
      ...request,
      identifier_decision: {
        ...request.identifier_decision,
        verified_gtin: "X036000291452",
      },
    })
  );
});

Deno.test("reviewed identifier metadata rejects C1 and canonicalizes blank issuer", () => {
  const request = {
    action: "record_match",
    submission_id: submissionId,
    expected_evidence_revision: 1,
    evidence_manifest_sha256: "a".repeat(64),
    outcome: "new_product_verified",
    canonical_gtin14: null,
    index_built_at: indexBuiltAt,
    identity_method: "label_review",
    candidate_review_complete: true,
    index_revision: "complete-index",
    identifier_decision: {
      code_type: "other",
      issuer: " \u00a0 ",
      verified_gtin: null,
      package: "60 capsules",
      reason: "Read all candidate labels",
    },
  };
  assertEquals(
    parseRecordMatchRequest(request).identifierDecision?.issuer,
    null,
  );
  for (const key of ["issuer", "package", "reason"]) {
    assertThrows(() =>
      parseRecordMatchRequest({
        ...request,
        identifier_decision: {
          ...request.identifier_decision,
          [key]: "X\u0085Y",
        },
      })
    );
  }
  assertThrows(() =>
    parseRecordMatchRequest({
      ...request,
      identifier_decision: {
        ...request.identifier_decision,
        verified_gtin: "036000291452",
      },
    })
  );
});

Deno.test("v2 GTIN review keeps substantive reason and permits null package", () => {
  const result = parseRecordMatchRequest({
    action: "record_match",
    submission_id: submissionId,
    expected_evidence_revision: 1,
    evidence_manifest_sha256: "a".repeat(64),
    outcome: "no_match_verified",
    canonical_gtin14: "00036000291452",
    index_built_at: indexBuiltAt,
    identity_method: "gtin",
    candidate_review_complete: true,
    index_revision: "complete-index",
    identifier_decision: {
      code_type: "other",
      issuer: null,
      verified_gtin: "036000291452",
      package: null,
      reason: "Compared exact GTIN candidates against full label",
    },
  });
  assertEquals(result.identifierDecision?.package, null);
  assertEquals(
    result.identifierDecision?.reason,
    "Compared exact GTIN candidates against full label",
  );
});
