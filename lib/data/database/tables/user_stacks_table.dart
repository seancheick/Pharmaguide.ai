import 'package:drift/drift.dart';

/// User supplement/medication stack — tracks items the user is taking.
/// Supports soft-delete via [deletedAt] and Supabase sync via [syncedAt].
class UserStacksLocal extends Table {
  TextColumn get id => text()(); // UUID
  TextColumn get type => text().withDefault(
    const Constant('supplement'),
  )(); // supplement | medication
  TextColumn get name => text()();
  TextColumn get dsldId => text().named('dsld_id').nullable()();
  TextColumn get rxcui => text().nullable()();
  TextColumn get ingredientKeys =>
      text().named('ingredient_keys').nullable()(); // JSON array
  TextColumn get drugClassesCol =>
      text().named('drug_classes').nullable()(); // JSON array
  /// Generic ingredient RXCUI for brand→generic interaction matching.
  /// When user adds "Synthroid" (rxcui=224920), this stores "10582"
  /// (levothyroxine IN) so curated interactions keyed on the generic fire.
  TextColumn get genericRxcui => text().named('generic_rxcui').nullable()();

  /// JSON array of individual ingredient RXCUIs for combination drugs.
  /// E.g., Lisinopril/HCTZ → ["29046", "5487"]. Each ingredient is
  /// matched independently against the curated interaction DB.
  TextColumn get ingredientRxcuisCol =>
      text().named('ingredient_rxcuis').nullable()(); // JSON array
  TextColumn get dosage => text().nullable()();
  TextColumn get frequency => text().nullable()();
  DateTimeColumn get addedAt =>
      dateTime().named('added_at').withDefault(currentDateAndTime)();
  DateTimeColumn get clientUpdatedAt =>
      dateTime().named('client_updated_at').withDefault(currentDateAndTime)();
  DateTimeColumn get deletedAt => dateTime().named('deleted_at').nullable()();
  DateTimeColumn get syncedAt => dateTime().named('synced_at').nullable()();

  /// A terminal remote integrity error blocks only this exact local version
  /// from automatic retry. Any later edit updates [clientUpdatedAt] and
  /// makes it eligible again.
  DateTimeColumn get syncBlockedAt =>
      dateTime().named('sync_blocked_at').nullable()();

  @override
  Set<Column> get primaryKey => {id};

  @override
  String get tableName => 'user_stacks_local';
}
