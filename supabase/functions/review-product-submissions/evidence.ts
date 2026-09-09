// One revision token shared by image, match and review requests. Clients echo
// the database fingerprint; they do not reconstruct PostgreSQL's JSON encoding.
export function parseEvidenceBinding(body: Record<string, unknown>): {
  expectedEvidenceRevision: number;
  evidenceManifestSha256: string;
} {
  const revision = body.expected_evidence_revision;
  const digest = body.evidence_manifest_sha256;
  if (
    typeof revision !== "number" || !Number.isSafeInteger(revision) ||
    revision < 1 ||
    typeof digest !== "string" || !/^[0-9a-f]{64}$/.test(digest)
  ) {
    throw new Error("current evidence revision and manifest required");
  }
  return { expectedEvidenceRevision: revision, evidenceManifestSha256: digest };
}

export function assertDraftEvidenceBinding(
  extraction: Record<string, unknown>,
  snapshot: Record<string, unknown>,
  revision: number,
): void {
  const draft = extraction.draft_payload as Record<string, unknown>;
  const equalSnapshot = (value: unknown): boolean => {
    if (!value || typeof value !== "object" || Array.isArray(value)) {
      return false;
    }
    const record = value as Record<string, unknown>;
    return Object.keys(record).length === Object.keys(snapshot).length &&
      Object.keys(snapshot).every((key) => record[key] === snapshot[key]);
  };
  if (
    !draft || extraction.evidence_revision !== revision ||
    draft.evidence_revision !== revision ||
    !equalSnapshot(extraction.input_image_hashes) ||
    !equalSnapshot(draft.evidence_snapshot) ||
    ["schema_version", "provider", "model", "prompt_version"].some((key) =>
      draft[key] !== extraction[key]
    )
  ) {
    throw new Error("extraction does not belong to the reviewed evidence");
  }
}
