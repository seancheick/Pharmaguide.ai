import { assertThrows } from "jsr:@std/assert@1.0.14";
import {
  assertDraftEvidenceBinding,
  parseEvidenceBinding,
} from "./evidence.ts";

Deno.test("evidence binding rejects absent malformed and noninteger revisions", () => {
  for (const revision of [null, [], 0, 1.5, "1", Number.MAX_SAFE_INTEGER + 1]) {
    assertThrows(() =>
      parseEvidenceBinding({
        expected_evidence_revision: revision,
        evidence_manifest_sha256: "a".repeat(64),
      })
    );
  }
  assertThrows(() =>
    parseEvidenceBinding({
      expected_evidence_revision: 1,
      evidence_manifest_sha256: "foreign",
    })
  );
});
Deno.test("inner and outer draft metadata must bind to the same verified photo set", () => {
  const snapshot = { photo1: "a".repeat(64) };
  const metadata = {
    schema_version: "label_draft_v1",
    provider: "human",
    model: "human",
    prompt_version: "p1",
    evidence_revision: 2,
  };
  const draft = { ...metadata, evidence_snapshot: snapshot };
  const extraction = {
    ...metadata,
    input_image_hashes: snapshot,
    draft_payload: draft,
  };
  assertDraftEvidenceBinding(extraction, snapshot, 2);
  for (
    const patch of [{ evidence_revision: 1 }, { provider: "foreign" }, {
      evidence_snapshot: {},
    }, { evidence_snapshot: { photo2: "a".repeat(64) } }]
  ) {
    assertThrows(() =>
      assertDraftEvidenceBinding(
        { ...extraction, draft_payload: { ...draft, ...patch } },
        snapshot,
        2,
      )
    );
  }
  assertThrows(() =>
    assertDraftEvidenceBinding(
      { ...extraction, evidence_revision: 1 },
      snapshot,
      2,
    )
  );
});
