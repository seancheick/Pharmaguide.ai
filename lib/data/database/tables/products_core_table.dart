import 'package:drift/drift.dart';

/// Products core table — 88 columns matching pipeline export schema v1.3.0.
/// This table is READ-ONLY in the app (populated by pipeline via Supabase).
class ProductsCore extends Table {
  // Identity
  TextColumn get dsldId => text().named('dsld_id')();
  TextColumn get productName => text().named('product_name')();
  TextColumn get brandName => text().named('brand_name').nullable()();
  TextColumn get upcSku => text().named('upc_sku').nullable()();
  TextColumn get imageUrl => text().named('image_url').nullable()();
  IntColumn get imageIsPdf =>
      integer().named('image_is_pdf').withDefault(const Constant(0))();
  TextColumn get thumbnailKey =>
      text().named('thumbnail_key').nullable()();
  TextColumn get detailBlobSha256 =>
      text().named('detail_blob_sha256').nullable()();
  TextColumn get interactionSummaryHint =>
      text().named('interaction_summary_hint').nullable()();
  TextColumn get decisionHighlights =>
      text().named('decision_highlights').nullable()();

  // Product status
  TextColumn get productStatus =>
      text().named('product_status').nullable()();
  TextColumn get discontinuedDate =>
      text().named('discontinued_date').nullable()();
  TextColumn get formFactor =>
      text().named('form_factor').nullable()();
  TextColumn get supplementType =>
      text().named('supplement_type').nullable()();

  // Scores
  RealColumn get scoreQuality80 =>
      real().named('score_quality_80').nullable()();
  TextColumn get scoreDisplay80 =>
      text().named('score_display_80').nullable()();
  TextColumn get scoreDisplay100Equivalent =>
      text().named('score_display_100_equivalent').nullable()();
  RealColumn get score100Equivalent =>
      real().named('score_100_equivalent').nullable()();
  TextColumn get grade => text().named('grade').nullable()();
  TextColumn get verdict => text().named('verdict').nullable()();
  TextColumn get safetyVerdict =>
      text().named('safety_verdict').nullable()();
  RealColumn get mappedCoverage =>
      real().named('mapped_coverage').nullable()();

  // Section scores
  RealColumn get scoreIngredientQuality =>
      real().named('score_ingredient_quality').nullable()();
  RealColumn get scoreIngredientQualityMax =>
      real().named('score_ingredient_quality_max').nullable()();
  RealColumn get scoreSafetyPurity =>
      real().named('score_safety_purity').nullable()();
  RealColumn get scoreSafetyPurityMax =>
      real().named('score_safety_purity_max').nullable()();
  RealColumn get scoreEvidenceResearch =>
      real().named('score_evidence_research').nullable()();
  RealColumn get scoreEvidenceResearchMax =>
      real().named('score_evidence_research_max').nullable()();
  RealColumn get scoreBrandTrust =>
      real().named('score_brand_trust').nullable()();
  RealColumn get scoreBrandTrustMax =>
      real().named('score_brand_trust_max').nullable()();

  // Percentile
  RealColumn get percentileRank =>
      real().named('percentile_rank').nullable()();
  RealColumn get percentileTopPct =>
      real().named('percentile_top_pct').nullable()();
  TextColumn get percentileCategory =>
      text().named('percentile_category').nullable()();
  TextColumn get percentileLabel =>
      text().named('percentile_label').nullable()();
  IntColumn get percentileCohort =>
      integer().named('percentile_cohort').nullable()();

  // Dietary flags
  IntColumn get isGlutenFree =>
      integer().named('is_gluten_free').withDefault(const Constant(0))();
  IntColumn get isDairyFree =>
      integer().named('is_dairy_free').withDefault(const Constant(0))();
  IntColumn get isSoyFree =>
      integer().named('is_soy_free').withDefault(const Constant(0))();
  IntColumn get isVegan =>
      integer().named('is_vegan').withDefault(const Constant(0))();
  IntColumn get isVegetarian =>
      integer().named('is_vegetarian').withDefault(const Constant(0))();
  IntColumn get isOrganic =>
      integer().named('is_organic').withDefault(const Constant(0))();
  IntColumn get isNonGmo =>
      integer().named('is_non_gmo').withDefault(const Constant(0))();

  // Safety flags
  IntColumn get hasBannedSubstance => integer()
      .named('has_banned_substance')
      .withDefault(const Constant(0))();
  IntColumn get hasRecalledIngredient => integer()
      .named('has_recalled_ingredient')
      .withDefault(const Constant(0))();
  IntColumn get hasHarmfulAdditives => integer()
      .named('has_harmful_additives')
      .withDefault(const Constant(0))();
  IntColumn get hasAllergenRisks => integer()
      .named('has_allergen_risks')
      .withDefault(const Constant(0))();
  TextColumn get blockingReason =>
      text().named('blocking_reason').nullable()();

  // Health-specific
  IntColumn get isProbiotic =>
      integer().named('is_probiotic').withDefault(const Constant(0))();
  IntColumn get containsSugar =>
      integer().named('contains_sugar').withDefault(const Constant(0))();
  IntColumn get containsSodium =>
      integer().named('contains_sodium').withDefault(const Constant(0))();
  IntColumn get diabetesFriendly => integer()
      .named('diabetes_friendly')
      .withDefault(const Constant(0))();
  IntColumn get hypertensionFriendly => integer()
      .named('hypertension_friendly')
      .withDefault(const Constant(0))();

  // Manufacturer
  IntColumn get isTrustedManufacturer => integer()
      .named('is_trusted_manufacturer')
      .withDefault(const Constant(0))();
  IntColumn get hasThirdPartyTesting => integer()
      .named('has_third_party_testing')
      .withDefault(const Constant(0))();
  IntColumn get hasFullDisclosure => integer()
      .named('has_full_disclosure')
      .withDefault(const Constant(0))();

  // JSON arrays (stored as TEXT, parsed in Dart)
  TextColumn get certPrograms =>
      text().named('cert_programs').nullable()();
  TextColumn get badges => text().named('badges').nullable()();
  TextColumn get topWarnings =>
      text().named('top_warnings').nullable()();
  TextColumn get flags => text().named('flags').nullable()();

  // v1.3.0: Stack Interaction
  TextColumn get ingredientFingerprint =>
      text().named('ingredient_fingerprint').nullable()();
  TextColumn get keyNutrientsSummary =>
      text().named('key_nutrients_summary').nullable()();
  IntColumn get containsStimulants => integer()
      .named('contains_stimulants')
      .withDefault(const Constant(0))();
  IntColumn get containsSedatives => integer()
      .named('contains_sedatives')
      .withDefault(const Constant(0))();
  IntColumn get containsBloodThinners => integer()
      .named('contains_blood_thinners')
      .withDefault(const Constant(0))();

  // v1.3.0: Social Sharing
  TextColumn get shareTitle =>
      text().named('share_title').nullable()();
  TextColumn get shareDescription =>
      text().named('share_description').nullable()();
  TextColumn get shareHighlights =>
      text().named('share_highlights').nullable()();
  TextColumn get shareOgImageUrl =>
      text().named('share_og_image_url').nullable()();

  // v1.3.0: Search & Filter
  TextColumn get primaryCategory =>
      text().named('primary_category').nullable()();
  TextColumn get secondaryCategories =>
      text().named('secondary_categories').nullable()();
  IntColumn get containsOmega3 => integer()
      .named('contains_omega3')
      .withDefault(const Constant(0))();
  IntColumn get containsProbiotics => integer()
      .named('contains_probiotics')
      .withDefault(const Constant(0))();
  IntColumn get containsCollagen => integer()
      .named('contains_collagen')
      .withDefault(const Constant(0))();
  IntColumn get containsAdaptogens => integer()
      .named('contains_adaptogens')
      .withDefault(const Constant(0))();
  IntColumn get containsNootropics => integer()
      .named('contains_nootropics')
      .withDefault(const Constant(0))();
  TextColumn get keyIngredientTags =>
      text().named('key_ingredient_tags').nullable()();

  // v1.3.0: Goal Matching
  TextColumn get goalMatches =>
      text().named('goal_matches').nullable()();
  RealColumn get goalMatchConfidence =>
      real().named('goal_match_confidence').nullable()();

  // v1.3.0: Dosing
  TextColumn get dosingSummary =>
      text().named('dosing_summary').nullable()();
  IntColumn get servingsPerContainer =>
      integer().named('servings_per_container').nullable()();

  // v1.3.0: Allergen
  TextColumn get allergenSummary =>
      text().named('allergen_summary').nullable()();

  // Metadata
  TextColumn get scoringVersion =>
      text().named('scoring_version').nullable()();
  TextColumn get outputSchemaVersion =>
      text().named('output_schema_version').nullable()();
  TextColumn get enrichmentVersion =>
      text().named('enrichment_version').nullable()();
  TextColumn get scoredDate =>
      text().named('scored_date').nullable()();
  TextColumn get exportVersion => text().named('export_version')();
  TextColumn get exportedAt => text().named('exported_at')();

  @override
  Set<Column> get primaryKey => {dsldId};

  @override
  String get tableName => 'products_core';
}
