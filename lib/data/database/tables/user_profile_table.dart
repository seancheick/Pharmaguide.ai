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
  /// v6.0 profile flags — additive to conditions[]. Stores transient
  /// or history-flag IDs that the v6.0 profile_gate evaluates against
  /// (post_op_recovery, hypoglycemia_history, bleeding_history). The
  /// existing pregnant/breastfeeding/ttc/surgery_scheduled flags are
  /// derived from `conditions[]` for backward compatibility — Flutter
  /// maps them into the evaluator's profile_flags set internally.
  TextColumn get profileFlags => text()
      .named('profile_flags')
      .withDefault(const Constant('[]'))(); // JSON array
  DateTimeColumn get createdAt =>
      dateTime().named('created_at').withDefault(currentDateAndTime)();
  DateTimeColumn get lastUpdated =>
      dateTime().named('last_updated').withDefault(currentDateAndTime)();

  @override
  String get tableName => 'user_profile';
}
