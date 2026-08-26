type JsonObject = Record<string, unknown>;

export type MatchOutcome =
  | "catalog_match"
  | "dsld_match"
  | "identity_ambiguous"
  | "no_match_verified"
  | "not_this_product";

export type RecordMatchRequest = {
  submissionId: string;
  outcome: MatchOutcome;
  canonicalGtin14: string;
  indexBuiltAt: string;
  matchedDsldId: string | null;
  candidateDsldIds: string[];
  reason: string | null;
};

const UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const GTIN14_PATTERN = /^[0-9]{14}$/;
const PRODUCT_ID_PATTERN = /^([0-9]{1,30}|PG_SUB_[0-9A-F]{32})$/;
const TIMESTAMP_PATTERN =
  /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,6})?(?:Z|[+-]\d{2}:\d{2})$/;
const OUTCOMES = new Set<MatchOutcome>([
  "catalog_match",
  "dsld_match",
  "identity_ambiguous",
  "no_match_verified",
  "not_this_product",
]);
const ALLOWED_FIELDS = new Set([
  "action",
  "submission_id",
  "outcome",
  "canonical_gtin14",
  "index_built_at",
  "matched_dsld_id",
  "candidate_dsld_ids",
  "reason",
]);

function isObject(value: unknown): value is JsonObject {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}

function requiredString(value: unknown, name: string, max: number): string {
  if (
    typeof value !== "string" || value.trim().length === 0 ||
    value.length > max
  ) {
    throw new Error(`invalid ${name}`);
  }
  return value.trim();
}

function productId(value: unknown, name: string): string {
  const parsed = requiredString(value, name, 40);
  if (!PRODUCT_ID_PATTERN.test(parsed)) throw new Error(`invalid ${name}`);
  return parsed;
}

function hasValidGtinCheckDigit(gtin: string): boolean {
  let sum = 0;
  for (let index = 0; index < gtin.length - 1; index += 1) {
    const digit = Number(gtin[index]);
    const weight = (gtin.length - 1 - index) % 2 === 1 ? 3 : 1;
    sum += digit * weight;
  }
  return (10 - (sum % 10)) % 10 === Number(gtin.at(-1));
}

export function parseRecordMatchRequest(value: unknown): RecordMatchRequest {
  if (!isObject(value)) throw new Error("match request must be an object");
  if (Object.keys(value).some((key) => !ALLOWED_FIELDS.has(key))) {
    throw new Error("unknown match field");
  }
  if (value.action !== "record_match") throw new Error("invalid match action");

  const submissionId = requiredString(value.submission_id, "submission id", 36)
    .toLowerCase();
  if (!UUID_PATTERN.test(submissionId)) throw new Error("invalid submission id");

  const outcome = requiredString(value.outcome, "match outcome", 40) as MatchOutcome;
  if (!OUTCOMES.has(outcome)) throw new Error("invalid match outcome");

  const canonicalGtin14 = requiredString(
    value.canonical_gtin14,
    "canonical GTIN-14",
    14,
  );
  if (
    !GTIN14_PATTERN.test(canonicalGtin14) ||
    !hasValidGtinCheckDigit(canonicalGtin14)
  ) {
    throw new Error("invalid canonical GTIN-14");
  }

  const indexBuiltAt = requiredString(value.index_built_at, "index built-at", 40);
  if (
    !TIMESTAMP_PATTERN.test(indexBuiltAt) ||
    !Number.isFinite(Date.parse(indexBuiltAt))
  ) {
    throw new Error("invalid index built-at");
  }

  const matchedDsldId = value.matched_dsld_id === undefined ||
      value.matched_dsld_id === null
    ? null
    : productId(value.matched_dsld_id, "matched product id");
  const rawCandidates = value.candidate_dsld_ids ?? [];
  if (!Array.isArray(rawCandidates) || rawCandidates.length > 100) {
    throw new Error("invalid match candidates");
  }
  const candidateDsldIds = rawCandidates.map((candidate) =>
    productId(candidate, "candidate product id")
  );
  if (new Set(candidateDsldIds).size !== candidateDsldIds.length) {
    throw new Error("duplicate match candidate");
  }
  const reason = value.reason === undefined || value.reason === null
    ? null
    : requiredString(value.reason, "match reason", 1000);

  if (outcome === "catalog_match" || outcome === "dsld_match") {
    if (matchedDsldId === null || candidateDsldIds.length !== 0 || reason !== null) {
      throw new Error("invalid exact-match evidence");
    }
  } else if (outcome === "identity_ambiguous") {
    if (matchedDsldId !== null || candidateDsldIds.length < 2 || reason !== null) {
      throw new Error("invalid ambiguous-match evidence");
    }
  } else if (outcome === "no_match_verified") {
    if (matchedDsldId !== null || candidateDsldIds.length !== 0 || reason !== null) {
      throw new Error("invalid no-match evidence");
    }
  } else if (
    matchedDsldId === null || candidateDsldIds.length !== 0 || reason === null
  ) {
    throw new Error("invalid wrong-product override");
  }

  return {
    submissionId,
    outcome,
    canonicalGtin14,
    indexBuiltAt,
    matchedDsldId,
    candidateDsldIds,
    reason,
  };
}
