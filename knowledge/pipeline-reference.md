# Pipeline Reference

> Quick reference for the data pipeline output consumed by the Flutter app.  
> Source: `dsld_clean` repo, `FINAL_EXPORT_SCHEMA_V1.md`, `SCORING_ENGINE_SPEC.md`

---

## Key Pipeline Data Files (scripts/data/)

| File | Entries | Purpose | Scoring Role |
|------|---------|---------|--------------|
| `ingredient_quality_map.json` | 563 parents | Quality scoring for known ingredients | **Bonus** (Section A: Ingredient Quality, max 25) |
| `banned_recalled_ingredients.json` | 143 | Regulatory safety disqualifications | **Penalty/Gate** (B0 hard-stop, BLOCKED verdict) |
| `harmful_additives.json` | 115 | Harmful additive identification | **Penalty** (Section B: Safety & Purity) |
| `backed_clinical_studies.json` | 197 (all PMID-backed) | Clinical evidence for bonus points | **Bonus** (Section C: Evidence & Research, max 20) |
| `allergens.json` | Big 8 types | Allergen classification | **Flag** (profile-driven alerts) |
| `rda_optimal_uls.json` | -- | Dosing adequacy benchmarks (RDA, AI, UL) | **Penalty** (B7: 150%+ UL triggers dose warning) |
| `manufacturer_violations.json` | -- | Brand trust penalties | **Penalty** (Section D: Brand Trust, max 5) |
| `synergy_cluster.json` | -- | Ingredient synergy groupings | **Bonus** (Section A sub-score) |

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

### Scores
| Column | Type | Range | Notes |
|--------|------|-------|-------|
| `score_quality_80` | REAL | 0-80 | Canonical pipeline score. NULL = not scored |
| `score_display_80` | TEXT | -- | Pre-formatted: "71.1/80" |
| `score_display_100_equivalent` | TEXT | -- | Pre-formatted: "88.8/100" |
| `score_100_equivalent` | REAL | 0-100 | Display convenience |
| `grade` | TEXT | -- | Exceptional / Excellent / Good / Fair / Below Avg / Low / Very Poor |
| `verdict` | TEXT | -- | SAFE / CAUTION / POOR / UNSAFE / BLOCKED / NOT_SCORED |

### Section Scores
| Column | Max | Section |
|--------|-----|---------|
| `score_ingredient_quality` | 25 | A: Ingredient Quality |
| `score_safety_purity` | 30 | B: Safety & Purity |
| `score_evidence_research` | 20 | C: Evidence & Research |
| `score_brand_trust` | 5 | D: Brand Trust |

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

## Verdict Precedence (Deterministic)

```
BLOCKED > UNSAFE > MODERATE > REVIEW > RECOMMENDED
```

App maps these to display verdicts:
- `BLOCKED` -> Red hard-stop screen (B0 gate)
- `UNSAFE` -> Red verdict banner
- `POOR` -> Orange verdict banner
- `CAUTION` -> Amber verdict banner
- `SAFE` -> Green verdict banner
- `NOT_SCORED` -> Gray, no score ring, explanation text

---

## Scoring Formula Summary

```
Total = A + B + C + D + violation_penalty
       (25) (30) (20) (5)

Clamped to [0, 80]
score_100 = (score_80 / 80) * 100
```

Grade scale (applied to score_100_equivalent):
- >= 90: Exceptional
- >= 80: Excellent
- >= 70: Good
- >= 60: Fair
- >= 50: Below Avg
- >= 32: Low
- < 32: Very Poor

No grade assigned for BLOCKED, UNSAFE, or NOT_SCORED.
