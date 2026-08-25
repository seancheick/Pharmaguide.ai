type JsonObject = Record<string, unknown>;

export type ListStatus =
  | "open"
  | "submitted"
  | "under_review"
  | "approved"
  | "rejected"
  | "duplicate";

export type ListCursor = {
  submittedAt: string;
  id: string;
};

export type ListRequest = {
  status: ListStatus | null;
  kind: "label_mismatch" | "missing_product" | null;
  limit: number;
  submissionId: string | null;
  after: ListCursor | null;
};

const ALLOWED_FIELDS = new Set([
  "action",
  "after",
  "kind",
  "limit",
  "status",
  "submission_id",
]);
const ALLOWED_CURSOR_FIELDS = new Set(["id", "submitted_at"]);
const STATUSES = new Set<ListStatus>([
  "open",
  "submitted",
  "under_review",
  "approved",
  "rejected",
  "duplicate",
]);
const KINDS = new Set(["label_mismatch", "missing_product"]);
const UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const TIMESTAMP_PATTERN =
  /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,6})?(?:Z|[+-]\d{2}:\d{2})$/;

function isObject(value: unknown): value is JsonObject {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}

function rejectUnknownKeys(
  value: JsonObject,
  allowed: ReadonlySet<string>,
): void {
  if (Object.keys(value).some((key) => !allowed.has(key))) {
    throw new Error("unknown list field");
  }
}

function uuid(value: unknown, name: string): string {
  if (typeof value !== "string" || !UUID_PATTERN.test(value)) {
    throw new Error(`invalid ${name}`);
  }
  return value.toLowerCase();
}

function timestamp(value: unknown): string {
  if (
    typeof value !== "string" || !TIMESTAMP_PATTERN.test(value) ||
    !Number.isFinite(Date.parse(value))
  ) {
    throw new Error("invalid submitted_at cursor");
  }
  return value;
}

export function parseListRequest(value: unknown): ListRequest {
  if (!isObject(value)) throw new Error("list request must be an object");
  rejectUnknownKeys(value, ALLOWED_FIELDS);
  if (value.action !== "list") throw new Error("invalid list action");

  const rawLimit = value.limit ?? 50;
  if (
    !Number.isInteger(rawLimit) || Number(rawLimit) < 1 ||
    Number(rawLimit) > 100
  ) {
    throw new Error("invalid list limit");
  }

  let status: ListStatus | null = null;
  if (value.status !== undefined && value.status !== null) {
    if (
      typeof value.status !== "string" ||
      !STATUSES.has(value.status as ListStatus)
    ) {
      throw new Error("invalid list status");
    }
    status = value.status as ListStatus;
  }

  let kind: ListRequest["kind"] = null;
  if (value.kind !== undefined && value.kind !== null) {
    if (typeof value.kind !== "string" || !KINDS.has(value.kind)) {
      throw new Error("invalid list kind");
    }
    kind = value.kind as ListRequest["kind"];
  }

  const submissionId = value.submission_id === undefined ||
      value.submission_id === null
    ? null
    : uuid(value.submission_id, "submission id");

  let after: ListCursor | null = null;
  if (value.after !== undefined && value.after !== null) {
    if (!isObject(value.after)) throw new Error("invalid list cursor");
    rejectUnknownKeys(value.after, ALLOWED_CURSOR_FIELDS);
    after = {
      submittedAt: timestamp(value.after.submitted_at),
      id: uuid(value.after.id, "cursor id"),
    };
  }
  if (submissionId !== null && after !== null) {
    throw new Error("submission id and cursor cannot be combined");
  }

  return {
    status,
    kind,
    limit: Number(rawLimit),
    submissionId,
    after,
  };
}

export function reviewStatusesForList(
  status: ListStatus | null,
): string[] | null {
  if (status === null) return null;
  if (status === "open") return ["submitted", "under_review"];
  return [status];
}

export function cursorFilter(after: ListCursor): string {
  return `submitted_at.gt.${after.submittedAt},` +
    `and(submitted_at.eq.${after.submittedAt},id.gt.${after.id})`;
}

export function nextListCursor(
  rows: JsonObject[],
  limit: number,
): { submitted_at: string; id: string } | null {
  if (rows.length < limit) return null;
  const last = rows.at(-1);
  if (!last) return null;
  return {
    submitted_at: timestamp(last.submitted_at),
    id: uuid(last.id, "cursor id"),
  };
}
