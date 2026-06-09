import 'package:drift/drift.dart';

/// Products core table — 91 typed columns matching pipeline export schema
/// v1.3.2+. The pipeline DB also ships an additional `ingredients_text`
/// column (v1.6.x, 2026-05-12; column 92) indexed by `products_fts` for
/// ingredient-name search — it's read via raw SQL in core_database.dart
/// rather than declared here, so the `.g.dart` doesn't need build_runner
/// regen alongside pipeline schema bumps.
/// This table is READ-ONLY in the app (populated by pipeline via Supabase).
///
/// v1.3.1 added (2026-04): net_contents_quantity, net_contents_unit
///   Powers the refill-reminder feature. `net_contents_quantity` is the
///   physical unit count in the bottle (e.g. 60 for a 60-capsule bottle);
///   `net_contents_unit` is the verbatim label unit ("Capsule(s)", "mL",
///   "Gram(s)", etc.). Compute days_until_empty =
///     net_contents_quantity / (servingSizes[0].maxQuantity *
///                              servingSizes[0].maxDailyServings)
///
/// v1.3.2 added (2026-04): calories_per_serving
///   Hybrid nutrition surface: calories is the highest-value user filter
///   so it lives as its own column. The other four macros
///   (total_carbohydrates_g, total_fat_g, protein_g, dietary_fiber_g) are
///   in the detail_blob under `nutrition_detail` for forward compat without
///   schema bloat. Promote them to columns later if usage justifies it.
class ProductsCore extends Table {
  // Identity
  TextColumn get dsldId => text().named('dsld_id')();
  TextColumn get productName => text().named('product_name')();
  TextColumn get brandName => text().named('brand_name').nullable()();
  TextColumn get upcSku => text().named('upc_sku').nullable()();
  TextColumn get imageUrl => text().named('image_url').nullable()();
  IntColumn get imageIsPdf => integer().named('image_is_pdf').nullable()();
  TextColumn get thumbnailKey => text().named('thumbnail_key').nullable()();
  TextColumn get imageThumbnailUrl =>
      text().named('image_thumbnail_url').nullable()();
  TextColumn get detailBlobSha256 =>
      text().named('detail_blob_sha256').nullable()();
  TextColumn get interactionSummaryHint =>
      text().named('interaction_summary_hint').nullable()();
  TextColumn get decisionHighlights =>
      text().named('decision_highlights').nullable()();

  // Product status
  TextColumn get productStatus => text().named('product_status').nullable()();
  TextColumn get discontinuedDate =>
      text().named('discontinued_date').nullable()();
  TextColumn get formFactor => text().named('form_factor').nullable()();
  TextColumn get supplementType => text().named('supplement_type').nullable()();

  // Scores
  //
  // DUAL-SCHEMA (v3 ↔ v4): every score column here is nullable so the SAME
  // Drift table opens against BOTH a legacy v3 bundle (has score_quality_80,
  // no v4 columns) and a v4 build (export schema 2.0.0 — dropped /80, added
  // the v4 /100 contract). `CoreDatabase.beforeOpen` backfills whichever
  // side's columns are missing (see `_ensureCompatColumns`), so neither a
  // typed query nor `SELECT *` ever hits a "no such column".
  //
  // Legacy v3 /80 headline — DROPPED by the v4 build. Kept declared (nullable)
  // only so a still-shipping v3 bundle keeps reading; never the v4 source of
  // truth. Rank/display on the effective score, not this.
  RealColumn get scoreQuality80 =>
      real().named('score_quality_80').nullable()();
  TextColumn get scoreDisplay80 =>
      text().named('score_display_80').nullable()();
  TextColumn get scoreDisplay100Equivalent =>
      text().named('score_display_100_equivalent').nullable()();
  // Honest /100 mirror — present in BOTH v3 and v4. Mirrors
  // quality_score_v4_100 on a v4 build (NULL when suppressed) and carries the
  // v3 /100 on a legacy bundle, so it is the cross-schema score fallback.
  RealColumn get score100Equivalent =>
      real().named('score_100_equivalent').nullable()();
  TextColumn get grade => text().named('grade').nullable()();
  TextColumn get verdict => text().named('verdict').nullable()();
  TextColumn get safetyVerdict => text().named('safety_verdict').nullable()();
  RealColumn get mappedCoverage => real().named('mapped_coverage').nullable()();

  // v4 scoring contract (export schema 2.0.0). Nullable for dual-schema
  // reads (see note above). `quality_score_v4_100` is the canonical shipped
  // score (NULL when status != 'scored'); `quality_score_status` drives
  // display/eligibility; `quality_tier` is the Elite…Poor band;
  // `quality_score_suppressed_reason` says why a suppressed score is NULL.
  // `raw_score_v4_100` is AUDIT-ONLY — never display or rank on it.
  RealColumn get qualityScoreV4100 =>
      real().named('quality_score_v4_100').nullable()();
  TextColumn get qualityScoreStatus =>
      text().named('quality_score_status').nullable()();
  TextColumn get qualityTier => text().named('quality_tier').nullable()();
  TextColumn get qualityScoreSuppressedReason =>
      text().named('quality_score_suppressed_reason').nullable()();
  RealColumn get rawScoreV4100 => real().named('raw_score_v4_100').nullable()();
  TextColumn get v4Module => text().named('v4_module').nullable()();
  TextColumn get v4Confidence => text().named('v4_confidence').nullable()();
  TextColumn get scoreModelVersion =>
      text().named('score_model_version').nullable()();

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
  RealColumn get percentileRank => real().named('percentile_rank').nullable()();
  RealColumn get percentileTopPct =>
      real().named('percentile_top_pct').nullable()();
  TextColumn get percentileCategory =>
      text().named('percentile_category').nullable()();
  TextColumn get percentileLabel =>
      text().named('percentile_label').nullable()();
  IntColumn get percentileCohort =>
      integer().named('percentile_cohort').nullable()();

  // Dietary flags
  IntColumn get isGlutenFree => integer().named('is_gluten_free').nullable()();
  IntColumn get isDairyFree => integer().named('is_dairy_free').nullable()();
  IntColumn get isSoyFree => integer().named('is_soy_free').nullable()();
  IntColumn get isVegan => integer().named('is_vegan').nullable()();
  IntColumn get isVegetarian => integer().named('is_vegetarian').nullable()();
  IntColumn get isOrganic => integer().named('is_organic').nullable()();
  IntColumn get isNonGmo => integer().named('is_non_gmo').nullable()();

  // Safety flags
  IntColumn get hasBannedSubstance =>
      integer().named('has_banned_substance').nullable()();
  IntColumn get hasRecalledIngredient =>
      integer().named('has_recalled_ingredient').nullable()();
  IntColumn get hasHarmfulAdditives =>
      integer().named('has_harmful_additives').nullable()();
  IntColumn get hasAllergenRisks =>
      integer().named('has_allergen_risks').nullable()();
  TextColumn get blockingReason => text().named('blocking_reason').nullable()();

  // Health-specific
  IntColumn get isProbiotic => integer().named('is_probiotic').nullable()();
  IntColumn get containsSugar => integer().named('contains_sugar').nullable()();
  IntColumn get containsSodium =>
      integer().named('contains_sodium').nullable()();
  IntColumn get diabetesFriendly =>
      integer().named('diabetes_friendly').nullable()();
  IntColumn get hypertensionFriendly =>
      integer().named('hypertension_friendly').nullable()();

  // Manufacturer
  IntColumn get isTrustedManufacturer =>
      integer().named('is_trusted_manufacturer').nullable()();
  IntColumn get hasThirdPartyTesting =>
      integer().named('has_third_party_testing').nullable()();
  IntColumn get hasFullDisclosure =>
      integer().named('has_full_disclosure').nullable()();

  // JSON arrays (stored as TEXT, parsed in Dart)
  TextColumn get certPrograms => text().named('cert_programs').nullable()();
  TextColumn get badges => text().named('badges').nullable()();
  TextColumn get topWarnings => text().named('top_warnings').nullable()();
  TextColumn get flags => text().named('flags').nullable()();

  // v1.3.0: Stack Interaction
  TextColumn get ingredientFingerprint =>
      text().named('ingredient_fingerprint').nullable()();
  TextColumn get keyNutrientsSummary =>
      text().named('key_nutrients_summary').nullable()();
  IntColumn get containsStimulants =>
      integer().named('contains_stimulants').nullable()();
  IntColumn get containsSedatives =>
      integer().named('contains_sedatives').nullable()();
  IntColumn get containsBloodThinners =>
      integer().named('contains_blood_thinners').nullable()();

  // v1.3.0: Social Sharing
  TextColumn get shareTitle => text().named('share_title').nullable()();
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
  IntColumn get containsOmega3 =>
      integer().named('contains_omega3').nullable()();
  IntColumn get containsProbiotics =>
      integer().named('contains_probiotics').nullable()();
  IntColumn get containsCollagen =>
      integer().named('contains_collagen').nullable()();
  IntColumn get containsAdaptogens =>
      integer().named('contains_adaptogens').nullable()();
  IntColumn get containsNootropics =>
      integer().named('contains_nootropics').nullable()();
  TextColumn get keyIngredientTags =>
      text().named('key_ingredient_tags').nullable()();

  // NOTE (v1.6.x, 2026-05-12): the pipeline DB also carries a column
  // `ingredients_text` (aggregated active + inactive ingredient display
  // names) at position 92, indexed by `products_fts` for ingredient-name
  // search. It's intentionally NOT declared here as a typed Drift column
  // so the `.g.dart` doesn't need build_runner regen alongside pipeline
  // schema bumps. The FTS5 MATCH path picks it up automatically; the LIKE
  // fallback in core_database.dart reads it via raw customSelect SQL.

  // v1.3.0: Goal Matching
  TextColumn get goalMatches => text().named('goal_matches').nullable()();
  RealColumn get goalMatchConfidence =>
      real().named('goal_match_confidence').nullable()();

  // v1.3.0: Dosing
  TextColumn get dosingSummary => text().named('dosing_summary').nullable()();
  IntColumn get servingsPerContainer =>
      integer().named('servings_per_container').nullable()();

  // v1.3.1: Net Contents (refill reminder feature)
  RealColumn get netContentsQuantity =>
      real().named('net_contents_quantity').nullable()();
  TextColumn get netContentsUnit =>
      text().named('net_contents_unit').nullable()();

  // v1.3.0: Allergen
  TextColumn get allergenSummary =>
      text().named('allergen_summary').nullable()();

  // v1.3.2: Nutrition hybrid — calories is the one filter column;
  // carbs/fat/protein/fiber live in detail_blob.nutrition_detail
  RealColumn get caloriesPerServing =>
      real().named('calories_per_serving').nullable()();

  // Metadata
  TextColumn get scoringVersion => text().named('scoring_version').nullable()();
  TextColumn get outputSchemaVersion =>
      text().named('output_schema_version').nullable()();
  TextColumn get enrichmentVersion =>
      text().named('enrichment_version').nullable()();
  TextColumn get scoredDate => text().named('scored_date').nullable()();
  TextColumn get exportVersion => text().named('export_version')();
  TextColumn get exportedAt => text().named('exported_at')();

  @override
  Set<Column> get primaryKey => {dsldId};

  @override
  String get tableName => 'products_core';
}
