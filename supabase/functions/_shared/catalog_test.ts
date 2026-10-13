import {
  barcodeCandidates,
  BLOB_KEYS_READ,
  capText,
  CatalogFacts,
  type CatalogRow,
  type CatalogStore,
  CatalogUnavailableError,
  type Json,
  toProductFacts,
} from "./catalog.ts";

function assert(condition: unknown, message: string): asserts condition {
  if (!condition) throw new Error(message);
}

function assertEquals(actual: unknown, expected: unknown, message = "values differ"): void {
  const a = JSON.stringify(actual);
  const e = JSON.stringify(expected);
  if (a !== e) throw new Error(`${message}\n  actual:   ${a}\n  expected: ${e}`);
}

// Copied from the pipeline contract so drift fails loudly:
//   PharmaGuide_Pipeline scripts/audit_contract_sync.py::BLOB_TOP_LEVEL
//   (dsld_clean @ 586d02f68, 2026-10-12). true = deprecated "schema_3".
// If the pipeline renames or deprecates a key this module reads, update the
// reader and this copy in the same change.
export const PIPELINE_BLOB_TOP_LEVEL: Record<string, boolean> = {
  dsld_id: false, blob_version: false, product_name: false, brand_name: false,
  brand_name_raw: true, brand_family: true, primary_type: false,
  classification_confidence: false, classification_reasons: false, product_role: false,
  product_role_evidence: true, completeness_claim_mismatch: false, ingredients: false,
  display_ingredients: false, inactive_ingredients: false, label_record: false,
  label_source_rows: false, label_ledger_audit: false, label_ledger_omissions: false,
  row_ledger: false, row_ledger_summary: true, warnings: false, warnings_profile_gated: false,
  allergens: false, gluten_free_validated: true, compliance_detail: true,
  certification_detail: false, proprietary_blend_detail: false, proprietary_blend: false,
  dietary_sensitivity_detail: true, formulation_detail: false, serving_info: false,
  manufacturer_detail: false, evidence_data: false, rda_ul_data: false, nutrition_detail: false,
  unmapped_actives: false, unverified_ingredient: true, score_bonuses: false,
  score_penalties: false, raw_actives_count: false, raw_inactives_count: false,
  ingredients_dropped_reasons: false, non_gmo_audit: false, omega3_audit: false,
  proprietary_blend_audit: false, supplement_type_audit: false, audit: false,
  product_safety_status: false, quality_assessment_status: false, v4_safety_gate: true,
  v4_dose_safety: true, v4_completeness_gate: true, v4_score_provenance: true,
  product_line: false, secondary_type: false, banned_substance_detail: false,
  product_status_detail: false, product_status: false, quality_pillars_v4: false,
  v4_confidence_detail: false, v4_score_explanation: false, interaction_summary: false,
  synergy_detail: false, adult_multi_coverage: false, prenatal_coverage: false,
  probiotic_detail: false, ingredient_quality_data: false,
};

/// Every key a public product response may contain (no personal fields).
export const PUBLIC_FACT_KEYS = new Set([
  "forms", "prefix", "percent",
  "quality_score_v4_100", "raw_source_path", "owner_row_ref", "source_role", "display_form_label", "form_status", "display_dose_label", "dose_status", "form_evidence", "references_structured", "url", "pmid", "supports_claims", "serving_info", "basis_count", "basis_unit", "min_servings_per_day", "max_servings_per_day", "servings_per_day_source", "basis_reason", "primary_type", "product_role", "label_record", "source_name", "source_record_id", "source_date", "source_updated_date", "label_source_url", "metadata_status", "quality_pillars_v4", "formulation", "dose", "evidence", "transparency", "verification", "safety_hygiene", "score", "max", "reason", "evidence_result_state", "display_state", "safety_summary", "safety_summary_one_liner", "sort", "offset", "total_matches", "next_offset", "supplement_type",
  "identity", "dsld_id", "product_name", "brand_name", "product_line", "form_factor", "upc",
  "product_status", "ingredients", "name", "standard_name", "amount", "unit", "identity_resolved",
  "quality", "quality_tier", "quality_score_status", "quality_score_confidence",
  "quality_assessment_status", "product_safety_status", "mapped_coverage", "warnings", "type",
  "severity", "title", "detail", "action", "ingredient", "evidence_level", "source", "sources",
  "pmids", "upper_limit_flags", "nutrient", "pipeline_warnings", "pct_of_upper_limit",
  "limitations",
]);

export function collectKeys(value: unknown, out = new Set<string>()): Set<string> {
  if (Array.isArray(value)) value.forEach((v) => collectKeys(v, out));
  else if (value && typeof value === "object") {
    for (const [k, v] of Object.entries(value)) {
      out.add(k);
      collectKeys(v, out);
    }
  }
  return out;
}

export function row(overrides: Partial<CatalogRow> = {}): CatalogRow {
  return {
    catalog_version: "2026.10.12.142202",
    dsld_id: "1060",
    product_name: "Sport Milk Chocolate",
    brand_name: "GNC",
    brand_family: "GNC",
    product_line: "Mega Men",
    upc_sku: "050428381397",
    form_factor: "powder",
    supplement_type: "multivitamin",
    product_status: "active",
    quality_tier: "Good",
    quality_score_status: "scored",
    product_safety_status: "caution",
    mapped_coverage: 1,
    quality_score_confidence: "high",
    quality_assessment_status: "complete",
    ...overrides,
  };
}

export function blob(overrides: Json = {}): Json {
  return {
    dsld_id: "1060",
    product_name: "Sport Milk Chocolate",
    brand_name: "GNC",
    product_line: "Mega Men",
    quality_assessment_status: "complete",
    product_safety_status: "caution",
    ingredients: [
      { name: "Vitamin A", standard_name: "Vitamin A", quantity: 5000, unit: "IU", is_mapped: true, notes: "x" },
    ],
    warnings: [
      {
        type: "harmful_additive", severity: "moderate", display_mode_default: "critical",
        title: "Contains Titanium Dioxide", detail: "Pipeline text.", evidence_level: "established",
        source: "harmful_additives_db", sources: ["https://pubmed.ncbi.nlm.nih.gov/12345678/"],
        condition_ids: [], drug_class_ids: [], population_warnings: ["IGNORED"],
      },
      { type: "harmful_additive", severity: "low", display_mode_default: "suppress", title: "Hidden filler" },
      { type: "interaction", severity: "mystery_level", display_mode_default: "suppress", title: "Unknown severity shows" },
      { type: "interaction", severity: "avoid", display_mode_default: "suppress", title: "Hard always shows" },
      {
        type: "interaction", severity: "caution", display_mode_default: "critical", title: "Pregnancy only",
        condition_ids: ["pregnancy"], drug_class_ids: [],
      },
      {
        type: "interaction", severity: "avoid", display_mode_default: "critical", title: "Below dose threshold",
        dose_decision: { consumer_disposition: "suppress" },
      },
      { type: "interaction", severity: "monitor", direction: "beneficial", title: "Helps the condition" },
      {
        type: "interaction", severity: "caution", materiality: "dose_dependent", dose_floor_status: "below",
        title: "Below emitted floor",
      },
    ],
    warnings_profile_gated: [],
    rda_ul_data: {
      analyzed_ingredients: [
        { standard_name: "Niacin", over_ul: true, pct_ul: 250, warnings: ["Exceeds the adult UL."] },
        { standard_name: "Zinc", over_ul: true, ul_gate_eligible: false, warnings: ["Compound weight"] },
        { standard_name: "Iron", over_ul: true, skip_ul_check: true, warnings: ["Skipped"] },
        { standard_name: "Vitamin C", over_ul: false, warnings: ["Within limit"] },
      ],
    },
    v4_score_provenance: { quality_tier: "Exceptional" },
    ...overrides,
  };
}

Deno.test("every blob key the mapper reads is declared and not deprecated in BLOB_TOP_LEVEL", () => {
  for (const key of BLOB_KEYS_READ) {
    assert(key in PIPELINE_BLOB_TOP_LEVEL, `${key} is not in the pipeline BLOB_TOP_LEVEL contract`);
    assert(!PIPELINE_BLOB_TOP_LEVEL[key], `${key} is deprecated for schema 3; stop reading it`);
  }
});

Deno.test("toProductFacts touches only the pinned blob keys", () => {
  const touched = new Set<string>();
  const proxy = new Proxy(blob(), {
    get(target, key, receiver) {
      if (typeof key === "string") touched.add(key);
      return Reflect.get(target, key, receiver);
    },
  });
  toProductFacts(proxy, row());
  for (const key of touched) {
    assert((BLOB_KEYS_READ as readonly string[]).includes(key), `mapper read undeclared blob key ${key}`);
  }
});

Deno.test("public facts never contain keys outside the allowlist", () => {
  const facts = toProductFacts(blob(), row({ mapped_coverage: 0.1 }));
  for (const key of collectKeys(facts)) {
    assert(PUBLIC_FACT_KEYS.has(key), `unexpected key in public facts: ${key}`);
  }
});

Deno.test("warnings follow the app's no-profile filter and keep evidence + sources", () => {
  const facts = toProductFacts(blob(), row());
  const titles = (facts.warnings as Json[]).map((w) => w.title);
  assertEquals(titles, ["Contains Titanium Dioxide", "Unknown severity shows", "Hard always shows"]);
  const first = (facts.warnings as Json[])[0];
  assertEquals(first.evidence_level, "established");
  assertEquals(first.source, "harmful_additives_db");
  assertEquals(first.pmids, ["12345678"]);
  assert(
    (facts.limitations as string[]).some((l) => l.includes("specific conditions, medications, pregnancy")),
    "withheld profile-tagged rules must be disclosed as a limitation",
  );
});

Deno.test("upper-limit flags honor skip_ul_check and ul_gate_eligible", () => {
  const facts = toProductFacts(blob(), row());
  assertEquals((facts.upper_limit_flags as Json[]).map((f) => f.nutrient), ["Niacin"]);
  // Real shape (dsld 1060, catalog 2026.10.12.142202): the exceedance lives in
  // safety_flags while the analyzed row has no over_ul / pct_ul of its own.
  const message = "Provides 50 mg NE per day on its own, 143% of the general adult upper limit of 35 mg NE, before other sources are counted.";
  const fromFlags = toProductFacts(
    blob({
      rda_ul_data: {
        safety_flags: [
          { nutrient: "Niacin", pct_ul: 142.85714285714286, warning: message, ul_gate_eligible: true },
          { nutrient: "Zinc", pct_ul: 300, warning: "Compound weight", ul_gate_eligible: false },
        ],
        analyzed_ingredients: [{ standard_name: "Vitamin B3 (Niacin)", quantity: 50, unit: "mg", warnings: [message] }],
      },
    }),
    row(),
  );
  assertEquals(fromFlags.upper_limit_flags, [{
    nutrient: "Niacin",
    pipeline_warnings: [message],
    pct_of_upper_limit: 142.9,
    evidence_level: null,
    source: "PharmaGuide upper-limit analysis (rda_ul_data)",
  }]);
  assert(
    !(fromFlags.limitations as string[]).some((l) => l.includes("dose comparisons")),
    "a row already covered by a pipeline safety flag is not unconfirmed",
  );
  const unresolved = toProductFacts(
    blob({ rda_ul_data: { analyzed_ingredients: [{ standard_name: "Boron", warnings: ["Check UL"] }] } }),
    row(),
  );
  assertEquals(unresolved.upper_limit_flags, []);
  assert(
    (unresolved.limitations as string[]).some((l) => l.includes("upper-limit")),
    "an unconfirmed UL comparison must be disclosed",
  );
});

Deno.test("coverage below 0.3 or unknown states that no reassurance can be drawn", () => {
  const low = toProductFacts(blob(), row({ mapped_coverage: 0.29, product_safety_status: "no_known_catalog_concern" }));
  assert(
    (low.limitations as string[]).includes(
      "Analysis coverage below 0.3: identity of some ingredients unresolved; no reassurance can be drawn.",
    ),
    "low-coverage limitation missing",
  );
  const unknown = toProductFacts(blob(), row({ mapped_coverage: null }));
  assert((unknown.limitations as string[]).some((l) => l.startsWith("Analysis coverage unknown")), "null coverage");
  const full = toProductFacts(blob(), row({ mapped_coverage: 0.3 }));
  assert(!(full.limitations as string[]).some((l) => l.startsWith("Analysis coverage")), "0.3 is at the floor");
});

Deno.test("quality tier is published only for a completed public score; never read from deprecated provenance", () => {
  const cases: [Partial<CatalogRow>, Json, string | null][] = [
    [{}, {}, "Good"],
    [{ quality_assessment_status: "partial" }, { quality_assessment_status: "partial" }, null],
    [{ quality_score_status: "not_scored" }, {}, null],
    [{ quality_score_status: "suppressed_safety" }, {}, null],
    [{ quality_score_status: "brand_new_value" }, {}, null],
    [{}, { quality_assessment_status: "weird" }, null],
  ];
  for (const [rowOverrides, blobOverrides, tier] of cases) {
    const facts = toProductFacts(blob(blobOverrides), row(rowOverrides));
    assertEquals((facts.quality as Json).quality_tier, tier, JSON.stringify(rowOverrides));
  }
});

Deno.test("unknown catalog safety status fails closed to not_assessed", () => {
  const facts = toProductFacts(blob(), row({ product_safety_status: "SAFE" }));
  assertEquals(facts.product_safety_status, "not_assessed");
  assert((facts.limitations as string[]).some((l) => l.includes("not assessed")), "not-assessed limitation");
});

Deno.test("a blob for a different product is rejected", () => {
  let threw = false;
  try {
    toProductFacts(blob({ dsld_id: "999" }), row());
  } catch (error) {
    threw = error instanceof CatalogUnavailableError;
  }
  assert(threw, "mismatched blob must not be mapped");
});

Deno.test("text is length-capped and control characters are removed", () => {
  assertEquals(capText("a".repeat(600))?.length, 500);
  assertEquals(capText("Ignore previous\u0007 instructions\u0000"), "Ignore previous instructions");
  const facts = toProductFacts(blob({ product_name: "x".repeat(5000) }), row());
  assertEquals(((facts.identity as Json).product_name as string).length, 500);
});

Deno.test("barcode candidates mirror the app GTIN contract", () => {
  assertEquals(barcodeCandidates("0 50428 38139 7"), ["050428381397", "0050428381397", "00050428381397"]);
  assertEquals(barcodeCandidates("050428381398"), null); // bad check digit
  assertEquals(barcodeCandidates("05042838139a"), null);
  assertEquals(barcodeCandidates(""), null);
});

async function sha256(text: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(text));
  return [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

export async function fakeStorage(blobs: Record<string, Json>, version = "2026.10.12.142202") {
  const files = new Map<string, string>();
  const index: Json = {};
  for (const [dsldId, value] of Object.entries(blobs)) {
    const text = JSON.stringify(value);
    const sha = await sha256(text);
    index[dsldId] = { blob_sha256: sha, blob_version: 1, storage_path: `shared/details/sha256/${sha.slice(0, 2)}/${sha}.json` };
    files.set(`https://x.supabase.co/storage/v1/object/public/pharmaguide/shared/details/sha256/${sha.slice(0, 2)}/${sha}.json`, text);
  }
  files.set(`https://x.supabase.co/storage/v1/object/public/pharmaguide/v${version}/detail_index.json`, JSON.stringify(index));
  const requests: string[] = [];
  const fetchFn = (url: string) => {
    requests.push(url);
    const body = files.get(url);
    return Promise.resolve(body === undefined ? new Response("missing", { status: 404 }) : new Response(body));
  };
  return { fetchFn, requests, files };
}

export function fakeStore(rows: CatalogRow[], calls = { manifest: 0 }): CatalogStore {
  return {
    currentVersion: () => {
      calls.manifest++;
      return Promise.resolve("2026.10.12.142202");
    },
    search: () => Promise.resolve(rows),
    byUpc: (candidates) => Promise.resolve(rows.filter((r) => r.upc_sku && candidates.includes(r.upc_sku))),
    byDsldId: (id) => Promise.resolve(rows.find((r) => r.dsld_id === id) ?? null),
  };
}

Deno.test("manifest and detail index are reused within their 60 s cache window", async () => {
  let now = 0;
  const calls = { manifest: 0 };
  const storage = await fakeStorage({ "1060": blob() });
  const catalog = new CatalogFacts({
    store: fakeStore([row()], calls),
    fetchFn: storage.fetchFn,
    supabaseUrl: "https://x.supabase.co/",
    now: () => now,
  });
  await catalog.currentVersion();
  now = 59_000;
  await catalog.currentVersion();
  assertEquals(calls.manifest, 1);
  now = 61_000;
  await catalog.currentVersion();
  assertEquals(calls.manifest, 2);

  await catalog.blob("2026.10.12.142202", "1060");
  await catalog.blob("2026.10.12.142202", "1060");
  assertEquals(storage.requests.filter((u) => u.endsWith("detail_index.json")).length, 1);
});

Deno.test("same-version corrections refresh facts within the index TTL even when facts were cached later", async () => {
  let now = 0;
  const storage = await fakeStorage({ "1060": blob() });
  const catalog = new CatalogFacts({ store: fakeStore([row()]), fetchFn: storage.fetchFn,
    supabaseUrl: "https://x.supabase.co", now: () => now });
  await catalog.detailIndex(row().catalog_version);
  now = 59_000;
  const original = await catalog.productFacts(row());
  const corrected = blob({ warnings: [{ type: "recall", severity: "high", title: "Corrected warning", message: "Authored recall", source: "FDA" }] });
  const replacement = await fakeStorage({ "1060": corrected });
  for (const [url, body] of replacement.files) storage.files.set(url, body);
  assertEquals(await catalog.productFacts(row()), original, "cache remains bounded but reusable before expiry");
  now = 60_000;
  assertEquals(await catalog.productFacts(row()), toProductFacts(corrected, row()), "facts must not extend an old index's freshness");
});

Deno.test("expired index cannot serve cached facts for removed products or unavailable storage", async () => {
  for (const unavailable of [false, true]) {
    let now = 0;
    const storage = await fakeStorage({ "1060": blob() });
    const catalog = new CatalogFacts({ store: fakeStore([row()]), fetchFn: storage.fetchFn,
      supabaseUrl: "https://x.supabase.co", now: () => now });
    await catalog.productFacts(row());
    const indexUrl = [...storage.files.keys()].find((url) => url.endsWith("detail_index.json"))!;
    if (unavailable) storage.files.delete(indexUrl);
    else storage.files.set(indexUrl, "{}");
    now = 60_000;
    let refused = false;
    try { await catalog.productFacts(row()); } catch (error) { refused = error instanceof CatalogUnavailableError; }
    assert(refused, "expired cached facts must not mask a removed product or failed index refresh");
  }
});

Deno.test("facts reflect updated row safety even when the content-addressed blob is unchanged", async () => {
  const storage = await fakeStorage({ "1060": blob() });
  const catalog = new CatalogFacts({ store: fakeStore([row()]), fetchFn: storage.fetchFn, supabaseUrl: "https://x.supabase.co" });
  await catalog.productFacts(row());
  const correctedRow = row({ product_safety_status: "blocked", product_name: "Corrected name" });
  assertEquals(await catalog.productFacts(correctedRow), toProductFacts(blob(), correctedRow));
});

Deno.test("a blob whose bytes do not match the index hash is refused", async () => {
  const storage = await fakeStorage({ "1060": blob() });
  for (const [url] of storage.files) {
    if (url.includes("/sha256/")) storage.files.set(url, JSON.stringify(blob({ product_name: "Tampered" })));
  }
  const catalog = new CatalogFacts({ store: fakeStore([row()]), fetchFn: storage.fetchFn, supabaseUrl: "https://x.supabase.co" });
  let threw = false;
  try {
    await catalog.blob("2026.10.12.142202", "1060");
  } catch (error) {
    threw = error instanceof CatalogUnavailableError;
  }
  assert(threw, "tampered blob must fail the integrity check");
});

Deno.test("upper-limit facts preserve authored evidence and do not invent an established grade", () => {
  const facts = toProductFacts(blob({ rda_ul_data: {
    safety_flags: [
      { nutrient: "Niacin", pct_ul: 250, warning: "Authored warning", evidence_level: "moderate", source: "Authored source" },
      { nutrient: "Zinc", pct_ul: 200, warning: "Another authored warning" },
    ],
    analyzed_ingredients: [
      { standard_name: "Vitamin C", over_ul: true, pct_ul: 150, warnings: ["Authored row warning"] },
    ],
  } }), row());
  const flags = facts.upper_limit_flags as Json[];
  assertEquals(flags[0].evidence_level, "moderate");
  assertEquals(flags[0].source, "Authored source");
  assertEquals(flags[1].evidence_level, null);
  assertEquals(flags[2].evidence_level, null);
  assert((facts.limitations as string[]).some((s) => s.includes("evidence grade")), "missing grade disclosed");
});

Deno.test("comparison retains serving basis, source ownership, forms and canonical quality", () => {
  const facts = toProductFacts(blob({
    serving_info: { basis_count: 1, basis_unit: "capsule", min_servings_per_day: 1, max_servings_per_day: 3 },
    row_ledger: [{ row_ref: "ingredientRows[0]", owner_row_ref: null },
      { row_ref: "ingredientRows[0].nestedRows[0]", owner_row_ref: "ingredientRows[0]" }],
    ingredients: [
      { name: "Magnesium", quantity: 135, unit: "mg", raw_source_path: "ingredientRows[0]" },
      { name: "Magnesium Citrate", quantity: 55, unit: "mg", raw_source_path: "ingredientRows[0].nestedRows[0]", display_form_label: "citrate", form_status: "known" },
    ],
    quality_pillars_v4: { dose: { score: 10, max: 20, reason: "Published dose explanation." } },
  }), row({ quality_score_v4_100: 80 } as Partial<CatalogRow>));
  assertEquals((facts.quality as Json).quality_score_v4_100, 80);
  assertEquals((facts.serving_info as Json).max_servings_per_day, 3);
  const ingredients = facts.ingredients as Json[];
  assertEquals(ingredients[1].owner_row_ref, "ingredientRows[0]");
  assertEquals(ingredients[1].display_form_label, "citrate");
  assertEquals(ingredients[0].amount, 135);
  assertEquals(((facts.quality_pillars_v4 as Json).dose as Json).reason, "Published dose explanation.");
});

Deno.test("warning qualifications survive and absent evidence is disclosed", () => {
  const detail = "a".repeat(520) + " Human harm is unproven.";
  const facts = toProductFacts(blob({ warnings: [{ title: "Finding", detail, severity: "moderate", source: "registry" }] }), row());
  assertEquals((facts.warnings as Json[])[0].detail, detail);
  assert((facts.limitations as string[]).some(x => x.includes("citation")), "missing citation disclosed");
});

Deno.test("comparison preserves every declared form without inventing proportions", () => {
  const facts = toProductFacts(blob({ ingredients: [{ name: "Magnesium", quantity: 120, unit: "mg",
    display_form_label: "Magnesium Citrate", forms: [
      { name: "Magnesium Citrate", prefix: "as", percent: null, private_field: "not public" },
      { name: "Magnesium Malate", prefix: null, percent: null }, null, {},
    ] }, { name: "Other", forms: null }] }), row());
  const ingredients = facts.ingredients as Json[];
  assertEquals(ingredients[0].forms, [
    { name: "Magnesium Citrate", prefix: "as", percent: null },
    { name: "Magnesium Malate", prefix: null, percent: null },
  ]);
  assertEquals(ingredients[0].amount, 120);
  assertEquals(ingredients[1].forms, []);
});

Deno.test("comparison never exposes a suppressed or incomplete score as rankable", () => {
  for (const overrides of [{quality_score_status:"suppressed_safety"}, {quality_score_status:"not_scored"}, {quality_assessment_status:"partial"}]) {
    const facts = toProductFacts(blob({quality_assessment_status:overrides.quality_assessment_status ?? "complete"}), row({quality_score_v4_100:99,...overrides}));
    assertEquals((facts.quality as Json).quality_score_v4_100, null);
  }
});

Deno.test("oversized clinical text is omitted with disclosure, not a clipped qualification", () => {
  const facts = toProductFacts(blob({warnings:[{severity:"moderate",detail:"a".repeat(20001),safety_summary:"Complete shorter statement."}]}),row());
  assertEquals((facts.warnings as Json[])[0].detail,null);
  assertEquals((facts.warnings as Json[])[0].safety_summary,"Complete shorter statement.");
  assert((facts.limitations as string[]).some(x=>x.includes("omitted rather than shortened")),"omission disclosed");
});
