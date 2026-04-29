import 'package:drift/drift.dart';

/// User profile table — stores the single user profile with health preferences.
class UserProfiles extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get nickname => text().nullable()();
  TextColumn get ageBracket => text().named('age_bracket').nullable()();
  TextColumn get sex => text().nullable()();
  TextColumn get goals =>
      text().withDefault(const Constant('[]'))(); // JSON array
  TextColumn get conditions =>
      text().withDefault(const Constant('[]'))(); // JSON array
  TextColumn get drugClasses => text()
      .named('drug_classes')
      .withDefault(const Constant('[]'))(); // JSON array
  TextColumn get allergens =>
      text().withDefault(const Constant('[]'))(); // JSON array
  DateTimeColumn get createdAt =>
      dateTime().named('created_at').withDefault(currentDateAndTime)();
  DateTimeColumn get lastUpdated =>
      dateTime().named('last_updated').withDefault(currentDateAndTime)();

  @override
  String get tableName => 'user_profile';
}
