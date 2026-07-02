// Threshold-gating data table for condition-tagged interaction warnings.
//
// Spec: INITIATIVE_PRODUCT_DETAIL_CLEANUP.md, Sprint S2.1, T3 (+ Path A
// extension 2026-04-29: positive-profile bullet generator for the T12
// Personal Fit card).
//
// Why this exists
// ───────────────
// The pipeline generates condition-tagged warnings (e.g., "monitor with
// your TTC profile when this product contains vitamin D"). Pre-fix, the
// rule fired regardless of dose — so a 1000-IU vitamin D supplement
// triggered a TTC monitor flag, even though vitamin D is BENEFICIAL
// for fertility and pre-conception health (ACOG, NIH ODS recommend
// 600-1000 IU/day during pre-conception). That false-positive flag is
// the headline bug Sean caught in the 2026-04-29 walkthrough.
//
// This table captures, per (condition, canonical-ingredient) pair,
// either:
//   - `directionality: positive` — the nutrient is BENEFICIAL for the
//     condition. Monitor/caution warnings should NEVER fire. (vitamin D
//     for TTC, folate for pregnancy, magnesium for diabetes, etc.)
//   - `minDose` — fire only when the dose meets or exceeds the
//     clinical-meaningful threshold. (vitamin A for pregnancy fires
//     above 3000 IU because retinol is teratogenic at high dose.)
//
// V1 coverage focuses on the highest-impact pairs (folate / iron /
// vitamin D for pregnancy + TTC; magnesium for diabetes + hypertension;
// vitamin A retinol teratogenicity; omega-3 / vitamin E / ginkgo /
// garlic / curcumin for bleeding disorders + scheduled surgery).
// Backlog B6 in the initiative tracks expansion against the latest
// clinical literature in 6 months. T4 wires the lookup into the
// warning generator.

/// How a nutrient relates to a condition for warning-gating purposes.
enum NutrientDirectionality {
  /// The nutrient is beneficial for the condition. Monitor / caution
  /// warnings should NEVER fire — surfacing them just teaches users
  /// to ignore future warnings (the boy-who-cried-wolf effect that
  /// erodes medical-grade trust).
  positive,

  /// Threshold-gated: fire only when the dose meets or exceeds the
  /// clinical-meaningful trigger. Below threshold the nutrient is
  /// either neutral or beneficial for the condition; above threshold
  /// the warning genuinely applies.
  neutral,
}

/// A single (condition, canonical-ingredient) gating entry.
class ConditionThreshold {
  final NutrientDirectionality directionality;

  /// Minimum dose at which the warning should fire. Null when
  /// [directionality] is [NutrientDirectionality.positive] (always
  /// suppress) or when no clinical threshold is established
  /// (caller treats null as "fire as today" — a passthrough).
  final double? minDose;

  /// Unit the threshold is expressed in (e.g. `'mg'`, `'IU'`,
  /// `'mcg'`). Null when [minDose] is null.
  final String? doseUnit;

  /// One-line evidence pointer (PubMed PMID, NIH ODS factsheet, ACOG
  /// guideline, etc). Lets a future auditor verify the threshold
  /// without spelunking the original PR. Not surfaced in UI.
  final String? rationale;

  const ConditionThreshold._({
    required this.directionality,
    this.minDose,
    this.doseUnit,
    this.rationale,
  });

  /// Beneficial nutrient for the condition — suppress warnings always.
  const ConditionThreshold.positive({String? rationale})
    : this._(
        directionality: NutrientDirectionality.positive,
        rationale: rationale,
      );

  /// Threshold-gated — fire only when dose >= [minDose] [doseUnit].
  const ConditionThreshold.aboveDose({
    required double minDose,
    required String doseUnit,
    String? rationale,
  }) : this._(
         directionality: NutrientDirectionality.neutral,
         minDose: minDose,
         doseUnit: doseUnit,
         rationale: rationale,
       );
}

/// Threshold table — keyed by `[conditionId][canonicalIngredientId]`.
///
/// Both keys are lowercase + underscore-joined to match the rest of
/// the pipeline (`vitamin_d`, `magnesium_glycinate`, `vitamin_a`).
/// Lookup happens via [lookupConditionThreshold] which canonicalizes
/// the raw `ingredient_name` from the warning blob.
///
/// V1 — populated against the user's 14 condition list
/// (`SchemaIds.conditions`). Pairs absent from this table fall through
/// to the existing pipeline behavior (fire as authored). Adding entries
/// is purely additive — never destructive — so growing the table is a
/// safe, incremental change.
const Map<String, Map<String, ConditionThreshold>> conditionThresholds = {
  // ─── ttc — trying to conceive ────────────────────────────────────
  'ttc': {
    // ACOG / NIH ODS recommend 600-1000 IU/day during pre-conception.
    // Pre-fix this fired a "monitor" flag at 1000 IU which was the
    // exact false positive that motivated the whole initiative.
    'vitamin_d': ConditionThreshold.positive(
      rationale: 'NIH ODS: vitamin D supports fertility / pre-conception',
    ),
    'vitamin_d3': ConditionThreshold.positive(
      rationale: 'NIH ODS: vitamin D3 form, same guidance as vitamin_d',
    ),
    // Folate is mandatory pre-conception — 400-800 mcg/day to prevent
    // neural-tube defects (ACOG). Triggering a monitor flag for any
    // folate-containing product would actively harm guidance.
    'folate': ConditionThreshold.positive(
      rationale: 'ACOG: 400-800 mcg/day mandatory pre-conception',
    ),
    'folic_acid': ConditionThreshold.positive(
      rationale: 'ACOG: synthetic folate, same guidance as folate',
    ),
    // Iron supplementation is recommended when stores are low; not
    // contraindicated otherwise.
    'iron': ConditionThreshold.positive(
      rationale: 'ACOG: iron supplementation recommended when low',
    ),
    // Vitamin A — retinol is teratogenic at high dose. Threshold 3000
    // IU/day (900 mcg RAE) per WHO / NIH ODS upper-limit guidance for
    // pre-conception. Below threshold = beneficial; above = real risk.
    'vitamin_a': ConditionThreshold.aboveDose(
      minDose: 3000,
      doseUnit: 'IU',
      rationale:
          'WHO / NIH ODS: retinol teratogenic above 3000 IU pre-conception',
    ),
    'retinol': ConditionThreshold.aboveDose(
      minDose: 3000,
      doseUnit: 'IU',
      rationale: 'WHO / NIH ODS: teratogenic above 3000 IU pre-conception',
    ),
    // Caffeine — modest intake (under ~200 mg/day) compatible with TTC
    // per most fertility guidelines.
    'caffeine': ConditionThreshold.aboveDose(
      minDose: 200,
      doseUnit: 'mg',
      rationale: 'ASRM / ACOG: limit to under 200 mg/day during TTC',
    ),
  },

  // ─── pregnancy ───────────────────────────────────────────────────
  'pregnancy': {
    'vitamin_d': ConditionThreshold.positive(
      rationale: 'NIH ODS / ACOG: vitamin D recommended during pregnancy',
    ),
    'vitamin_d3': ConditionThreshold.positive(
      rationale: 'NIH ODS / ACOG: same as vitamin_d',
    ),
    'folate': ConditionThreshold.positive(
      rationale: 'ACOG: required throughout pregnancy',
    ),
    'folic_acid': ConditionThreshold.positive(
      rationale: 'ACOG: required throughout pregnancy',
    ),
    'iron': ConditionThreshold.positive(
      rationale: 'ACOG: routine supplementation during pregnancy',
    ),
    'calcium': ConditionThreshold.positive(
      rationale: 'NIH ODS: 1000 mg/day recommended during pregnancy',
    ),
    'vitamin_b12': ConditionThreshold.positive(
      rationale: 'NIH ODS: required during pregnancy',
    ),
    'choline': ConditionThreshold.positive(
      rationale: 'NIH ODS: 450 mg/day recommended during pregnancy',
    ),
    // Vitamin A retinol is the strict-threshold case: teratogenic
    // above 10000 IU/day (300% of RDA). Set conservative threshold of
    // 3000 IU = adequate dietary intake; above this we warn.
    'vitamin_a': ConditionThreshold.aboveDose(
      minDose: 3000,
      doseUnit: 'IU',
      rationale:
          'CDC / WHO: teratogenic above 10000 IU; warn above adequate intake',
    ),
    'retinol': ConditionThreshold.aboveDose(
      minDose: 3000,
      doseUnit: 'IU',
      rationale: 'CDC / WHO: teratogenic above adequate intake',
    ),
    'caffeine': ConditionThreshold.aboveDose(
      minDose: 200,
      doseUnit: 'mg',
      rationale: 'ACOG: limit to under 200 mg/day during pregnancy',
    ),
  },

  // ─── lactation — breastfeeding ───────────────────────────────────
  'lactation': {
    'vitamin_d': ConditionThreshold.positive(
      rationale: 'NIH ODS: continued supplementation during lactation',
    ),
    'vitamin_d3': ConditionThreshold.positive(rationale: 'same as vitamin_d'),
    'vitamin_b12': ConditionThreshold.positive(
      rationale: 'NIH ODS: required during lactation',
    ),
    'iron': ConditionThreshold.positive(
      rationale: 'ACOG: postpartum iron supplementation recommended',
    ),
    'calcium': ConditionThreshold.positive(
      rationale: 'NIH ODS: 1000 mg/day recommended during lactation',
    ),
  },

  // ─── diabetes ────────────────────────────────────────────────────
  // Pre-fix, vitamin D triggered a diabetes monitor flag — but vitamin
  // D is not a diabetes risk (NIH ODS: trials show no significant
  // glycemic benefit or harm), so suppress rather than warn.
  'diabetes': {
    'vitamin_d': ConditionThreshold.positive(
      rationale:
          'NIH ODS Vitamin D (HP fact sheet): clinical trials show no '
          'significant effect on glucose homeostasis, insulin resistance, '
          'or HbA1c — vitamin D is not a diabetes risk, so suppress. '
          '(Corrected 2026-07-02: the prior PMID was a wrong-topic '
          'mis-cite, removed after live-API content verification.)',
    ),
    'vitamin_d3': ConditionThreshold.positive(rationale: 'same as vitamin_d'),
    'magnesium': ConditionThreshold.positive(
      rationale:
          'PMID 28150351: improves insulin sensitivity / glycemic control',
    ),
    'magnesium_glycinate': ConditionThreshold.positive(
      rationale: 'same as magnesium',
    ),
    'magnesium_citrate': ConditionThreshold.positive(
      rationale: 'same as magnesium',
    ),
    'chromium': ConditionThreshold.positive(
      rationale: 'NIH ODS: modest benefit on glycemic control',
    ),
    // Niacin (high-dose) raises blood glucose — fire above 500 mg.
    'niacin': ConditionThreshold.aboveDose(
      minDose: 500,
      doseUnit: 'mg',
      rationale: 'NIH ODS: high-dose niacin worsens glycemic control',
    ),
    // T16.2b (2026-04-30) — close ALA + Vanadium false positives Sean
    // caught in PureLean Pure Pack (pipeline fired CAUTION + MONITOR
    // tags at sub-clinical doses). Pre-T16.2b, the table had no entry
    // for these two pairs, so the gate fell through to "fire as
    // authored" — exactly the boy-who-cried-wolf erosion of trust the
    // S2.1 work was built to prevent.
    //
    // Alpha-lipoic acid: hypoglycemic effect documented above
    // ~600 mg/day combined with diabetes meds (the pipeline's own
    // "What to do" text confirms the threshold). PureLean ships
    // 350 mg → suppressed.
    'alpha_lipoic_acid': ConditionThreshold.aboveDose(
      minDose: 600,
      doseUnit: 'mg',
      rationale:
          'PMID 22374556 (T2D RCT, DL-ALA 300-1200 mg/day incl. 600 mg): lowers '
          'fasting glucose/HbA1c dose-dependently; additive hypoglycemia when '
          'combined with glucose-lowering meds is mechanistic inference. '
          '(Corrected 2026-07-02: the prior citation here was a wrong-topic '
          'mis-cite and was removed after live-API content verification.)',
    ),
    // Vanadium: clinical hypoglycemic data lives at pharmacologic
    // doses (50-200 MG vanadyl sulfate). Supplements ship at
    // mcg-level (50-1000 mcg) — three orders of magnitude below the
    // clinical effect dose. Threshold expressed in supplement-side
    // units (mcg) so the unit-match check in the gate fires only
    // when a label genuinely doses 50 mg+. PureLean ships 50 mcg →
    // suppressed.
    'vanadium': ConditionThreshold.aboveDose(
      minDose: 50000,
      doseUnit: 'mcg',
      rationale:
          'NIH ODS: hypoglycemic at 50-200 mg pharmacologic doses; '
          'supplemental mcg doses below clinical effect',
    ),
    // T16.2e (2026-04-30) — close two more diabetes false positives
    // Sean caught in PureLean's §7 "Relevant to your health" surface.
    // Pre-T16.2e the table had no entries for these, so they fell
    // through to "fire as authored" even after T16.2b dose-gated
    // ALA / Vanadium / Niacin. Both are directionally beneficial for
    // glycemic control; tagging `positive` suppresses the warning AND
    // makes them eligible for "supports your blood sugar goal" bullets
    // on the Personal Fit card.
    //
    // Cinnamon: NIH ODS — Cinnamomum cassia at 1-6 g/day shows modest
    // fasting-glucose reduction in T2D (no hypoglycemia concern at any
    // typical supplemental dose).
    'cinnamon': ConditionThreshold.positive(
      rationale: 'NIH ODS: modest fasting-glucose reduction in T2D',
    ),
    'cinnamon_extract': ConditionThreshold.positive(
      rationale: 'same as cinnamon',
    ),
    'cinnamon_bark': ConditionThreshold.positive(rationale: 'same as cinnamon'),
    // Pipeline ships full DSLD label form ("Cinnamon Bark Extract,
    // Dried") for some products. Canonicalizes to this key after
    // T16.2e's punctuation-strip update.
    'cinnamon_bark_extract': ConditionThreshold.positive(
      rationale: 'same as cinnamon',
    ),
    'cinnamon_bark_extract_dried': ConditionThreshold.positive(
      rationale: 'same as cinnamon',
    ),
    // Inositol: well-established benefit for insulin sensitivity,
    // especially myo-inositol for PCOS-related insulin resistance
    // (2-4 g/day). Not a hypoglycemic at any typical supplemental dose.
    'inositol': ConditionThreshold.positive(
      rationale:
          'PMID 29042448 (Unfer 2017, meta-analysis of 9 RCTs): myo-inositol '
          'significantly lowers fasting insulin and HOMA-IR in PCOS; benefit '
          'is real but evidence is mixed across meta-analyses. (Corrected '
          '2026-07-02: prior PMID was a wrong-topic mis-cite, removed after '
          'live-API content verification.)',
    ),
    'myo_inositol': ConditionThreshold.positive(rationale: 'same as inositol'),
    'd_chiro_inositol': ConditionThreshold.positive(
      rationale: 'same as inositol',
    ),
  },

  // ─── hypertension ────────────────────────────────────────────────
  'hypertension': {
    // Magnesium is BP-lowering — beneficial.
    'magnesium': ConditionThreshold.positive(
      rationale: 'PMID 22318649: modest BP-lowering effect',
    ),
    'magnesium_glycinate': ConditionThreshold.positive(
      rationale: 'same as magnesium',
    ),
    // Caffeine raises BP — flag above moderate intake.
    'caffeine': ConditionThreshold.aboveDose(
      minDose: 200,
      doseUnit: 'mg',
      rationale: 'NIH: acutely raises BP; flag above moderate intake',
    ),
    // Licorice causes pseudoaldosteronism / hypertension — flag any
    // appreciable dose.
    'licorice': ConditionThreshold.aboveDose(
      minDose: 100,
      doseUnit: 'mg',
      rationale: 'NIH ODS: glycyrrhizin causes pseudoaldosteronism',
    ),
  },

  // ─── kidney_disease ──────────────────────────────────────────────
  // Renal-clearance concerns at high dose for several minerals.
  'kidney_disease': {
    'magnesium': ConditionThreshold.aboveDose(
      minDose: 400,
      doseUnit: 'mg',
      rationale: 'NIH ODS: renal accumulation risk above UL',
    ),
    'potassium': ConditionThreshold.aboveDose(
      minDose: 250,
      doseUnit: 'mg',
      rationale:
          'KDIGO: hyperkalemia risk in CKD even at low supplemental doses',
    ),
    'vitamin_d': ConditionThreshold.aboveDose(
      minDose: 4000,
      doseUnit: 'IU',
      rationale: 'KDOQI: high-dose calcium/phosphate concern in advanced CKD',
    ),
    'zinc': ConditionThreshold.aboveDose(
      minDose: 40,
      doseUnit: 'mg',
      rationale: 'NIH ODS: above UL for adults',
    ),
  },

  // ─── bleeding_disorders ──────────────────────────────────────────
  // Multiple supplements have antiplatelet / anticoagulant effects
  // that compound bleeding risk above moderate doses.
  'bleeding_disorders': {
    'omega_3': ConditionThreshold.aboveDose(
      minDose: 3000,
      doseUnit: 'mg',
      rationale:
          'NIH ODS Omega-3 (HP fact sheet): high doses (~2-15 g/day) may '
          'increase bleeding time via reduced platelet aggregation, most '
          'relevant with anticoagulants; 3 g/day is a conservative flag '
          'point (FDA deems up to 5 g/day EPA+DHA safe). (Corrected '
          '2026-07-02: prior PMID was a wrong-topic mis-cite.)',
    ),
    'fish_oil': ConditionThreshold.aboveDose(
      minDose: 3000,
      doseUnit: 'mg',
      rationale: 'same as omega_3',
    ),
    'vitamin_e': ConditionThreshold.aboveDose(
      minDose: 400,
      doseUnit: 'IU',
      rationale:
          'NIH ODS Vitamin E (HP fact sheet): clinically significant bleeding '
          'effects (platelet inhibition, antagonism of vitamin K-dependent '
          'clotting) probably exceed 400 IU/day, especially with '
          'anticoagulants. (Corrected 2026-07-02: prior PMID was about '
          'all-cause mortality, not the bleeding mechanism cited — replaced '
          'after live-API content verification.)',
    ),
    'ginkgo': ConditionThreshold.aboveDose(
      minDose: 120,
      doseUnit: 'mg',
      rationale:
          'NCCIH Ginkgo: may increase bleeding risk, especially with '
          'anticoagulant/antiplatelet drugs (human studies + case reports); '
          '120 mg is a conservative flag point. (Corrected 2026-07-02: prior '
          'PMID was a wrong-topic mis-cite.)',
    ),
    'garlic': ConditionThreshold.aboveDose(
      minDose: 600,
      doseUnit: 'mg',
      rationale: 'NIH ODS: high-dose extracts inhibit platelet aggregation',
    ),
    'curcumin': ConditionThreshold.aboveDose(
      minDose: 1000,
      doseUnit: 'mg',
      rationale:
          'MSK About Herbs (Turmeric): may increase bleeding risk, especially '
          'with anticoagulant/antiplatelet drugs (preclinical data + case '
          'report); sources give no validated mg/day cutoff, so 1 g is a '
          'conservative flag point. (Corrected 2026-07-02: prior PMID was a '
          'wrong-topic mis-cite.)',
    ),
  },

  // ─── surgery_scheduled ──────────────────────────────────────────
  // Same anticoagulant-supplement concerns; stop ~2 weeks pre-op.
  'surgery_scheduled': {
    'omega_3': ConditionThreshold.aboveDose(
      minDose: 3000,
      doseUnit: 'mg',
      rationale:
          'ASA peri-operative guidance: discontinue high-dose 2 weeks pre-op',
    ),
    'fish_oil': ConditionThreshold.aboveDose(
      minDose: 3000,
      doseUnit: 'mg',
      rationale: 'same as omega_3',
    ),
    'vitamin_e': ConditionThreshold.aboveDose(
      minDose: 400,
      doseUnit: 'IU',
      rationale: 'ASA: discontinue 2 weeks pre-op',
    ),
    'ginkgo': ConditionThreshold.aboveDose(
      minDose: 120,
      doseUnit: 'mg',
      rationale: 'ASA: discontinue 2 weeks pre-op',
    ),
    'garlic': ConditionThreshold.aboveDose(
      minDose: 600,
      doseUnit: 'mg',
      rationale: 'ASA: discontinue 2 weeks pre-op',
    ),
  },

  // ─── thyroid_disorder ────────────────────────────────────────────
  'thyroid_disorder': {
    'iodine': ConditionThreshold.aboveDose(
      minDose: 150,
      doseUnit: 'mcg',
      rationale:
          'NIH ODS: excess intake destabilizes both hyper- and hypo-thyroidism',
    ),
    'selenium': ConditionThreshold.positive(
      rationale:
          'NIH ODS Selenium (HP fact sheet): some trials show selenium lowers '
          'thyroid antibodies (TPOAb) in autoimmune thyroiditis, but evidence '
          'on clinical benefit is mixed and does not support routine use; flag '
          'only above UL. (Corrected 2026-07-02: prior PMID was a wrong-topic '
          'mis-cite.)',
    ),
  },

  // ─── seizure_disorder ────────────────────────────────────────────
  'seizure_disorder': {
    // High-dose B6 alters anticonvulsant levels — therapeutic doses
    // (under 100 mg) are fine.
    'vitamin_b6': ConditionThreshold.aboveDose(
      minDose: 100,
      doseUnit: 'mg',
      rationale:
          'NIH ODS Vitamin B6 (HP fact sheet): pyridoxine 200 mg/day can '
          'reduce phenytoin and phenobarbital serum levels (whether lower '
          'doses do is unknown); 100 mg is a conservative flag point. '
          '(Corrected 2026-07-02: prior PMID was a wrong-topic mis-cite.)',
    ),
  },

  // ─── high_cholesterol ────────────────────────────────────────────
  'high_cholesterol': {
    'omega_3': ConditionThreshold.positive(
      rationale: 'AHA: triglyceride-lowering at 2-4 g/day, beneficial',
    ),
    'fish_oil': ConditionThreshold.positive(rationale: 'same as omega_3'),
    'niacin': ConditionThreshold.positive(
      rationale: 'AHA: prescription-strength lowers LDL / raises HDL',
    ),
  },

  // heart_disease, liver_disease, autoimmune intentionally absent for
  // V1 — pairs there are too case-by-case (e.g., autoimmune × selenium
  // depends on which autoimmune disease) to encode without specialist
  // input. Backlog B6 covers expansion.
};

/// Look up a threshold entry for the given (condition, ingredient)
/// pair. Returns `null` when there's no entry — caller should fall
/// through to existing behavior (typically: fire the warning).
///
/// `ingredientName` accepts the raw value from the pipeline blob
/// (`'Vitamin D'`, `'Magnesium Glycinate'`, etc.) — internally it's
/// normalized to the same canonical lowercase + underscore form used
/// elsewhere in the app (matches `prettifyIngredientName`'s reverse
/// direction).
ConditionThreshold? lookupConditionThreshold({
  required String conditionId,
  required String ingredientName,
}) {
  final canonical = canonicalizeIngredientName(ingredientName);
  if (canonical.isEmpty) return null;
  final table = conditionThresholds[conditionId.trim().toLowerCase()];
  if (table == null) return null;

  // Direct hit on the full canonical name.
  final direct = table[canonical];
  if (direct != null) return direct;

  // T16.2f (2026-04-30) — parenthetical-strip fallback. Pipeline names
  // commonly embed latin names / sources / percentages in parens
  // (`'Cinnamon (Cinnamomum cassia) extract'`, `'Curcumin (95%)'`).
  // Sean's PureLean Pure Pack live walkthrough caught the gap: a
  // direct cinnamon_extract entry didn't match the pipeline's
  // `cinnamon_cinnamomum_cassia_extract` canonical. Stripping the
  // parenthetical first gives us the simpler `cinnamon_extract` form
  // that the table keys on. Only re-tried when the strip actually
  // changes the string — keeps the common-case lookup at one map hit.
  final stripped = ingredientName.replaceAll(RegExp(r'\([^)]*\)'), ' ').trim();
  if (stripped != ingredientName.trim() && stripped.isNotEmpty) {
    final canonicalStripped = canonicalizeIngredientName(stripped);
    if (canonicalStripped.isNotEmpty && canonicalStripped != canonical) {
      final fallback = table[canonicalStripped];
      if (fallback != null) return fallback;
    }
  }

  return null;
}

/// Canonicalize a free-text ingredient name to the lowercase +
/// underscore-joined form used in the threshold table keys.
///
/// `'Vitamin D'`                       → `'vitamin_d'`
/// `'Magnesium Glycinate'`             → `'magnesium_glycinate'`
/// `'  Iron '`                         → `'iron'`
/// `'Vitamin-D3'`                      → `'vitamin_d3'`
/// `'Cinnamon Bark Extract, Dried'`    → `'cinnamon_bark_extract_dried'`
/// `'Vitamin C (as ascorbic acid)'`    → `'vitamin_c_as_ascorbic_acid'`
///
/// **T16.2e (2026-04-30) — punctuation strip:** Sean's PureLean live
/// walkthrough surfaced "Cinnamon Bark Extract, Dried" leaking through
/// the §7 condition_summary surface even after we added cinnamon_*
/// positive entries. Pre-T16.2e the canonicalizer only collapsed
/// whitespace and hyphens, so the comma+space survived as literal
/// `,_dried` characters in the key. Pipeline names commonly carry
/// trailing descriptor punctuation (`", Dried"`, `" (USP)"`,
/// `", powder."`) that the table side never matches. Strip the lot at
/// the boundary so the table keys can stay clean.
String canonicalizeIngredientName(String raw) {
  final trimmed = raw.trim().toLowerCase();
  if (trimmed.isEmpty) return '';
  // Whitespace, hyphens, AND punctuation runs all collapse to a single
  // underscore. Trailing/leading underscores are stripped after
  // collapsing so `'(USP)'` → `'usp'`, not `'_usp_'`.
  final collapsed = trimmed.replaceAll(RegExp(r'[\s\-,.;:()\[\]/]+'), '_');
  // Strip any leading/trailing underscores left behind by punctuation
  // at the edges.
  final canonical = collapsed.replaceAll(RegExp(r'^_+|_+$'), '');
  return _ingredientCanonicalAliases[canonical] ?? canonical;
}

const Map<String, String> _ingredientCanonicalAliases = {
  // DSLD and pipeline blobs use all of these for niacin depending on
  // source row. The threshold table intentionally keys the clinical
  // rule once as `niacin`, so aliases must collapse before dose lookup.
  'vitamin_b_3': 'niacin',
  'vitamin_b3': 'niacin',
  'vitamin_b_3_niacin': 'niacin',
  'vitamin_b3_niacin': 'niacin',
};

// ════════════════════════════════════════════════════════════════════
// Positive-profile bullet generator (Path A extension, 2026-04-29)
// ════════════════════════════════════════════════════════════════════
//
// Sean's design call: don't just suppress false-positive monitor flags
// (T3 + T4 do that) — actively credit the product when an ingredient
// is BENEFICIAL for the user's profile. The Personal Fit card (T12)
// will surface these as causal bullets:
//
//   • Magnesium supports your blood pressure goal
//   • Vitamin D is recommended during pregnancy
//
// Architecturally clean because the `positive` entries in the
// threshold table are LITERALLY the list of beneficial pairings — zero
// new data, just a thin function on top.
//
// Two phrase templates by condition type:
//   - Medical states (pregnancy / lactation / TTC) → "is recommended
//     during X" (clinically accurate; these aren't "goals" the user
//     chose, they're medical states)
//   - Managed conditions / chronic states          → "supports your X
//     goal/health" (goal-driven framing matches the user's mental
//     model — they're trying to manage BP/blood sugar/cholesterol)

/// Per-condition phrase appended after the ingredient display name to
/// form the bullet copy. Only conditions that have at least one
/// `positive` threshold entry need a phrase here. Adding a `positive`
/// entry without a phrase is silently skipped (forward-compat: future
/// table growth doesn't break the bullet generator).
const Map<String, String> _conditionSupportPhrase = {
  // Medical states — "is recommended during X" framing.
  'pregnancy': 'is recommended during pregnancy',
  'lactation': 'is recommended during breastfeeding',
  'ttc': 'is recommended during pre-conception',
  // Managed / chronic conditions — "supports your X" framing.
  'diabetes': 'supports your blood sugar goal',
  'hypertension': 'supports your blood pressure goal',
  'thyroid_disorder': 'supports your thyroid health',
  'high_cholesterol': 'supports your cholesterol goal',
};

/// Build "[Ingredient] [phrase]" bullets for the Personal Fit card,
/// covering every (condition × ingredient) pair where the threshold
/// table marks the ingredient as `positive` for the condition.
///
/// **Output ordering:** condition-major, in the order [userConditionIds]
/// arrives (so caller controls priority — usually their own profile
/// order, which reflects what they care about most).
///
/// **Dedup rule:** at most ONE bullet per condition. Products often
/// list multiple forms of the same nutrient (`Magnesium`, `Magnesium
/// Glycinate`, `Magnesium Citrate` all in one label) — emitting three
/// near-identical "supports your blood pressure goal" bullets would
/// burn the card's 2-bullet budget on one nutrient. We pick the first
/// matching ingredient per condition and stop.
///
/// **Skip rules:**
/// - Conditions absent from [_conditionSupportPhrase] are skipped (no
///   phrase = no bullet). Future-proofs against adding `positive`
///   entries to conditions we haven't decided phrasing for yet.
/// - Ingredients without a matching threshold entry → fall through.
/// - Ingredients with `neutral` directionality → fall through (those
///   are dose-gated risks, not benefits).
List<String> generatePositiveProfileBullets({
  required List<String> ingredientNames,
  required List<String> userConditionIds,
}) {
  if (ingredientNames.isEmpty || userConditionIds.isEmpty) return const [];

  final bullets = <String>[];
  final seenConditions = <String>{};

  for (final rawCondition in userConditionIds) {
    final condition = rawCondition.trim().toLowerCase();
    if (seenConditions.contains(condition)) continue;
    final phrase = _conditionSupportPhrase[condition];
    if (phrase == null) continue;

    for (final ingredient in ingredientNames) {
      final entry = lookupConditionThreshold(
        conditionId: condition,
        ingredientName: ingredient,
      );
      if (entry?.directionality == NutrientDirectionality.positive) {
        bullets.add('${_displayName(ingredient)} $phrase');
        seenConditions.add(condition);
        break; // Max one bullet per condition.
      }
    }
  }

  return bullets;
}

/// Title-case the ingredient for display. Mirrors the canonicalize
/// rules so `'magnesium_glycinate'` and `'Magnesium Glycinate'` and
/// `'magnesium-glycinate'` all render the same.
///
/// Hand-rolled instead of importing `prettifyIngredientName` because
/// that helper doesn't normalize hyphens — it would title-case
/// `'vitamin-d'` to `'Vitamin-d'` (lowercase 'd'). Inlining keeps this
/// file self-contained and consistent with [canonicalizeIngredientName].
String _displayName(String raw) {
  final canonical = canonicalizeIngredientName(raw);
  if (canonical.isEmpty) return '';
  // Branded shorthands commonly appearing in pipeline data — preserve
  // their canonical casing rather than title-casing to "Vitamin D3"
  // (already correct) or worse "Vitamin_d3".
  const brandedForms = <String, String>{
    'vitamin_d': 'Vitamin D',
    'vitamin_d3': 'Vitamin D3',
    'vitamin_a': 'Vitamin A',
    'vitamin_b6': 'Vitamin B6',
    'vitamin_b12': 'Vitamin B12',
    'vitamin_c': 'Vitamin C',
    'vitamin_e': 'Vitamin E',
    'vitamin_k': 'Vitamin K',
    'vitamin_k2': 'Vitamin K2',
    'omega_3': 'Omega-3',
  };
  final branded = brandedForms[canonical];
  if (branded != null) return branded;

  return canonical
      .split('_')
      .where((part) => part.isNotEmpty)
      .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
      .join(' ');
}
