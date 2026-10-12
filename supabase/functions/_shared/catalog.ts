// Public catalog facts for AI-assistant servers (MCP). Product data only:
// nothing here reads, accepts or returns personal data.
//
// Data path (pipeline repo `scripts/sync_to_supabase.py`):
//   export_manifest (is_current)        -> current catalog version
//   catalog_search_current / search_catalog() -> slim per-product rows
//   storage pharmaguide/v{version}/detail_index.json -> dsld_id -> blob sha256
//   storage pharmaguide/shared/details/sha256/{sha[0:2]}/{sha}.json -> detail blob
// Paths mirror lib/data/supabase/supabase_contract.dart.
//
// Semantics mirror the app's owners; the pipeline decides, this file renders:
//   lib/core/scoring/catalog_product_semantics.dart (safety / completion / not-scored)
//   lib/core/scoring/coverage.dart (kLowCoverageFloor = 0.3, null coverage = 0)
//   lib/features/product_detail/product_detail_helpers.dart
//     filterProductDetailWarningsForProfile with an empty profile
//   lib/services/warnings/condition_gate.dart (disposition / floor / beneficial gates)
//   lib/services/health/dose_safety.dart (UL eligibility contract)
//   lib/services/gtin.dart (barcode lookup candidates)

export const STORAGE_BUCKET = "pharmaguide";
export const BLOB_PREFIX = "shared/details/sha256";
export const LOW_COVERAGE_FLOOR = 0.3;
export const TEXT_CAP = 500;
export const MANIFEST_TTL_MS = 60_000;
const MAX_CACHED_INDEX_VERSIONS = 2;
const MAX_CACHED_FACTS = 200;
const MAX_INGREDIENTS = 100;
const MAX_WARNINGS = 50;
const MAX_SOURCES = 10;

export type FetchLike = (input: string, init?: RequestInit) => Promise<Response>;
export type Json = Record<string, unknown>;

/// One row of `catalog_search_current` (pipeline schema section 9).
export interface CatalogRow {
  catalog_version: string;
  dsld_id: string;
  product_name: string;
  brand_name: string | null;
  brand_family: string | null;
  product_line: string | null;
  upc_sku: string | null;
  form_factor: string | null;
  supplement_type: string | null;
  product_status: string | null;
  quality_tier: string | null;
  quality_score_status: string | null;
  product_safety_status: string | null;
  mapped_coverage: number | null;
  quality_score_confidence: string | null;
  quality_assessment_status: string | null;
  match_score?: number | null;
}

export const CATALOG_ROW_COLUMNS = [
  "catalog_version", "dsld_id", "product_name", "brand_name", "brand_family",
  "product_line", "upc_sku", "form_factor", "supplement_type", "product_status",
  "quality_tier", "quality_score_status", "product_safety_status",
  "mapped_coverage", "quality_score_confidence", "quality_assessment_status",
] as const;

/// Top-level blob keys this module reads. A test pins them to the pipeline's
/// BLOB_TOP_LEVEL contract (none may be undeclared or schema-3 deprecated).
export const BLOB_KEYS_READ = [
  "dsld_id", "product_name", "brand_name", "product_line", "ingredients",
  "warnings", "warnings_profile_gated", "quality_assessment_status", "rda_ul_data",
] as const;

export interface CatalogStore {
  currentVersion(): Promise<string | null>;
  search(args: { query: string; brand?: string; form?: string; limit: number }): Promise<CatalogRow[]>;
  byUpc(candidates: string[]): Promise<CatalogRow[]>;
  byDsldId(dsldId: string): Promise<CatalogRow | null>;
}

export class CatalogUnavailableError extends Error {}

// ---------------------------------------------------------------------------
// Text hygiene (S8): every string is data, length-capped, control-free.
// ---------------------------------------------------------------------------

export function capText(value: unknown, max = TEXT_CAP): string | null {
  if (typeof value !== "string" && typeof value !== "number") return null;
  // deno-lint-ignore no-control-regex
  const text = String(value).replace(/[\u0000-\u0008\u000B-\u001F\u007F]/g, "").trim();
  if (!text) return null;
  return text.length > max ? `${text.slice(0, max - 1)}…` : text;
}

function lower(value: unknown): string {
  return typeof value === "string" ? value.trim().toLowerCase() : "";
}

function finiteNumber(value: unknown): number | null {
  const n = typeof value === "string" && value.trim() !== "" ? Number(value) : value;
  return typeof n === "number" && Number.isFinite(n) ? n : null;
}

function stringList(value: unknown): string[] {
  if (!Array.isArray(value)) return [];
  return value.filter((v): v is string => typeof v === "string" && v.trim() !== "");
}

function asObject(value: unknown): Json | null {
  return value && typeof value === "object" && !Array.isArray(value) ? value as Json : null;
}

// ---------------------------------------------------------------------------
// Semantics (mirrors catalog_product_semantics.dart; never invents meaning)
// ---------------------------------------------------------------------------

const SAFETY_STATUSES = new Set([
  "blocked", "unsafe", "caution", "no_known_catalog_concern", "not_assessed",
]);

/// Empty or unknown values are schema drift and fail closed to not_assessed.
/// (The legacy verdict fallback is not available here, and it never supplies
/// reassurance anyway.)
export function catalogSafetyStatus(value: unknown): string {
  const status = lower(value);
  return SAFETY_STATUSES.has(status) ? status : "not_assessed";
}

/// complete | partial | failed. Unknown populated values fail closed.
export function catalogAssessmentStatus(
  assessmentStatus: unknown,
  scoreStatus: unknown,
): "complete" | "partial" | "failed" {
  const status = lower(assessmentStatus);
  if (status === "complete" || status === "partial" || status === "failed") return status;
  if (status) return "failed";
  const score = lower(scoreStatus);
  if (score === "scored" || score === "suppressed_safety") return "complete";
  // No numeric score is published to this surface, so the app's
  // "number present -> complete" fallback cannot apply: stay partial.
  return "partial";
}

/// Quality tier shown only for a completed public score; otherwise null plus
/// the limitation explaining why.
export function publicQuality(row: Pick<
  CatalogRow,
  "quality_tier" | "quality_score_status" | "quality_score_confidence" | "quality_assessment_status"
>, assessmentOverride?: unknown): { quality: Json; limitations: string[] } {
  const limitations: string[] = [];
  const scoreStatus = lower(row.quality_score_status);
  const completion = catalogAssessmentStatus(
    assessmentOverride ?? row.quality_assessment_status,
    row.quality_score_status,
  );
  let tier = capText(row.quality_tier, 60);
  if (completion === "failed" || scoreStatus === "not_scored" ||
      (scoreStatus && !["scored", "suppressed_safety"].includes(scoreStatus)) ||
      (!scoreStatus && !tier)) {
    tier = null;
    limitations.push("No public quality score: the catalog assessment did not produce one.");
  } else if (scoreStatus === "suppressed_safety") {
    tier = null;
    limitations.push("Quality score withheld because of a catalog safety finding.");
  } else if (completion === "partial") {
    tier = null;
    limitations.push(
      "Quality assessment incomplete: a required part was not assessed, so no definitive quality tier is published.",
    );
  }
  const confidence = capText(row.quality_score_confidence, 40);
  const confidenceKey = lower(confidence).replaceAll("-", "_");
  if (tier && confidence && !["high", "moderate", "medium"].includes(confidenceKey)) {
    limitations.push("Quality score confidence is limited.");
  }
  return {
    quality: {
      quality_tier: tier,
      quality_score_status: capText(row.quality_score_status, 40),
      quality_score_confidence: confidence,
      quality_assessment_status: completion,
    },
    limitations,
  };
}

export function coverageLimitations(mappedCoverage: number | null): string[] {
  if (mappedCoverage === null) {
    return ["Analysis coverage unknown: identity of some ingredients may be unresolved; no reassurance can be drawn."];
  }
  if (mappedCoverage < LOW_COVERAGE_FLOOR) {
    return ["Analysis coverage below 0.3: identity of some ingredients unresolved; no reassurance can be drawn."];
  }
  return [];
}

// ---------------------------------------------------------------------------
// Warnings: the app's no-profile product-detail filter
// ---------------------------------------------------------------------------

const HARD_SEVERITIES = new Set(["contraindicated", "critical", "avoid", "high"]);
const KNOWN_SEVERITIES = new Set([
  ...HARD_SEVERITIES, "caution", "moderate", "monitor", "low", "no_data",
  "informational", "info", "safe",
]);

function isHard(severity: string): boolean {
  return HARD_SEVERITIES.has(severity);
}

function profileTagged(w: Json): boolean {
  return stringList(w.condition_ids).length > 0 || stringList(w.drug_class_ids).length > 0 ||
    (typeof w.condition_id === "string" && w.condition_id.trim() !== "") ||
    (typeof w.drug_class_id === "string" && w.drug_class_id.trim() !== "");
}

/// Returns the public (no-profile) warnings plus whether any profile-tagged
/// rule was withheld. Order of gates follows filterProductDetailWarningsForProfile.
export function publicWarnings(rawWarnings: unknown): { visible: Json[]; profileTaggedWithheld: boolean } {
  const visible: Json[] = [];
  let profileTaggedWithheld = false;
  for (const raw of Array.isArray(rawWarnings) ? rawWarnings : []) {
    const w = asObject(raw);
    if (!w) continue;
    const severity = lower(w.severity);
    const hard = isHard(severity);
    // 1. Pipeline consumer disposition is authoritative.
    const decision = asObject(w.dose_decision);
    if (decision && lower(decision.consumer_disposition) === "suppress") continue;
    // 2. Emitted dose floor (only without a dose_decision).
    if (!decision && ["below", "form_mismatch"].includes(lower(w.dose_floor_status)) &&
        lower(w.materiality) === "dose_dependent" && lower(w.direction) !== "beneficial" &&
        KNOWN_SEVERITIES.has(severity) && !hard) continue;
    // 3. Beneficial-direction rows are not warnings unless hard.
    if (lower(w.direction) === "beneficial" && !hard) continue;
    // 4. Profile-tagged rules never become global alerts without a profile.
    if (profileTagged(w)) {
      profileTaggedWithheld = true;
      continue;
    }
    // 5. Display mode, with the app's fail-safes for hard / unknown severity.
    const mode = lower(w.display_mode_default);
    const show = mode === "critical" || mode === "informational" || hard ||
      (mode === "suppress" && !KNOWN_SEVERITIES.has(severity)) || mode !== "suppress";
    if (!show) continue;
    visible.push(w);
  }
  return { visible, profileTaggedWithheld };
}

function pmidsFrom(w: Json): string[] {
  const pmids = new Set<string>();
  for (const id of stringList(w.source_pmids)) {
    if (/^\d{1,9}$/.test(id.trim())) pmids.add(id.trim());
  }
  for (const url of stringList(w.sources)) {
    const match = /pubmed\.ncbi\.nlm\.nih\.gov\/(\d{1,9})/.exec(url);
    if (match) pmids.add(match[1]);
  }
  return [...pmids].slice(0, MAX_SOURCES);
}

/// Pipeline-authored text passes through verbatim (length-capped).
export function warningFacts(w: Json): Json {
  return {
    type: capText(w.type, 60),
    severity: capText(w.severity, 40),
    title: capText(w.title),
    detail: capText(w.detail),
    action: capText(w.action),
    ingredient: capText(w.ingredient_name, 120),
    evidence_level: capText(w.evidence_level, 60),
    source: capText(w.source, 120),
    sources: stringList(w.sources).slice(0, MAX_SOURCES).map((s) => capText(s, 300)),
    pmids: pmidsFrom(w),
  };
}

/// UL exceedances the pipeline decided itself, honoring its eligibility flags
/// (skip_ul_check / ul_gate_eligible): first `rda_ul_data.safety_flags`
/// (pipeline-computed pct_ul), then per-row over_ul / pct_ul. A row with a
/// pipeline UL message but no structured decision needs the app's unit
/// conversion; it is disclosed as a limitation, never shown as a finding.
export function upperLimitFacts(rdaUlData: unknown): { flags: Json[]; unconfirmed: boolean } {
  const data = asObject(rdaUlData);
  const rows = data?.analyzed_ingredients;
  const flags: Json[] = [];
  let unconfirmed = false;
  const seen = new Set<string>();
  const covered = new Set<string>();
  for (const raw of Array.isArray(data?.safety_flags) ? data.safety_flags : []) {
    const flag = asObject(raw);
    if (!flag || flag.skip_ul_check === true || flag.ul_gate_eligible === false) continue;
    const pct = finiteNumber(flag.pct_ul);
    const message = typeof flag.warning === "string" ? flag.warning.trim() : "";
    const name = capText(flag.nutrient, 120);
    if (pct === null || pct <= 100 || !message || !name) continue;
    covered.add(message);
    if (seen.has(name.toLowerCase())) continue;
    seen.add(name.toLowerCase());
    flags.push({
      nutrient: name,
      pipeline_warnings: [capText(message)],
      pct_of_upper_limit: Math.round(pct * 10) / 10,
      evidence_level: "established",
      source: "PharmaGuide upper-limit analysis (rda_ul_data)",
    });
  }
  for (const raw of Array.isArray(rows) ? rows : []) {
    const row = asObject(raw);
    if (!row || row.skip_ul_check === true || row.ul_gate_eligible === false) continue;
    const messages = stringList(row.warnings);
    if (messages.length === 0 || messages.every((m) => covered.has(m.trim()))) continue;
    const pct = finiteNumber(row.pct_ul);
    let exceeded: boolean | null = null;
    if (row.over_ul === true) exceeded = true;
    else if (row.over_ul === false) exceeded = false;
    else if (pct !== null) exceeded = pct > 100;
    if (exceeded === null) {
      unconfirmed = true;
      continue;
    }
    if (!exceeded) continue;
    const name = capText(row.standard_name ?? row.ingredient, 120);
    if (!name || seen.has(name.toLowerCase())) continue;
    seen.add(name.toLowerCase());
    flags.push({
      nutrient: name,
      pipeline_warnings: messages.slice(0, 5).map((m) => capText(m)),
      pct_of_upper_limit: pct,
      evidence_level: "established",
      source: "PharmaGuide upper-limit analysis (rda_ul_data)",
    });
  }
  return { flags, unconfirmed };
}

function ingredientFacts(raw: unknown): Json[] {
  const out: Json[] = [];
  for (const item of Array.isArray(raw) ? raw : []) {
    const ing = asObject(item);
    if (!ing) continue;
    out.push({
      name: capText(ing.name ?? ing.standard_name, 200),
      standard_name: capText(ing.standard_name, 200),
      amount: finiteNumber(ing.quantity),
      unit: capText(ing.unit, 40),
      identity_resolved: typeof ing.is_mapped === "boolean" ? ing.is_mapped : null,
    });
    if (out.length >= MAX_INGREDIENTS) break;
  }
  return out;
}

/// Pure mapper: detail blob + its catalog row -> the only facts a public tool
/// may return. Throws when the blob is not the requested product.
export function toProductFacts(blob: unknown, row: CatalogRow): Json {
  const b = asObject(blob);
  if (!b || String(b.dsld_id ?? "") !== String(row.dsld_id)) {
    throw new CatalogUnavailableError("detail record does not match the requested product");
  }
  const mappedCoverage = finiteNumber(row.mapped_coverage);
  const { quality, limitations: qualityLimits } = publicQuality(row, b.quality_assessment_status);
  const { visible, profileTaggedWithheld: taggedInline } = publicWarnings(b.warnings);
  // warnings_profile_gated holds rules that only apply to a matching profile.
  const profileTaggedWithheld = taggedInline ||
    (Array.isArray(b.warnings_profile_gated) && b.warnings_profile_gated.length > 0);
  const ul = upperLimitFacts(b.rda_ul_data);
  const safetyStatus = catalogSafetyStatus(row.product_safety_status);
  const ingredients = ingredientFacts(b.ingredients);

  const limitations = [
    "Public catalog view: no personal profile (conditions, medications, pregnancy, breastfeeding, allergies) was checked.",
    ...coverageLimitations(mappedCoverage),
    ...qualityLimits,
  ];
  if (safetyStatus === "not_assessed") {
    limitations.push("Catalog safety status not assessed for this product.");
  }
  if (profileTaggedWithheld) {
    limitations.push(
      "Some PharmaGuide warnings for this product apply only to specific conditions, medications, pregnancy or breastfeeding; they are not included in this public view.",
    );
  }
  if (ul.unconfirmed) {
    limitations.push("Some upper-limit (UL) dose comparisons are evaluated only in the PharmaGuide app and are not included here.");
  }
  if (Array.isArray(b.ingredients) && b.ingredients.length > MAX_INGREDIENTS) {
    limitations.push(`Ingredient list truncated to the first ${MAX_INGREDIENTS} entries.`);
  }
  if (visible.length > MAX_WARNINGS) {
    limitations.push(`Warning list truncated to the first ${MAX_WARNINGS} entries.`);
  }

  return {
    identity: {
      dsld_id: capText(row.dsld_id, 20),
      product_name: capText(b.product_name ?? row.product_name),
      brand_name: capText(b.brand_name ?? row.brand_name, 200),
      product_line: capText(b.product_line ?? row.product_line, 200),
      form_factor: capText(row.form_factor, 60),
      upc: capText(row.upc_sku, 20),
      product_status: capText(row.product_status, 40),
    },
    ingredients,
    quality,
    product_safety_status: safetyStatus,
    quality_assessment_status: quality.quality_assessment_status,
    mapped_coverage: mappedCoverage,
    warnings: visible.slice(0, MAX_WARNINGS).map(warningFacts),
    upper_limit_flags: ul.flags,
    limitations,
  };
}

/// Slim search/barcode match (no blob needed).
export function toMatch(row: CatalogRow): Json {
  const { quality } = publicQuality(row);
  const score = finiteNumber(row.match_score);
  return {
    dsld_id: capText(row.dsld_id, 20),
    product_name: capText(row.product_name),
    brand_name: capText(row.brand_name, 200),
    product_line: capText(row.product_line, 200),
    form_factor: capText(row.form_factor, 60),
    product_status: capText(row.product_status, 40),
    quality_tier: quality.quality_tier,
    product_safety_status: catalogSafetyStatus(row.product_safety_status),
    match_confidence: score === null ? null : Math.round(Math.min(1, Math.max(0, score)) * 100) / 100,
  };
}

/// S8 envelope around every tool result.
export function envelope(data: unknown, catalogVersion: string | null, now = new Date()): Json {
  return {
    data,
    name_source: "catalog",
    catalog_version: catalogVersion,
    generated_at: now.toISOString(),
  };
}

// ---------------------------------------------------------------------------
// Barcodes (mirrors lib/services/gtin.dart for manual entry)
// ---------------------------------------------------------------------------

export function isValidGtin(value: string): boolean {
  if (!/^(?:\d{8}|\d{12}|\d{13}|\d{14})$/.test(value)) return false;
  const body = value.slice(0, -1);
  let sum = 0;
  for (let pos = 1; pos <= body.length; pos++) {
    sum += Number(body[body.length - pos]) * (pos % 2 === 1 ? 3 : 1);
  }
  return (10 - (sum % 10)) % 10 === Number(value[value.length - 1]);
}

export function expandUpcE(value: string): string | null {
  if (!/^\d{8}$/.test(value)) return null;
  const [ns, d1, d2, d3, d4, d5, d6, check] = value.split("");
  if (ns !== "0" && ns !== "1") return null;
  const body = ["0", "1", "2"].includes(d6)
    ? `${ns}${d1}${d2}${d6}0000${d3}${d4}${d5}`
    : d6 === "3"
    ? `${ns}${d1}${d2}${d3}00000${d4}${d5}`
    : d6 === "4"
    ? `${ns}${d1}${d2}${d3}${d4}00000${d5}`
    : `${ns}${d1}${d2}${d3}${d4}${d5}0000${d6}`;
  const expanded = `${body}${check}`;
  return isValidGtin(expanded) ? expanded : null;
}

export function gtinWidthCandidates(digits: string): Set<string> {
  const out = new Set([digits]);
  if (digits.length === 8) out.add(digits.padStart(14, "0"));
  if (digits.length === 12) {
    out.add(`0${digits}`);
    out.add(`00${digits}`);
  }
  if (digits.length === 13) {
    if (digits.startsWith("0")) out.add(digits.slice(1));
    out.add(`0${digits}`);
  }
  if (digits.length === 14) {
    if (digits.startsWith("0")) out.add(digits.slice(1));
    if (digits.startsWith("00")) out.add(digits.slice(2));
    if (digits.startsWith("000000")) out.add(digits.slice(6));
  }
  return out;
}

/// Lookup candidates for a typed barcode, or null when it is not a valid GTIN.
export function barcodeCandidates(input: string): string[] | null {
  if (typeof input !== "string" || input.length > 40 || /[^0-9\s-]/.test(input)) return null;
  const digits = input.replace(/[^0-9]/g, "");
  if (!digits) return null;
  if (digits.length === 8) {
    const isEan8 = isValidGtin(digits);
    const upcA = expandUpcE(digits);
    if (!isEan8 && !upcA) return null;
    const out = new Set([digits, ...gtinWidthCandidates(isEan8 ? digits : upcA!)]);
    if (isEan8 && upcA) for (const c of gtinWidthCandidates(upcA)) out.add(c);
    return [...out];
  }
  return isValidGtin(digits) ? [...gtinWidthCandidates(digits)] : null;
}

// ---------------------------------------------------------------------------
// Fetching + caching (S7)
// ---------------------------------------------------------------------------

async function sha256Hex(bytes: ArrayBuffer): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  return [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

export class CatalogFacts {
  #store: CatalogStore;
  #fetch: FetchLike;
  #publicBase: string;
  #now: () => number;
  #manifest: { version: string | null; at: number } | null = null;
  #indexes = new Map<string, Promise<Map<string, string>>>();
  #facts = new Map<string, Json>();

  constructor(opts: { store: CatalogStore; fetchFn: FetchLike; supabaseUrl: string; now?: () => number }) {
    this.#store = opts.store;
    this.#fetch = opts.fetchFn;
    this.#publicBase = `${opts.supabaseUrl.replace(/\/+$/, "")}/storage/v1/object/public/${STORAGE_BUCKET}`;
    this.#now = opts.now ?? Date.now;
  }

  get store(): CatalogStore {
    return this.#store;
  }

  /// Current export_manifest db_version, cached for 60 s.
  async currentVersion(): Promise<string | null> {
    const now = this.#now();
    if (this.#manifest && now - this.#manifest.at < MANIFEST_TTL_MS) return this.#manifest.version;
    const version = await this.#store.currentVersion();
    this.#manifest = { version, at: now };
    return version;
  }

  /// dsld_id -> blob sha256 for one catalog version (cached; versions are immutable).
  detailIndex(version: string): Promise<Map<string, string>> {
    const cached = this.#indexes.get(version);
    if (cached) return cached;
    const pending = this.#loadIndex(version);
    pending.catch(() => this.#indexes.delete(version));
    this.#indexes.set(version, pending);
    while (this.#indexes.size > MAX_CACHED_INDEX_VERSIONS) {
      this.#indexes.delete(this.#indexes.keys().next().value!);
    }
    return pending;
  }

  async #loadIndex(version: string): Promise<Map<string, string>> {
    if (!/^[0-9A-Za-z._-]{1,64}$/.test(version)) throw new CatalogUnavailableError("bad catalog version");
    const response = await this.#fetch(`${this.#publicBase}/v${version}/detail_index.json`);
    if (!response.ok) throw new CatalogUnavailableError(`detail index HTTP ${response.status}`);
    const parsed = asObject(await response.json());
    if (!parsed) throw new CatalogUnavailableError("detail index malformed");
    const index = new Map<string, string>();
    for (const [dsldId, entry] of Object.entries(parsed)) {
      const sha = asObject(entry)?.blob_sha256;
      if (typeof sha === "string" && /^[0-9a-f]{64}$/.test(sha)) index.set(dsldId, sha);
    }
    return index;
  }

  /// Detail blob, verified against the index hash before it is parsed.
  async blob(version: string, dsldId: string): Promise<unknown> {
    const sha = (await this.detailIndex(version)).get(dsldId);
    if (!sha) throw new CatalogUnavailableError("no detail record for this product");
    const response = await this.#fetch(`${this.#publicBase}/${BLOB_PREFIX}/${sha.slice(0, 2)}/${sha}.json`);
    if (!response.ok) throw new CatalogUnavailableError(`detail blob HTTP ${response.status}`);
    const bytes = await response.arrayBuffer();
    if (await sha256Hex(bytes) !== sha) throw new CatalogUnavailableError("detail blob failed integrity check");
    return JSON.parse(new TextDecoder().decode(bytes));
  }

  /// Public facts for one catalog row (bounded cache keyed by version + id).
  async productFacts(row: CatalogRow): Promise<Json> {
    const key = `${row.catalog_version}:${row.dsld_id}`;
    const hit = this.#facts.get(key);
    if (hit) return hit;
    const facts = toProductFacts(await this.blob(row.catalog_version, row.dsld_id), row);
    this.#facts.set(key, facts);
    if (this.#facts.size > MAX_CACHED_FACTS) this.#facts.delete(this.#facts.keys().next().value!);
    return facts;
  }
}

/// Production store: PostgREST over fetch with the service-role key. The key
/// never leaves this server and no caller input reaches a URL unvalidated.
export function postgrestCatalogStore(opts: {
  supabaseUrl: string;
  serviceKey: string;
  fetchFn?: FetchLike;
}): CatalogStore {
  const base = `${opts.supabaseUrl.replace(/\/+$/, "")}/rest/v1`;
  const fetchFn = opts.fetchFn ?? fetch;
  const headers = {
    apikey: opts.serviceKey,
    Authorization: `Bearer ${opts.serviceKey}`,
    "Content-Type": "application/json",
    Accept: "application/json",
  };
  const select = `select=${CATALOG_ROW_COLUMNS.join(",")}`;
  async function rows(path: string, init?: RequestInit): Promise<CatalogRow[]> {
    const response = await fetchFn(`${base}/${path}`, { ...init, headers });
    if (!response.ok) throw new CatalogUnavailableError(`catalog query HTTP ${response.status}`);
    const body = await response.json();
    return Array.isArray(body) ? body as CatalogRow[] : [];
  }
  return {
    async currentVersion() {
      const found = await rows("export_manifest?select=db_version&is_current=eq.true&limit=1") as unknown as
        { db_version?: unknown }[];
      const version = found[0]?.db_version;
      return typeof version === "string" ? version : null;
    },
    search({ query, brand, form, limit }) {
      return rows("rpc/search_catalog", {
        method: "POST",
        body: JSON.stringify({ p_query: query, p_brand: brand ?? null, p_form: form ?? null, p_limit: limit }),
      });
    },
    byUpc(candidates) {
      const safe = candidates.filter((c) => /^\d{8,14}$/.test(c));
      if (safe.length === 0) return Promise.resolve([]);
      return rows(`catalog_search_current?${select}&upc_sku=in.(${safe.join(",")})&order=dsld_id&limit=25`);
    },
    async byDsldId(dsldId) {
      if (!/^\d{1,12}$/.test(dsldId)) return null;
      const found = await rows(`catalog_search_current?${select}&dsld_id=eq.${dsldId}&limit=1`);
      return found[0] ?? null;
    },
  };
}
