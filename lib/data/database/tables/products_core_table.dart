import 'package:drift/drift.dart';

/// Products core table — exact generated app projection for export schema 2.4.
/// Server/reporting columns and compatibility aliases remain in SQLite but are
/// deliberately absent from Drift. The projection is generated from the
/// pipeline's `scripts/core_export_model.py` and enforced by a release test.
///
/// Intentionally undeclared examples include:
///   - `ingredients_text` (v1.6.x, 2026-05-12) — indexed by `products_fts`
///     for ingredient-name search; read via raw SQL in core_database.dart
///     so the `.g.dart` doesn't need build_runner regen alongside pipeline
///     schema bumps.
///   - `quality_score_version`, `scoring_engine_version`,
///     `classification_schema_version`, `v4_config_fingerprint` —
///     pipeline provenance/version metadata the app never reads.
/// This table is READ-ONLY in the app (populated by pipeline via Supabase).
///
/// v1.3.1 added (2026-04): net_contents_quantity, net_contents_unit
///   Powers the refill-reminder feature. `net_contents_quantity` is the
///   physical unit count in the bottle (e.g. 60 for a 60-capsule bottle);
///   `net_contents_unit` is the verbatim label unit ("Capsule(s)", "mL",
///   "Gram(s)", etc.). days_until_empty divides net_contents_quantity by the
///   amount consumed per day.
///
///   Do NOT derive the daily serving count from `servingSizes[0]`. A product
///   can declare several serving rows (e.g. a 5 mL child serving and a 10 mL
///   adult serving), and element zero is the child row on those — DSLD 317115
///   would report a 1-3/day child regimen instead of its 1-4/day adult one.
///   The pipeline resolves this once, in scripts/serving_frequency.py, using
///   the highest-quantity (adult) row; consume the value it publishes rather
///   than re-deriving it here.
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

  // Scores — v4 production contract (export schema 2.4.0+).
  TextColumn get grade => text().named('grade').nullable()();
  TextColumn get verdict => text().named('verdict').nullable()();
  TextColumn get safetyVerdict => text().named('safety_verdict').nullable()();
  RealColumn get mappedCoverage => real().named('mapped_coverage').nullable()();

  // `quality_score_v4_100` is the whole-number canonical shipped score
  // (NULL when status != 'scored'); `quality_score_status` drives
  // display/eligibility; `quality_tier` is the Elite…Poor band;
  // `quality_score_suppressed_reason` says why a suppressed score is NULL.
  RealColumn get qualityScoreV4100 =>
      real().named('quality_score_v4_100').nullable()();
  TextColumn get qualityScoreStatus =>
      text().named('quality_score_status').nullable()();
  // Independent catalog states. Neither field includes personalized
  // medication/condition/allergy logic, and product_safety_status never
  // derives from the numeric quality score.
  TextColumn get productSafetyStatus =>
      text().named('product_safety_status').nullable()();
  TextColumn get qualityAssessmentStatus =>
      text().named('quality_assessment_status').nullable()();
  TextColumn get qualityTier => text().named('quality_tier').nullable()();
  TextColumn get qualityScoreSuppressedReason =>
      text().named('quality_score_suppressed_reason').nullable()();
  TextColumn get v4Module => text().named('v4_module').nullable()();
  TextColumn get qualityScoreConfidence =>
      text().named('quality_score_confidence').nullable()();
  TextColumn get scoreUnavailableReason =>
      text().named('score_unavailable_reason').nullable()();
  TextColumn get routeConfidence =>
      text().named('route_confidence').nullable()();
  TextColumn get scoreModelVersion =>
      text().named('score_model_version').nullable()();

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

  /// Compact product-level release summary.
  ///
  /// This is not a second consumer-warning feed: non-blocked products use the
  /// profile-gated detail-blob warning contract. The app reads this field only
  /// as a blocked-product fallback for regulatory source links.
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
  // v2.x: goals present but below effective dose (Coverage "Partially
  // supported" bucket). JSON array of GOAL_* ids, disjoint from goal_matches.
  TextColumn get goalMatchesUnderdosed =>
      text().named('goal_matches_underdosed').nullable()();

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
