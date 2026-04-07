import 'package:drift/drift.dart';

/// User favorites — bookmarked products for quick access.
class UserFavorites extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get dsldId => text().named('dsld_id')();
  DateTimeColumn get addedAt =>
      dateTime().named('added_at').withDefault(currentDateAndTime)();

  @override
  String get tableName => 'user_favorites';
}
