import 'package:drift/drift.dart';

/// User supplement/medication stack — tracks items the user is taking.
/// Supports soft-delete via [deletedAt] and Supabase sync via [syncedAt].
class UserStacksLocal extends Table {
  TextColumn get id => text()(); // UUID
  TextColumn get type => text()
      .withDefault(const Constant('supplement'))(); // supplement | medication
  TextColumn get name => text()();
  TextColumn get dsldId => text().named('dsld_id').nullable()();
  TextColumn get rxcui => text().nullable()();
  TextColumn get ingredientKeys =>
      text().named('ingredient_keys').nullable()(); // JSON array
  TextColumn get drugClassesCol =>
      text().named('drug_classes').nullable()(); // JSON array
  TextColumn get dosage => text().nullable()();
  TextColumn get frequency => text().nullable()();
  DateTimeColumn get addedAt =>
      dateTime().named('added_at').withDefault(currentDateAndTime)();
  DateTimeColumn get clientUpdatedAt => dateTime()
      .named('client_updated_at')
      .withDefault(currentDateAndTime)();
  DateTimeColumn get deletedAt =>
      dateTime().named('deleted_at').nullable()();
  DateTimeColumn get syncedAt =>
      dateTime().named('synced_at').nullable()();

  @override
  Set<Column> get primaryKey => {id};

  @override
  String get tableName => 'user_stacks_local';
}
