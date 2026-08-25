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
