# FINAL EXPORT SCHEMA V1

> Version: 2.0.0 — 2026-06-08
> Consumes: v4 six-pillar scorer (`score_supplements_v4` + `scoring_v4/`) via the export adapter; enrichment schema v5.1.0+
> Status: ACTIVE — **v2.0.0 BREAKING:** the production catalog is v4 only. The legacy /80 columns `score_quality_80` + `score_display_80` are **DROPPED**; the canonical shipped score is `quality_score_v4_100` (/100), with `score_100_equivalent` / `score_display_100_equivalent` as honest /100 compat mirrors. New `products_core` columns: `quality_score_v4_100`, `quality_score_status` (scored/suppressed_safety/not_scored), `quality_tier`, `quality_score_suppressed_reason`, `raw_score_v4_100` (audit only), `v4_module`, `v4_confidence`, `score_model_version`, `quality_score_version`, `scoring_engine_version`, `classification_schema_version`, `v4_config_fingerprint`. New detail-blob keys: `quality_pillars_v4`, `clean_label_flags_v4`, `raw_score_v4_100`, `v4_safety_gate`, `v4_completeness_gate`, `v4_score_provenance`, `v4_score_explanation`. Ranking/dedup/index move to `quality_score_v4_100`. Flutter must read `quality_score_v4_100`, rank/exclude on `quality_score_status`, and render the six `quality_pillars_v4`.
>
> Status (v1 history): v1.6.1 landed the unified inactive-ingredient resolver + Vitamin A IU→mcg RAE form-aware conversion + canonical_id / delivers_markers propagation.
> Updated: **v1.6.1 adds (2026-05-12): (a) unified inactive-ingredient resolver via `scripts/inactive_ingredient_resolver.py` — consults `banned_recalled_ingredients.json`, `harmful_additives.json`, `other_ingredients.json` in priority order with strict standard_name+aliases-only matching; (b) four new fields on every inactive blob entry: `is_banned`, `safety_reason`, `matched_source`, `matched_rule_id` — closes the TiO2/Talc silent-ship gap (1,178+311 occurrences now correctly flagged is_safety_concern=true / severity_status=critical); (c) `canonical_id` + `delivers_markers` now emitted on every active blob entry — was 0% emit pre-fix, 100% post-fix on mapped actives. Foundational for interaction rules, stack-checking, evidence routing, biomarker scoring; (d) `display_label` for branded botanicals now preserves brand + species + plant-part + form (e.g. "Capsimax(TM) Capsicum Fruit Extract" → "Capsimax Capsicum Fruit Extract", trademark stripped); (e) Vitamin A IU labels now normalize form-aware to mcg RAE (β-carotene factor 0.1, retinol 0.3) — pregnancy UL gate now evaluable. v1.6.0 added `profile_gate` passthrough on `interaction` / `drug_interaction` warning entries. v1.5.0 introduced the canonical active + inactive ingredient contract (`display_form_label` / `form_status` / `form_match_status` / `dose_status` on actives; `display_label` / `display_role_label` / `severity_status` / `is_safety_concern` on inactives). Legacy fields (`form`, `is_harmful`) kept for back-compat and documented as deprecated. v1.4.0 adds `image_thumbnail_url` TEXT column (91 cols) and `normalize_upc` field. v1.3.4 added CAERS B8 penalty scoring (159 adverse event signals) and offline UNII cache (172K substances). v1.3.3 expanded interaction rules to 129 (now 145 per `scripts/data/interaction_rules.json` schema 6.1.0). v1.3.2 adds `calories_per_serving` REAL column (90 cols) and two new detail_blob subkeys: `nutrition_detail` (all five macros) and `unmapped_actives` (transparency panel). v1.3.1 bugfixes `dosing_summary`/`servings_per_container` and adds `net_contents_quantity` + `net_contents_unit` for refill-reminder features. Schema now has 91 columns; `build_final_db.py` CORE_COLUMN_COUNT is the runtime source of truth.**
>
> **Score visibility gate (v2.0.0):** `quality_score_status` controls whether Flutter may show a quality score. `scored` rows expose `quality_score_v4_100`; `suppressed_safety` rows ship with a null display score plus a hard safety verdict; `not_scored` rows ship without a product-quality score. V4 may still emit audit/provenance fields for diagnostics, but Flutter must never display `raw_score_v4_100` as product quality when display is suppressed. `unmapped_actives` remains present in detail blobs as a coverage/provenance surface; final export and route-readiness gates decide score visibility rather than blindly treating every unmapped active as a shipped score.
>
> Previous updates: scoring v3.4 alignment, omega-3 bonus export note, interaction_summary, dose_threshold_evaluation, condition/drug_class mapping, and Flutter convenience fields (`detail_blob_sha256`, `image_is_pdf`, `interaction_summary_hint`, `decision_highlights`)

## Purpose

This document defines the exact contract between the pipeline (this repo) and the
PharmaGuide Flutter app. The pipeline produces a SQLite database and per-product
detail blobs. The app consumes them.

This contract is frozen. Field renames after the app ships are expensive.

Assumptions:

- `quality_score_v4_100` is the canonical shipped quality score; `score_100_equivalent`
  and `score_display_100_equivalent` are /100 compatibility mirrors.
- `quality_pillars_v4` is the canonical score-detail surface for Flutter. Legacy
  `section_breakdown` fields may still exist in detail blobs for audit/history but
  must not be treated as the production score model.
- `key_ingredient_tags` is safe for Flutter product-row parsing: mapped actives use
  canonical IDs, and unmapped active rows fall back to cleaner `normalized_key` so
  product cards/search/stack intelligence are not empty while waiting for detail blobs.
- User personalization (`score_fit_20`) is computed locally on the phone.
- V1 does not claim true product-level recall support; only ingredient-level
  recalled/banned safety logic is exported.

---

## Architecture

```
Pipeline repo (dsld-clean)
  └── build_final_db.py
        ├── pharmaguide_core.db       ← ships to phone / downloadable artifact
        │     ├── products_core       ← one row per product
        │     ├── products_fts        ← full-text search
        │     ├── reference_data      ← small rule tables for offline scoring
        │     └── export_manifest     ← local build/version metadata
        ├── detail_blobs/             ← local one JSON per product build output
        │     ├── 15123.json
        │     ├── 37323.json
        │     └── ...
        ├── detail_index.json         ← compatibility/audit map for hashed remote blob paths
        ├── export_manifest.json      ← top-level manifest for Supabase
        └── export_audit_report.json  ← safety-category counts and per-build audit
```

On the phone, the app uses two local Drift databases:

- `pharmaguide_core.db` — read-only bundled/exported reference DB from the pipeline
- `user_data.db` — app-created read/write DB that contains `product_detail_cache`,
  `user_profile`, `user_favorites`, `user_scan_history`, and `user_stacks_local`
  so OTA swaps never overwrite user-generated state

---

## Table: `products_core`

```sql
CREATE TABLE products_core (
    dsld_id                       TEXT PRIMARY KEY,
    product_name                  TEXT NOT NULL,
    brand_name                    TEXT,
    upc_sku                       TEXT,
    image_url                     TEXT,    -- remote source URL; not guaranteed offline
    image_is_pdf                  INTEGER DEFAULT 0,
    thumbnail_key                 TEXT,    -- optional runtime/cache key, not a device path
    detail_blob_sha256            TEXT,    -- primary app resolver for hashed detail payload fetch
    interaction_summary_hint      TEXT,    -- compact JSON for instant condition/drug flagging
    decision_highlights           TEXT,    -- compact JSON: positive/caution/trust hero copy

    product_status                TEXT,    -- active, discontinued, off_market
    discontinued_date             TEXT,    -- ISO-8601
    form_factor                   TEXT,    -- tablet, capsule, powder, gummy, liquid, etc.
    supplement_type               TEXT,    -- e.g. single_nutrient, targeted, specialty, probiotic

    score_display_100_equivalent  TEXT,    -- e.g. "88/100" (mirror of quality_score_v4_100)
    score_100_equivalent          REAL,    -- /100 compat mirror of quality_score_v4_100
    grade                         TEXT,    -- v2.0.0: derived from quality_tier
    verdict                       TEXT,    -- SAFE, CAUTION, POOR, UNSAFE, BLOCKED, NOT_SCORED
    safety_verdict                TEXT,    -- backward-compatible safety label
    mapped_coverage               REAL,

    -- V4 SCORING (export schema v2.0.0) — canonical /100 six-pillar contract.
    -- Legacy /80 columns (score_quality_80, score_display_80) were DROPPED at v2.0.0.
    quality_score_v4_100            REAL,   -- canonical shipped score (/100); NULL when suppressed/not_scored
    quality_score_status            TEXT,   -- scored | suppressed_safety | not_scored
    quality_tier                    TEXT,   -- Elite/Excellent/Strong/Acceptable/Weak/Poor
    quality_score_suppressed_reason TEXT,
    raw_score_v4_100                REAL,   -- audit/debug only; NEVER the shipped score
    v4_module                       TEXT,   -- generic/probiotic/omega/multi_or_prenatal/sports
    v4_confidence                   TEXT,
    score_model_version             TEXT,   -- loud stamp: "v4"
    quality_score_version           TEXT,
    scoring_engine_version          TEXT,
    classification_schema_version   TEXT,
    v4_config_fingerprint           TEXT,

    score_ingredient_quality      REAL,    -- max 25
    score_ingredient_quality_max  REAL,
    score_safety_purity           REAL,    -- max 30
    score_safety_purity_max       REAL,
    score_evidence_research       REAL,    -- max 20
    score_evidence_research_max   REAL,
    score_brand_trust             REAL,    -- max 5
    score_brand_trust_max         REAL,

    percentile_rank               REAL,
    percentile_top_pct            REAL,
    percentile_category           TEXT,
    percentile_label              TEXT,
    percentile_cohort             INTEGER,

    is_gluten_free                INTEGER DEFAULT 0,
    is_dairy_free                 INTEGER DEFAULT 0,
    is_soy_free                   INTEGER DEFAULT 0,
    is_vegan                      INTEGER DEFAULT 0,
    is_vegetarian                 INTEGER DEFAULT 0,
    is_organic                    INTEGER DEFAULT 0,
    is_non_gmo                    INTEGER DEFAULT 0,   -- needs normalized enrichment export

    has_banned_substance          INTEGER DEFAULT 0,
    has_recalled_ingredient       INTEGER DEFAULT 0,   -- ingredient-level, not product recall
    has_harmful_additives         INTEGER DEFAULT 0,
    has_allergen_risks            INTEGER DEFAULT 0,
    blocking_reason               TEXT,                -- banned_ingredient, recalled_ingredient, etc.

    is_probiotic                  INTEGER DEFAULT 0,
    contains_sugar                INTEGER DEFAULT 0,
    contains_sodium               INTEGER DEFAULT 0,
    diabetes_friendly             INTEGER DEFAULT 0,   -- defaults to FALSE when data absent
    hypertension_friendly         INTEGER DEFAULT 0,   -- defaults to FALSE when data absent

    is_trusted_manufacturer       INTEGER DEFAULT 0,
    has_third_party_testing       INTEGER DEFAULT 0,
    has_full_disclosure           INTEGER DEFAULT 0,

    cert_programs                 TEXT,    -- JSON array
    badges                        TEXT,    -- JSON array
    top_warnings                  TEXT,    -- JSON array, max 5
    flags                         TEXT,    -- JSON array

    -- ===============================================================================
    -- v1.3.0 ENHANCEMENTS (2026-04-07) — 23 new columns
    -- ===============================================================================

    -- Enhancement 1: Stack Interaction Checking
    ingredient_fingerprint        TEXT,    -- JSON: compact ingredient dose map for stack checking
    key_nutrients_summary         TEXT,    -- JSON: top 5-10 nutrients with doses
    contains_stimulants           INTEGER DEFAULT 0,  -- caffeine, synephrine, etc.
    contains_sedatives            INTEGER DEFAULT 0,  -- melatonin, valerian, etc.
    contains_blood_thinners       INTEGER DEFAULT 0,  -- omega-3, garlic, ginkgo, etc.

    -- Enhancement 2: Social Sharing Metadata
    share_title                   TEXT,    -- Pre-formatted share title with score
    share_description             TEXT,    -- Pre-formatted 2-3 sentence summary
    share_highlights              TEXT,    -- JSON array: 3-4 key positive attributes
    share_og_image_url            TEXT,    -- Open Graph optimized image URL

    -- Enhancement 3: Search & Filter Optimization
    primary_category              TEXT,    -- omega-3, probiotic, multivitamin, collagen, protein, etc.
    secondary_categories          TEXT,    -- JSON array: adaptogen, nootropic, anti-inflammatory, etc.
    contains_omega3               INTEGER DEFAULT 0,
    contains_probiotics           INTEGER DEFAULT 0,
    contains_collagen             INTEGER DEFAULT 0,
    contains_adaptogens           INTEGER DEFAULT 0,
    contains_nootropics           INTEGER DEFAULT 0,
    key_ingredient_tags           TEXT,    -- JSON array: top 5 priority ingredients

    -- Enhancement 4: Goal Matching Preview
    goal_matches                  TEXT,    -- JSON array: matched goal IDs (e.g. ["GOAL_SLEEP_QUALITY"])
    goal_match_confidence         REAL,    -- 0.0-1.0: average cluster weight

    -- Enhancement 5: Dosing Guidance
    dosing_summary                TEXT,    -- "Take 2 capsules daily"
    servings_per_container        INTEGER, -- 60
    net_contents_quantity         REAL,    -- v1.3.1: netContents[0].quantity (e.g. 90)
    net_contents_unit             TEXT,    -- v1.3.1: netContents[0].unit (e.g. "Capsule(s)", "mL")

    -- Enhancement 6: Allergen Summary
    allergen_summary              TEXT,    -- "Contains: Soy, Tree Nuts"

    -- v1.3.2: Nutrition column (hybrid — calories is the highest-value user filter)
    calories_per_serving          REAL,    -- kcal per serving from nutritionalInfo.calories.amount; NULL when not declared

    scoring_version               TEXT,
    output_schema_version         TEXT,
    enrichment_version            TEXT,
    scored_date                   TEXT,
    export_version                TEXT NOT NULL,
    exported_at                   TEXT NOT NULL
);

CREATE INDEX idx_products_core_upc ON products_core(upc_sku);
CREATE INDEX idx_products_core_name ON products_core(product_name);
CREATE INDEX idx_products_core_brand ON products_core(brand_name);
CREATE INDEX idx_products_core_verdict ON products_core(verdict);
CREATE INDEX idx_core_score ON products_core(quality_score_v4_100);
CREATE INDEX idx_products_core_type ON products_core(supplement_type);
CREATE INDEX idx_products_core_status ON products_core(product_status);

-- v1.3.0 Indexes (partial indexes for better performance)
CREATE INDEX idx_products_core_primary_category ON products_core(primary_category);
CREATE INDEX idx_products_core_contains_omega3 ON products_core(contains_omega3) WHERE contains_omega3 = 1;
CREATE INDEX idx_products_core_contains_probiotics ON products_core(contains_probiotics) WHERE contains_probiotics = 1;
CREATE INDEX idx_products_core_contains_collagen ON products_core(contains_collagen) WHERE contains_collagen = 1;
CREATE INDEX idx_products_core_contains_adaptogens ON products_core(contains_adaptogens) WHERE contains_adaptogens = 1;
CREATE INDEX idx_products_core_contains_nootropics ON products_core(contains_nootropics) WHERE contains_nootropics = 1;
```

### Column Sources

| Column                         | Source                                                    | Notes                                                                                   |
| ------------------------------ | --------------------------------------------------------- | --------------------------------------------------------------------------------------- |
| `dsld_id`                      | `enriched.dsld_id`                                        |                                                                                         |
| `product_name`                 | `enriched.product_name`                                   |                                                                                         |
| `brand_name`                   | `enriched.brandName`                                      |                                                                                         |
| `upc_sku`                      | `enriched.upcSku`                                         | Barcode lookup                                                                          |
| `image_url`                    | `enriched.imageUrl`                                       | May be PDF, not a real image. Not offline.                                              |
| `image_is_pdf`                 | Derived from `imageUrl`                                   | Lets Flutter skip PDF URLs before image widget load                                     |
| `thumbnail_key`                | NULL at export                                            | Populated by app at runtime                                                             |
| `detail_blob_sha256`           | SHA-256 of exported detail blob JSON                      | Primary runtime resolver for hashed shared payload fetch                                |
| `interaction_summary_hint`     | Derived from `interaction_profile`                        | Compact JSON for instant condition/drug banners before detail hydration                 |
| `decision_highlights`          | Derived from enriched/scored safety + trust signals       | Compact JSON for hero summary copy (`positive`, `caution`, `trust`)                     |
| `product_status`               | `enriched.status`                                         | DSLD lifecycle, NOT safety                                                              |
| `discontinued_date`            | `enriched.discontinuedDate`                               | ISO date or NULL                                                                        |
| `form_factor`                  | `enriched.form_factor`                                    |                                                                                         |
| `supplement_type`              | `enriched.supplement_type.type`                           | Current observed values include `single_nutrient`, `targeted`, `specialty`, `probiotic` |
| `quality_score_v4_100`         | `quality_score_v4_100` (export adapter)                   | **Canonical shipped score** (/100); NULL when suppressed/not_scored                     |
| `quality_score_status`         | adapter `quality_score_status`                            | scored / suppressed_safety / not_scored                                                 |
| `quality_tier`                 | adapter `quality_tier`                                    | Elite/Excellent/Strong/Acceptable/Weak/Poor                                             |
| `raw_score_v4_100`             | adapter `raw_score_v4_100`                                | Audit/debug only — NEVER the shipped score                                              |
| `score_model_version`          | adapter (`"v4"`)                                          | Loud model stamp                                                                        |
| `score_display_100_equivalent` | `quality_score_v4_100` → "NN/100"                         | /100 compat mirror (was `scored.display_100`)                                           |
| `score_100_equivalent`         | `quality_score_v4_100`                                    | /100 compat mirror                                                                      |
| `grade`                        | derived from `quality_tier`                               | v2.0.0 (legacy /80 `score_quality_80`/`score_display_80` columns dropped)               |
| `verdict`                      | `scored.verdict`                                          | SAFE/CAUTION/POOR/UNSAFE/BLOCKED/NOT_SCORED                                             |
| `safety_verdict`               | `scored.safety_verdict`                                   | Backward-compat                                                                         |
| `mapped_coverage`              | `scored.mapped_coverage`                                  | 0.0-1.0                                                                                 |
| `score_ingredient_quality`     | `scored.section_scores.A_ingredient_quality.score`        | max 25                                                                                  |
| `score_safety_purity`          | `scored.section_scores.B_safety_purity.score`             | max 30                                                                                  |
| `score_evidence_research`      | `scored.section_scores.C_evidence_research.score`         | max 20                                                                                  |
| `score_brand_trust`            | `scored.section_scores.D_brand_trust.score`               | max 5                                                                                   |
| `has_banned_substance`         | `contaminant_data.banned_substances.substances`           | exact/alias match with `status == "banned"` only                                        |
| `has_recalled_ingredient`      | Same source, `status == "recalled"`                       | Ingredient recalled, NOT product                                                        |
| `blocking_reason`              | Derived from exact/alias contaminant matches + verdict    | Used for `CAUTION`/`UNSAFE`/`BLOCKED` safety explanation                                |
| `diabetes_friendly`            | `enriched.dietary_sensitivity_data.diabetes_friendly`     | Defaults to 0 (cautious) when absent                                                    |
| `hypertension_friendly`        | `enriched.dietary_sensitivity_data.hypertension_friendly` | Defaults to 0 (cautious) when absent                                                    |
| `scoring_version`              | `scored.scoring_metadata.scoring_version`                 |                                                                                         |
| `output_schema_version`        | `scored.output_schema_version`                            |                                                                                         |
| `enrichment_version`           | `enriched.enrichment_version`                             |                                                                                         |
| `export_version`               | Build parameter                                           | Semver TEXT, e.g. "1.3.0"                                                               |
| `exported_at`                  | Build timestamp                                           | ISO-8601                                                                                |
| **v1.3.0 Additions**           |                                                           |                                                                                         |
| `ingredient_fingerprint`       | Generated from `ingredient_quality_data.ingredients`      | JSON with nutrients{}, herbs[], pharmacological_flags{}                                 |
| `key_nutrients_summary`        | Generated from `ingredient_quality_data.ingredients`      | JSON array of top 5-10 nutrients with amounts                                           |
| `contains_stimulants`          | Derived from ingredient names                             | Boolean: caffeine, synephrine, bitter orange, yohimbine, etc.                           |
| `contains_sedatives`           | Derived from ingredient names                             | Boolean: melatonin, valerian, passionflower, lemon balm, GABA                           |
| `contains_blood_thinners`      | Derived from ingredient names                             | Boolean: omega-3, garlic, ginkgo, turmeric, curcumin, vitamin E                         |
| `share_title`                  | Generated from product_name, brandName, score_100         | Pre-formatted: "Nature's Bounty Magnesium - 92/100 ⭐"                                  |
| `share_description`            | Generated from grade, evidence, certs, dietary flags      | Pre-formatted 2-3 sentence summary                                                      |
| `share_highlights`             | Generated from formulation_detail, certs, dietary flags   | JSON array of 3-4 positive attributes                                                   |
| `share_og_image_url`           | `enriched.imageUrl`                                       | Product image URL (OG image generation future enhancement)                              |
| `primary_category`             | Classified from ingredients + supplement_type             | omega-3, probiotic, multivitamin, collagen, protein, etc.                               |
| `secondary_categories`         | Classified from ingredients + synergy_detail              | JSON array: adaptogen, nootropic, anti-inflammatory, heart-health, immune-support       |
| `contains_omega3`              | Derived from ingredient names                             | Boolean: omega-3, fish oil, EPA, DHA                                                    |
| `contains_probiotics`          | `supplement_type.type == "probiotic"`                     | Boolean                                                                                 |
| `contains_collagen`            | Derived from ingredient names                             | Boolean: collagen, collagen peptides                                                    |
| `contains_adaptogens`          | Derived from ingredient names                             | Boolean: ashwagandha, rhodiola, holy basil, ginseng, maca, reishi                       |
| `contains_nootropics`          | Derived from ingredient names                             | Boolean: lion's mane, bacopa, ginkgo, alpha-GPC, L-theanine, citicoline                 |
| `key_ingredient_tags`          | Top 5 priority ingredients                                | JSON array: ["ashwagandha", "magnesium", "vitamin_d"]                                   |
| `goal_matches`                 | Matched against `user_goals_to_clusters.json`             | JSON array of goal IDs, e.g. ["GOAL_SLEEP_QUALITY", "GOAL_REDUCE_STRESS_ANXIETY"]       |
| `goal_match_confidence`        | Average cluster weight for matched goals                  | 0.0-1.0 float                                                                           |
| `dosing_summary`               | Generated from `enriched.servingSizes[0]` + `form_factor` | v1.3.1: reads `minQuantity`/`maxQuantity`/`unit` + `maxDailyServings`. Pre-formatted: "Take 2 capsules daily" |
| `servings_per_container`       | `enriched.servingsPerContainer`                           | v1.3.1: integer passthrough from cleaner (was previously reading a nonexistent path)    |
| `net_contents_quantity`        | `enriched.netContents[0].quantity`                        | v1.3.1: REAL, NULL when missing. Powers refill-reminder `days_until_empty` calc.        |
| `net_contents_unit`            | `enriched.netContents[0].unit`                            | v1.3.1: TEXT verbatim (e.g. "Capsule(s)", "mL", "Gram(s)")                              |
| `allergen_summary`             | Generated from `allergen_hits`                            | "Contains: Soy, Tree Nuts" or NULL                                                      |
| `calories_per_serving`         | `enriched.nutrition_summary.calories_per_serving`         | v1.3.2: REAL kcal per serving; NULL when not declared. Primary nutrition filter column.  |

### What Is NOT Stored

| Data                 | Reason                          |
| -------------------- | ------------------------------- |
| `score_fit_20`       | Computed on-device per user     |
| `score_combined_100` | Computed on-device per user     |
| `off_market`         | Redundant with `product_status` |
| Price / daily cost   | User-entered                    |
| Product-level recall | No data source yet              |
| Offline image data   | Runtime concern                 |

### Detail payload resolution

`products_core.detail_blob_sha256` is now the primary runtime key for detail hydration.
The app can derive the storage path directly:

```text
shared/details/sha256/{blob_sha256[0:2]}/{blob_sha256}.json
```

`detail_index.json` is still exported and uploaded for:

- compatibility with older clients/tooling
- audit/debug workflows
- release verification

---

## Table: `products_fts`

```sql
CREATE VIRTUAL TABLE products_fts USING fts5(
    product_name, brand_name,
    content='products_core', content_rowid='rowid',
    tokenize='porter unicode61'
);
```

---

## Table: `product_detail_cache` (app-side, stored in `user_data.db`)

```sql
CREATE TABLE product_detail_cache (
    dsld_id          TEXT PRIMARY KEY,
    detail_json      TEXT NOT NULL,    -- plain JSON in v1
    cached_at        TEXT NOT NULL,
    source           TEXT NOT NULL,    -- bundled, preload, server
    detail_version   TEXT NOT NULL,    -- app stores the blob's blob_version here
    FOREIGN KEY (dsld_id) REFERENCES products_core(dsld_id)
);
```

---

## Table: `reference_data`

Small rule tables for offline Section F (user fit) scoring.

| Key                      | Source file                       | Size   | Purpose                                                                               |
| ------------------------ | --------------------------------- | ------ | ------------------------------------------------------------------------------------- |
| `rda_optimal_uls`        | rda_optimal_uls.json              | ~199KB | Dosage vs age/sex-specific RDA/UL                                                     |
| `interaction_rules`      | ingredient_interaction_rules.json | ~75KB  | Medical compatibility (45 rules, 14 conditions, 9 drug classes)                       |
| `clinical_risk_taxonomy` | clinical_risk_taxonomy.json       | ~5KB   | Severity classification (14 conditions incl. diabetes merged, high_cholesterol added) |
| `user_goals_clusters`    | user_goals_to_clusters.json       | ~11KB  | Goal matching                                                                         |

```sql
CREATE TABLE reference_data (
    key         TEXT PRIMARY KEY,
    version     TEXT NOT NULL,
    data        TEXT NOT NULL,    -- JSON
    updated_at  TEXT NOT NULL
);
```

---

## Table: `export_manifest`

```sql
CREATE TABLE export_manifest (
    key   TEXT PRIMARY KEY,
    value TEXT NOT NULL
);
```

Required rows:

| Key                | Example value          |
| ------------------ | ---------------------- |
| `db_version`       | `2026.03.29.232343`    |
| `pipeline_version` | `3.4.0`                |
| `scoring_version`  | `3.4.0`                |
| `generated_at`     | `2026-03-29T22:33:24Z` |
| `product_count`    | `180423`               |
| `min_app_version`  | `1.0.0`                |
| `schema_version`   | `1`                    |

`db_version` is generated from the UTC build timestamp as `YYYY.MM.DD.HHMMSS`.
The SQLite `export_manifest` table intentionally omits `checksum`, because the
checksum describes the final DB file bytes and would otherwise become
self-referential.

The standalone `export_manifest.json` file also includes:

- `checksum`: SHA-256 of the final `pharmaguide_core.db` artifact
- `detail_blob_count`: total product-keyed local detail blobs in the build output
- `detail_blob_unique_count`: unique hashed detail payloads that may need remote upload
- `detail_index_checksum`: SHA-256 of the versioned `detail_index.json`
- `errors`: an array of failed products with `dsld_id` and `error`

These fields are JSON-only and are used for distribution verification, CI gates,
and the remote Supabase manifest.

---

## Detail Blob Contract

One local JSON file per product is emitted during build as `{dsld_id}.json`.
Remote distribution does not use that filename directly: the Flutter app reads
`products_core.detail_blob_sha256`, derives the hashed payload path, then fetches
the payload from shared storage. `detail_index.json` remains available as a
compatibility/audit fallback. The payload is cached on-device in
`product_detail_cache.detail_json` after first access.

### Structure

```json
{
  "dsld_id": "37323",
  "blob_version": 1,
  "ingredients": [...],
  "inactive_ingredients": [...],
  "warnings": [...],
  "score_bonuses": [...],
  "score_penalties": [...],
  "section_breakdown": {
    "ingredient_quality": {"score", "max", "sub": {..., "probiotic_breakdown": {...}, "omega3_breakdown": {...}}},
    "safety_purity": {"score", "max", "sub": {..., "B5_blend_evidence": [...], "B7_penalty", "B7_dose_safety_evidence": [...]}},
    "evidence_research": {"score", "max", "matched_entries", "ingredient_points": {...}},
    "brand_trust": {"score", "max", "sub": {...}},
    "violation_penalty": 0.0
  },
  "compliance_detail": {...},
  "certification_detail": {...},
  "proprietary_blend_detail": {...},
  "dietary_sensitivity_detail": {...},
  "formulation_detail": {...},
  "serving_info": {...},
  "manufacturer_detail": {...},
  "probiotic_detail": {...}, // optional
  "synergy_detail": {...},   // optional
  "interaction_summary": {
    "highest_severity": "avoid",
    "condition_summary": {
      "<condition_id>": {
        "label": "Pregnancy",
        "highest_severity": "avoid",
        "ingredient_count": 2,
        "ingredients": ["Vitamin A", "Retinyl Palmitate"],
        "rule_ids": ["R001"],
        "actions": ["Do not use preformed Vitamin A above 3000 mcg RAE in pregnancy."]
      }
    },
    "drug_class_summary": {
      "<drug_class_id>": {
        "label": "Retinoids",
        "highest_severity": "avoid",
        "ingredient_count": 1,
        "ingredients": ["Vitamin A"],
        "rule_ids": ["R002"],
        "actions": ["Avoid use with retinoid medications."]
      }
    }
  },
  "evidence_data": {...},
  "rda_ul_data": {...},
  "nutrition_detail": {
    "calories_per_serving": 120.0,
    "total_carbohydrates_g": 10.0,
    "total_fat_g": 5.0,
    "protein_g": 8.0,
    "dietary_fiber_g": 2.0
  },
  "unmapped_actives": {
    "names": ["Exotic Extract", "Typo Ingredient"],
    "total": 2,
    "excluding_banned_exact_alias": 2
  }
}
```

#### Nutrition detail (`nutrition_detail`)

Added in v1.3.2. Always present (even when all values are `null` — no null-checks needed on the Flutter side).

| Key                     | Type          | Notes                                                        |
|-------------------------|---------------|--------------------------------------------------------------|
| `calories_per_serving`  | float or null | kcal. Also promoted to `products_core.calories_per_serving`. |
| `total_carbohydrates_g` | float or null | grams                                                        |
| `total_fat_g`           | float or null | grams                                                        |
| `protein_g`             | float or null | grams                                                        |
| `dietary_fiber_g`       | float or null | grams                                                        |

Source: `enriched.nutrition_summary` ← `product.nutritionalInfo.*`.amount`. Not scored — transparency only.

#### Unmapped actives (`unmapped_actives`)

Added in v1.3.2. Always present (even when `names` is empty — no null-checks needed on the Flutter side). Use this to render a "X ingredients could not be mapped" transparency panel.

| Key                          | Type     | Notes                                                           |
|------------------------------|----------|-----------------------------------------------------------------|
| `names`                      | string[] | Ingredient names that could not be resolved in the IQM          |
| `total`                      | int      | Total unmapped actives before any exclusions                    |
| `excluding_banned_exact_alias` | int    | Unmapped count excluding ingredients with banned exact/alias hits |

Source: `scored.unmapped_actives` / `scored.unmapped_actives_total` / `scored.unmapped_actives_excluding_banned_exact_alias`.

### Active ingredient entry

```json
{
  "raw_source_text": "Vitamin A Palmitate",
  "name": "Vitamin A Palmitate",
  "standardName": "Retinyl Palmitate",
  "normalized_key": "vitamin_a",
  "forms": [{"name": "Palmitate"}],
  "quantity": 2000.0,
  "unit": "IU",
  "standard_name": "Vitamin A",
  "form": "retinyl palmitate",
  "matched_form": "retinyl palmitate",
  "matched_forms": [...],
  "extracted_forms": [...],
  "display_form_label": "Palmitate",
  "form_status": "known",
  "form_match_status": "mapped",
  "category": "vitamins",
  "bio_score": 14,
  "natural": false,
  "score": 14,
  "_score_note": "v3.6.0+: `score` is a deprecated alias of `bio_score` (no natural-source bonus). Pre-v3.6.0 blobs had `score = bio_score + 3*natural` (range 0-18). New consumers should read `bio_score` directly (range 0-15, pure form quality). Sourcing signal lives in section_breakdown.ingredient_quality.sub.A5e.",
  "notes": "The most common preformed Vitamin A in supplements...",
  "mapped": true,
  "safety_hits": [...],
  "normalized_amount": null,
  "normalized_unit": null,
  "role": "active",
  "parent_key": "vitamin_a",
  "dosage": 2000.0,
  "dosage_unit": "IU",
  "normalized_value": null,
  "is_mapped": true,
  "is_harmful": false,
  "harmful_severity": null,
  "is_safety_concern": false,
  "harmful_notes": null,
  "is_banned": false,
  "is_allergen": false,
  "identifiers": {"cui": "C0042839", "unii": "81G40H8B0T"},
  "display_label": "Vitamin A (Palmitate)",
  "display_dose_label": "2000 IU",
  "dose_status": "disclosed"
}
```

#### Canonical active ingredient contract (v1.5.0)

The pipeline emits explicit display + routing fields so Flutter
renders directly without local inference. Single source of truth
per concern.

| Field                 | Type      | Values / Source                                                                                  |
| --------------------- | --------- | ------------------------------------------------------------------------------------------------ |
| `display_form_label`  | string?   | User-visible form (e.g. `"Palmitate"`). `null` when form genuinely unknown.                      |
| `form_status`         | enum      | `"known"` \| `"unknown"`                                                                          |
| `form_match_status`   | enum      | `"mapped"` (in IQM) \| `"unmapped"` (label disclosed but not in IQM) \| `"n/a"` (status=unknown) |
| `display_dose_label`  | string    | Pre-formatted: `"600 mcg"` / `"Amount not disclosed"` (blend member) / `"—"` (missing)           |
| `dose_status`         | enum      | `"disclosed"` \| `"not_disclosed_blend"` \| `"missing"`                                          |
| `is_safety_concern`   | boolean   | True only when `harmful_severity` is `moderate`/`high`/`critical`. Distinct from `is_harmful`.   |

**Resolution order for `display_form_label`:**
1. Cleaner `forms[0].name` if present (label-disclosed form).
2. Enricher `matched_form` prettified if non-placeholder (bridge for cleaner gaps).
3. Otherwise `null` with `form_status: "unknown"`.

**Deprecated fields** (kept for back-compat — Flutter should migrate then we delete):
- `form` — bare passthrough of `forms[0].name`. Use `display_form_label` instead.
- `is_harmful` — provenance flag (presence in `harmful_additives.json`), not a safety signal. Use `is_safety_concern` for routing.

### Inactive ingredient entry

```json
{
  "raw_source_text": "Silicon Dioxide",
  "name": "Silicon Dioxide",
  "standardName": "Silicon Dioxide (E551)",
  "normalized_key": "silicon_dioxide",
  "forms": [],
  "category": "flow_agent_anticaking",
  "is_additive": true,
  "additive_type": "anti_caking_agent",
  "functional_roles": ["anti_caking", "flow_agent"],
  "standard_name": "Silicon Dioxide (E551)",
  "severity_level": "low",
  "match_method": "alias",
  "matched_alias": "silicon dioxide",
  "notes": "Amorphous silicon dioxide used as anti-caking agent...",
  "mechanism_of_harm": "FDA GRAS at <2% w/w...",
  "common_uses": ["flow agent", "anti-caking", "tablet glidant"],
  "population_warnings": ["No specific population concerns at <2% w/w"],
  "is_harmful": true,
  "harmful_severity": "low",
  "harmful_notes": "FDA GRAS, EFSA 2018 data gap (precautionary, not finding of harm)...",
  "identifiers": {
    "cui": "C0037098",
    "cas": "7631-86-9",
    "pubchem_cid": 24261,
    "unii": "ETJ7Z6XBU4"
  },
  "display_label": "Silicon Dioxide (E551)",
  "display_role_label": "Anti-caking agent",
  "severity_status": "suppress",
  "is_safety_concern": false
}
```

#### Canonical inactive ingredient contract (v1.5.0)

| Field                | Type      | Values / Source                                                                                                                                  |
| -------------------- | --------- | ------------------------------------------------------------------------------------------------------------------------------------------------ |
| `display_label`      | string    | User-visible name. Prefers `standard_name`, falls back to `name`.                                                                                |
| `display_role_label` | string?   | Prettified excipient role (e.g. `"Anti-caking agent"`). `null` when the ingredient has no excipient role (bare amino acids etc.).               |
| `severity_status`    | enum      | `"critical"` (always show) \| `"suppress"` (Tradeoffs only — silicon dioxide, MCC) \| `"informational"` (flagged but not hazardous) \| `"n/a"` (non-additive). |
| `is_safety_concern`  | boolean   | True only when `harmful_severity` is `moderate`/`high`/`critical`. Distinguishes real risks from tracked-for-transparency excipients.            |

**Why `is_harmful` is not enough:** silicon dioxide and microcrystalline cellulose appear in `harmful_additives.json` (so `is_harmful: true`) but with `severity_level: low` because they're *tracked for transparency*, not because they're risks. The contract's `is_safety_concern` flag and `severity_status` enum lift that distinction out of Flutter so consumers read one field instead of cross-computing three.

#### Inactive contract additions (v1.6.1 — 2026-05-12)

Four new fields on every active **and** inactive ingredient blob entry, emitted by the unified inactive-ingredient resolver (`scripts/inactive_ingredient_resolver.py`). They are the single safety + provenance contract for Flutter — replaces the old scattered logic where `severity_status` came from `harmful_additives.json` only and silently missed `banned_recalled_ingredients.json` (Titanium Dioxide, Talc).

| Field             | Type    | Values / Source                                                                                                                                                       |
| ----------------- | ------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `is_banned`       | boolean | `True` ONLY when matched in `banned_recalled_ingredients.json` with `status="banned"`. Distinct from `high_risk` / `recalled` / `watchlist` — those use `severity_status` only. |
| `safety_reason`   | string? | One-line user-facing rationale when `is_safety_concern=true`. Pulled from the source entry's `safety_warning_one_liner` / `safety_summary_one_liner` / `reason` field. `null` otherwise. |
| `matched_source`  | enum?   | Provenance: `"banned_recalled"` \| `"harmful_additives"` \| `"other_ingredients"` \| `null` (unmatched). Tells Flutter (and the audit script) WHICH source file triggered the classification. |
| `matched_rule_id` | string? | Provenance: the source entry's `id` (e.g. `"BANNED_ADD_TITANIUM_DIOXIDE"`, `"ADD_SUCRALOSE"`, `"OI_TOCOPHEROL_PRESERVATIVE"`). Lets an audit prove which entry fired. |

**Resolver priority order** (highest authority wins):

1. `banned_recalled_ingredients.json` (skips `match_mode` ∈ {`disabled`, `historical`}).
2. `harmful_additives.json`.
3. `other_ingredients.json` (679 excipient role classifications).
4. Unmatched → `severity_status="n/a"`, all flags `false`, role labels `null`.

**Severity mapping** the resolver applies:

```
banned_recalled.status = "banned"       → severity_status="critical", is_banned=true,  is_safety_concern=true
banned_recalled.status = "high_risk"    → severity_status="critical", is_banned=false, is_safety_concern=true
banned_recalled.status = "recalled"     → severity_status="critical", is_banned=false, is_safety_concern=true
banned_recalled.status = "watchlist"    → severity_status="informational", is_safety_concern=false
harmful_additives.severity_level ∈
  {high, critical, moderate}            → severity_status="critical", is_safety_concern=true
harmful_additives.severity_level = "low" → severity_status="suppress",  is_safety_concern=false  (transparency)
other_ingredients (excipient match)     → severity_status="n/a",       is_safety_concern=false
```

**Matching guarantees**:
- Match on `standard_name` + `aliases` ONLY. Never on notes/description/mechanism_of_harm/safety_summary text. Prevents the Candurin Silver bleed-through ("titanium dioxide" appears in Candurin's description — must not turn every Candurin entry into a TiO2 match).
- Normalized exact match (lowercase, whitespace-normalized). No broad fuzzy.

**Audit gate**: `scripts/audit_inactive_safety.py` runs four CI-grade checks (banned-signal violations, notes-only false positives, unknown-role count, source distribution). Exits non-zero on any banned-in-inactive shipping without proper safety signal.

**Active ingredient canonical_id + delivers_markers (also v1.6.1)**: every active ingredient blob entry now also carries `canonical_id` (stable string id — `"vitamin_a"`, `"turmeric"`, `"camu_camu"`) used by interaction rules / stack matching / evidence routing / biomarker scoring / dedup / analytics, plus `delivers_markers` (the marker-via-ingredient evidence routing payload: turmeric → curcumin + PubMed citation). Both fields are derived from the IQM match record in the enriched product; build_final_db reads them at line 2497–2511.

### Warning entry

Each warning in the `warnings` array has a `type` field that determines which
additional fields are present:

```json
// banned_substance / recalled_ingredient / high_risk_ingredient / watchlist_substance
{
  "type": "banned_substance",
  "severity": "critical",
  "title": "Banned substance: DMAA",
  "detail": "FDA-banned stimulant with cardiovascular risks...",
  "source": "banned_recalled_ingredients",
  "date": "2026-01-09",
  "regulatory_date_label": "First FDA enforcement action",
  "clinical_risk": "critical"
}

// harmful_additive
{
  "type": "harmful_additive",
  "severity": "moderate",
  "title": "Contains Titanium Dioxide",
  "detail": "Nanoparticle concerns in gut epithelium...",
  "notes": "A white pigment used as an opacifier...",
  "mechanism_of_harm": "Nanoparticle concerns in gut epithelium...",
  "population_warnings": ["Children — immature gut barrier"],
  "category": "colorant",
  "source": "harmful_additives_db"
}

// allergen
{
  "type": "allergen",
  "severity": "moderate",
  "title": "Allergen: Soy & Soy Lecithin",
  "detail": "Presence: contains. Ingredient: soy lecithin",
  "notes": "Major allergen. Cross-reactivity with other legumes possible...",
  "supplement_context": "Common emulsifier/excipient and in protein products.",
  "prevalence": "high",
  "source": "allergen_db"
}

// interaction
{
  "type": "interaction",
  "severity": "avoid",
  "title": "Vitamin A / pregnancy",
  "detail": "Retinoid exposure risk during pregnancy.",
  "action": "Do not use preformed Vitamin A above 3000 mcg RAE in pregnancy.",
  "condition_id": "pregnancy",
  "ingredient_name": "Vitamin A",
  "evidence_level": "established",
  "sources": ["https://ods.od.nih.gov/factsheets/VitaminA-HealthProfessional/"],
  "dose_threshold_evaluation": {
    "evaluated": true,
    "matched_threshold": true,
    "thresholds_checked": [
      {
        "evaluated": true,
        "basis": "per_day",
        "computed_amount": 5000,
        "computed_unit": "mcg RAE",
        "threshold_value": 3000,
        "threshold_unit": "mcg RAE",
        "comparator": ">",
        "matched": true
      }
    ],
    "selected_from": "matched_threshold",
    "selected_severity": "avoid"
  },
  "source": "interaction_rules"
}

// drug_interaction
{
  "type": "drug_interaction",
  "severity": "avoid",
  "title": "Vitamin A / retinoids",
  "detail": "Overlapping retinoid exposure.",
  "action": "Avoid use with retinoid medications.",
  "drug_class_id": "retinoids",
  "ingredient_name": "Vitamin A",
  "evidence_level": "established",
  "sources": ["https://ods.od.nih.gov/factsheets/VitaminA-HealthProfessional/"],
  "dose_threshold_evaluation": {
    "evaluated": true,
    "matched_threshold": true,
    "thresholds_checked": [...],
    "selected_from": "matched_threshold",
    "selected_severity": "avoid"
  },
  "source": "interaction_rules"
}

// dietary
{
  "type": "dietary",
  "severity": "moderate",
  "title": "Diabetes",
  "detail": "Contains 5.0g sugar per serving.",
  "source": "dietary_sensitivity_data"
}

// status
{
  "type": "status",
  "severity": "info",
  "title": "Discontinued Product",
  "detail": "2025-12-31",
  "source": "dsld"
}
```

### Deprecation roadmap (v1.5.0+)

Fields below are kept for back-compat while Flutter migrates to the
canonical contract. Once the Flutter PR ships and consumers stop
reading them, they get deleted from `build_final_db.py` (single
delete commit per field, with a regression test pin).

**Active ingredient row:**

| Deprecated field | Replacement                  | Removal trigger                                |
| ---------------- | ---------------------------- | ---------------------------------------------- |
| `form`           | `display_form_label`         | Flutter migrates to `display_form_label`       |
| `is_harmful`     | `is_safety_concern` + `severity_status` | Flutter migrates routing logic        |

**Inactive ingredient row:**

| Deprecated field | Replacement                  | Removal trigger                                |
| ---------------- | ---------------------------- | ---------------------------------------------- |
| `severity_level` | `harmful_severity` (same value, picked one) | One field for one concept       |
| `match_method`   | move to `_debug` subkey      | Flutter never reads internal IQM telemetry     |
| `matched_alias`  | move to `_debug` subkey      | Same — internal pipeline diagnostics           |
| `is_harmful`     | `is_safety_concern` + `severity_status` | Flutter migrates routing logic        |

**Empty-string defaults:** several inactive fields (`category`,
`additive_type`, `severity_level`, `match_method`, `matched_alias`,
`notes`, `mechanism_of_harm`) currently emit `""` when unpopulated.
Convert to `null` once Flutter handles both — eliminates the empty-vs-null
ambiguity.

### Notes on detail blob

- Active ingredient `notes` come from IQM form notes. These are polished educational text.
- Inactive ingredient `notes` now come from `other_ingredients.json` reference data.
  `additive_type` and `common_uses` are reliable. If the ingredient matched
  `harmful_additives.json`, safety-specific `notes` and `mechanism_of_harm` take priority.
- `evidence_data` is included when enrichment produced clinical match output for the product.
- `rda_ul_data` is included when enrichment emitted an RDA/UL analysis block. It may still
  contain `collection_enabled: false` with a reason. When absent entirely, the app treats it
  as unavailable.
- `warnings` include banned/recalled/high-risk/watchlist ingredient hits, allergens, harmful
  additives, interaction warnings, drug interaction warnings, dietary warnings, and product
  status warnings. Each warning type carries specific provenance fields (see examples above).
- `dose_threshold_evaluation` is the raw interaction-rule evaluation payload emitted by the
  pipeline. The app should treat it as structured diagnostic data, not as a fixed
  `{threshold_mcg, actual_mcg}` shape.
- `score_bonuses` lists every positive scoring factor. Each entry has:
  `{id, label, score, detail?}`. The `id` is a section sub-score key (e.g. `"A2"`, `"A3"`,
  `"B4a"`, `"probiotic"`). `detail` is optional and present only on A3 (delivery tier name).
  The app can render these as a "What helped this score" section.
- `score_penalties` lists every negative scoring factor. The `id` determines which fields
  are present beyond the common `{id, label}`:
  - `B0` (banned/recalled): `{id, label, status, reason}`
  - `B1` (harmful additive): `{id, label, severity, reason}`
  - `B2` (allergen): `{id, label, severity, presence}`
  - `B3` (compliance claim): `{id, label, score}`
  - `B5` (proprietary blend): `{id, label, score, blend_count}`
  - `B6` (disease claims): `{id, label, score}`
  - `B7` (dose safety): `{id, label, severity, reason}` — one entry per ingredient exceeding 150% of highest adult UL. `severity` is `"critical"` at 200%+ or `"warning"` at 150-200%. `reason` includes nutrient name, amount, and UL value.
  - `violation` (scoring violation): `{id, label, score}`
    The app can render these as a "What hurt this score" section.
- `formulation_detail` carries the context behind A3/A4/A5 bonuses: delivery tier,
  absorption enhancers found, organic certification, standardized botanicals, synergy
  qualification, and non-GMO verification.
- `probiotic_detail` is present only for probiotic products. Includes strain composition,
  CFU data, clinical strain matches with evidence levels, prebiotic pairing, and survivability
  coating. The `probiotic_breakdown` in `section_breakdown.ingredient_quality.sub` carries
  the scoring sub-components (CFU, diversity, clinical strains, prebiotic, survivability).
- `omega3_breakdown` lives in `section_breakdown.ingredient_quality.sub` when the product
  has explicit EPA/DHA label amounts. This is the app-facing export for omega-3 dose context;
  the pipeline's legacy `E_dose_adequacy` compatibility output is not a separate final-export
  section.
- `synergy_detail` is present when synergy clusters were matched. Includes cluster names,
  matched ingredients with their doses and minimum effective dose thresholds, and
  qualification status.
- `identifiers` is present on both active and inactive ingredient entries when the source
  data file has CUI, CAS, PubChem CID, or UNII. Active ingredients pull from IQM parent
  entries; inactive ingredients pull from harmful_additives.json or other_ingredients.json.
  Banned/recalled and harmful_additive warning entries also carry identifiers. Only non-null
  fields are included to minimize blob size. The app can use CUI for UMLS lookups and
  PubChem CID for compound detail pages.
- Plain JSON TEXT in v1. Switch to compressed BLOB later if needed.

---

## `top_warnings` Export Rule

Warnings selected at export time. Priority order, max 5 items:

1. Banned substance (`status == "banned"` + exact/alias match)
2. Recalled ingredient (`status == "recalled"` + exact/alias match)
3. Watchlist ingredient (`status == "watchlist"` + exact/alias match)
4. Allergen risks (from `allergen_hits`)
5. Harmful additives (from `harmful_additives`, highest severity first)
6. Interaction warnings (from `interaction_profile.ingredient_alerts`, highest severity first)
7. Dietary sensitivity (structured warnings first, sugar/sodium fallback)
8. Product status (discontinued, off-market)

Each warning is a short string for scan card display. Full explanations live in the detail blob.

---

## Runtime Flow

```
App Launch
  -> Open local SQLite
  -> Read export_manifest
  -> If online: check Supabase for newer version
  -> If remote min_app_version is higher than local app version: force app update before parsing new release
  -> If newer: download full artifact to staging path in background (no binary diffing required in v1)
  -> Verify checksum from remote export_manifest.json
  -> Open/test staged DB
  -> Atomically swap only after verification passes
  -> Continue with local DB even if update fails

Barcode Scan
  -> Lookup upc_sku in products_core (local, instant)
  -> Render scan card from products_core
  -> Compute score_fit_20 locally from user_profile + reference_data
  -> On tap: load products_core top section instantly
  -> Check product_detail_cache
  -> If cached: render full detail instantly
  -> If not cached + online: fetch from Supabase -> cache -> render
  -> If not cached + offline: show core only, mark detail unavailable

Search
  -> Debounce input (~300ms)
  -> Query local FTS index with LIMIT 50
  -> Return results instantly
  -> Open product from products_core
  -> Hydrate detail via cache/server as needed
```

---

## Build Tooling

### Single brand export

```bash
python3 scripts/build_final_db.py \
  --enriched-dir output_Thorne_enriched/enriched \
  --scored-dir output_Thorne_scored/scored \
  --output-dir /tmp/final_db
```

### Multi-brand auto-discovery

```bash
python3 scripts/build_all_final_dbs.py \
  --scan-dir scripts/ \
  --output-dir /tmp/final_db_all
```

### CI validation

```bash
pytest scripts/tests/test_export_gate.py -q --tb=short
# Check audit report for contract failures:
python3 -c "
import json
r = json.load(open('/tmp/final_db_all/export_audit_report.json'))
assert r['counts']['export_contract_invalid'] == 0
"
```

---

## Stage 4: Distribution (Supabase)

After `build_final_db.py` produces the local build artifacts, `sync_to_supabase.py`
uploads them to Supabase Storage and rotates the manifest.

```bash
# Upload build output to Supabase (requires SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY in .env)
python3 scripts/sync_to_supabase.py <build_output_dir>

# Preview what would be uploaded without actually uploading
python3 scripts/sync_to_supabase.py <build_output_dir> --dry-run
```

### Storage paths

The DB artifact and index are versioned. Detail JSON blobs are content-addressed
and shared across versions so unchanged products do not get re-uploaded.

| Artifact             | Remote path                                                               |
| -------------------- | ------------------------------------------------------------------------- |
| SQLite database      | `pharmaguide/v{db_version}/pharmaguide_core.db`                           |
| Detail index         | `pharmaguide/v{db_version}/detail_index.json`                             |
| Detail blob payloads | `pharmaguide/shared/details/sha256/{blob_sha256[0:2]}/{blob_sha256}.json` |

### Supabase RPCs

| RPC               | Called by                                                     | Purpose                                                                                                                                                                                                             |
| ----------------- | ------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `rotate_manifest` | `sync_to_supabase.py` via `supabase_client.insert_manifest()` | Atomically inserts a new manifest row and marks the previous row as not current. Prevents a window where no row has `is_current=true`.                                                                              |
| `increment_usage` | Flutter app (authenticated users)                             | Atomic usage increment with day rollover for freemium tracking. Accepts `p_user_id` and `p_type` (`'scan'` or `'ai_message'`), returns a JSON object with `scans_today`, `ai_messages_today`, and `limit_exceeded`. |

### Sync behavior

- Compares local `db_version` against the remote manifest to decide whether a new
  artifact should be uploaded or downloaded.
- Uses the remote `checksum` to verify the downloaded SQLite artifact before swap-in.
- The client should treat `min_app_version` as a hard compatibility gate before promoting a downloaded release.
- Primary runtime path: use `products_core.detail_blob_sha256` to derive the hashed shared blob path directly.
- `detail_index.json` remains available for compatibility and audit workflows.
- If any unique detail blob upload fails, manifest rotation is aborted to prevent clients
  from seeing the new version and getting broken detail fetches. The DB file and detail
  index are safe to re-upload (upsert).
- Detail blob sync uses bounded concurrency and skips hashed blobs that already exist
  remotely, so unchanged product details are not re-uploaded on every DB version.
- App-side `product_detail_cache` should use release-version-aware invalidation and bounded LRU eviction.

---

## V1 Gaps

| Gap                       | Status                                                             |
| ------------------------- | ------------------------------------------------------------------ |
| `is_non_gmo`              | Evidence exists in label text, needs normalized boolean extraction |
| Product-level recalls     | Needs product/UPC-keyed FDA data source. Not faked in v1.          |
| Offline images            | `image_url` may be PDF. V1 uses placeholder + runtime cache.       |
| `rda_ul_data` enforcement | Must decide: always collect, or treat as optional in detail blob   |
