# Flutter Data Contract v1

> Version: 1.2.2 — 2026-04-02
> How the Flutter app reads data from the final DB at each screen level.
> Updated: launch free-tier limits (20/5 signed-in, 10/3 guest), omega-3 scoring/export alignment, interaction_summary, dose_threshold_evaluation, condition/drug_class mapping, direct detail hash resolver, UTC usage reset policy, and stack sync tombstones

App persistence layout for v1:
- `pharmaguide_core.db` — bundled/read-only reference DB from pipeline export
- `user_data.db` — local read/write DB for `product_detail_cache`, `user_profile`,
  `user_scan_history`, `user_stacks_local`, and `user_favorites`

---

## Screen 1: Scan Card

Source: `products_core` (local SQLite, instant)

```dart
class ScanCardData {
  final String dsldId;
  final String productName;
  final String brandName;
  final String? imageUrl;         // May be PDF — use placeholder if not a real image
  final bool imageIsPdf;          // exported convenience flag
  final String? thumbnailKey;     // runtime cache key, not a device path
  final String? detailBlobSha256; // primary hashed detail payload resolver
  final Map<String, dynamic> interactionSummaryHint; // compact banner signal
  final Map<String, String> decisionHighlights;      // positive/caution/trust hero copy

  // Status
  final String productStatus;     // active, discontinued, off_market
  final String? discontinuedDate;
  final String formFactor;
  final String supplementType;

  // Score
  final double? scoreQuality80;
  final String? scoreDisplay80;              // pre-formatted "71.1/80"
  final String? scoreDisplay100Equivalent;   // pre-formatted "88.8/100"
  final double? score100Equivalent;          // derived convenience
  final String? grade;            // Exceptional/Excellent/Good/Fair/...
  final String verdict;           // SAFE/CAUTION/POOR/UNSAFE/BLOCKED/NOT_SCORED
  final String safetyVerdict;

  // Percentile
  final double? percentileTopPct;
  final String? percentileLabel;

  // Display
  final List<Map> badges;         // from JSON column
  final List<String> topWarnings; // from JSON column, max 5
  final List<String> certPrograms;

  // Safety quick flags
  final bool hasBannedSubstance;
  final bool hasRecalledIngredient;  // ingredient-level, NOT product recall
  final bool hasHarmfulAdditives;
  final bool hasAllergenRisks;
  final String? blockingReason;      // e.g. high_risk_ingredient, recalled_ingredient
}
```

**SQL query:**

```sql
SELECT dsld_id, product_name, brand_name, image_url, image_is_pdf, thumbnail_key,
       detail_blob_sha256, interaction_summary_hint, decision_highlights,
       product_status, discontinued_date, form_factor, supplement_type,
       score_quality_80, score_display_80, score_display_100_equivalent,
       score_100_equivalent, grade, verdict, safety_verdict,
       percentile_top_pct, percentile_label,
       badges, top_warnings, cert_programs,
       has_banned_substance, has_recalled_ingredient,
       has_harmful_additives, has_allergen_risks, blocking_reason
FROM products_core
WHERE upc_sku = ?
ORDER BY CASE product_status WHEN 'active' THEN 0 ELSE 1 END,
         score_quality_80 DESC,
         dsld_id
LIMIT 1
```

Note: UPCs are not unique in the export. The app should either use the deterministic
ordering above for the instant scan card, or fetch all matches and offer a chooser
when the barcode resolves to multiple products.

**What the user sees:**

- Product name + brand
- Score circle (score_quality_80 normalized to 100 if no profile, or combined with fit_20 if profile exists)
- Grade word
- Verdict badge (color-coded)
- Top 3-5 warnings
- Certification badges
- Status badge (if discontinued/off-market)

---

## Screen 2: Full Product Page

Source: `products_core` (instant) + `product_detail_cache` (cached or fetched)

### Top section (instant, from products_core):

```dart
class ProductPageHeader {
  // Everything from ScanCardData, plus:
  final double mappedCoverage;

  // Section scores (for radar/bar chart)
  final double scoreIngredientQuality;     // /25
  final double scoreIngredientQualityMax;
  final double scoreSafetyPurity;          // /30
  final double scoreSafetyPurityMax;
  final double scoreEvidenceResearch;      // /20
  final double scoreEvidenceResearchMax;
  final double scoreBrandTrust;            // /5
  final double scoreBrandTrustMax;

  // Percentile detail
  final double? percentileRank;
  final String? percentileCategory;
  final int? percentileCohort;

  // Compliance tags
  final bool isGlutenFree;
  final bool isDairyFree;
  final bool isSoyFree;
  final bool isVegan;
  final bool isVegetarian;
  final bool isOrganic;

  // Quick info
  final bool isProbiotic;
  final bool containsSugar;
  final bool containsSodium;
  final bool diabetesFriendly;       // false when data absent — cautious default
  final bool hypertensionFriendly;   // false when data absent — cautious default
  final bool isTrustedManufacturer;
  final bool hasThirdPartyTesting;
  final bool hasFullDisclosure;
}
```

### Detail section (from detail blob):

```dart
class ProductDetail {
  final List<IngredientDetail> ingredients;
  final List<InactiveIngredient> inactiveIngredients;
  final List<Warning> warnings;
  final List<Map> scoreBonuses;          // @JsonKey(name: 'score_bonuses')
  final List<Map> scorePenalties;        // @JsonKey(name: 'score_penalties')
  final SectionBreakdown sectionBreakdown;
  final ComplianceDetail complianceDetail;
  final CertificationDetail certificationDetail;
  final ProprietaryBlendDetail proprietaryBlendDetail;
  final DietarySensitivityDetail dietarySensitivityDetail;
  final ServingInfo servingInfo;
  final ManufacturerDetail manufacturerDetail;
  final InteractionSummary? interactionSummary; // optional, only when rules matched
  final EvidenceData? evidenceData;
  final RdaUlData? rdaUlData;     // may exist with collectionEnabled == false and a reason
  final FormulationDetail formulationDetail;  // always present
  final ProbioticDetail? probioticDetail;     // optional, probiotic products only
  final SynergyDetail? synergyDetail;         // conditional: present when synergy clusters matched
}
```

```dart
class FormulationDetail {
  final String deliveryTier;                // e.g. "enteric", "liposomal", "standard"
  final String deliveryForm;                // e.g. "softgel", "capsule"
  final bool absorptionEnhancerPaired;      // true if enhancer found
  final List<String> absorptionEnhancers;   // e.g. ["BioPerine"]
  final bool isCertifiedOrganic;
  final String organicVerification;         // e.g. "usda_organic"
  final List<Map> standardizedBotanicals;   // botanical standardization info
  final bool synergyClusterQualified;       // true if synergy bonus earned
  final bool claimNonGmoVerified;           // Non-GMO Project Verified claim
}

class SynergyDetail {
  final bool qualified;                     // true if synergy bonus was applied
  final List<Map> clusters;                 // matched cluster objects with ingredient doses
}
```

**Loading flow:**

```
1. Show header instantly from products_core
2. Check product_detail_cache for dsld_id
3. If cached -> parse JSON -> render detail sections
4. If not cached + online -> read `detail_blob_sha256` from `products_core`, derive the hashed payload path, fetch from Supabase -> save to cache -> render
5. If `detail_blob_sha256` is missing on an older export -> fall back to active `detail_index.json`
5. If not cached + offline -> show header only, "Detail unavailable offline"
```

---

## Screen 3: Ingredient Detail (bottom sheet / detail card)

Source: `product_detail_cache` -> `ingredients[]` or `inactive_ingredients[]`

```dart
class IngredientDetail {
  final String rawSourceText;
  final String name;              // label-facing name
  final String standardName;      // cleaned label standardName
  final String normalizedKey;     // cleaned normalized_key
  final List<Map> forms;          // cleaned forms[] from label parsing
  final double? quantity;
  final String? unit;

  final String standard_name;     // IQM canonical name
  final String? form;             // IQM resolved form
  final String? matched_form;     // selected form match
  final List<Map> matched_forms;  // full multi-form evidence when present
  final List<Map> extracted_forms;// raw extracted form tokens when present
  final int? bio_score;           // 0-14
  final bool? natural;
  final double? score;            // real upstream field, do not rename
  final String notes;             // educational text from IQM form notes
  final String category;
  final bool mapped;
  final List<Map> safety_hits;    // exact upstream safety_hits plus export-derived entries
  final double? normalizedAmount;
  final String? normalizedUnit;

  // Computed fields
  final String role;              // always "active"
  final String parentKey;
  final double? dosage;
  final String? dosageUnit;
  final double? normalizedValue;
  final bool isMapped;

  // Safety flags
  final bool isHarmful;
  final String? harmfulSeverity;  // critical/high/moderate/low
  final String? harmfulNotes;     // mechanism or category
  final bool isBanned;            // exact/alias banned ingredient match
  final bool isAllergen;          // derived from allergen hit matching

  // Identifiers (non-null fields only; from IQM parent entry)
  final Map<String, dynamic>? identifiers; // {cui?, cas?, pubchem_cid?, unii?}
}

class InactiveIngredient {
  final String rawSourceText;
  final String name;
  final String standardName;      // label-facing standardName
  final String normalizedKey;     // @JsonKey(name: 'normalized_key')
  final List<Map> forms;
  final String category;          // from enrichment or other_ingredients.json reference
  final bool isAdditive;          // @JsonKey(name: 'is_additive')
  final String? additiveType;     // @JsonKey(name: 'additive_type')

  // Reference data (from harmful_additives.json or other_ingredients.json)
  final String? referenceStandardName; // @JsonKey(name: 'standard_name')
  final String? severityLevel;    // harmful additive severity (empty if not harmful)
  final String? matchMethod;
  final String? matchedAlias;
  final String notes;             // educational text: harmful_additives notes or other_ingredients notes
  final String? mechanismOfHarm;  // harmful additive mechanism (empty if not harmful)
  final List<String> commonUses;  // from other_ingredients.json, e.g. ["emulsifier", "binder"]
  final List<String> populationWarnings; // at-risk groups from harmful_additives.json

  // Safety flags
  final bool isHarmful;           // @JsonKey(name: 'is_harmful')
  final String? harmfulSeverity;  // @JsonKey(name: 'harmful_severity')
  final String? harmfulNotes;     // @JsonKey(name: 'harmful_notes')

  // Identifiers (non-null fields only; from harmful_additives or other_ingredients)
  final Map<String, dynamic>? identifiers; // {cui?, cas?, pubchem_cid?, unii?}
}
```

**What the user sees when tapping an active ingredient:**

- Ingredient name + form
- Bio score + natural + score explanation
- Dosage with units
- Raw label text so the user sees exactly what was scanned
- Educational notes (the "why this form matters" text from IQM)
- Safety flags if harmful/banned/allergen
- Category tag

**What the user sees when tapping an inactive ingredient:**

- Ingredient name + category
- Additive type badge
- Common uses tags (e.g. "emulsifier", "coating")
- Educational notes (from other_ingredients.json or harmful_additives.json)
- If harmful: severity badge + mechanism of harm + population warnings
- If not harmful: neutral informational display

---

## Screen 4: Warning Detail (expandable / bottom sheet)

Source: `product_detail_cache` -> `warnings[]`

```dart
class Warning {
  final String type;              // banned_substance, recalled_ingredient, watchlist_substance,
                                  // high_risk_ingredient, harmful_additive, allergen,
                                  // interaction, drug_interaction, dietary, status
  final String severity;          // critical, high, moderate, low, info,
                                  // avoid, contraindicated, caution, monitor
  final String title;             // short display title
  final String detail;            // primary explanation text

  // Type-specific fields (nullable, present based on type):

  // banned/recalled/watchlist/high_risk:
  final String? date;                  // regulatory date
  final String? regulatoryDateLabel;   // "First FDA enforcement action"
  final String? clinicalRisk;          // "critical", "high", "moderate", "low"

  // harmful_additive:
  final String? notes;                 // educational context
  final String? mechanismOfHarm;       // biological mechanism
  final List<String>? populationWarnings; // at-risk groups
  final String? category;             // e.g. "colorant_artificial"

  // allergen:
  final String? notes;                 // cross-reactivity info, clinical severity
  final String? supplementContext;     // why this allergen appears in supplements
  final String? prevalence;            // "high", "moderate", "low"

  // interaction / drug_interaction:
  final String? action;                // actionable guidance ("Do not use...")
  final String? evidenceLevel;         // "established", "probable", "theoretical"
  final List<String>? sources;         // DOI/URL citations
  final String? conditionId;           // interaction only: which health condition triggered this
  final String? drugClassId;           // drug_interaction only: which drug class triggered this
  final String? ingredientName;        // both: which ingredient caused the flag
  final Map<String, dynamic>? doseThresholdEvaluation;
      // @JsonKey(name: 'dose_threshold_evaluation')
      // Raw rule evaluation payload:
      // {evaluated, matched_threshold, thresholds_checked, selected_from, selected_severity}

  // warning identifiers are present on banned/high-risk/watchlist/recalled and harmful_additive
  final Map<String, dynamic>? identifiers;

  // all types:
  final String source;                 // provenance: "banned_recalled_ingredients",
                                       // "harmful_additives_db", "allergen_db",
                                       // "interaction_rules", "dietary_sensitivity_data", "dsld"
}
```

**What the user sees when expanding a warning:**

- Title + severity badge (color-coded)
- Detail text (reason for banned, mechanism for harmful, etc.)
- For interactions: actionable guidance + evidence level + citation links
- For allergens: supplement context + prevalence indicator
- For harmful additives: mechanism + population warnings
- Source attribution for credibility

---

## Section F: User Fit Score (computed on-device)

Source: `user_profile` + `reference_data` + `product_detail_cache.ingredients[]`

```dart
class FitScoreResult {
  final double scoreFit20;        // 0-20
  final double scoreCombined100;  // (scoreQuality80 + scoreFit20) * 100 / 100
  final double maxPossible;       // depends on which profile fields are filled

  // Sub-scores
  final double dosageAppropriate; // E1: 0-7
  final double goalMatch;         // E2a: 0-2
  final double ageAppropriate;    // E2b: 0-3
  final double medicalCompat;     // E2c: 0-8

  // Missing profile handling
  final List<String> missingFields; // ["age", "conditions"]
  final String displayText;       // "85/96 (88.5%) - Complete profile for full scoring"
}
```

**This is NEVER stored in the DB or pipeline output.** Always computed fresh on-device
from the user's current profile state.

### E1: Dosage Appropriateness (7 points)

Source: `rda_optimal_uls.json` (bundled in `reference_data` table) + user age/sex.

Compare each nutrient to age/sex-specific RDA and UL:

- Optimal range (50-200% RDA): 7 pts
- Adequate (25-50% RDA): 4 pts
- Low dose (<25% RDA): 2 pts
- Over UL: **-5 pts penalty**

**UL penalty always runs**, even without a complete profile. When no age/sex is set, E1
uses `highest_ul` from `rda_optimal_uls.json` as the fallback UL. The user doesn't get
the full 7 points for dosage range (defaults to 4 pts baseline without age), but they DO
get the -5 penalty if any nutrient exceeds the most conservative adult UL.

**Pipeline B7 vs phone E1 separation:** The pipeline (B7) only penalises products
exceeding 150%+ of highest_ul — those are objectively dangerous. E1 penalises any UL
breach using the user's personal UL or highest_ul fallback. Products between 100-150% of
UL are penalised ONLY by E1 on the phone, not by the pipeline.

### Missing Profile Handling

- No goals set: Score out of 98 (missing 2 pts)
- No age set: Score out of 97 for RDA adequacy (missing 3 pts for age check), BUT E1 still
  applies -5 UL penalty using highest_ul. Dosage range defaults to 4 pts baseline.
- No conditions: User gets full 8 pts (no conditions = no conflicts)
- Empty profile: Score out of ~91. E1 runs with highest_ul defaults (dangerous doses still
  penalised), E2a drops (no goals = missing 2), E2b drops (missing 3), E2c gets full 8.

---

## Barcode Lookup Query

```sql
-- Primary: exact UPC match
SELECT * FROM products_core
WHERE upc_sku = ?
ORDER BY CASE product_status WHEN 'active' THEN 0 ELSE 1 END,
         score_quality_80 DESC,
         dsld_id
LIMIT 1;

-- Fallback: FTS search
SELECT p.* FROM products_core p
JOIN products_fts f ON p.rowid = f.rowid
WHERE products_fts MATCH ?
LIMIT 50;
```

---

## Filter/Search Queries

```sql
-- Vegan products with score > 70, sorted by score
SELECT * FROM products_core
WHERE is_vegan = 1 AND score_quality_80 > 56  -- 56/80 = 70/100
ORDER BY score_quality_80 DESC;

-- Products with allergen risks
SELECT * FROM products_core WHERE has_allergen_risks = 1;

-- Gluten-free multivitamins
SELECT * FROM products_core
WHERE is_gluten_free = 1 AND supplement_type = 'multivitamin';

-- Text search
SELECT p.* FROM products_core p
JOIN products_fts f ON p.rowid = f.rowid
WHERE products_fts MATCH 'omega fish oil'
LIMIT 50;
```

Client behavior:

- debounce text search input by ~300ms to avoid query-per-keystroke load
- execute FTS queries asynchronously (via drift streams/Futures) to prevent UI thread blocking
- never materialize unbounded FTS results into Dart memory (always use `LIMIT 50`)
- use virtualized rendering for result lists
- implement latest-query-wins behavior so an older slower result can never overwrite a newer query in the UI

---

## What the App Does NOT Get from the Pipeline

| Data                  | Where it comes from               |
| --------------------- | --------------------------------- |
| `score_fit_20`        | Computed on-device                |
| `score_combined_100`  | Computed on-device                |
| Price / daily cost    | User enters manually              |
| Offline images        | Runtime cache or placeholder      |
| Product-level recalls | Future: separate FDA data source  |
| Account data          | Supabase Auth + app-local profile |

---

On the phone (always there, works offline)

Reference data lives in `pharmaguide_core.db`. App-created offline/user state
lives in `user_data.db`, which is never replaced during DB updates.

Everything in pharmaguide_core.db — bundled with the app at install or  
 downloaded on first launch:

┌────────────────┬─────────────────────────────────┬─────────────────┐  
 │ What │ Example │ Used for │  
 ├────────────────┼─────────────────────────────────┼─────────────────┤  
 │ Product name, │ "Thorne Basic Nutrients", UPC │ Instant scan │
│ brand, UPC │ 693749101234 │ lookup │  
 ├────────────────┼─────────────────────────────────┼─────────────────┤  
 │ Score + grade │ 71.2/80, "Good", SAFE │ Scan result │
│ + verdict │ │ card │  
 ├────────────────┼─────────────────────────────────┼─────────────────┤
│ Sub-section │ Ingredient: 22/25, Safety: │ 5-pillar card │  
 │ scores │ 28/30, Evidence: 16/20, Brand: │ headers │  
 │ │ 5/5 │ │
├────────────────┼─────────────────────────────────┼─────────────────┤  
 │ Safety flags │ has_banned=0, has_allergen=1, │ Warning dots, │
│ │ has_harmful_additive=0 │ verdict │  
 ├────────────────┼─────────────────────────────────┼─────────────────┤
│ Dietary │ is_vegan=1, is_gluten_free=1, │ Filter chips │  
 │ attributes │ diabetes_friendly=0 │ │  
 ├────────────────┼─────────────────────────────────┼─────────────────┤
│ Percentile │ Top 12% in Multivitamins │ Percentile │  
 │ ranking │ │ badge │  
 ├────────────────┼─────────────────────────────────┼─────────────────┤
│ Product status │ active / discontinued │ Status badge │  
 ├────────────────┼─────────────────────────────────┼─────────────────┤
│ Full-text │ products_fts table │ Search bar │  
 │ search index │ │ instant results │
├────────────────┼─────────────────────────────────┼─────────────────┤  
 │ Reference data │ RDA/UL values, interaction │ On-device │
│ (~313KB) │ rules, risk taxonomy, goal │ FitScore │
│ │ clusters │ calculation │  
 ├────────────────┼─────────────────────────────────┼─────────────────┤
│ Export │ local version + remote checksum │ "Do I need to │
│ manifest │ │ update?" check │  
 └────────────────┴─────────────────────────────────┴─────────────────┘

This is 65 columns across the full `products_core` export (~180K products, roughly tens of MB on-device depending on release). Instant at runtime once bundled/installed. No internet needed.

Fetched from Supabase (on-demand, cached after first view)

The detail blob — one JSON per product, fetched when the user taps into  
 the full result screen:

┌────────────────────┬──────────────────────────┬────────────────────┐
│ What │ Example │ Used for │
├────────────────────┼──────────────────────────┼────────────────────┤
│ Active ingredients │ Vitamin D3, 2000 IU, │ │
│ list │ bio_score: 14, "Premium │ Card 1 accordion │
│ │ Form" │ │  
 ├────────────────────┼──────────────────────────┼────────────────────┤
│ Inactive │ Cellulose, Magnesium │ │  
 │ ingredients │ Stearate, is_harmful: │ Card 2 accordion │
│ │ false │ │  
 ├────────────────────┼──────────────────────────┼────────────────────┤  
 │ Harmful additive │ mechanism_of_harm, │ │
│ detail │ population_warnings, │ Card 2 red rows │  
 │ │ notes │ │  
 ├────────────────────┼──────────────────────────┼────────────────────┤
│ Interaction │ severity, action, │ │  
 │ warnings │ evidence_level, dose │ Card 3 accordion │  
 │ │ threshold │ │
├────────────────────┼──────────────────────────┼────────────────────┤  
 │ Condition/drug │ interaction_summary: │ Orange alert │  
 │ flags │ pregnancy → │ banner │
│ │ contraindicated │ │  
 ├────────────────────┼──────────────────────────┼────────────────────┤  
 │ Clinical evidence │ RCT badges, study │ Card 3 study links │
│ matches │ descriptions │ │  
 ├────────────────────┼──────────────────────────┼────────────────────┤
│ Score │ "Synergy Bonus: Calcium │ Pros & │
│ bonuses/penalties │ + D3 (+2.0)" │ Considerations │
├────────────────────┼──────────────────────────┼────────────────────┤
│ Manufacturer │ trusted, │ │  
 │ detail │ third_party_tested, │ Card 4 rows │
│ │ region │ │  
 ├────────────────────┼──────────────────────────┼────────────────────┤  
 │ Probiotic detail │ CFU count, strain list │ Card 1 probiotic │
│ │ │ badge │  
 ├────────────────────┼──────────────────────────┼────────────────────┤  
 │ │ CUI, CAS, PubChem, UNII │ Data integrity │
│ Identifiers │ per ingredient + on │ (not shown to │
│ │ banned/harmful warnings │ users in MVP) │
└────────────────────┴──────────────────────────┴────────────────────┘

This is ~2-10KB per product. Fetched once, cached locally in  
 `user_data.db.product_detail_cache`.

Also from Supabase (user account stuff)

┌───────────────────────┬─────────────────┬─────────────────────────┐  
 │ What │ Direction │ Used for │
├───────────────────────┼─────────────────┼─────────────────────────┤  
 │ Auth │ App → Supabase │ Sign in/sign up │
│ (Google/Apple/Email) │ │ │
├───────────────────────┼─────────────────┼─────────────────────────┤  
 │ │ │ Supplement stack │
│ user_stacks │ App ↔ Supabase │ (synced for │
│ │ │ multi-device) │
│ │ │ Last-write-wins with │
│ │ │ tombstones (`deleted_at`) │
│ │ │ and `client_updated_at` │
│ │ │ as the conflict clock │
│ │ │ for MVP │
 ├───────────────────────┼─────────────────┼─────────────────────────┤
│ user_usage │ App ↔ Supabase │ Scan/AI limits (20 │
│ │ │ scans/day, 5 AI/day) │
│ │ │ reset on UTC day │
│ │ │ boundaries │
├───────────────────────┼─────────────────┼─────────────────────────┤  
 │ pending_products │ App → Supabase │ "Product not found" │  
 │ │ │ submissions with │
 │ │ │ normalized UPC dedupe │
├───────────────────────┼─────────────────┼─────────────────────────┤  
 │ │ App → Edge │ │  
 │ AI Pharmacist │ Function → │ Chat responses │
│ │ Gemini │ │  
 └───────────────────────┴─────────────────┴─────────────────────────┘

Never leaves the phone

┌────────────────────────────────────┬───────────────────────────────┐  
 │ What │ Stored in │
├────────────────────────────────────┼───────────────────────────────┤
│ Health profile (conditions, meds, │ Local SQLite user_profile │
│ goals, allergies) │ │
├────────────────────────────────────┼───────────────────────────────┤  
 │ score_fit_20 (personal match │ Computed fresh each time, │
│ score) │ never stored │  
 ├────────────────────────────────────┼───────────────────────────────┤
│ Guest scan / AI counters │ Hive local KV │
├────────────────────────────────────┼───────────────────────────────┤  
 │ Chat history │ Hive local KV │
├────────────────────────────────────┼───────────────────────────────┤  
 │ Scan history │ Local SQLite │
│ │ user_scan_history │  
 └────────────────────────────────────┴───────────────────────────────┘

## Implementation Notes for Flutter Developers

### 1. Mixed naming conventions in ingredient JSON

The detail blob uses **both** camelCase and snake_case on the same ingredient object.
This is intentional — they come from different pipeline stages:

- `standardName` — from label parsing (camelCase, label provenance)
- `standard_name` — from IQM quality mapping (snake_case, scoring provenance)
- `bio_score`, `matched_form`, `extracted_forms` — IQM fields (snake_case)
- `normalizedKey`, `rawSourceText` — label fields (varies)

**Do NOT normalize these.** Use explicit `@JsonKey` annotations:

```dart
@JsonKey(name: 'standardName')
final String standardName;     // label-parsed canonical

@JsonKey(name: 'standard_name')
final String standardNameIqm;  // IQM-resolved canonical
```

### 2. Warnings are polymorphic

The `type` field determines which optional fields are populated.
Do not use one flat model — use a sealed class or discriminated union:

```dart
sealed class Warning {
  String get type;
  String get severity;
  String get title;
  String get detail;
  String get source;
}

class BannedSubstanceWarning extends Warning { ... }
class HarmfulAdditiveWarning extends Warning { ... }
class AllergenWarning extends Warning { ... }
class InteractionWarning extends Warning { ... }
// etc.
```

Or use a single `Warning` class with nullable type-specific fields.
Either way, the parsing must check `type` before accessing fields like
`action`, `populationWarnings`, or `supplementContext`.

### 3. score_quality_80 can be NULL

Products with `verdict == "NOT_SCORED"` have `score_quality_80 = NULL`,
`grade = NULL`, `score_display_80 = NULL`, etc. Every score display path
needs a null guard. Show "Not Scored" or equivalent — never show 0.

### 4. image_url may be a PDF link

Many DSLD products have label PDF URLs, not actual image URLs.
Explicitly check for a `.pdf` extension _before_ passing to the image cache to prevent internal crashes. Show a placeholder image instead.
The `thumbnail_key` field is NULL at export — the app populates it
at runtime when it caches a real image.

### 5. reference_data is TEXT JSON — parse once at startup

The `reference_data` table stores large JSON blobs (up to ~200KB each).
Parse these once at app startup and hold the parsed objects in memory.
Do not re-parse on every product view or fit score calculation.

```dart
// At app startup:
final rdaData = jsonDecode(db.query('reference_data', where: 'key = ?', whereArgs: ['rda_optimal_uls']).first['data']);
// Cache rdaData in a singleton/provider — reuse for all fit score calculations.
```

### 6. diabetes_friendly / hypertension_friendly default to false

When dietary sensitivity data is absent or incomplete, these fields
default to `0` (false). This is the cautious/safe default for a medical app.
Do NOT interpret `false` as "confirmed not friendly" — it means
"insufficient data to confirm friendly." The UI should distinguish between
"not friendly" (explicit data) and "unknown" (data absent) if needed
by checking whether `dietary_sensitivity_detail` is populated in the
detail blob.

### 7. UPC collisions

Multiple products can share the same `upc_sku` (1:N relationship). The barcode scan query
uses deterministic ordering (active first, highest score, lowest dsld_id)
to pick one, but consider showing a chooser when `COUNT(*) > 1` for a UPC and the top two scores differ by less than 5 points.

### 8. User condition ID mapping

The app profile Health Concerns chips must map to the exact `condition_id` values
used in the pipeline taxonomy. This table is the single source of truth:

| App UI Chip              | `condition_id`       | Category       | Notes                                                 |
| ------------------------ | -------------------- | -------------- | ----------------------------------------------------- |
| Pregnancy                | `pregnancy`          | reproductive   | Teratogenicity, retinoid exposure, uterine stimulants |
| Lactation/Breastfeeding  | `lactation`          | reproductive   | Transfer via breast milk, infant safety               |
| Trying to Conceive (TTC) | `ttc`                | reproductive   | Fertility impact — clinically distinct from pregnancy |
| Hypertension             | `hypertension`       | cardiovascular | BP elevation, sympathomimetics                        |
| Heart Disease            | `heart_disease`      | cardiovascular | Cardiac risk, QT prolongation                         |
| Diabetes/Blood Sugar     | `diabetes`           | metabolic      | Covers type 1 and type 2 (merged)                     |
| High Cholesterol         | `high_cholesterol`   | cardiovascular | Statin interactions, liver load                       |
| Liver Disease            | `liver_disease`      | hepatic        | Hepatotoxicity, metabolism impairment                 |
| Kidney Disease           | `kidney_disease`     | renal          | Accumulation risk, electrolyte imbalance              |
| Thyroid Condition        | `thyroid_disorder`   | endocrine      | Absorption interference, iodine sensitivity           |
| Autoimmune               | `autoimmune`         | immunologic    | Immune stimulation contraindications                  |
| Epilepsy/Seizures        | `seizure_disorder`   | neurologic     | Seizure threshold lowering                            |
| Bleeding Disorders       | `bleeding_disorders` | hematologic    | Anticoagulant potentiation                            |
| Upcoming Surgery         | `surgery_scheduled`  | perioperative  | Bleeding risk, anesthesia interactions                |

Drug class chips (from user's medication list):

| App UI Chip          | `drug_class_id`       | Notes                             |
| -------------------- | --------------------- | --------------------------------- |
| Blood Thinners       | `anticoagulants`      | Warfarin, heparin, DOACs          |
| Antiplatelet Agents  | `antiplatelets`       | Aspirin, clopidogrel              |
| NSAIDs               | `nsaids`              | Ibuprofen, naproxen               |
| Blood Pressure Meds  | `antihypertensives`   | ACE inhibitors, ARBs, CCBs        |
| Diabetes Medications | `hypoglycemics`       | Metformin, insulin, sulfonylureas |
| Thyroid Medications  | `thyroid_medications` | Levothyroxine                     |
| Sedatives/Sleep Aids | `sedatives`           | Benzodiazepines, Z-drugs          |
| Immunosuppressants   | `immunosuppressants`  | Cyclosporine, tacrolimus          |
| Statins/Cholesterol  | `statins`             | Atorvastatin, simvastatin         |

**TTC vs Pregnancy vs Lactation**: These are three separate conditions because
the clinical risks differ. Pregnancy warnings are about teratogenicity (birth defects).
TTC warnings are about fertility impact (e.g., high-dose vitamin A reducing
fertility). Lactation warnings are about transfer through breast milk. The user
can select one or more. The app should match against all selected conditions.

Implementation recommendation: load `clinical_risk_taxonomy` once at startup via
a dedicated `TaxonomyService`/provider and validate the app-side chip mappings
in debug builds. Fail fast if the app IDs drift from the pipeline taxonomy.

### 9. Instant condition flagging on scan

When a user scans a product, use `interaction_summary` from the detail blob
for instant flagging — do NOT re-compute from warnings:

```dart
// Instant check from detail blob
final summary = blob['interaction_summary'];
if (summary != null) {
  final userConditions = userProfile.conditions; // {'pregnancy', 'diabetes'}
  final flagged = userConditions.intersection(
    summary['condition_summary'].keys.toSet()
  );

  for (final condition in flagged) {
    final info = summary['condition_summary'][condition];
    // info.highest_severity = "contraindicated"
    // info.ingredients = ["Vitamin A Palmitate"]
    // info.actions = ["Do not use preformed Vitamin A..."]
    showConditionAlert(condition, info);
  }
}
```

For detailed per-warning view with dose thresholds, filter the `warnings` array
by `condition_id` matching the user's conditions.

### 10. Supabase Storage path structure

The Flutter app fetches the core DB and hashed detail blob payloads from
Supabase Storage. `detail_index.json` remains a compatibility/audit artifact and
fallback resolver for older exports.
The version is determined by querying the `export_manifest` table for the row
where `is_current = true`, then reading its `db_version` column.

```
DB file:
  {SUPABASE_URL}/storage/v1/object/public/pharmaguide/v{version}/pharmaguide_core.db

Detail blob payload:
  {SUPABASE_URL}/storage/v1/object/public/pharmaguide/shared/details/sha256/{blob_sha256[0:2]}/{blob_sha256}.json
```

These are public bucket paths — readable with the anon key, no auth required.
The app should cache the DB file locally and only re-download when the manifest
version changes (compare against locally stored version).
`min_app_version` is a hard client gate. If the remote manifest requires a newer
app build, the client must force an app-store update before attempting to parse
or promote the new DB release.
DB update flow must be staged and verified:

- download to a staging path
- verify checksum using remote `export_manifest.json`
- perform a minimal SQLite open/readability check
- atomically swap in only after verification passes
- keep the previous DB on any failure
  The app should prefer `products_core.detail_blob_sha256` at runtime and only
  fall back to the active `detail_index.json` if the hash is absent.
  `product_detail_cache` requires explicit cache policy:
- release-version-aware invalidation
- bounded size
- LRU eviction
- O(1) lookup by `dsld_id`

### 11. `increment_usage` RPC

Flutter calls this RPC after each successful scan or AI message to enforce
server-side usage limits. It handles day rollover automatically using UTC day
boundaries (`reset_day_utc`).

```dart
// After a successful scan:
final result = await supabase.rpc('increment_usage', params: {
  'p_user_id': supabase.auth.currentUser!.id,
  'p_type': 'scan',  // or 'ai_message'
}) as Map<String, dynamic>;
// result = {scans_today: 3, ai_messages_today: 1, limit_exceeded: false, reset_day_utc: '2026-04-02'}
```

**Limits:** 20 scans/day, 5 AI messages/day for signed-in free users.
Guest policy is app-side: 10 lifetime scans, 3 AI messages/day.
**Return value:** `{scans_today, ai_messages_today, limit_exceeded, reset_day_utc}`.
When `limit_exceeded` is `true`, the app should show a paywall or "try again
tomorrow" message. The RPC is `SECURITY DEFINER`, validates that the caller
owns the `p_user_id`, and returns the existing counters without incrementing
when the limit has already been reached.

### 12. Identifiers on warning entries

The `identifiers` object (containing CUI, CAS, PubChem CID, UNII) appears on
**warning entries** as well as ingredient entries. Specifically:

- `banned_substance` / `recalled_ingredient` / `watchlist_substance` / `high_risk_ingredient` warnings
- `harmful_additive` warnings

This allows the app to cross-reference warnings against external databases
without a separate lookup. The identifiers come from the same reference data
that generated the warning. Allergen and interaction warnings do NOT carry
identifiers.
