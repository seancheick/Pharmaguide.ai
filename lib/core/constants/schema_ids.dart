/// Frozen schema IDs — must match pipeline exactly.
/// Source: clinical_risk_taxonomy.json, user_goals_to_clusters.json,
/// rda_optimal_uls.json, allergens.json
abstract final class SchemaIds {
  static const ageBrackets = ['14-18', '19-30', '31-50', '51-70', '71+'];

  static const sexOptions = ['Male', 'Female', 'Other', 'Prefer not to say'];

  // ---------------------------------------------------------------------------
  // "None" sentinels — Phase 11.7L.B.6.
  //
  // Each canonical list (goals/conditions/drugClasses/allergens) accepts a
  // single sentinel ID that means "the user EXPLICITLY chose nothing"
  // (distinct from "the user hasn't touched this surface yet" — an empty
  // list). The sentinels never match a pipeline-side IngredientFact or
  // allergen alias, so they're inert in the matcher; the UI reads them
  // via the `has<...>None` helpers on `ProfileState` to show explicit
  // "No specific goal right now" / "No known allergies" affordances.
  //
  // Mutual exclusion is enforced in `ProfileNotifier`'s toggle methods:
  // setting the sentinel clears the rest of the list, and toggling any
  // real ID clears the sentinel. Persisted as part of the existing
  // list columns — no drift migration required.
  // ---------------------------------------------------------------------------
  static const goalNone = 'GOAL_NONE';
  static const conditionNone = 'CONDITION_NONE';
  static const drugClassNone = 'DRUG_CLASS_NONE';
  static const allergenNone = 'ALLERGEN_NONE';

  /// All four sentinel IDs — useful for filter helpers (e.g. "drop
  /// sentinels before sending the list to the evaluator").
  static const Set<String> noneSentinels = {
    goalNone,
    conditionNone,
    drugClassNone,
    allergenNone,
  };

  static const conditions = [
    'pregnancy',
    'lactation',
    'ttc',
    'surgery_scheduled',
    'hypertension',
    'heart_disease',
    'diabetes',
    'bleeding_disorders',
    'kidney_disease',
    'liver_disease',
    'thyroid_disorder',
    'autoimmune',
    'seizure_disorder',
    'high_cholesterol',
  ];

  static const conditionLabels = {
    'pregnancy': 'Pregnancy',
    'lactation': 'Breastfeeding',
    'ttc': 'TTC (Trying to Conceive)',
    'surgery_scheduled': 'Upcoming Surgery',
    'hypertension': 'High Blood Pressure',
    'heart_disease': 'Heart Disease',
    'diabetes': 'Diabetes',
    'bleeding_disorders': 'Bleeding Disorders',
    'kidney_disease': 'Kidney Disease',
    'liver_disease': 'Liver Disease',
    'thyroid_disorder': 'Thyroid Condition',
    'autoimmune': 'Autoimmune Condition',
    'seizure_disorder': 'Epilepsy/Seizures',
    'high_cholesterol': 'High Cholesterol',
  };

  /// v6.0 profile flags — additive to [conditions]. The pipeline's
  /// `clinical_risk_taxonomy.json::profile_flags[]` contract has 7 flag
  /// IDs total. Four of them (`pregnant`, `breastfeeding`,
  /// `trying_to_conceive`, `surgery_scheduled`) are derived from the
  /// existing condition IDs at evaluator time
  /// (see ProfileState.evaluatorProfileFlags); the remaining 3 are
  /// distinct history/transient states and live as their own selectable
  /// flags here:
  ///   post_op_recovery     — currently in post-operative recovery (vs.
  ///                          surgery_scheduled = pre-op)
  ///   hypoglycemia_history — past low-blood-sugar events; escalates
  ///                          diabetes-medication interaction severity
  ///                          (e.g., berberine baseline caution → avoid)
  ///   bleeding_history     — past bleeding events / family history;
  ///                          distinct from `bleeding_disorders` condition
  ///                          (which is an active diagnosis). Escalates
  ///                          antiplatelet/anticoagulant interactions.
  static const profileFlags = [
    'post_op_recovery',
    'hypoglycemia_history',
    'bleeding_history',
    'severely_immunocompromised',
  ];

  static const profileFlagLabels = {
    'post_op_recovery': 'Post-Op Recovery',
    'hypoglycemia_history': 'Hypoglycemia History',
    'bleeding_history': 'Bleeding History',
    'severely_immunocompromised':
        'Severely immunocompromised (chemo, transplant)',
  };

  static const drugClasses = [
    'anticoagulants',
    'antiplatelets',
    'nsaids',
    'antihypertensives',
    'hypoglycemics_high_risk',
    'hypoglycemics_lower_risk',
    'hypoglycemics_unknown',
    'thyroid_medications',
    'sedatives',
    'immunosuppressants',
    'statins',
    'antidepressants_ssri_snri',
    'maois',
    'cardiac_glycosides',
    'anticholinergics',
  ];

  static const drugClassLabels = {
    'anticoagulants': 'Blood thinners',
    'antiplatelets': 'Antiplatelet medication',
    'nsaids': 'NSAIDs (Ibuprofen, Aspirin regularly)',
    'antihypertensives': 'Blood pressure medication',
    'hypoglycemics_high_risk': 'Higher low-blood-sugar risk diabetes meds',
    'hypoglycemics_lower_risk': 'Lower low-blood-sugar risk diabetes meds',
    'hypoglycemics_unknown': 'Not sure / other diabetes medication',
    'thyroid_medications': 'Thyroid medication',
    'sedatives': 'Sedatives / Sleep medication',
    'immunosuppressants': 'Immunosuppressants',
    'statins': 'Statins / Cholesterol medication',
    'antidepressants_ssri_snri': 'Antidepressants (SSRIs/SNRIs)',
    'maois': 'MAOIs',
    'cardiac_glycosides': 'Digoxin / Heart rhythm medication',
    'anticholinergics': 'Anticholinergic medication',
  };

  static const goals = [
    'GOAL_SLEEP_QUALITY',
    'GOAL_REDUCE_STRESS_ANXIETY',
    'GOAL_INCREASE_ENERGY',
    'GOAL_DIGESTIVE_HEALTH',
    'GOAL_WEIGHT_MANAGEMENT',
    'GOAL_CARDIOVASCULAR_HEART_HEALTH',
    'GOAL_HEALTHY_AGING_LONGEVITY',
    'GOAL_BLOOD_SUGAR_SUPPORT',
    'GOAL_IMMUNE_SUPPORT',
    'GOAL_FOCUS_MENTAL_CLARITY',
    'GOAL_MOOD_EMOTIONAL_WELLNESS',
    'GOAL_MUSCLE_GROWTH_RECOVERY',
    'GOAL_JOINT_BONE_MOBILITY',
    'GOAL_SKIN_HAIR_NAILS',
    'GOAL_LIVER_DETOX',
    'GOAL_PRENATAL_PREGNANCY',
    'GOAL_HORMONAL_BALANCE',
    'GOAL_EYE_VISION_HEALTH',
  ];

  static const goalLabels = {
    'GOAL_SLEEP_QUALITY': 'Sleep Quality',
    'GOAL_REDUCE_STRESS_ANXIETY': 'Reduce Stress/Anxiety',
    'GOAL_INCREASE_ENERGY': 'Increase Energy',
    'GOAL_DIGESTIVE_HEALTH': 'Digestive Health',
    'GOAL_WEIGHT_MANAGEMENT': 'Weight Management',
    'GOAL_CARDIOVASCULAR_HEART_HEALTH': 'Cardiovascular/Heart Health',
    'GOAL_HEALTHY_AGING_LONGEVITY': 'Healthy Aging/Longevity',
    'GOAL_BLOOD_SUGAR_SUPPORT': 'Blood Sugar Support',
    'GOAL_IMMUNE_SUPPORT': 'Immune Support',
    'GOAL_FOCUS_MENTAL_CLARITY': 'Focus & Mental Clarity',
    'GOAL_MOOD_EMOTIONAL_WELLNESS': 'Mood & Emotional Wellness',
    'GOAL_MUSCLE_GROWTH_RECOVERY': 'Muscle Growth & Recovery',
    'GOAL_JOINT_BONE_MOBILITY': 'Joint & Bone Mobility',
    'GOAL_SKIN_HAIR_NAILS': 'Skin, Hair, & Nails',
    'GOAL_LIVER_DETOX': 'Liver & Detox Support',
    'GOAL_PRENATAL_PREGNANCY': 'Prenatal/Pregnancy Support',
    'GOAL_HORMONAL_BALANCE': 'Hormonal Balance',
    'GOAL_EYE_VISION_HEALTH': 'Eye & Vision Health',
  };

  // ---------------------------------------------------------------------------
  // Canonical allergen IDs — source of truth is
  // `dsld_clean/scripts/data/allergens.json`. Promoted to SchemaIds in
  // Phase 11.7L.B.6 so the v2 ProfileSetup sheet can list every
  // canonical allergen individually (the legacy screen curated them
  // into 13 chips, hiding 4 IDs under group toggles — see
  // `migrateLegacyAllergenIds` for the previous expansion logic).
  //
  // Order is "common → less common" for chip render order. Keep in
  // lockstep with the `supported` Set in
  // `ProfileState.migrateLegacyAllergenIds`.
  // ---------------------------------------------------------------------------
  static const allergens = [
    'ALLERGEN_MILK',
    'ALLERGEN_EGGS',
    'ALLERGEN_FISH',
    'ALLERGEN_CRUSTACEANS',
    'ALLERGEN_MOLLUSCS',
    'ALLERGEN_TREE_NUTS',
    'ALLERGEN_PEANUTS',
    'ALLERGEN_WHEAT',
    'ALLERGEN_BARLEY',
    'ALLERGEN_RYE',
    'ALLERGEN_OATS',
    'ALLERGEN_SOY',
    'ALLERGEN_SESAME',
    'ALLERGEN_SULFITES',
    'ALLERGEN_CELERY',
    'ALLERGEN_MUSTARD',
    'ALLERGEN_LUPIN',
  ];

  static const allergenLabels = {
    'ALLERGEN_MILK': 'Milk / Dairy',
    'ALLERGEN_EGGS': 'Eggs',
    'ALLERGEN_FISH': 'Fish',
    'ALLERGEN_CRUSTACEANS': 'Crustaceans (crab, shrimp, lobster)',
    'ALLERGEN_MOLLUSCS': 'Molluscs (clams, mussels, oysters)',
    'ALLERGEN_TREE_NUTS': 'Tree nuts',
    'ALLERGEN_PEANUTS': 'Peanuts',
    'ALLERGEN_WHEAT': 'Wheat',
    'ALLERGEN_BARLEY': 'Barley',
    'ALLERGEN_RYE': 'Rye',
    'ALLERGEN_OATS': 'Oats',
    'ALLERGEN_SOY': 'Soy',
    'ALLERGEN_SESAME': 'Sesame',
    'ALLERGEN_SULFITES': 'Sulfites',
    'ALLERGEN_CELERY': 'Celery',
    'ALLERGEN_MUSTARD': 'Mustard',
    'ALLERGEN_LUPIN': 'Lupin',
  };

  static const goalPriorities = {
    'GOAL_SLEEP_QUALITY': 'high',
    'GOAL_REDUCE_STRESS_ANXIETY': 'high',
    'GOAL_INCREASE_ENERGY': 'high',
    'GOAL_DIGESTIVE_HEALTH': 'medium',
    'GOAL_WEIGHT_MANAGEMENT': 'high',
    'GOAL_CARDIOVASCULAR_HEART_HEALTH': 'high',
    'GOAL_HEALTHY_AGING_LONGEVITY': 'high',
    'GOAL_BLOOD_SUGAR_SUPPORT': 'medium',
    'GOAL_IMMUNE_SUPPORT': 'high',
    'GOAL_FOCUS_MENTAL_CLARITY': 'high',
    'GOAL_MOOD_EMOTIONAL_WELLNESS': 'medium',
    'GOAL_MUSCLE_GROWTH_RECOVERY': 'medium',
    'GOAL_JOINT_BONE_MOBILITY': 'medium',
    'GOAL_SKIN_HAIR_NAILS': 'low',
    'GOAL_LIVER_DETOX': 'low',
    'GOAL_PRENATAL_PREGNANCY': 'high',
    'GOAL_HORMONAL_BALANCE': 'medium',
    'GOAL_EYE_VISION_HEALTH': 'low',
  };
}
