import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/data/database/interaction_database.dart';
import 'package:pharmaguide/data/providers/database_providers.dart';
import 'package:pharmaguide/features/product_detail/providers/detail_blob_provider.dart';
import 'package:pharmaguide/features/product_detail/providers/profile_warning_rule_provider.dart';

const _ruleId = 'RULE_TEST_MAGNESIUM_DIABETES';
const _rule = <String, dynamic>{
  'id': _ruleId,
  'subject_ref': <String, dynamic>{'canonical_id': 'magnesium'},
  'condition_rules': <Map<String, dynamic>>[
    <String, dynamic>{
      'condition_id': 'diabetes',
      'severity': 'caution',
      'evidence_level': 'probable',
      'mechanism': 'Magnesium may affect glucose control.',
      'action': 'Monitor glucose with your clinician.',
      'sources': <String>[],
      'alert_headline': 'May affect glucose control',
      'alert_body': 'Discuss magnesium use with your clinician.',
      'informational_note': 'Magnesium may be relevant for diabetes.',
      'direction': 'harmful',
      'materiality': 'presence',
    },
  ],
  'drug_class_rules': <Map<String, dynamic>>[],
};

const _blob = <String, dynamic>{
  'warning_rule_refs': <Map<String, dynamic>>[
    <String, dynamic>{
      'rule_id': _ruleId,
      'type': 'interaction',
      'severity': 'caution',
      'condition_ids': <String>['diabetes'],
      'drug_class_ids': <String>[],
      'ingredient_name': 'Magnesium',
      'ingredient_canonical_id': 'magnesium',
      'direction': 'harmful',
      'materiality': 'presence',
    },
  ],
};

void main() {
  test('provider resolves compact refs into interaction warnings', () async {
    final database = InteractionDatabase.memory();
    addTearDown(database.close);
    await database.customStatement(
      'INSERT INTO profile_warning_rules '
      '(rule_id, canonical_id, source_version, rule_json) VALUES (?, ?, ?, ?)',
      <Object?>[_ruleId, 'magnesium', '6.2.4', jsonEncode(_rule)],
    );
    final container = ProviderContainer(
      overrides: [
        interactionDatabaseProvider.overrideWithValue(database),
        detailBlobProvider.overrideWith((ref, dsldId) async => _blob),
      ],
    );
    addTearDown(container.dispose);
    final subscription = container.listen(
      profileWarningRuleWarningsProvider('123'),
      (_, _) {},
    );
    addTearDown(subscription.close);

    final warnings = await container.read(
      profileWarningRuleWarningsProvider('123').future,
    );

    expect(warnings, hasLength(1));
    expect(warnings.single.title, 'Magnesium / diabetes');
    expect(warnings.single.mechanism, 'Magnesium may affect glucose control.');
  });

  test(
    'missing local rule surfaces an error instead of an empty result',
    () async {
      final database = InteractionDatabase.memory();
      addTearDown(database.close);
      final container = ProviderContainer(
        overrides: [
          interactionDatabaseProvider.overrideWithValue(database),
          detailBlobProvider.overrideWith((ref, dsldId) async => _blob),
        ],
      );
      addTearDown(container.dispose);
      final subscription = container.listen(
        profileWarningRuleWarningsProvider('123'),
        (_, _) {},
      );
      addTearDown(subscription.close);

      await expectLater(
        container.read(profileWarningRuleWarningsProvider('123').future),
        throwsFormatException,
      );
    },
  );

  test(
    'schema 2.4 blob without refs does not require interaction DB',
    () async {
      final container = ProviderContainer(
        overrides: [
          detailBlobProvider.overrideWith(
            (ref, dsldId) async => const <String, dynamic>{
              'warnings': <Map<String, dynamic>>[],
            },
          ),
        ],
      );
      addTearDown(container.dispose);
      final subscription = container.listen(
        profileWarningRuleWarningsProvider('123'),
        (_, _) {},
      );
      addTearDown(subscription.close);

      expect(
        await container.read(profileWarningRuleWarningsProvider('123').future),
        isEmpty,
      );
    },
  );
}
