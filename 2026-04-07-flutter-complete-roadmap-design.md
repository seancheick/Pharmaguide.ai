# PharmaGuide Flutter App — Complete Development Roadmap v2.0

> **Version:** 2.0 — 2026-04-07
> **Backend:** Export Schema v1.3.0 (88 columns) | Scoring v3.4.0 | Enrichment v5.1.0
> **Scope:** V1.0 through V3.1 — 31 sprints (0-30) across 7 releases
> **Repos:** Pipeline (`dsld_clean`) + Flutter app (new repo) connected via Supabase
> **Interaction Data:** 100+ pipeline rules (all 14 conditions, 9+ drug classes) + Flutter-side interaction DB (Supp.ai-validated)

---

## Development Philosophy

1. **Offline-First:** SQLite cache on device, Supabase hydration on cache miss, graceful degradation
2. **Privacy-First:** User health data never leaves device. FitScore and stack scoring computed locally
3. **Safety-First:** Deterministic scoring, no ML guessing. Interaction warnings before any stack addition
4. **Transparency-First:** Every score point explained, every warning sourced with PMIDs
5. **Accuracy-First:** Medical-grade product. No bulk assumptions. Verify before shipping

### Two-Repo Architecture

```
Pipeline Repo (dsld_clean)              Flutter Repo (new)
========================               =================
Clean -> Enrich -> Score               User-facing mobile app
         |                                      |
         v                                      v
pharmaguide_core.db  ----Supabase---->  Local SQLite cache
detail_blobs/        ----Supabase---->  product_detail_cache
                                        user_data.db (profile, stack, favorites)
                                        interactions_db (drug-specific pairs)
```

### Two-Database Phone Architecture

- `pharmaguide_core.db` — Read-only, bundled/OTA-updated from pipeline via Supabase
- `user_data.db` — Read/write, user-created data (profile, stack, favorites, scan history, detail cache)

OTA swaps never overwrite user data. Separate databases guarantee this.

### Interaction Data: Two Layers

| Layer | Location | Scope | Example |
|-------|----------|-------|---------|
| Pipeline rules | `pharmaguide_core.db` via `interaction_summary` | Supplement ingredient -> drug class + condition | "Ginkgo interacts with anticoagulants class" |
| Flutter interaction DB | `user_data.db` or bundled JSON | Specific drug -> specific supplement (and sup-sup, med-med) | "Warfarin + Ginkgo = Moderate, bleeding risk" |

Pipeline layer powers product-level warnings and E2c scoring. Flutter layer powers real-time stack safety checking when users have specific medications.

---

## Severity Standardization (System-Wide)

All interaction severities use this enum everywhere — pipeline, Flutter, AI chat, stack checker:

| Severity | UI | Color | E2c Penalty | Stack Penalty |
|----------|-----|-------|-------------|---------------|
| `contraindicated` | BLOCK — Do Not Use | Red | -8 (disqualified) | -15 to -20 |
| `avoid` | AVOID | Red | -5 | -10 to -15 |
| `caution` | CAUTION | Orange | -3 | -5 to -10 |
| `monitor` | MONITOR | Yellow | -1 | -2 to -5 |
| `safe` | SAFE | Green | 0 | 0 |

Evidence levels (from pipeline, carried through to UI):

| Level | Label | Meaning |
|-------|-------|---------|
| `established` | Strong Evidence | Multiple clinical studies |
| `probable` | Good Evidence | Limited clinical + pharmacological basis |
| `theoretical` | Theoretical | Mechanism-based, limited human data |

---

## Unified Interaction Result Model

Every interaction warning — whether from pipeline, stack checker, or AI chat — uses this structure:

```dart
class InteractionResult {
  final String id;
  final String type;           // drug_supplement, supplement_supplement, drug_drug, condition_supplement
  final String severity;       // contraindicated, avoid, caution, monitor
  final String evidenceLevel;  // established, probable, theoretical
  final String agent1Name;
  final String agent2Name;
  final String mechanism;
  final String management;     // actionable guidance
  final bool doseDependant;
  final String? doseThreshold; // e.g. ">3g" for fish oil
  final List<String> sourceUrls;
  final String source;         // pipeline, stack_engine, ai_chat
}
```

One format everywhere. Product detail, stack checker, and AI chat all render this same object.

---

## "Don't Build" Guardrails

| Feature | Why Skip |
|---------|----------|
| AI-generated stack recommendations | Liability risk. Our advantage is deterministic scoring |
| Macro/nutrition tracking | Cronometer and MacroFactor own this. Different product |
| Cycling protocols / "off days" | Niche biohacker feature, not mass market |
| Social stack sharing (community forums) | Community features are hard. Ship utility first |
| Free-text medication entry without normalization | NEVER store unvalidated medication names |

---

## VERSION RELEASES

---

## V1.0 — Core Product

**Identity:** "Scan, score, understand, and stack supplements safely"

**Ship gate:** 180K products searchable, FitScore working, stack safety checker working, all 14 conditions + all drug classes firing warnings, barcode scanning functional.

---

### Sprint 0: Foundation + Profile Setup (Week 1-2)

#### 0.1 Project Setup

- Flutter project initialization (latest stable)
- Folder structure: `lib/` (features, core, data, services), `assets/`, `test/`
- State management setup (Riverpod or Bloc — dev's choice)
- Dependency injection
- Navigation framework (GoRouter)
- Theme system with severity color tokens

#### 0.2 Welcome / Onboarding (Skip-able)

- App benefits overview (3 slides max)
- Privacy statement: "Your health information stays on your device"
- "Get Started" CTA

#### 0.3 Profile Setup Flow

**Step 1: Basic Info** (Required for FitScore)
- Nickname (optional, text input)
- Age Bracket (required, dropdown)
  - Values: `"14-18"`, `"19-30"`, `"31-50"`, `"51-70"`, `"71+"`
  - Source: `rda_optimal_uls.json` -> `_metadata.age_brackets`
- Sex (required, radio buttons)
  - Values: `Male`, `Female`, `Other`, `Prefer not to say`
  - Fallback: Other/Prefer not to say -> use highest UL for all nutrients

**Step 2: Health Goals** (Optional, max 2)
- 18 goals from `user_goals_to_clusters.json`
- UI: Modal with multi-select chips, sorted by `goal_priority` (high -> medium -> low)
- Enforce max 2 selections
- Detect conflicting goals from `conflicting_goals` field, show warning
- Benefit text: "Powers smart interaction warnings and personalized AI insights"

**Step 3: Health Profile** (Optional, critical for safety)

**Section A: Health Concerns** (14 conditions from `clinical_risk_taxonomy.json`)
- Sort by `display_priority` (pregnancy, lactation, TTC first)
- Max recommended: 5-7 selections
- Benefit text: "Ensures safe recommendations based on your conditions"

**Section B: Medications You Take** (9+ drug classes from `clinical_risk_taxonomy.json`)
- Presented as simple yes/no checklist, NOT medication names
- Labels use user-friendly names:
  - "Blood thinners" (anticoagulants)
  - "Antiplatelet medication" (antiplatelets)
  - "NSAIDs (Ibuprofen, Aspirin regularly)" (nsaids)
  - "Blood pressure medication" (antihypertensives)
  - "Diabetes medication" (hypoglycemics)
  - "Thyroid medication" (thyroid_medications)
  - "Sedatives / Sleep medication" (sedatives)
  - "Immunosuppressants" (immunosuppressants)
  - "Statins / Cholesterol medication" (statins)
  - Additional classes as pipeline expands (SSRIs, MAOIs, etc.)
- Quick-select helpers (e.g., "Taking BP meds?" if hypertension selected)
- Note: "In a future update, you'll be able to add specific medications for more precise warnings"

**Step 4: Allergies** (Optional)
- 17 allergens from `allergens.json` (food/supplement allergens ONLY)
- NO medication allergies (Penicillin, Sulfa, NSAIDs removed)
- Sort by prevalence (high -> moderate -> low)

**Step 5: Review & Save**
- Profile completeness score (0-100%)
- "Save & Continue" button
- "Skip for now" option (minimum: age + sex required for FitScore)

**Profile Data Model:**

```dart
class UserProfile {
  String? nickname;
  String? ageBracket;       // "14-18", "19-30", "31-50", "51-70", "71+"
  String? sex;              // "Male", "Female", "Other", "Prefer not to say"
  List<String> goals;       // max 2, e.g. ["GOAL_SLEEP_QUALITY", "GOAL_REDUCE_STRESS_ANXIETY"]
  List<String> conditions;  // e.g. ["pregnancy", "diabetes"]
  List<String> drugClasses; // e.g. ["anticoagulants", "statins"] — from checklist, replaced by stack in V1.1
  List<String> allergens;   // e.g. ["ALLERGEN_SOY", "ALLERGEN_MILK"]
  DateTime createdAt;
  DateTime lastUpdated;
}
```

**Profile Completeness Scoring:**

```
Required (40%):
  Age bracket: 20%
  Sex: 20%

Optional (60%):
  Goals: 20%
  Conditions + Drug classes: 20%
  Allergies: 10%
  Nickname: 10%

Thresholds:
  0-39%: Incomplete
  40-59%: Basic
  60-79%: Good
  80-100%: Complete
```

---

### Sprint 1: Database + Core Services (Week 3-4)

#### 1.1 Local Database Setup

- SQLite initialization via Drift (Flutter SQLite ORM)
- Two database files:
  - `pharmaguide_core.db` (read-only, ~105MB, ~180K products)
  - `user_data.db` (read-write, user state)

**`pharmaguide_core.db` tables** (from pipeline):
- `products_core` — 88 columns, one row per product
- `products_fts` — FTS5 full-text search index
- `reference_data` — bundled JSON files for offline scoring
- `export_manifest` — version metadata

**`user_data.db` tables** (app-created):
- `user_profile` — profile data
- `user_stacks_local` — supplement stack (V1.0: supplements only)
- `user_favorites` — bookmarked products
- `user_scan_history` — recent scans
- `product_detail_cache` — cached detail blobs

#### 1.2 Supabase Integration

- Connection setup (anon key + service role)
- OTA update check: compare `export_manifest.json` checksums
- Download `pharmaguide_core.db` on first launch
- Download detail blobs on-demand (cache after first view)
- Auth: Google/Apple/Email sign-in

#### 1.3 Reference Data Bundler

Bundle 4 JSON files into `reference_data` table (~313KB total):
1. `rda_optimal_uls.json` (199KB) — E1, E2b
2. `user_goals_to_clusters.json` (11KB) — E2a
3. `clinical_risk_taxonomy.json` (5KB) — UI labels, E2c
4. `interaction_rules.json` (75KB) — Reference only in V1.0
5. `timing_rules.json` (~25KB) — Timing conflict data (new)

#### 1.4 Core Services

```dart
DatabaseService       // SQLite operations (Drift)
ProfileService        // CRUD for user profile
SyncService           // Supabase sync + OTA updates
ReferenceDataService  // Load bundled JSON
```

---

### Sprint 2: Product Catalog + Search (Week 5-6)

#### 2.1 Home Screen

- Search bar (debounced, 300ms)
- Profile completeness widget (if < 60%)
- Quick category filters: Omega-3, Probiotics, Adaptogens, Multivitamin, Collagen, Nootropics
  - Uses v1.3.0 indexed fields: `contains_omega3`, `contains_probiotics`, etc.
- "My Stack" preview (3 products max, "View All" CTA)

#### 2.2 Search + Filter

- Full-text search (FTS5 on `products_fts`)
- Category filters using v1.3.0 fields:
  - `primary_category`, `secondary_categories`
  - `contains_omega3`, `contains_probiotics`, `contains_collagen`, `contains_adaptogens`, `contains_nootropics`
  - `key_ingredient_tags`
- Dietary filters: `is_vegan`, `is_gluten_free`, `is_organic`, `diabetes_friendly`, `hypertension_friendly`
- Sort options: Quality score, Alphabetical, Percentile rank
- Performance: all filtering from `products_core` (no detail blob fetch needed)
- Virtualized list rendering, LIMIT 50 on FTS, latest-query-wins

#### 2.3 Product Card (Scan Results)

- Product name + brand
- Quality score (80-point, color-coded) OR 100-equivalent
- Verdict badge (RECOMMENDED / REVIEW / MODERATE / UNSAFE / BLOCKED)
- Goal match badge (if profile complete) — from v1.3.0 `goal_matches`
- Allergen warning (if matches user allergies) — from v1.3.0 `allergen_summary`
- "Add to Stack" button

#### 2.4 Barcode Scanning

- Camera-based barcode scanner (UPC/EAN)
- Lookup: `products_core WHERE upc_sku = ?`
- Handle multiple matches (same UPC, different products): show chooser
- Handle no match: "Product not found — try searching by name"

---

### Sprint 3: Product Detail + Score Transparency (Week 7-8)

#### 3.1 Detail View — Instant Header (from `products_core`)

- Product name, brand, form factor, supplement type
- Score circle with quality score + grade
- Verdict badge (color-coded)
- Section score breakdown (A/B/C/D bars):
  - Ingredient Quality: `score_ingredient_quality` / 25
  - Safety & Purity: `score_safety_purity` / 30
  - Evidence & Research: `score_evidence_research` / 20
  - Brand Trust: `score_brand_trust` / 5
- Percentile ranking: "Top 12% in Multivitamins"
- Dietary tags: vegan, gluten-free, organic, etc.

#### 3.2 Detail View — Full Detail (from detail blob, fetched/cached)

- Active ingredients list with per-ingredient:
  - Name, form, dosage, bio_score
  - Educational notes (from IQM form notes)
  - Safety flags (harmful, banned, allergen)
  - Identifiers (CUI, CAS, PubChem — not shown to users in MVP)
- Inactive ingredients with:
  - Additive type, common uses, harmful severity if applicable
  - Mechanism of harm + population warnings for harmful additives
- Score bonuses and penalties (transparent: "Synergy Bonus: Calcium + D3 (+2.0)")
- Clinical evidence matches with PMID links (clickable)
- Evidence tier badges
- Manufacturer detail (trusted, third-party tested)
- Synergy detail from v1.3.0 `synergy_detail`

#### 3.3 Interaction Warnings (from detail blob `interaction_summary`)

- Display `condition_summary` matches against user profile conditions
- Display `drug_class_summary` matches against user profile drug classes
- Each warning shows:
  - Severity badge (color-coded using standardized enum)
  - Evidence level badge (established / probable / theoretical)
  - Mechanism text
  - Actionable management guidance
  - Clickable source URLs (PMID links)
- Warnings sorted by severity (contraindicated first)

#### 3.4 Proprietary Blend Warning

- If product has proprietary blends (from `formulation_detail`):
  - Show banner: "This product contains proprietary blends — ingredient amounts are hidden. Our analysis is limited."
  - Explain B5 penalty impact on score

#### 3.5 Unknown Ingredient Handling

- If `mapped_coverage` < 0.5:
  - Show warning: "This product contains ingredients we cannot fully verify. Score may not reflect complete safety profile."
- If `mapped_coverage` < 0.3:
  - Strengthen warning: "Limited data available for this product. Use with caution and consult your healthcare provider."
- Never display "safe" when data is incomplete

#### 3.6 FitScore Section (from on-device calculation, Sprint 4)

- Personal FitScore (E1 + E2a + E2b + E2c = 0-20 pts)
- Combined score: (quality_80 + fit_20) * 100 / 100
- Missing profile fields indicator: "Complete your profile for full scoring"

#### 3.7 Actions

- "Add to Stack" (triggers stack safety check, Sprint 5)
- "Share" — uses v1.3.0 pre-computed `share_title`, `share_description`, `share_highlights`
- "Save to Favorites"

---

### Sprint 4: FitScore Engine (Week 9-10)

**CRITICAL:** This is the ONLY on-device scoring. Everything else is pre-computed by pipeline.

#### 4.1 E1: Dosage Appropriateness (7 pts)

```dart
class E1Calculator {
  // Load rda_optimal_uls.json from reference_data
  // For each nutrient in product:
  //   1. Get age/sex-specific RDA and UL
  //   2. Calculate percent of RDA
  //   3. Score:
  //      - UL exceeded: -5 pts (ALWAYS runs, even without profile)
  //      - 50-200% of RDA: +7/n pts
  //      - 25-50% of RDA: +4/n pts
  //      - < 25% of RDA: +2/n pts
  //   4. No age/sex? Use highest_ul fallback, baseline 4 pts
  // Clamp to [-5, 7]
}
```

#### 4.2 E2a: Goal Alignment (2 pts)

```dart
class E2aCalculator {
  // Load user_goals_to_clusters.json
  // Match product's synergy clusters against user's goals
  // Apply cluster_weights, respect core_clusters and anti_clusters
  // Normalize to 0-2 scale
}
```

#### 4.3 E2b: Age Appropriateness (3 pts)

```dart
class E2bCalculator {
  // Load rda_optimal_uls.json
  // For each nutrient: compare to age-group average RDA
  // Penalize if way outside range (< 10% or > 500%)
  // Clamp to [0, 3]
}
```

#### 4.4 E2c: Medical Compatibility (8 pts)

```dart
class E2cCalculator {
  // Start with 8 pts
  // Load interaction_summary from detail blob
  // Check condition_summary for matches against user conditions:
  //   contraindicated: -8 (product disqualified)
  //   avoid: -5
  //   caution: -3
  //   monitor: -1
  // Check drug_class_summary for matches against user drug classes:
  //   Same penalties as above
  // Clamp to [0, 8]
}
```

V1.0: `userDrugClasses` comes from profile checklist.
V1.1: `userDrugClasses` derived from medication stack (profile checklist becomes optional/hidden).

#### 4.5 Combined FitScore

```dart
class FitScoreResult {
  final double scoreFit20;         // E1 + E2a + E2b + E2c (0-20)
  final double scoreCombined100;   // (scoreQuality80 + scoreFit20) * 100 / 100
  final double e1;                 // Dosage appropriateness
  final double e2a;                // Goal alignment
  final double e2b;                // Age appropriateness
  final double e2c;                // Medical compatibility
  final List<String> missingFields; // ["goals", "conditions"]
  final String displayText;        // "85/96 (88.5%) — Complete profile for full scoring"
}
```

FitScore is NEVER stored in the pipeline DB. Always computed fresh on-device from current profile state.

---

### Sprint 5: Stack Management + Safety Checker (Week 11-13)

**CRITICAL:** This is the hero feature. Split into 5a and 5b.

#### Sprint 5a: Stack Management + Basic Safety (Week 11-12)

**5a.1 My Stack Screen**
- List view: all products in stack
- Per-product: name, brand, quality score, verdict badge
- Dosing summary (v1.3.0 field)
- Total products count
- Stack Safety Score (see 5b)

**5a.2 Add to Stack Flow**
1. User taps "Add to Stack" on product detail
2. Run `StackInteractionChecker.checkSafety()`
3. If warnings: display modal with warnings (severity-sorted)
4. User confirms or cancels
5. If confirmed: add to `user_stacks_local`, show success toast

**5a.3 Stack Interaction Checker (supplement-supplement)**

```dart
class StackInteractionChecker {
  Future<List<InteractionResult>> checkSafety(
    ProductsCore newProduct,
    List<ProductsCore> stackProducts,
    UserProfile profile,
  ) async {
    final results = <InteractionResult>[];

    // Check 1: Cumulative nutrient doses (UL overages)
    // Parse ingredient_fingerprint for all products
    // Sum doses per nutrient across stack
    // Compare against age/sex-specific UL from rda_optimal_uls.json
    // Flag: >100% UL = caution, >150% UL = avoid

    // Check 2: Stimulant/sedative antagonism
    // Uses contains_stimulants, contains_sedatives from products_core
    // No detail blob fetch needed

    // Check 3: Blood thinner stacking
    // Uses contains_blood_thinners from products_core
    // Multiple blood-thinning supplements = increased risk

    // Check 4: Duplicate active ingredients
    // Parse ingredient_fingerprint for overlapping ingredients
    // Flag same herb/nutrient in multiple products

    // Check 5: Timing conflicts (from timing_rules.json)
    // Check if any pair needs time separation
    // E.g., iron + calcium = "Take 4 hours apart"

    return results;
  }
}
```

**Performance:** <100ms for all checks. No network needed — all data in `products_core` v1.3.0 fields.

**5a.4 Stack Actions**
- Remove from stack
- View product detail
- Re-run safety check

#### Sprint 5b: Stack Safety Score + Synergies (Week 12-13)

**5b.1 Stack Safety Score (0-100)**

```dart
class StackSafetyScore {
  final int score;                    // 0-100
  final String riskTier;              // excellent, good, caution, moderate_risk, high_risk
  final String riskColor;             // green, green, yellow, orange, red
  final String riskLabel;             // "Your stack looks great", etc.
  final List<InteractionResult> issues;
  final List<SynergyResult> synergies;
  final List<TimingOptimization> optimizations;
}
```

**Formula:**

```
Stack Safety Score = 100
  - interaction_penalties     (sum of all pair penalties, per severity bands)
  - duplicate_exposure_penalties  (UL overages from stacking)
  - timing_conflict_penalties     (absorption conflicts when taken together)
  + synergy_bonuses              (positive combinations found)

Hard-stop rules:
  If ANY contraindicated interaction: cap at 25, force RED
  If ANY avoid interaction: cap at 50, force ORANGE
  Max total deduction: -75 (floor at 25)
  Max total bonus: +15 (ceiling stays 100)
```

**Penalty bands per pair:**

| Severity | Per-Pair Penalty |
|----------|------------------|
| contraindicated | -15 to -20 |
| avoid | -10 to -15 |
| caution | -5 to -10 |
| monitor | -2 to -5 |

**Synergy bands per pair:**

| Evidence | Per-Pair Bonus |
|----------|----------------|
| Strong clinical | +5 to +6 |
| Moderate observational | +3 to +4 |
| Theoretical | +1 to +2 |

**Risk tiers:**

| Score | Tier | Color | Label |
|-------|------|-------|-------|
| 90-100 | Excellent | Green | "Your stack looks great" |
| 75-89 | Good | Green | "Minor optimizations available" |
| 60-74 | Caution | Yellow | "Some concerns to review" |
| 40-59 | Moderate Risk | Orange | "Important issues found" |
| 0-39 | High Risk | Red | "Serious interactions detected" |

**5b.2 Positive Synergy Surfacing**

Show green checkmarks for good combinations alongside warnings:
- "Vitamin D + K2 — Enhanced calcium absorption (strong evidence)"
- "Calcium + D3 — Synergy bonus earned (+2.0 on product score)"

Data source: `synergy_cluster.json` from pipeline + `synergy_detail` in detail blobs.

**5b.3 Timing Optimization Display**

Show actionable timing advice:
- "Your score improves from 68 to 74 if you separate Iron and Calcium by 4 hours"
- "Take magnesium at bedtime for best absorption"
- "Probiotics: take on empty stomach, 30min before meals"

Data source: `timing_rules.json` (new reference data file).

**5b.4 Stack Summary UX**

```
Stack Safety Score: 74 (Caution)

Issues:
  🔴 2 serious interactions
  🟠 3 moderate concerns
  
Optimizations:
  💡 2 timing improvements available
  
Synergies:
  🟢 3 positive combinations detected
```

---

### Sprint 6: Social Sharing (Week 14)

#### 6.1 Share Button (Product Detail)

Uses v1.3.0 pre-computed fields — instant, no detail blob fetch:

```dart
void shareProduct(ProductsCore product) {
  final highlights = (jsonDecode(product.shareHighlights) as List).join('\n- ');
  Share.share('''
${product.shareTitle}

${product.shareDescription}

Key highlights:
- $highlights

Analyzed by PharmaGuide
''');
}
```

#### 6.2 Stack Share

- Share entire stack summary as formatted text or image
- Include Stack Safety Score + top synergies

---

### Sprint 7: Settings + Profile Management (Week 15)

#### 7.1 Settings Screen

- Edit profile (re-open profile setup flow)
- Privacy settings
- Notification preferences
- About / Legal
- Data export (GDPR compliance)

#### 7.2 Profile Edit Impact

- On profile change: invalidate all cached FitScores
- Recompute FitScores for favorited and stacked products
- Show impact: "3 products now have different fit scores"

---

### Sprint 8: Testing + QA + Ship (Week 16-17)

#### 8.1 Testing

- Unit tests: FitScore calculators (E1, E2a, E2b, E2c)
- Unit tests: StackInteractionChecker, StackSafetyScore
- Widget tests: profile setup, search, product detail
- Integration tests: full user flows (scan -> view -> add to stack -> check safety)
- Manual QA: iOS + Android

#### 8.2 Performance Validation

| Metric | Target |
|--------|--------|
| App size | < 60MB (iOS/Android) |
| Cold start | < 3s |
| Search latency | < 200ms |
| FitScore calculation | < 100ms |
| Stack interaction check | < 100ms |
| Detail blob fetch | < 500ms (cache miss) |

#### 8.3 V1.0 Ship Checklist

- [ ] All 6 profile fields implemented with exact schema IDs
- [ ] Drug class checklist working (9+ classes)
- [ ] FitScore engine (E1, E2a, E2b, E2c) complete
- [ ] Stack interaction checker complete with safety score
- [ ] Timing conflicts detected
- [ ] Synergies surfaced
- [ ] Search + filter working (all v1.3.0 fields)
- [ ] Product detail screen with transparent score breakdown
- [ ] Barcode scanning functional
- [ ] Interaction warnings with severity + evidence + clickable sources
- [ ] Proprietary blend warning displayed
- [ ] Unknown ingredient fallback warning displayed
- [ ] At least 180K products loaded
- [ ] Social sharing working
- [ ] Offline mode functional (local catalog)
- [ ] OTA update mechanism working

---

## V1.1 — Medication Intelligence

**Identity:** "Add your medications, get complete interaction coverage"

**Ship gate:** Medication search working, drug-supplement warnings firing from stack, derived drug classes replacing profile checkboxes, depletion checker active.

---

### Sprint 9: Medication Stack + RxNorm (Week 18-20)

#### 9.1 Unified Stack Model

Update `user_stacks_local` to support both types:

```sql
user_stacks_local (
  id TEXT PRIMARY KEY,
  type TEXT NOT NULL,          -- 'supplement' | 'medication'
  name TEXT NOT NULL,
  dsld_id TEXT,                -- supplement: links to products_core
  rxcui TEXT,                  -- medication: RxNorm concept ID
  ingredient_keys TEXT,        -- JSON array: normalized ingredient keys
  drug_classes TEXT,           -- JSON array: derived from rxcui mapping
  dosage TEXT,                 -- optional: "500mg"
  frequency TEXT,              -- optional: "twice daily"
  added_at TEXT NOT NULL,
  client_updated_at TEXT NOT NULL,
  deleted_at TEXT,             -- tombstone for sync
  synced_at TEXT
)
```

#### 9.2 Medication Search Service

```dart
class MedicationService {
  Future<List<MedicationSearchResult>> search(String query);
  Future<MedicationNormalized> normalize(String rxcui);
}
```

- RxNorm API for search + normalization
- Cache results locally to avoid repeated API calls
- Fallback: bundled top-500 medications for offline search

#### 9.3 Drug Class Mapping

**`drug_class_map.json`** — Maps RxCUI to drug classes:

```json
{
  "_metadata": { "total_entries": 500, "schema_version": "1.0.0" },
  "mappings": {
    "1161204": { "name": "Warfarin", "drug_classes": ["anticoagulants"] },
    "860975": { "name": "Metformin", "drug_classes": ["hypoglycemics"] }
  }
}
```

#### 9.4 Flutter-Side Interaction DB

**`interactions_db.json`** — Specific drug-supplement pairs:

```json
{
  "_metadata": {
    "total_entries": 200,
    "schema_version": "1.0.0",
    "sources": ["manual_curation", "suppai_validated", "rxnorm"]
  },
  "interactions": [
    {
      "id": "DDI_WAR_GINKGO",
      "type": "Med-Sup",
      "agent1_name": "Warfarin",
      "agent1_rxcui": "1161204",
      "agent1_drug_classes": ["anticoagulants"],
      "agent2_name": "Ginkgo Biloba",
      "agent2_cui": "C0028077",
      "agent2_ingredient_key": "ginkgo_biloba",
      "severity": "caution",
      "evidence_level": "established",
      "interaction_effect_type": "Enhancer",
      "mechanism": "Increased bleeding risk due to antiplatelet effects",
      "management": "Use with caution. Monitor for signs of bleeding.",
      "dose_dependent": false,
      "dose_threshold": null,
      "source_urls": ["https://pubmed.ncbi.nlm.nih.gov/16365593/"],
      "last_reviewed": "2026-04-07"
    }
  ]
}
```

**Data sourcing strategy:**
1. Manual curation (highest trust — pharmacist-reviewed)
2. Supp.ai database (literature-mined, filtered by confidence, reviewed before inclusion)
3. RxNorm drug class mappings (for drug -> class bridging)
4. NatMed / ChEMBL (supplementary validation)

#### 9.5 Scanner / Add Flow Update

```
[ Scan Product ]

+ Add manually

  → What are you adding?
    [ Supplement ]    [ Medication ]

Supplement: search by name or scan barcode
Medication: search by name (RxNorm autocomplete)
  → Select result
  → (Optional) dosage / frequency
  → Add to stack
```

Single entry point. No separate "Add Prescription" button.

---

### Sprint 10: StackSafetyEngine + Depletion Checker (Week 21-23)

#### 10.1 StackSafetyEngine

```dart
class StackSafetyEngine {
  // Phase 1 (V1.1):
  Future<List<InteractionResult>> checkDrugSupplement(stack);
    // Uses Flutter-side interactions_db.json
    // Matches specific drug-supplement pairs
    // Falls back to drug_class-level matching from pipeline

  Future<List<InteractionResult>> checkSupplementSupplement(stack);
    // Uses pipeline ingredient_fingerprint + timing_rules
    // Already built in V1.0 Sprint 5 — now enhanced

  // Phase 2 (V3.0):
  Future<List<InteractionResult>> checkDrugDrug(stack);
    // Deferred — requires comprehensive drug-drug database
}
```

#### 10.2 Medication-Induced Depletion Checker

**`medication_depletions.json`** — New data file:

```json
{
  "_metadata": { "total_entries": 50, "schema_version": "1.0.0" },
  "depletions": {
    "hypoglycemics": {
      "metformin": {
        "depletes": [
          {
            "nutrient": "vitamin_b12",
            "evidence_level": "established",
            "mechanism": "Reduces B12 absorption in ileum",
            "recommendation": "Consider B12 supplementation (500-1000mcg)",
            "source_urls": ["https://pubmed.ncbi.nlm.nih.gov/28394004/"]
          }
        ]
      }
    },
    "statins": {
      "_class_wide": {
        "depletes": [
          {
            "nutrient": "coq10",
            "evidence_level": "probable",
            "mechanism": "Inhibits CoQ10 synthesis via HMG-CoA reductase pathway",
            "recommendation": "Consider CoQ10 supplementation (100-200mg)",
            "source_urls": ["https://pubmed.ncbi.nlm.nih.gov/15199295/"]
          }
        ]
      }
    }
  }
}
```

**UX when user adds medication:**
- "You're taking Metformin — this commonly depletes Vitamin B12."
- "Your stack does not include B12." OR "Your stack already includes B12 — good."
- "Consider adding B12 to your stack" with product suggestions from catalog

#### 10.3 Derived Drug Classes

```dart
List<String> deriveDrugClasses(List<StackItem> stack) {
  return stack
    .where((i) => i.type == StackItemType.medication)
    .expand((i) => i.drugClasses ?? [])
    .toSet()
    .toList();
}
```

Replace `userProfile.drugClasses` with `deriveDrugClasses(userStack)` in E2c calculator. Profile drug class checklist becomes optional (hidden if medications are in stack).

---

### Sprint 11: Product Comparison + Polish (Week 24-25)

#### 11.1 Product Comparison (Side-by-Side)

When viewing a product, show "Similar Products" based on `primary_category`:

```sql
SELECT * FROM products_core
WHERE primary_category = ?
  AND dsld_id != ?
ORDER BY score_quality_80 DESC
LIMIT 5;
```

Comparison table shows:
- Quality score
- Key nutrient amounts (from `key_nutrients_summary`)
- Form quality indicators
- Dietary flags
- Price tier (if available)

#### 11.2 V1.1 Testing + Ship

- Test medication search + normalization
- Test StackSafetyEngine (drug-supplement pairs)
- Test depletion checker recommendations
- Test derived drug classes in E2c
- Test product comparison

---

## V1.2 — Trust & Transparency

**Identity:** "Every score explained, every warning sourced"

**Ship gate:** Every FitScore point has human-readable explanation. All warnings show source attribution. Recompute strategy prevents stale scores.

---

### Sprint 12: FitScore Explanation Layer (Week 26-27)

#### 12.1 FitScore Breakdown with Explanations

```dart
class FitScoreBreakdown {
  final double e1;
  final double e2a;
  final double e2b;
  final double e2c;
  final List<String> explanations;
  final List<ScoreImpact> impacts;
}

class ScoreImpact {
  final String component;    // "E2c: Medical Compatibility"
  final double delta;        // -5.0
  final String reason;       // "Potential interaction with anticoagulants"
  final String severity;     // "avoid"
}
```

**Example output:**
```
Your FitScore: 13/20

  E1 Dosage (5/7): Good dose range for your age group
  E2a Goals (2/2): Strong match with Sleep Quality goal
  E2b Age (3/3): Age-appropriate formulation
  E2c Medical (3/8):
    ↓ -5: Potential interaction with blood thinners (avoid)

Overall: 78/100 (quality 65 + fit 13)
```

#### 12.2 Recompute Strategy

```dart
class ScoreVersion {
  final DateTime lastComputedAt;
  final String dataVersion;      // export_manifest version
  final String profileVersion;   // hash of profile state
  final String stackVersion;     // hash of stack state
}
```

**Recompute triggers:**
- User profile changes (any field)
- Stack changes (add/remove product or medication)
- New DB version downloaded (OTA update)
- Manual refresh (pull-to-refresh)

**Staleness detection:**
- Compare stored `profileVersion` + `stackVersion` with current
- Show indicator: "Score may be outdated — tap to refresh"

---

### Sprint 13: Trust Layer + Doctor PDF (Week 28-29)

#### 13.1 Trust Layer UI

Every warning card shows:
```
⚠️ Caution: Ginkgo + Anticoagulants

Increased bleeding risk due to antiplatelet effects.
Take with caution. Monitor for signs of bleeding.

Evidence: Established (Strong clinical data)
Sources:
  • PubMed: PMID 16365593  [tap to open]
  • FDA Supplement Guidance  [tap to open]
```

Every score bonus/penalty shows its source:
```
+2.0 Synergy Bonus: Calcium + Vitamin D3
  Source: backed_clinical_studies (PMID: 12456789)

-3.0 Harmful Additive: Titanium Dioxide
  Source: harmful_additives_db (Severity: moderate)
```

#### 13.2 Doctor-Ready PDF Report

Export user's complete supplement profile:
- Profile summary (conditions, medications, goals)
- Current stack with all products and scores
- All active interaction warnings with severity + evidence + sources
- Stack Safety Score with breakdown
- Depletion alerts (V1.1)
- Generated as clean PDF for healthcare provider review

---

## V2.0 — AI Intelligence & Personalization

**Identity:** "Your personal supplement advisor"

**Ship gate:** AI chat working with context-aware answers. Gap analysis generating actionable insights. Alternative suggestions working.

---

### Sprint 14-15: AI Chat Foundation (Week 30-33)

#### 14.1 Gate-Based Interaction Checker

Deterministic gates fire FIRST (< 50ms), LLM fallback for open-ended questions (2-5s):

```
User: "Can I take St. John's Wort with Zoloft?"

Gate match: RULE_SJW_SSRI → contraindicated
→ Instant response with structured card:

🔴 CONTRAINDICATED
St. John's Wort + SSRIs (Sertraline/Zoloft)
Risk: Serotonin syndrome
Severity: Serious (Established evidence)
Action: Do not combine. Consult your doctor.
Source: PMID:12345678

Symptoms to watch:
  • Agitation
  • Sweating  
  • Rapid heart rate
```

#### 14.2 Population-Adjusted Risk Scoring

Modify severity for specific populations:
- Elderly: lower thresholds for stimulants, NSAIDs
- Renal: flag supplements with kidney-unsafe ingredients
- Pregnancy: flag any rule with `pregnancy_category != safe`

#### 14.3 Structured Output Schema

AI responses return structured objects for rich UI cards:

```dart
class ChatResponse {
  final String severity;
  final double confidence;
  final String mechanismSummary;
  final List<String> itemsFlagged;
  final List<String> references;
  final String? alternativeSuggestion;
  final String? doseAssessment;
}
```

#### 14.4 Persistent Session State

Returning users don't re-specify their medication list. Session state persists for 30 days.

---

### Sprint 16: Temporal Context + Form-Specific Guidance (Week 34-35)

- Washout/onset/half-life data for ~30 medications
- Form-specific gate branching: "Magnesium glycinate for sleep is fine alongside sertraline — the concern is the 5-HTP"
- DSL gate expansion: migrate simple gate replies to `gates.json` for clinical reviewer editing

---

### Sprint 17: Alternative Suggestion Engine (Week 36-37)

When flagging unsafe combo, proactively suggest safer alternative:
- "Instead of 5-HTP for sleep with Zoloft, try magnesium glycinate — here's why it's safer"
- Alternatives are goal-matched AND interaction-checked against user's current stack
- Never suggest an alternative that creates a new interaction

---

### Sprint 18: Nutrient Gap Analysis (Week 38-39)

Analyze user's current stack vs their goals:
- Map stack ingredients to goal clusters (from `user_goals_to_clusters.json`)
- Identify gaps: "Your Sleep Quality goal needs melatonin or magnesium — your stack doesn't include either"
- Identify overlaps: "You have 3 products with Vitamin D — consider consolidating"
- Identify excess: "Total Vitamin D across your stack exceeds UL by 40%"
- Suggest specific products to fill gaps from catalog

---

### Sprint 19: Evaluation Modes + Prescription OCR (Week 40-41)

#### 19.1 Evaluation Modes

```dart
enum EvaluationMode {
  safety,       // E2c + interactions prioritized
  optimization, // E2a + synergies prioritized
  stackCheck    // interactions only, skip scoring
}
```

User selects mode based on intent:
- "Is this safe?" -> safety mode
- "Is this good for my goals?" -> optimization mode
- "Can I combine these?" -> stack check mode

#### 19.2 Prescription OCR

- Scan medication label with camera
- Extract drug name via OCR
- Match to RxNorm
- Add to medication stack

#### 19.3 Empathetic Tone Adaptation

Detect anxiety level from message patterns. Adjust response:
- Reassurance first for anxious users
- Simplified bullets
- Action step at top

---

## V2.1 — Engagement & Retention

**Identity:** "Daily companion for your supplement routine"

**Ship gate:** Dose reminders working, starter stacks available, FDA notifications active.

---

### Sprint 20: Dose Reminders + Reorder Alerts (Week 42-43)

#### 20.1 Dose Reminders

- "Time to take your magnesium (best absorbed at night)"
- Timing based on `timing_rules.json` data
- Push notifications (configurable)
- Daily touchpoint for retention

#### 20.2 Reorder Reminders

- Track servings_per_container from v1.3.0 field
- If user scanned 60-day supply on Jan 1, ping late Feb:
  - "Running low on Vitamin D3?"
  - Optional: affiliate purchase links (Amazon, iHerb)

---

### Sprint 21: Starter Stacks + FDA Notifications (Week 44-45)

#### 21.1 Starter Stacks (Curated Protocols)

Pre-built supplement protocols for common goals:
- Sleep Optimization stack (3-4 products)
- Energy Support stack
- Joint Health stack
- Immune Support stack
- Stress/Anxiety Relief stack

Each shows:
- Products with scores
- Timing schedule
- Interaction analysis (pre-checked for safety)
- "Adopt whole stack" or "Pick individual items"

#### 21.2 FDA Recall Push Notifications

- Monitor FDA recall data (from pipeline's `fda_weekly_sync`)
- If recalled ingredient found in user's stack products:
  - Push notification: "Safety alert for [Product Name]"
  - In-app banner with detail

---

### Sprint 22: Feedback Loop + Progress Tracking (Week 46-47)

#### 22.1 User Feedback

Simple on every warning and score:
- "Is this helpful?" (thumbs up / thumbs down)
- Log: product_id, interaction_type, user profile snapshot (anonymized)
- Data becomes gold for improving rules

#### 22.2 Progress Tracking

- Stack history over time (timeline view)
- Score changes when products added/removed
- "Your stack safety improved from 62 to 84 this month"

---

## V3.0 — Platform & Ecosystem

**Identity:** "From app to health platform"

**Ship gate:** REST API live with paying customers. Practitioner portal functional. Family profiles working.

---

### Sprint 23-24: B2B REST API (Week 48-51)

```
POST /api/v1/interactions/check
{
  "products": ["upc:012345678901", "upc:098765432109"],
  "medications": ["metformin", "lisinopril"],
  "user_profile": {
    "age": 45,
    "conditions": ["diabetes", "hypertension"]
  }
}

RESPONSE:
{
  "interactions": [...],
  "timing_optimization": {...},
  "quality_scores": {...},
  "stack_safety_score": 74,
  "risk_tier": "caution"
}
```

**Pricing tiers:**
- Free: 100 API calls/month (developer sandbox)
- Starter: $99/month for 10,000 calls
- Growth: $499/month for 100,000 calls
- Enterprise: custom pricing + SLA

---

### Sprint 25: White-Label SDK + Certification (Week 52-53)

#### 25.1 Embeddable Widgets

- Interaction Checker Widget (iframe or React/Flutter component)
- Barcode Scanner SDK (mobile SDK for iOS/Android)

#### 25.2 "PharmaGuide Verified" Badge

- Supplement brands pay for safety certification
- Badge displayed on products that pass quality + safety thresholds
- Revenue stream + marketing for brands

---

### Sprint 26: Family Profiles (Week 54-55)

- Multiple profiles per account (partner, kids, parents)
- Each profile has own age/sex/conditions/medications/goals/allergens
- Scores and warnings personalized per profile
- Stack per profile (kids' supplements vs adult supplements)

---

### Sprint 27: Practitioner Portal (Week 56-57)

- Healthcare providers create account
- View patient stacks (with patient consent)
- Recommend products to patients
- Monitor interaction alerts
- Generate patient reports
- Revenue: practitioner subscription

---

## V3.1 — Premium Intelligence

**Identity:** "The moat no one can replicate"

---

### Sprint 28: Lab Integration (Week 58-60)

- Upload bloodwork PDF
- OCR/parse biomarker values
- Cross-reference with stack:
  - "Your Vitamin D is 22 ng/mL (low). Your stack has 1,000 IU. Research suggests 2,000-4,000 IU for raising levels."
- Suggest products to address deficiencies
- Premium subscription feature

---

### Sprint 29: Interaction Matrix + Governance (Week 61-63)

#### 29.1 Interaction Matrix

100+ curated interaction pairs with:
- Severity, mechanism, dose-dependent flag, dose threshold
- Onset timing, alternatives, population modifiers, references
- The killer feature: dose-aware, population-adjusted interaction data

#### 29.2 Clinical Governance Dashboard

- All claims with review status
- Reference coverage stats
- Gate hit rates
- Claims due for review
- Makes PharmaGuide auditable: "How do you know this?" has a real answer

---

### Sprint 30: Drug-Drug Interactions + Wearables + Data Licensing (Week 64-66)

#### 30.1 Drug-Drug Interactions

- Complete `Med-Med` type in interactions_db
- Full StackSafetyEngine coverage: drug-drug, drug-supplement, supplement-supplement

#### 30.2 Wearable Integration

- Apple Health / Google Fit
- Import health metrics for context-aware scoring

#### 30.3 Data Licensing

- Anonymized aggregate insights to researchers, insurance, health analytics
- Affiliate/referral purchase links for product recommendations

---

## Performance Targets (All Versions)

| Metric | V1.0 | V1.1 | V2.0 |
|--------|------|------|------|
| App size | < 60MB | < 65MB | < 80MB |
| Cold start | < 3s | < 3s | < 4s |
| Search latency | < 200ms | < 200ms | < 200ms |
| FitScore calc | < 100ms | < 100ms | < 100ms |
| Stack safety check | < 100ms | < 200ms | < 200ms |
| Detail blob fetch | < 500ms | < 500ms | < 500ms |
| AI chat (gate hit) | N/A | N/A | < 50ms |
| AI chat (LLM fallback) | N/A | N/A | < 5s |

---

## Success Metrics (Per Version)

### V1.0

- Profile completion rate: > 60%
- Stack adoption: > 40% of users add 1+ product
- Average session time: > 3 minutes
- Interaction warning read rate: > 80%

### V1.1

- Medication addition rate: > 25% of users add 1+ medication
- Depletion alert engagement: > 50% tap to learn more
- Drug-supplement warning accuracy: > 95% (validated against Supp.ai)

### V2.0

- AI chat sessions per user: > 2/week
- Alternative suggestion adoption: > 15%
- Nutrient gap resolution: > 30% add suggested product

### V2.1

- Dose reminder opt-in: > 40%
- Starter stack adoption: > 20%
- 30-day retention: > 35%

### V3.0

- API customers: > 10 paying accounts
- Practitioner signups: > 100
- Family profile creation: > 15% of users

---

## Privacy & Security (All Versions)

### On-Device (Local)
- User profile: encrypted SQLite (`flutter_secure_storage`)
- Health data NEVER uploaded to Supabase
- FitScore and Stack Safety Score computed 100% on-device
- Medication data stays local unless user opts into cloud sync

### Supabase (Remote)
- Stores: product catalog, detail blobs, images, auth
- No PII, no health data
- Read-only product access (user can't modify product data)
- Stack sync: opt-in, last-write-wins with tombstones

### OTA Updates
- Checksum verification (`export_manifest.json`)
- Rollback on corruption
- Silent background sync

---

## Competitive Positioning

| Competitor Weakness | PharmaGuide Strength |
|---------------------|---------------------|
| "AI hallucinations" / unreliable data | Pharmacist-reviewed, evidence-graded rules with PMIDs |
| Vague "may interact" warnings | Severity levels + mechanisms + evidence strength |
| Can't handle proprietary blends | Explicit blend detection + "limited analysis" flagging |
| Supplement-second UX (food trackers) | Supplement-first design |
| No condition-specific filtering | User profile -> personalized alerts |
| Missing compounds silently ignored | "Unknown ingredient" explicit warnings |
| No stack-level analysis | Full stack safety scoring with timing optimization |
| No medication depletion awareness | Proactive depletion alerts with product suggestions |
| No offline mode | Offline-first architecture, 180K products local |
| General chatbot health advice | Deterministic gates + curated KB + LLM |

**One-liner:** "The only supplement checker that shows you WHY, not just what."

---

## Data Files Summary

### Pipeline Repo (shipped via Supabase)
| File | Purpose |
|------|---------|
| `ingredient_interaction_rules.json` | 100+ supplement -> condition/drug class rules |
| `clinical_risk_taxonomy.json` | 14 conditions, 9+ drug classes, severity levels |
| `user_goals_to_clusters.json` | 18 goals with cluster weights |
| `rda_optimal_uls.json` | Age/sex-specific RDA and UL values |
| `synergy_cluster.json` | Positive combination rules |
| `allergens.json` | 17 food/supplement allergens |
| `timing_rules.json` | Supplement timing and absorption rules (new) |

### Flutter Repo (bundled or OTA-updated)
| File | Purpose | Version |
|------|---------|---------|
| `drug_class_map.json` | RxCUI -> drug class mapping | V1.1 |
| `interactions_db.json` | Specific drug-supplement pairs (Supp.ai-validated) | V1.1 |
| `medication_depletions.json` | Drug -> nutrient depletion alerts | V1.1 |
| `timing_rules.json` | Timing optimization data | V1.0 |
| `starter_stacks.json` | Curated supplement protocols | V2.1 |

---

**Next:** Create implementation plan from this spec.
