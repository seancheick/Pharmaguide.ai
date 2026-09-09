import { assertEquals, assertThrows } from "jsr:@std/assert@1";
import { parseCleanupClaims } from "./claims.ts";

const id = "00000000-0000-0000-0000-000000000001";
const token = "00000000-0000-0000-0000-000000000002";
const claim = {
  submission_id: id,
  claim_token: token,
  evidence_revision: 2,
  evidence_object_paths: [`${token}/${id}/${token}`],
  reviewer_object_paths: [],
};

Deno.test("cleanup claims preserve the deletion scope and fencing token", () => {
  assertEquals(parseCleanupClaims([claim]), [claim]);
  assertEquals(parseCleanupClaims([]), []);
});
Deno.test("cleanup refuses an entire malformed claim batch before deletion", () => {
  for (
    const bad of [
      null,
      {},
      { ...claim, claim_token: null },
      { ...claim, claim_token: [token] },
      { ...claim, submission_id: [id] },
      { ...claim, evidence_revision: 1.5 },
      { ...claim, evidence_object_paths: [`${token}/${token}/${token}`] },
      { ...claim, reviewer_object_paths: ["../../foreign"] },
      {
        ...claim,
        evidence_object_paths: [
          ...claim.evidence_object_paths,
          ...claim.evidence_object_paths,
        ],
      },
    ]
  ) {
    assertThrows(() => parseCleanupClaims([claim, bad]));
  }
  assertThrows(() => parseCleanupClaims([claim, claim]));
});
