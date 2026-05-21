// Release gate: bundled catalog canonical IDs must drive Quick Check hits.

import 'dart:io';

import 'package:drift/drift.dart' as drift;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:pharmaguide/core/constants/severity.dart';
import 'package:pharmaguide/data/database/core_database.dart';
import 'package:pharmaguide/data/database/interaction_database.dart';
import 'package:pharmaguide/features/quick_check/quick_check_logic.dart';

Future<File> _materializeAsset(String assetPath, Directory dir) async {
  final data = await rootBundle.load(assetPath);
  final bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  final file = File(p.join(dir.path, p.basename(assetPath)));
  await file.writeAsBytes(bytes, flush: true);
  return file;
}

Future<ProductsCoreData> _productForCanonicalId(
  CoreDatabase db,
  String canonicalId,
) async {
  final row = await db
      .customSelect(
        '''
        SELECT dsld_id FROM products_core
        WHERE EXISTS (
          SELECT 1 FROM json_each(key_ingredient_tags)
          WHERE lower(value) = lower(?)
        )
        ORDER BY dsld_id
        LIMIT 1
        ''',
        variables: [drift.Variable.withString(canonicalId)],
        readsFrom: {db.productsCore},
      )
      .getSingleOrNull();
  expect(row, isNotNull, reason: 'No bundled product exposes $canonicalId');
  final product = await db.findById(row!.data['dsld_id'] as String);
  expect(product, isNotNull);
  return product!;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'bundled catalog exposes canonical IDs that fire curated Quick Check',
    () async {
      final tmpDir = await Directory.systemTemp.createTemp('quick-check-gate');
      addTearDown(() => tmpDir.delete(recursive: true));

      final coreFile = await _materializeAsset(
        'assets/db/pharmaguide_core.db',
        tmpDir,
      );
      final interactionFile = await _materializeAsset(
        'assets/db/interaction_db.sqlite',
        tmpDir,
      );

      final coreDb = CoreDatabase.open(coreFile.path);
      final interactionDb = InteractionDatabase.open(interactionFile.path);
      addTearDown(coreDb.close);
      addTearDown(interactionDb.close);

      final fixtures =
          <
            ({
              String canonicalId,
              String medicationName,
              String rxcui,
              List<String> drugClasses,
              Severity expectedSeverity,
            })
          >[
            (
              canonicalId: 'potassium',
              medicationName: 'Lisinopril',
              rxcui: '29046',
              drugClasses: ['class:ace_inhibitors'],
              expectedSeverity: Severity.avoid,
            ),
            (
              canonicalId: 'st_johns_wort',
              medicationName: 'Sertraline',
              rxcui: '36437',
              drugClasses: ['class:ssris'],
              expectedSeverity: Severity.contraindicated,
            ),
            (
              canonicalId: 'magnesium',
              medicationName: 'Omeprazole',
              rxcui: '7646',
              drugClasses: ['class:antacids'],
              expectedSeverity: Severity.caution,
            ),
            (
              canonicalId: 'calcium',
              medicationName: 'Levothyroxine',
              rxcui: '10582',
              drugClasses: <String>[],
              expectedSeverity: Severity.avoid,
            ),
            (
              canonicalId: 'iron',
              medicationName: 'Levothyroxine',
              rxcui: '10582',
              drugClasses: <String>[],
              expectedSeverity: Severity.avoid,
            ),
            (
              canonicalId: 'vitamin_k',
              medicationName: 'Warfarin',
              rxcui: '11289',
              drugClasses: ['class:anticoagulants'],
              expectedSeverity: Severity.avoid,
            ),
            (
              canonicalId: 'ashwagandha',
              medicationName: 'Metformin',
              rxcui: '6809',
              drugClasses: ['class:diabetes_meds'],
              expectedSeverity: Severity.caution,
            ),
            (
              canonicalId: 'turmeric',
              medicationName: 'Warfarin',
              rxcui: '11289',
              drugClasses: ['class:anticoagulants'],
              expectedSeverity: Severity.caution,
            ),
            (
              canonicalId: 'banned_red_yeast_rice',
              medicationName: 'Atorvastatin',
              rxcui: '83367',
              drugClasses: ['class:statins'],
              expectedSeverity: Severity.avoid,
            ),
            (
              canonicalId: 'banned_cbd_us',
              medicationName: 'Warfarin',
              rxcui: '11289',
              drugClasses: ['class:anticoagulants'],
              expectedSeverity: Severity.caution,
            ),
            (
              canonicalId: 'nootropic_vinpocetine',
              medicationName: 'Warfarin',
              rxcui: '11289',
              drugClasses: ['class:anticoagulants'],
              expectedSeverity: Severity.caution,
            ),
            (
              canonicalId: 'horse_chestnut_seed',
              medicationName: 'Warfarin',
              rxcui: '11289',
              drugClasses: ['class:anticoagulants'],
              expectedSeverity: Severity.caution,
            ),
          ];

      for (final fixture in fixtures) {
        final supplement = QuickCheckItem.supplement(
          await _productForCanonicalId(coreDb, fixture.canonicalId),
        );
        final medication = QuickCheckItem.medication(
          name: fixture.medicationName,
          rxcui: fixture.rxcui,
          drugClasses: fixture.drugClasses,
        );

        final results = await runQuickCheckPair(
          supplement,
          medication,
          interactionDb,
        );

        expect(
          results,
          isNotEmpty,
          reason:
              '${fixture.canonicalId} should fire a curated Quick Check rule',
        );
        expect(
          results.first.severity,
          fixture.expectedSeverity,
          reason:
              '${fixture.canonicalId} should render the expected severity tier',
        );
      }
    },
  );

  test(
    'bundled coconut products have ingredient identity without false incomplete state',
    () async {
      final tmpDir = await Directory.systemTemp.createTemp('quick-check-clean');
      addTearDown(() => tmpDir.delete(recursive: true));

      final coreFile = await _materializeAsset(
        'assets/db/pharmaguide_core.db',
        tmpDir,
      );
      final interactionFile = await _materializeAsset(
        'assets/db/interaction_db.sqlite',
        tmpDir,
      );

      final coreDb = CoreDatabase.open(coreFile.path);
      final interactionDb = InteractionDatabase.open(interactionFile.path);
      addTearDown(coreDb.close);
      addTearDown(interactionDb.close);

      final supplement = QuickCheckItem.supplement(
        await _productForCanonicalId(coreDb, 'pii_extra_virgin_coconut_oil'),
      );
      final medication = QuickCheckItem.medication(
        name: 'Warfarin',
        rxcui: '11289',
        drugClasses: const ['class:anticoagulants'],
      );

      expect(supplement.hasInteractionIdentity, isTrue);

      final results = await runQuickCheckPair(
        supplement,
        medication,
        interactionDb,
      );

      expect(
        results,
        isEmpty,
        reason:
            'Coconut should be a resolved clean check, not ingredient-data incomplete',
      );
    },
  );
}
