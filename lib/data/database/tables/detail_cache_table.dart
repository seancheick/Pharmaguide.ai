import 'package:drift/drift.dart';

/// Product detail cache — stores full detail blob JSON for offline access.
/// Keyed by [dsldId], with SHA-256 for freshness checking.
class DetailCache extends Table {
  TextColumn get dsldId => text().named('dsld_id')();
  TextColumn get blobJson =>
      text().named('blob_json')(); // Full detail blob JSON
  TextColumn get sha256 => text().nullable()();
  DateTimeColumn get cachedAt => dateTime()
      .named('cached_at')
      .withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {dsldId};

  @override
  String get tableName => 'product_detail_cache';
}
