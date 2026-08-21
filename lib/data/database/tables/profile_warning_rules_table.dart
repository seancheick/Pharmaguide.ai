import 'package:drift/drift.dart';

/// Versioned profile-gated warning rules embedded in interaction DB schema 2.
///
/// Schema-3 catalog blobs retain only compact rule references. The prose and
/// evidence are resolved from this local table so the app never needs a
/// network request to render a safety warning.
@DataClassName('ProfileWarningRuleRow')
class ProfileWarningRules extends Table {
  TextColumn get ruleId => text().named('rule_id')();
  TextColumn get canonicalId => text().named('canonical_id')();
  TextColumn get sourceVersion => text().named('source_version')();
  TextColumn get ruleJson => text().named('rule_json')();

  @override
  Set<Column> get primaryKey => {ruleId};

  @override
  String get tableName => 'profile_warning_rules';
}
