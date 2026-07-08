import 'package:drift/drift.dart';

/// Curated drug↔supplement / supplement↔supplement interaction rows.
///
/// Mirrors `interactions` in `interaction_db.sqlite` (built by the
/// pipeline's `build_interaction_db.py`, schema_version 1.0.0).
///
/// READ-ONLY in the app — every row is shipped pre-built and verified
/// by the pipeline's `verify_interactions.py` gates (RxNorm/UMLS CUI
/// validation, severity normalization, Major+ source gate). The app
/// must never write to this table.
///
/// Column shapes match `scripts/build_interaction_db.SCHEMA_SQL`
/// exactly. Snake_case is forced via `.named()` so the generated Drift
/// query SQL matches the underlying schema. Anything that drifts here
/// will surface as a runtime "no such column" error on first lookup.
@DataClassName('InteractionRow')
class Interactions extends Table {
  // Identity
  TextColumn get id => text()();

  // Agent 1 (always the drug-side when one party is a drug, after
  // verify_interactions.py direction-normalizes Med-Sup ↔ Sup-Med).
  TextColumn get agent1Type => text().named('agent1_type')();
  TextColumn get agent1Name => text().named('agent1_name')();
  TextColumn get agent1Id => text().named('agent1_id')();
  TextColumn get agent1CanonicalId =>
      text().named('agent1_canonical_id').nullable()();
  TextColumn get agent1DrugClass =>
      text().named('agent1_drug_class').nullable()();

  // Agent 2
  TextColumn get agent2Type => text().named('agent2_type')();
  TextColumn get agent2Name => text().named('agent2_name')();
  TextColumn get agent2Id => text().named('agent2_id')();
  TextColumn get agent2CanonicalId =>
      text().named('agent2_canonical_id').nullable()();
  TextColumn get agent2DrugClass =>
      text().named('agent2_drug_class').nullable()();

  // Clinical fields
  TextColumn get severity => text()(); // contraindicated|avoid|caution|monitor
  TextColumn get effectType => text()
      .named('effect_type')
      .nullable()(); // inhibitor|enhancer|additive|neutral
  TextColumn get mechanism => text()();
  TextColumn get management => text()();
  TextColumn get evidenceLevel => text()
      .named('evidence_level')
      .nullable()(); // established|probable|theoretical

  // Provenance arrays — stored as JSON text, parsed at the model layer.
  TextColumn get sourceUrlsJson => text().named('source_urls_json')();
  TextColumn get sourcePmidsJson => text().named('source_pmids_json')();

  // Behavior flags
  IntColumn get bidirectional => integer().withDefault(const Constant(1))();
  IntColumn get doseDependent =>
      integer().named('dose_dependent').withDefault(const Constant(0))();
  TextColumn get doseThresholdText =>
      text().named('dose_threshold_text').nullable()();
  TextColumn get direction => text().nullable()();
  TextColumn get materiality => text().nullable()();
  TextColumn get doseThresholdJson =>
      text().named('dose_threshold_json').nullable()();

  // Audit / origin
  TextColumn get typeAuthored => text().named('type_authored')();
  TextColumn get source => text()(); // 'curated'|'suppai'|'override'
  TextColumn get provenance => text()(); // E3: nih_ods|nccih|dailymed|...

  // E4 tombstone columns — every row carries lineage so retired
  // interactions can stay in the DB for audit while being filtered
  // out of live queries via WHERE retired_at IS NULL.
  TextColumn get versionAdded => text().named('version_added')();
  TextColumn get versionLastModified => text().named('version_last_modified')();
  TextColumn get retiredAt => text().named('retired_at').nullable()();
  TextColumn get retiredReason => text().named('retired_reason').nullable()();
  TextColumn get lastUpdated => text().named('last_updated')();

  // Optional food-advisory display fields. Present only for rows where
  // alert_style='food_advisory_note'; clinical pairwise rows leave these
  // null and render through mechanism/management as before.
  TextColumn get alertStyle => text().named('alert_style').nullable()();
  TextColumn get noteBody => text().named('note_body').nullable()();
  TextColumn get practicalGuidance =>
      text().named('practical_guidance').nullable()();

  @override
  Set<Column> get primaryKey => {id};

  @override
  String get tableName => 'interactions';
}
