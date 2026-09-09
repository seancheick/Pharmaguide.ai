export type CleanupClaim = {
  submission_id: string;
  claim_token: string;
  evidence_revision: number;
  evidence_object_paths: string[];
  reviewer_object_paths: string[];
};

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;
export function parseCleanupClaims(value: unknown): CleanupClaim[] {
  if (!Array.isArray(value) || value.length > 100) {
    throw new Error("invalid cleanup claims");
  }
  const seen = new Set<string>();
  for (const row of value) {
    if (
      !row || typeof row !== "object" ||
      typeof row.submission_id !== "string" ||
      typeof row.claim_token !== "string" || !UUID.test(row.submission_id) ||
      !UUID.test(row.claim_token) || seen.has(row.submission_id) ||
      !Number.isSafeInteger(row.evidence_revision) || row.evidence_revision < 1
    ) {
      throw new Error("invalid cleanup claim");
    }
    seen.add(row.submission_id);
    for (
      const paths of [row.evidence_object_paths, row.reviewer_object_paths]
    ) {
      if (
        !Array.isArray(paths) || new Set(paths).size !== paths.length ||
        !paths.every((path) => {
          if (typeof path !== "string") return false;
          const parts = path.split("/");
          return parts.length === 3 && parts.every((part) => UUID.test(part)) &&
            parts[1] === row.submission_id;
        })
      ) throw new Error("invalid cleanup object scope");
    }
  }
  return value;
}
