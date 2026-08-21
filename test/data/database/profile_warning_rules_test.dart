import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/data/database/interaction_database.dart';

void main() {
  test(
    'local interaction DB resolves versioned profile warning rules',
    () async {
      final database = InteractionDatabase.memory();
      addTearDown(database.close);
      const rule = <String, dynamic>{
        'id': 'RULE_TEST_MAGNESIUM_DIABETES',
        'subject_ref': <String, dynamic>{
          'db': 'ingredient_quality_map',
          'canonical_id': 'magnesium',
        },
        'condition_rules': <Map<String, dynamic>>[
          <String, dynamic>{
            'condition_id': 'diabetes',
            'severity': 'caution',
            'mechanism': 'Test mechanism',
          },
        ],
      };
      await database.customStatement(
        'INSERT INTO profile_warning_rules '
        '(rule_id, canonical_id, source_version, rule_json) VALUES (?, ?, ?, ?)',
        <Object?>[
          'RULE_TEST_MAGNESIUM_DIABETES',
          'magnesium',
          '6.2.4',
          jsonEncode(rule),
        ],
      );

      final resolved = await database.lookupProfileWarningRules(const <String>{
        'RULE_TEST_MAGNESIUM_DIABETES',
      });

      expect(resolved.keys, <String>{'RULE_TEST_MAGNESIUM_DIABETES'});
      expect(
        resolved['RULE_TEST_MAGNESIUM_DIABETES']?['subject_ref'],
        rule['subject_ref'],
      );
      expect(await database.countProfileWarningRules(), 1);
    },
  );

  test('empty profile warning lookup does not query the database', () async {
    final database = InteractionDatabase.memory();
    addTearDown(database.close);

    expect(await database.lookupProfileWarningRules(const <String>{}), isEmpty);
  });
}
