export type JsonObject = Record<string, unknown>;

const TOP_LEVEL_FIELDS = new Set([
  "brandName",
  "fullName",
  "ingredientRows",
  "nutritionalInfo",
  "offMarket",
  "otherIngredients",
  "otherIngredientsDisclosure",
  "physicalState",
  "productType",
  "servingSizes",
  "servingsPerContainer",
  "statements",
]);
const INGREDIENT_FIELDS = new Set([
  "alternateNames",
  "category",
  "description",
  "forms",
  "ingredientGroup",
  "ingredientId",
  "name",
  "nestedRows",
  "notes",
  "order",
  "quantity",
  "uniiCode",
]);
const QUANTITY_FIELDS = new Set([
  "dailyValueTargetGroup",
  "operator",
  "quantity",
  "servingSizeOrder",
  "servingSizeQuantity",
  "servingSizeUnit",
  "unit",
]);
const FORM_FIELDS = new Set([
  "category",
  "ingredientGroup",
  "ingredientId",
  "name",
  "order",
  "percent",
  "prefix",
  "uniiCode",
]);
const SERVING_FIELDS = new Set([
  "inSFB",
  "maxDailyServings",
  "maxQuantity",
  "minDailyServings",
  "minQuantity",
  "notes",
  "order",
  "unit",
]);
const STATEMENT_FIELDS = new Set(["notes", "type"]);
const CLASSIFICATION_FIELDS = new Set([
  "langualCode",
  "langualCodeDescription",
  "name",
]);
const DISCLOSURES = new Set([
  "present",
  "declared_none",
  "included_on_facts_panel",
]);
const MAX_INGREDIENT_DEPTH = 5;
const MAX_TOTAL_INGREDIENT_ROWS = 500;

function isObject(value: unknown): value is JsonObject {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}

function object(value: unknown, name: string): JsonObject {
  if (!isObject(value)) throw new Error(`${name} must be an object`);
  return value;
}

function rejectUnknownKeys(
  value: JsonObject,
  allowed: ReadonlySet<string>,
  name: string,
): void {
  const unknown = Object.keys(value).filter((key) => !allowed.has(key));
  if (unknown.length > 0) {
    throw new Error(`${name} contains unknown field ${unknown.sort()[0]}`);
  }
}

function stringValue(
  value: unknown,
  name: string,
  maxLength: number,
  allowEmpty = false,
): string {
  if (typeof value !== "string" || value.length > maxLength) {
    throw new Error(`${name} must be a string`);
  }
  const normalized = value.trim();
  if (!allowEmpty && normalized.length === 0) {
    throw new Error(`${name} must not be empty`);
  }
  return normalized;
}

function optionalString(
  value: unknown,
  name: string,
  maxLength: number,
): void {
  if (value !== undefined && value !== null) {
    stringValue(value, name, maxLength, true);
  }
}

function finiteNumber(
  value: unknown,
  name: string,
  minimum: number,
): number {
  if (
    typeof value !== "number" || !Number.isFinite(value) || value < minimum
  ) {
    throw new Error(`${name} must be a finite number >= ${minimum}`);
  }
  return value;
}

function optionalPositiveInteger(value: unknown, name: string): void {
  if (value === undefined || value === null) return;
  if (!Number.isInteger(value) || (value as number) <= 0) {
    throw new Error(`${name} must be a positive integer`);
  }
}

function validateQuantity(value: unknown, path: string): void {
  const quantity = object(value, path);
  rejectUnknownKeys(quantity, QUANTITY_FIELDS, path);
  finiteNumber(quantity.quantity, `${path}.quantity`, 0);
  stringValue(quantity.unit, `${path}.unit`, 80);
  optionalPositiveInteger(
    quantity.servingSizeOrder,
    `${path}.servingSizeOrder`,
  );
  if (quantity.servingSizeQuantity !== undefined) {
    finiteNumber(
      quantity.servingSizeQuantity,
      `${path}.servingSizeQuantity`,
      0,
    );
  }
  optionalString(quantity.operator, `${path}.operator`, 20);
  optionalString(quantity.servingSizeUnit, `${path}.servingSizeUnit`, 80);
  if (quantity.dailyValueTargetGroup !== undefined) {
    if (
      !Array.isArray(quantity.dailyValueTargetGroup) ||
      quantity.dailyValueTargetGroup.length > 30
    ) {
      throw new Error(`${path}.dailyValueTargetGroup must be an array`);
    }
  }
}

function validateForm(value: unknown, path: string): void {
  const form = object(value, path);
  rejectUnknownKeys(form, FORM_FIELDS, path);
  stringValue(form.name, `${path}.name`, 300);
  optionalPositiveInteger(form.order, `${path}.order`);
  optionalPositiveInteger(form.ingredientId, `${path}.ingredientId`);
  optionalString(form.prefix, `${path}.prefix`, 80);
  optionalString(form.category, `${path}.category`, 120);
  optionalString(form.ingredientGroup, `${path}.ingredientGroup`, 300);
  optionalString(form.uniiCode, `${path}.uniiCode`, 80);
  if (form.percent !== undefined && form.percent !== null) {
    const percent = finiteNumber(form.percent, `${path}.percent`, 0);
    if (percent > 100) throw new Error(`${path}.percent must be <= 100`);
  }
}

function validateIngredientRow(
  value: unknown,
  path: string,
  depth: number,
  rowCounter: { count: number },
): void {
  if (depth > MAX_INGREDIENT_DEPTH) {
    throw new Error(`${path} exceeds maximum nesting depth`);
  }
  rowCounter.count += 1;
  if (rowCounter.count > MAX_TOTAL_INGREDIENT_ROWS) {
    throw new Error("ingredient rows exceed maximum total");
  }
  const row = object(value, path);
  rejectUnknownKeys(row, INGREDIENT_FIELDS, path);
  stringValue(row.name, `${path}.name`, 300);
  stringValue(row.ingredientGroup, `${path}.ingredientGroup`, 300);
  optionalPositiveInteger(row.order, `${path}.order`);
  optionalPositiveInteger(row.ingredientId, `${path}.ingredientId`);
  optionalString(row.category, `${path}.category`, 120);
  optionalString(row.description, `${path}.description`, 2000);
  optionalString(row.notes, `${path}.notes`, 2000);
  optionalString(row.uniiCode, `${path}.uniiCode`, 80);

  if (!Array.isArray(row.quantity) || row.quantity.length > 20) {
    throw new Error(`${path}.quantity must contain 0..20 rows`);
  }
  row.quantity.forEach((quantity, index) =>
    validateQuantity(quantity, `${path}.quantity[${index}]`)
  );
  if (!Array.isArray(row.forms) || row.forms.length > 20) {
    throw new Error(`${path}.forms must contain 0..20 rows`);
  }
  row.forms.forEach((form, index) =>
    validateForm(form, `${path}.forms[${index}]`)
  );
  if (!Array.isArray(row.nestedRows) || row.nestedRows.length > 100) {
    throw new Error(`${path}.nestedRows must contain 0..100 rows`);
  }
  row.nestedRows.forEach((nested, index) =>
    validateIngredientRow(
      nested,
      `${path}.nestedRows[${index}]`,
      depth + 1,
      rowCounter,
    )
  );
  if (row.alternateNames !== undefined) {
    if (
      !Array.isArray(row.alternateNames) || row.alternateNames.length > 50 ||
      !row.alternateNames.every((name, index) => {
        try {
          stringValue(name, `${path}.alternateNames[${index}]`, 300);
          return true;
        } catch {
          return false;
        }
      })
    ) {
      throw new Error(`${path}.alternateNames must contain valid strings`);
    }
  }
}

function validateServingSize(value: unknown, path: string): void {
  const serving = object(value, path);
  rejectUnknownKeys(serving, SERVING_FIELDS, path);
  finiteNumber(serving.minQuantity, `${path}.minQuantity`, Number.EPSILON);
  finiteNumber(serving.maxQuantity, `${path}.maxQuantity`, Number.EPSILON);
  stringValue(serving.unit, `${path}.unit`, 80);
  optionalPositiveInteger(serving.order, `${path}.order`);
  optionalString(serving.notes, `${path}.notes`, 1000);
  for (const field of ["minDailyServings", "maxDailyServings"] as const) {
    if (serving[field] !== undefined && serving[field] !== null) {
      finiteNumber(serving[field], `${path}.${field}`, Number.EPSILON);
    }
  }
  if (serving.inSFB !== undefined && typeof serving.inSFB !== "boolean") {
    throw new Error(`${path}.inSFB must be a boolean`);
  }
  if ((serving.maxQuantity as number) < (serving.minQuantity as number)) {
    throw new Error(`${path}.maxQuantity must be >= minQuantity`);
  }
}

function validateStatements(value: unknown): void {
  if (!Array.isArray(value) || value.length > 100) {
    throw new Error("statements must contain 0..100 rows");
  }
  value.forEach((raw, index) => {
    const path = `statements[${index}]`;
    const statement = object(raw, path);
    rejectUnknownKeys(statement, STATEMENT_FIELDS, path);
    stringValue(statement.type, `${path}.type`, 200);
    stringValue(statement.notes, `${path}.notes`, 5000);
  });
}

function validateClassification(value: unknown, name: string): void {
  const classification = object(value, name);
  rejectUnknownKeys(classification, CLASSIFICATION_FIELDS, name);
  optionalString(classification.langualCode, `${name}.langualCode`, 40);
  optionalString(
    classification.langualCodeDescription,
    `${name}.langualCodeDescription`,
    300,
  );
  optionalString(classification.name, `${name}.name`, 300);
  const display = classification.name ?? classification.langualCodeDescription;
  stringValue(display, `${name} display name`, 300);
}

function validateServingsPerContainer(value: unknown): void {
  if (typeof value === "number") {
    finiteNumber(value, "servingsPerContainer", Number.EPSILON);
    return;
  }
  const text = stringValue(value, "servingsPerContainer", 40);
  const parsed = Number(text);
  if (!Number.isFinite(parsed) || parsed <= 0) {
    throw new Error("servingsPerContainer must be positive");
  }
}

export function validateManualLabelV1(value: unknown): JsonObject {
  const payload = object(value, "approved payload");
  rejectUnknownKeys(payload, TOP_LEVEL_FIELDS, "approved payload");
  stringValue(payload.brandName, "approved payload.brandName", 300);
  stringValue(payload.fullName, "approved payload.fullName", 300);

  if (
    !Array.isArray(payload.ingredientRows) ||
    payload.ingredientRows.length === 0 ||
    payload.ingredientRows.length > 200
  ) {
    throw new Error("approved payload.ingredientRows must contain 1..200 rows");
  }
  const rowCounter = { count: 0 };
  payload.ingredientRows.forEach((row, index) =>
    validateIngredientRow(row, `ingredientRows[${index}]`, 1, rowCounter)
  );

  if (
    !Array.isArray(payload.servingSizes) ||
    payload.servingSizes.length === 0 || payload.servingSizes.length > 20
  ) {
    throw new Error("approved payload.servingSizes must contain 1..20 rows");
  }
  payload.servingSizes.forEach((serving, index) =>
    validateServingSize(serving, `servingSizes[${index}]`)
  );

  if (
    payload.offMarket !== undefined && payload.offMarket !== 0 &&
    payload.offMarket !== 1 && payload.offMarket !== false &&
    payload.offMarket !== true
  ) {
    throw new Error("approved payload.offMarket must be 0 or 1");
  }
  if (payload.servingsPerContainer !== undefined) {
    validateServingsPerContainer(payload.servingsPerContainer);
  }
  if (payload.physicalState !== undefined) {
    validateClassification(payload.physicalState, "physicalState");
  }
  if (payload.productType !== undefined) {
    validateClassification(payload.productType, "productType");
  }
  if (payload.statements !== undefined) validateStatements(payload.statements);
  if (
    payload.nutritionalInfo !== undefined &&
    !isObject(payload.nutritionalInfo)
  ) {
    throw new Error("nutritionalInfo must be an object");
  }

  const disclosure = stringValue(
    payload.otherIngredientsDisclosure,
    "otherIngredientsDisclosure",
    40,
  );
  if (!DISCLOSURES.has(disclosure)) {
    throw new Error("otherIngredientsDisclosure is unresolved or invalid");
  }
  const otherIngredients = payload.otherIngredients === undefined
    ? ""
    : stringValue(payload.otherIngredients, "otherIngredients", 20_000, true);
  if (disclosure === "present" && otherIngredients.length === 0) {
    throw new Error("present other ingredients require text");
  }
  if (disclosure !== "present" && otherIngredients.length !== 0) {
    throw new Error(`${disclosure} requires empty otherIngredients`);
  }
  return payload;
}

// ---------------------------------------------------------------------------
// label_draft_v1: the provenance-bound partial draft an extractor produces.
//
// A draft is what a reviewer starts from, never what the catalog ingests. It
// may carry explicit unknowns, per-field photo provenance and typed
// discrepancies; it may not carry anything a model is forbidden to mint
// (identities, citations, scores, verdicts). Mirrors
// scripts/submission_review/extraction/envelope.py in the pipeline repo; both
// pin fixtures/label_draft_v1_cases.json by checksum. Validation never
// normalizes label text and returns the value unchanged.

export const LABEL_DRAFT_SCHEMA_VERSION = "label_draft_v1";

const DRAFT_FORBIDDEN_KEYS: ReadonlySet<string> = new Set([
  "canonical_id",
  "canonical_ids",
  "clean_identity_id",
  "cui",
  "rxcui",
  "unii",
  "pmid",
  "pmids",
  "score",
  "scores",
  "verdict",
  "benefit",
  "benefits",
  "safety_verdict",
]);
const DRAFT_FIELD_STATUSES = new Set(["read", "partial", "unreadable", "not_present"]);
const DRAFT_ROW_STATUSES = new Set(["read", "partial", "unreadable"]);
const DRAFT_READABILITIES = new Set(["ok", "partial", "unreadable"]);
const DRAFT_PHOTO_ISSUES = new Set([
  "glare",
  "blur",
  "cut_off",
  "curved",
  "dark",
  "small_print",
]);
const DRAFT_PHOTO_ROLES = new Set([
  "front_identity",
  "supplement_facts",
  "ingredient_disclosure",
  "directions_warnings",
  "barcode",
  "lot_expiry",
]);
const DRAFT_DISCLOSURE_HINTS = new Set([
  "present",
  "declared_none",
  "on_facts_panel",
  "unknown",
]);
const DRAFT_DISCREPANCY_CODES = new Set([
  "barcode_mismatch",
  "multiple_products",
  "front_facts_brand_conflict",
  "declared_role_mismatch",
  "facts_panel_missing",
  "facts_unreadable",
  "cut_off_text",
  "foreign_language",
  "handwritten",
  "expired_date_seen",
  "injection_text_present",
  "serving_basis_ambiguous",
  "catalog_candidate",
  "model_failure",
]);
const DRAFT_SEVERITIES = new Set(["info", "warning", "critical"]);
const DRAFT_TOP_LEVEL_KEYS = new Set([
  "schema_version",
  "provider",
  "model",
  "prompt_version",
  "job_key",
  "result_fingerprint",
  "evidence_revision",
  "evidence_snapshot",
  "sent_inputs",
  "photo_roles",
  "identity",
  "serving",
  "ingredient_rows",
  "other_ingredients",
  "statements",
  "discrepancies",
  "abstained",
  "abstain_reason",
  "overall_confidence",
]);
const DRAFT_OPTIONAL_TOP_LEVEL_KEYS = new Set([
  "job_key",
  "result_fingerprint",
  "evidence_revision",
]);
const DRAFT_MAX_INGREDIENT_ROWS = 500;
const DRAFT_MAX_STATEMENTS = 100;
const DRAFT_MAX_DISCREPANCIES = 100;
const DRAFT_MAX_TEXT = 2000;
const DRAFT_MAX_SHORT = 200;
const DRAFT_UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;
const DRAFT_SHA256 = /^[0-9a-f]{64}$/;
const DRAFT_TOKEN = /^[A-Za-z0-9._:/+-]{1,120}$/;

type Snapshot = Record<string, string>;

function draftFail(path: string, message: string): never {
  throw new Error(`${path}: ${message}`);
}

function draftObject(value: unknown, path: string): JsonObject {
  if (!isObject(value)) draftFail(path, "must be an object");
  return value;
}

function draftList(value: unknown, path: string, maximum: number): unknown[] {
  if (!Array.isArray(value)) draftFail(path, "must be an array");
  if (value.length > maximum) draftFail(path, `at most ${maximum} items`);
  return value;
}

function draftRejectUnknown(
  value: JsonObject,
  allowed: ReadonlySet<string>,
  path: string,
): void {
  const unknown = Object.keys(value).filter((key) => !allowed.has(key)).sort();
  if (unknown.length > 0) draftFail(path, `unknown key ${unknown[0]}`);
}

function draftRejectForbiddenKeys(value: unknown, path: string): void {
  if (Array.isArray(value)) {
    value.forEach((child, index) =>
      draftRejectForbiddenKeys(child, `${path}[${index}]`)
    );
    return;
  }
  if (!isObject(value)) return;
  for (const [key, child] of Object.entries(value)) {
    if (DRAFT_FORBIDDEN_KEYS.has(key.toLowerCase())) {
      draftFail(`${path}.${key}`, "model output may not carry this key");
    }
    draftRejectForbiddenKeys(child, `${path}.${key}`);
  }
}

function draftToken(value: unknown, path: string): void {
  if (typeof value !== "string" || !DRAFT_TOKEN.test(value)) {
    draftFail(path, "must be a short token");
  }
}

function draftText(
  value: unknown,
  path: string,
  maximum: number,
  required: boolean,
): void {
  if (value === null && !required) return;
  if (typeof value !== "string") draftFail(path, "must be text");
  if (required && value.trim().length === 0) draftFail(path, "must not be empty");
  if (value.length > maximum) draftFail(path, `at most ${maximum} characters`);
}

function draftFiniteNumber(
  value: unknown,
  path: string,
  minimum: number | null = null,
): number {
  if (typeof value !== "number" || !Number.isFinite(value)) {
    draftFail(path, "must be a finite number");
  }
  if (minimum !== null && value < minimum) {
    draftFail(path, `must be at least ${minimum}`);
  }
  return value;
}

function draftPositiveInt(value: unknown, path: string): void {
  if (!Number.isInteger(value) || (value as number) < 1) {
    draftFail(path, "must be a positive integer");
  }
}

function draftConfidence(value: unknown, path: string): void {
  if (value === null || value === undefined) return;
  const number = draftFiniteNumber(value, path);
  if (number < 0 || number > 1) draftFail(path, "must be between 0 and 1");
}

function draftPhotoRef(value: unknown, path: string, snapshot: Snapshot): string {
  if (typeof value !== "string" || !(value in snapshot)) {
    draftFail(path, "must reference a snapshot photo");
  }
  return value;
}

function draftRegion(value: unknown, path: string): void {
  const region = draftObject(value, path);
  draftRejectUnknown(region, new Set(["x", "y", "w", "h"]), path);
  const components: Record<string, number> = {};
  for (const key of ["x", "y", "w", "h"]) {
    const component = draftFiniteNumber(region[key], `${path}.${key}`);
    if (component < 0 || component > 1) {
      draftFail(`${path}.${key}`, "must be a fraction of the image");
    }
    components[key] = component;
  }
  if (
    components.x + components.w > 1.000001 ||
    components.y + components.h > 1.000001
  ) {
    draftFail(path, "must stay inside the image");
  }
}

function draftSources(
  value: unknown,
  path: string,
  snapshot: Snapshot,
): unknown[] {
  const sources = draftList(value, path, Object.keys(snapshot).length * 4);
  sources.forEach((source, index) => {
    const spath = `${path}[${index}]`;
    const entry = draftObject(source, spath);
    draftRejectUnknown(
      entry,
      new Set(["photo_id", "supporting_text", "region"]),
      spath,
    );
    draftPhotoRef(entry.photo_id, `${spath}.photo_id`, snapshot);
    draftText(
      entry.supporting_text ?? null,
      `${spath}.supporting_text`,
      DRAFT_MAX_TEXT,
      false,
    );
    if (entry.region !== undefined && entry.region !== null) {
      draftRegion(entry.region, `${spath}.region`);
    }
  });
  return sources;
}

function draftField(
  value: unknown,
  path: string,
  snapshot: Snapshot,
  numeric = false,
): void {
  const field = draftObject(value, path);
  draftRejectUnknown(
    field,
    new Set(["value", "status", "confidence", "sources"]),
    path,
  );
  const status = field.status;
  if (typeof status !== "string" || !DRAFT_FIELD_STATUSES.has(status)) {
    draftFail(`${path}.status`, "unknown field status");
  }
  const raw = field.value ?? null;
  const sources = draftSources(field.sources, `${path}.sources`, snapshot);
  if (status === "read" || status === "partial") {
    if (raw === null) draftFail(`${path}.value`, `${status} field requires a value`);
    if (sources.length === 0) {
      draftFail(`${path}.sources`, `${status} field requires a source`);
    }
  } else {
    if (raw !== null) draftFail(`${path}.value`, `${status} field must have no value`);
    if (sources.length > 0) {
      draftFail(`${path}.sources`, `${status} field must have no sources`);
    }
  }
  if (raw !== null) {
    if (numeric) {
      draftFiniteNumber(raw, `${path}.value`, 0);
    } else if (isObject(raw) || Array.isArray(raw)) {
      draftFail(`${path}.value`, "must be text or a number");
    } else if (typeof raw === "string") {
      draftText(raw, `${path}.value`, DRAFT_MAX_TEXT, true);
    } else {
      draftFiniteNumber(raw, `${path}.value`);
    }
  }
  draftConfidence(field.confidence, `${path}.confidence`);
}

function draftNullableField(
  value: unknown,
  path: string,
  snapshot: Snapshot,
  numeric = false,
): void {
  if (value === null || value === undefined) return;
  draftField(value, path, snapshot, numeric);
}

function draftAmount(value: unknown, path: string, snapshot: Snapshot): void {
  if (value === null || value === undefined) return;
  const field = draftObject(value, path);
  draftRejectUnknown(
    field,
    new Set(["value", "status", "confidence", "sources"]),
    path,
  );
  const status = field.status;
  if (typeof status !== "string" || !DRAFT_FIELD_STATUSES.has(status)) {
    draftFail(`${path}.status`, "unknown field status");
  }
  const raw = field.value ?? null;
  const sources = draftSources(field.sources, `${path}.sources`, snapshot);
  if (status === "read" || status === "partial") {
    const amount = draftObject(raw, `${path}.value`);
    draftRejectUnknown(amount, new Set(["value", "unit_text"]), `${path}.value`);
    draftFiniteNumber(amount.value, `${path}.value.value`, 0);
    draftText(amount.unit_text, `${path}.value.unit_text`, DRAFT_MAX_SHORT, true);
    if (sources.length === 0) {
      draftFail(`${path}.sources`, `${status} amount requires a source`);
    }
  } else if (raw !== null || sources.length > 0) {
    draftFail(`${path}.value`, `${status} amount must have no value`);
  }
  draftConfidence(field.confidence, `${path}.confidence`);
}

function draftSnapshot(value: unknown): Snapshot {
  const snapshot = draftObject(value, "$.evidence_snapshot");
  const entries = Object.entries(snapshot);
  if (entries.length === 0) {
    draftFail("$.evidence_snapshot", "at least one photo required");
  }
  const result: Snapshot = {};
  for (const [photoId, digest] of entries) {
    if (!DRAFT_UUID.test(photoId)) {
      draftFail("$.evidence_snapshot", `invalid photo id ${photoId}`);
    }
    if (typeof digest !== "string" || !DRAFT_SHA256.test(digest)) {
      draftFail(`$.evidence_snapshot.${photoId}`, "invalid sha256");
    }
    result[photoId] = digest;
  }
  return result;
}

function draftSentInputs(value: unknown, snapshot: Snapshot): void {
  const items = draftList(
    value,
    "$.sent_inputs",
    Object.keys(snapshot).length * 4,
  );
  items.forEach((item, index) => {
    const path = `$.sent_inputs[${index}]`;
    const entry = draftObject(item, path);
    draftRejectUnknown(entry, new Set(["photo_id", "sha256", "crop"]), path);
    const photoId = draftPhotoRef(entry.photo_id, `${path}.photo_id`, snapshot);
    if (entry.sha256 !== snapshot[photoId]) {
      draftFail(`${path}.sha256`, "must equal the snapshot hash");
    }
    if (entry.crop !== undefined && entry.crop !== null) {
      draftRegion(entry.crop, `${path}.crop`);
    }
  });
}

function draftPhotoRoles(value: unknown, snapshot: Snapshot): void {
  const roles = draftList(value, "$.photo_roles", Object.keys(snapshot).length);
  roles.forEach((item, index) => {
    const path = `$.photo_roles[${index}]`;
    const entry = draftObject(item, path);
    draftRejectUnknown(
      entry,
      new Set(["photo_id", "declared", "inferred", "readability", "issues"]),
      path,
    );
    draftPhotoRef(entry.photo_id, `${path}.photo_id`, snapshot);
    for (
      const role of draftList(
        entry.declared,
        `${path}.declared`,
        DRAFT_PHOTO_ROLES.size,
      )
    ) {
      if (typeof role !== "string" || !DRAFT_PHOTO_ROLES.has(role)) {
        draftFail(`${path}.declared`, `unknown role ${String(role)}`);
      }
    }
    draftList(entry.inferred, `${path}.inferred`, DRAFT_PHOTO_ROLES.size)
      .forEach((inferred, j) => {
        const ipath = `${path}.inferred[${j}]`;
        const inferredObject = draftObject(inferred, ipath);
        draftRejectUnknown(inferredObject, new Set(["role", "confidence"]), ipath);
        if (
          typeof inferredObject.role !== "string" ||
          !DRAFT_PHOTO_ROLES.has(inferredObject.role)
        ) {
          draftFail(`${ipath}.role`, "unknown role");
        }
        draftConfidence(inferredObject.confidence, `${ipath}.confidence`);
      });
    if (
      typeof entry.readability !== "string" ||
      !DRAFT_READABILITIES.has(entry.readability)
    ) {
      draftFail(`${path}.readability`, "unknown readability");
    }
    for (
      const issue of draftList(entry.issues, `${path}.issues`, DRAFT_PHOTO_ISSUES.size)
    ) {
      if (typeof issue !== "string" || !DRAFT_PHOTO_ISSUES.has(issue)) {
        draftFail(`${path}.issues`, `unknown issue ${String(issue)}`);
      }
    }
  });
}

function draftIngredientRows(value: unknown, snapshot: Snapshot): void {
  const rows = draftList(value, "$.ingredient_rows", DRAFT_MAX_INGREDIENT_ROWS);
  const headers = new Set<number>();
  rows.forEach((item, index) => {
    const path = `$.ingredient_rows[${index}]`;
    const row = draftObject(item, path);
    draftRejectUnknown(
      row,
      new Set([
        "display_name",
        "amount",
        "percent_dv",
        "form_text",
        "parent_index",
        "is_blend_header",
        "status",
      ]),
      path,
    );
    draftField(row.display_name, `${path}.display_name`, snapshot);
    draftAmount(row.amount, `${path}.amount`, snapshot);
    draftNullableField(row.percent_dv, `${path}.percent_dv`, snapshot, true);
    draftNullableField(row.form_text, `${path}.form_text`, snapshot);
    if (typeof row.is_blend_header !== "boolean") {
      draftFail(`${path}.is_blend_header`, "must be boolean");
    }
    if (typeof row.status !== "string" || !DRAFT_ROW_STATUSES.has(row.status)) {
      draftFail(`${path}.status`, "unknown row status");
    }
    const parent = row.parent_index ?? null;
    if (parent !== null) {
      if (!Number.isInteger(parent)) {
        draftFail(`${path}.parent_index`, "must be an integer or null");
      }
      const parentIndex = parent as number;
      if (parentIndex < 0 || parentIndex >= index) {
        draftFail(`${path}.parent_index`, "must reference an earlier row");
      }
      if (!headers.has(parentIndex)) {
        draftFail(`${path}.parent_index`, "must reference a blend header");
      }
    }
    if (row.is_blend_header === true) headers.add(index);
  });
}

function draftDiscrepancies(value: unknown, snapshot: Snapshot): void {
  const items = draftList(value, "$.discrepancies", DRAFT_MAX_DISCREPANCIES);
  items.forEach((item, index) => {
    const path = `$.discrepancies[${index}]`;
    const entry = draftObject(item, path);
    draftRejectUnknown(
      entry,
      new Set(["code", "severity", "detail", "photo_ids"]),
      path,
    );
    if (typeof entry.code !== "string" || !DRAFT_DISCREPANCY_CODES.has(entry.code)) {
      draftFail(`${path}.code`, "unknown discrepancy code");
    }
    if (
      typeof entry.severity !== "string" || !DRAFT_SEVERITIES.has(entry.severity)
    ) {
      draftFail(`${path}.severity`, "unknown severity");
    }
    draftText(entry.detail ?? null, `${path}.detail`, DRAFT_MAX_TEXT, false);
    draftList(entry.photo_ids, `${path}.photo_ids`, Object.keys(snapshot).length)
      .forEach((photoId, j) =>
        draftPhotoRef(photoId, `${path}.photo_ids[${j}]`, snapshot)
      );
  });
}

/** Validate a partial draft; returns the value unchanged (no normalization). */
export function validateLabelDraftV1(value: unknown): JsonObject {
  const draft = draftObject(value, "$");
  draftRejectUnknown(draft, DRAFT_TOP_LEVEL_KEYS, "$");
  for (const key of [...DRAFT_TOP_LEVEL_KEYS].sort()) {
    if (!DRAFT_OPTIONAL_TOP_LEVEL_KEYS.has(key) && !(key in draft)) {
      draftFail(`$.${key}`, "required");
    }
  }
  draftRejectForbiddenKeys(draft, "$");
  if (draft.schema_version !== LABEL_DRAFT_SCHEMA_VERSION) {
    draftFail("$.schema_version", `must be ${LABEL_DRAFT_SCHEMA_VERSION}`);
  }
  for (const key of ["provider", "model", "prompt_version"]) {
    draftToken(draft[key], `$.${key}`);
  }
  for (const key of ["job_key", "result_fingerprint"]) {
    if (draft[key] !== undefined && draft[key] !== null) {
      draftToken(draft[key], `$.${key}`);
    }
  }
  if (draft.evidence_revision !== undefined && draft.evidence_revision !== null) {
    draftPositiveInt(draft.evidence_revision, "$.evidence_revision");
  }

  const snapshot = draftSnapshot(draft.evidence_snapshot);
  draftSentInputs(draft.sent_inputs, snapshot);
  draftPhotoRoles(draft.photo_roles, snapshot);

  const identity = draftObject(draft.identity, "$.identity");
  draftRejectUnknown(
    identity,
    new Set(["brand", "product_name", "barcode_digits_seen"]),
    "$.identity",
  );
  draftField(identity.brand, "$.identity.brand", snapshot);
  draftField(identity.product_name, "$.identity.product_name", snapshot);
  draftNullableField(
    identity.barcode_digits_seen,
    "$.identity.barcode_digits_seen",
    snapshot,
  );

  const serving = draftObject(draft.serving, "$.serving");
  draftRejectUnknown(
    serving,
    new Set(["size", "servings_per_container", "basis_text"]),
    "$.serving",
  );
  for (const key of ["size", "servings_per_container", "basis_text"]) {
    draftField(serving[key], `$.serving.${key}`, snapshot);
  }

  draftIngredientRows(draft.ingredient_rows, snapshot);

  const other = draftObject(draft.other_ingredients, "$.other_ingredients");
  draftRejectUnknown(
    other,
    new Set(["text", "disclosure_hint"]),
    "$.other_ingredients",
  );
  draftNullableField(other.text, "$.other_ingredients.text", snapshot);
  if (
    typeof other.disclosure_hint !== "string" ||
    !DRAFT_DISCLOSURE_HINTS.has(other.disclosure_hint)
  ) {
    draftFail("$.other_ingredients.disclosure_hint", "unknown disclosure hint");
  }

  draftList(draft.statements, "$.statements", DRAFT_MAX_STATEMENTS)
    .forEach((statement, index) =>
      draftField(statement, `$.statements[${index}]`, snapshot)
    );

  draftDiscrepancies(draft.discrepancies, snapshot);

  if (typeof draft.abstained !== "boolean") {
    draftFail("$.abstained", "must be boolean");
  }
  const reason = draft.abstain_reason ?? null;
  if (draft.abstained) {
    draftText(reason, "$.abstain_reason", DRAFT_MAX_SHORT, true);
  } else if (reason !== null) {
    draftText(reason, "$.abstain_reason", DRAFT_MAX_SHORT, false);
  }
  draftConfidence(draft.overall_confidence, "$.overall_confidence");
  return draft;
}
