import 'package:drift/drift.dart';

/// Tier-2 supp.ai research pair corpus.
///
/// Mirrors `research_pairs` in `interaction_db.sqlite`. Sourced from
/// the supp.ai extraction pipeline (see pipeline `ingest_suppai.py`),
/// filtered to ≥2 papers AND at least one human study to keep the
/// bundle under §11.3 size targets.
///
/// **These rows are NOT safety warnings.** supp.ai is an extractive
/// corpus of "X and Y appear in N papers together" — there is no
/// curated severity, no mechanism, no management text. The app must
/// surface them only as "research available" info chips, never as
/// AVOID/CAUTION banners. Spec §11.2 + §9.
///
/// Severity-bearing rows live in [Interactions]. The two tiers must
/// stay strictly separated in the UI.
@DataClassName('ResearchPairRow')
class ResearchPairs extends Table {
  /// Stable id of the form `CUI_A-CUI_B` with `CUI_A < CUI_B`
  /// lexicographically. Pipeline guarantees this ordering so the
  /// pair is direction-agnostic.
  TextColumn get pairId => text().named('pair_id')();

  TextColumn get cuiA => text().named('cui_a')();
  TextColumn get cuiB => text().named('cui_b')();
  TextColumn get entityAName => text().named('entity_a_name')();
  TextColumn get entityBName => text().named('entity_b_name')();
  TextColumn get entityAType => text().named('entity_a_type')();
  TextColumn get entityBType => text().named('entity_b_type')();

  TextColumn get canonicalIdA =>
      text().named('canonical_id_a').nullable()();
  TextColumn get canonicalIdB =>
      text().named('canonical_id_b').nullable()();
  TextColumn get rxcuiA => text().named('rxcui_a').nullable()();
  TextColumn get rxcuiB => text().named('rxcui_b').nullable()();

  IntColumn get paperCount => integer().named('paper_count')();
  IntColumn get humanStudyCount => integer().named('human_study_count')();
  IntColumn get clinicalStudyCount =>
      integer().named('clinical_study_count')();

  /// JSON array of up to 3 representative sentences from supp.ai.
  TextColumn get topSentencesJson => text().named('top_sentences_json')();

  /// JSON array of up to 5 PMIDs.
  TextColumn get topPmidsJson => text().named('top_pmids_json')();

  IntColumn get latestPaperYear =>
      integer().named('latest_paper_year').nullable()();

  TextColumn get source =>
      text().withDefault(const Constant('suppai'))();
  TextColumn get lastUpdated => text().named('last_updated')();

  @override
  Set<Column> get primaryKey => {pairId};

  @override
  String get tableName => 'research_pairs';
}
