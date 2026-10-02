# Pipeline Reference

> Quick reference for the data pipeline output consumed by the Flutter app.  
> Source: `dsld_clean` repo, `FINAL_EXPORT_SCHEMA_V1.md`, `SCORING_ENGINE_SPEC.md`

---

## Key Pipeline Data Files (scripts/data/)

| File | Entries | Purpose | Scoring Role |
|------|---------|---------|--------------|
| `ingredient_quality_map.json` | 563 parents | Quality scoring for known ingredients | Formulation input; current scoring config owns credit |
| `banned_recalled_ingredients.json` | 143 | Regulatory safety disqualifications | **Penalty/Gate** (B0 hard-stop, BLOCKED verdict) |
| `harmful_additives.json` | 115 | Harmful additive identification | Existing safety and quality owners determine applicable judgments |
| `backed_clinical_studies.json` | 197 (all PMID-backed) | Clinical evidence for bonus points | Evidence input; applicable reviewed evidence determines credit |
| `allergens.json` | Big 8 types | Allergen classification | **Flag** (profile-driven alerts) |
| `rda_optimal_uls.json` | -- | Dosing adequacy benchmarks (RDA, AI, UL) | Existing Dose/exposure and Safety owners consume applicable benchmarks |
| `manufacturer_violations.json` | -- | Brand trust penalties | Verification input; current scoring config owns consequences |
| `synergy_cluster.json` | -- | Ingredient synergy groupings | Formulation input; current scoring config owns credit |

All files use `_metadata` contract: `schema_version`, `last_updated`, `total_entries`.

---

## products_core Table -- Key Columns

### Identity & Display
| Column | Type | Notes |
|--------|------|-------|
| `dsld_id` | TEXT PK | NIH DSLD product ID |
| `product_name` | TEXT NOT NULL | |
| `brand_name` | TEXT | |
| `upc_sku` | TEXT | Barcode lookup |
| `image_url` | TEXT | May be PDF -- check `image_is_pdf` |
| `image_is_pdf` | INTEGER | 1 = skip image widget |
| `detail_blob_sha256` | TEXT | Primary resolver for hashed detail fetch |

### Independent Quality, Safety and Completion

| Column | Type | Notes |
|--------|------|-------|
| `quality_score_v4_100` | REAL | Canonical public whole-number quality score /100; null when not displayable |
| `quality_score_status` | TEXT | `scored` / `suppressed_safety` / `not_scored`; controls score display eligibility |
| `quality_tier` | TEXT | Exceptional / Excellent / Very good / Good / Needs improvement / Poor; quality only |
| `product_safety_status` | TEXT | `blocked` / `unsafe` / `caution` / `no_known_catalog_concern` / `not_assessed`; independent of score |
| `quality_assessment_status` | TEXT | `complete` / `partial` / `failed`; completion is distinct from score availability |
| `score_100_equivalent` | REAL | Compatibility mirror of the public /100 quality score |
| `score_display_100_equivalent` | TEXT | Compatibility display mirror |
| `grade` | TEXT | Compatibility label derived from `quality_tier` |
| `verdict` | TEXT | Compatibility/readiness only: SAFE / CAUTION / UNSAFE / BLOCKED / NOT_SCORED. POOR is readable only in older cached catalogs |

The legacy `score_quality_80` and `score_display_80` columns were removed in
export schema 2.0.0. Never restore them or infer safety from quality.

### Quality Pillars

| Pillar | Maximum |
|--------|---------|
| Formulation | 20 |
| Dose | 20 |
| Evidence | 20 |
| Transparency | 15 |
| Verification | 15 |
| Safety/Hygiene | 10 |

These are components of the quality score; the Safety/Hygiene pillar does not
replace the independent catalog safety disposition.

### Safety Flags
| Column | Type | Meaning |
|--------|------|---------|
| `has_banned_substance` | INTEGER | Ingredient-level banned (B0 gate) |
| `has_recalled_ingredient` | INTEGER | Ingredient-level recalled (NOT product recall) |
| `has_harmful_additives` | INTEGER | Contains harmful additives |
| `has_allergen_risks` | INTEGER | Contains known allergens |
| `blocking_reason` | TEXT | Why product is BLOCKED (if applicable) |

### Interaction & Stack Checking (v1.3.0)
| Column | Type | Notes |
|--------|------|-------|
| `interaction_summary_hint` | TEXT (JSON) | Compact condition/drug flag for instant banners |
| `ingredient_fingerprint` | TEXT (JSON) | Compact ingredient-dose map for stack cross-checking |
| `key_nutrients_summary` | TEXT (JSON) | Top 5-10 nutrients with doses |
| `contains_stimulants` | INTEGER | Caffeine, synephrine, etc. |
| `contains_sedatives` | INTEGER | Melatonin, valerian, etc. |
| `contains_blood_thinners` | INTEGER | Omega-3, garlic, ginkgo, etc. |

### Search & Filter (v1.3.0)
| Column | Type | Notes |
|--------|------|-------|
| `primary_category` | TEXT | omega-3, probiotic, multivitamin, collagen, protein, etc. |
| `secondary_categories` | TEXT (JSON) | adaptogen, nootropic, anti-inflammatory, etc. |
| `goal_matches` | TEXT (JSON) | Matched goal IDs (e.g., GOAL_SLEEP_QUALITY) |

---

## Detail Blob Key Structures

### interaction_summary (inside detail blob)

```json
{
  "conditions": {
    "diabetes": {
      "severity": "major",
      "mechanism": "Chromium may alter insulin sensitivity",
      "recommendation": "Monitor blood glucose closely",
      "evidence_level": "moderate",
      "affected_ingredients": ["chromium_picolinate"]
    }
  },
  "drug_classes": {
    "blood_thinners": {
      "severity": "major",
      "mechanism": "Omega-3 fatty acids have antiplatelet effects",
      "recommendation": "Consult physician before combining",
      "evidence_level": "strong",
      "affected_ingredients": ["fish_oil", "epa", "dha"]
    }
  }
}
```

### section_breakdown (inside detail blob)

```json
{
  "ingredient_quality": {
    "score": 18.5,
    "max": 25,
    "sub": {
      "bioavailability": { "score": 5.0, "max": 8 },
      "premium_forms": { "score": 3.5, "max": 5 },
      "omega3_breakdown": { ... }
    }
  },
  "safety_purity": { "score": 24.0, "max": 30 },
  "evidence_research": { "score": 12.0, "max": 20 },
  "brand_trust": { "score": 3.0, "max": 5 }
}
```

### warnings (inside detail blob)

```json
[
  {
    "type": "banned_ingredient",
    "severity": "critical",
    "ingredient": "ephedra",
    "mechanism_of_harm": "Cardiovascular risk",
    "population_warnings": ["all populations"],
    "regulatory_reference": "FDA 2004 ban"
  }
]
```

---

## Severity Enum Values

| Value | Meaning | UI Treatment |
|-------|---------|-------------|
| `critical` | Immediate safety concern (banned, recalled) | Red banner, hard-stop |
| `major` | Significant interaction or risk | Red text, prominent warning |
| `moderate` | Notable concern, may need monitoring | Amber text, caution card |
| `minor` | Low-level concern, informational | Gray text, expandable detail |
| `informational` | No safety concern, context only | No visual emphasis |

---

## Evidence Level Values

| Value | Meaning | Data Backing |
|-------|---------|-------------|
| `strong` | Multiple RCTs, meta-analyses | PMID-backed clinical studies |
| `moderate` | Some RCTs, consistent observational data | PMID-backed |
| `limited` | Few studies, inconsistent results | May or may not have PMIDs |
| `insufficient` | Insufficient evidence to evaluate | No clinical backing |
| `traditional` | Traditional/historical use only | No clinical backing |

---

## Consumer Status Ownership

`lib/core/scoring/catalog_product_semantics.dart` is the app's existing typed
reader. Consumers use `product_safety_status` for warnings and hard guards,
`quality_tier` for quality, `quality_score_status` for number availability, and
`quality_assessment_status` for completed-rating eligibility.

- `blocked` / `unsafe`: retain existing safety warning and score-suppression guards.
- `caution`: render the independent safety warning; it is not a quality tier.
- `no_known_catalog_concern`: no catalog safety finding; never personalized medical reassurance.
- `not_assessed`: unknown safety assessment; never substitute a positive legacy label.
- Quality ratings are independent of safety findings. BLOCKED/UNSAFE preserve
  the existing suppression of displayed scores and tiers.

The legacy `verdict` is compatibility/readiness data, not the consumer safety
owner. `POOR` is never newly emitted; it remains readable in old catalogs as a
quality alias. When typed safety is missing, the existing compatibility owner
preserves BLOCKED/UNSAFE/CAUTION warnings but treats SAFE and POOR as not assessed.
Do not render a green Safe or orange Poor safety banner from those cache labels.

## Scoring Formula Summary

The pipeline's existing v4 scorer assembles the six quality pillars /100 using
`scripts/scoring_v4/config/quality_score.json`. That config owns numerical rules,
floors, caps and tier boundaries; Flutter consumes the public score and tier.

`lib/core/scoring/score_tier.dart::catalogTier` renders the pipeline tier, with its
existing explicitly named fallback only for older cached records. Do not create
another score calculation, grade ladder or quality-to-safety conversion.

Score suppression, assessment completion and catalog safety remain separate
contracts. Their current eligibility behavior lives in
`catalog_product_semantics.dart`; preserve its hard guards and conservative
handling of unknown fields.
