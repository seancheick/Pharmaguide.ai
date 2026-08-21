import 'package:drift/drift.dart';

/// Embedded key/value metadata for the bundled interaction DB.
///
/// Mirrors `interaction_db_metadata` in `interaction_db.sqlite`. The
/// pipeline writes the following keys (M2 / spec §6.3 step 8, as
/// amended in T7 to drop sha256_checksum):
///
/// - `schema_version`            — e.g. "1.0.0"
/// - `built_at`                  — ISO 8601 UTC build timestamp
/// - `source_drafts_count`       — curated draft rows after verification
/// - `source_suppai_count`       — supp.ai pairs after filtering
/// - `total_interactions`        — final row count after dedup/conflict
/// - `override_count`            — manual overrides applied
/// - `resolved_conflict_count`   — severity conflicts auto-resolved
/// - `interaction_db_version`    — human-readable release tag
/// - `pipeline_version`          — pipeline build version
/// - `min_app_version`           — min Flutter app version that can read it
/// - `profile_warning_rules_count` — schema-2 embedded rule row count
/// - `profile_warning_rules_version` — authored rule-registry version
///
/// **`sha256_checksum` is intentionally NOT embedded.** Storing the
/// file's own hash inside the file would invalidate the hash. The
/// adjacent `interaction_db_manifest.json` is the sole source of truth
/// for the file checksum (T7 fix).
@DataClassName('InteractionDbMetadataRow')
class InteractionDbMetadataTable extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column> get primaryKey => {key};

  @override
  String get tableName => 'interaction_db_metadata';
}
