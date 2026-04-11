import 'package:drift/drift.dart';

/// Drug class → member RXCUI map.
///
/// Mirrors `drug_class_map` in `interaction_db.sqlite`. Populated by
/// `build_interaction_db.py` from `scripts/data/drug_classes.json`,
/// which is itself seeded from the NLM RxClass API.
///
/// Used by:
///   1. M3 `lookupByDrugClass` — given a `class:statins`-style id,
///      return every interaction row that names that class as either
///      agent.
///   2. M4 medication entry — when a user types a drug, the app fetches
///      its classes from RxNorm and uses this table to enumerate the
///      sibling drugs that share an interaction profile.
@DataClassName('DrugClassMapRow')
class DrugClassMap extends Table {
  TextColumn get classId => text().named('class_id')();
  TextColumn get className => text().named('class_name')();

  /// JSON array of member RXCUIs (e.g. `["1539", "36567", ...]`).
  /// Stored as text because Drift has no first-class array type and
  /// the membership list is read in bulk, never queried by element.
  TextColumn get drugRxcuisJson => text().named('drug_rxcuis_json')();

  TextColumn get source => text()(); // 'rxclass' | 'manual'
  TextColumn get lastUpdated => text().named('last_updated')();

  @override
  Set<Column> get primaryKey => {classId};

  @override
  String get tableName => 'drug_class_map';
}
