// Release gate: bundled catalog canonical IDs must drive Quick Check hits.

@Tags(['bundle'])
library;

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
              String expectedInteractionId,
            })
          >[
            (
              canonicalId: 'potassium',
              medicationName: 'Lisinopril',
              rxcui: '29046',
              drugClasses: ['class:ace_inhibitors'],
              expectedInteractionId: 'DSI_ACEI_POTASSIUM',
            ),
            (
              canonicalId: 'st_johns_wort',
              medicationName: 'Sertraline',
              rxcui: '36437',
              drugClasses: ['class:ssris'],
              expectedInteractionId: 'DSI_SSRI_SJW',
            ),
            (
              canonicalId: 'calcium',
              medicationName: 'Levothyroxine',
              rxcui: '10582',
              drugClasses: <String>[],
              expectedInteractionId: 'DSI_LEVOTHYROXINE_CALCIUM',
            ),
            (
              canonicalId: 'iron',
              medicationName: 'Levothyroxine',
              rxcui: '10582',
              drugClasses: <String>[],
              expectedInteractionId: 'DSI_LEVOTHYROXINE_IRON',
            ),
            (
              canonicalId: 'vitamin_k',
              medicationName: 'Warfarin',
              rxcui: '11289',
              drugClasses: ['class:anticoagulants'],
              expectedInteractionId: 'DSI_WAR_VITK',
            ),
            (
              canonicalId: 'ashwagandha',
              medicationName: 'Metformin',
              rxcui: '6809',
              drugClasses: ['class:diabetes_meds'],
              expectedInteractionId: 'DSI_DM_ASHWAGANDHA',
            ),
            (
              canonicalId: 'turmeric',
              medicationName: 'Warfarin',
              rxcui: '11289',
              drugClasses: ['class:anticoagulants'],
              expectedInteractionId: 'DSI_WAR_TURMERIC',
            ),
            (
              canonicalId: 'red_yeast_rice',
              medicationName: 'Atorvastatin',
              rxcui: '83367',
              drugClasses: ['class:statins'],
              expectedInteractionId: 'DSI_STATINS_RYR',
            ),
            (
              canonicalId: 'horse_chestnut_seed',
              medicationName: 'Warfarin',
              rxcui: '11289',
              drugClasses: ['class:anticoagulants'],
              expectedInteractionId: 'DSI_ANTICOAG_HORSE_CHESTNUT',
            ),
          ];

      final liveVinpocetine = await coreDb
          .customSelect(
            '''
            SELECT
              COUNT(*) AS n,
              SUM(CASE WHEN safety_verdict = 'CAUTION' THEN 1 ELSE 0 END)
                AS caution_n,
              SUM(CASE WHEN quality_score_status = 'scored' THEN 1 ELSE 0 END)
                AS scored_n,
              SUM(CASE WHEN blocking_reason IS NOT NULL THEN 1 ELSE 0 END)
                AS blocked_n
            FROM products_core
            WHERE EXISTS (
              SELECT 1 FROM json_each(key_ingredient_tags)
              WHERE lower(value) = 'vinpocetine'
            )
            ''',
            readsFrom: {coreDb.productsCore},
          )
          .getSingle();
      final liveVinpocetineCount = liveVinpocetine.read<int>('n');
      expect(liveVinpocetineCount, greaterThan(0));
      expect(
        liveVinpocetine.read<int>('caution_n'),
        liveVinpocetineCount,
        reason: 'the reviewed FDA vinpocetine policy must render as CAUTION',
      );
      expect(
        liveVinpocetine.read<int>('scored_n'),
        liveVinpocetineCount,
        reason: 'reviewed vinpocetine products must remain fully scored',
      );
      expect(
        liveVinpocetine.read<int>('blocked_n'),
        0,
        reason:
            'tentative legal status must not leak into the hard-blocking '
            'reason surface',
      );

      for (final fixture in fixtures) {
        // This gate verifies consumer parity, not a second clinical policy.
        // CI hydrates the published DB; local validation may stage a newer
        // candidate. Assert the exact authored enum without the production
        // severity parser so malformed source or consumer-softened values fail.
        final authored = await interactionDb
            .customSelect(
              'SELECT severity FROM interactions WHERE id = ? '
              'AND retired_at IS NULL',
              variables: [
                drift.Variable.withString(fixture.expectedInteractionId),
              ],
              readsFrom: {interactionDb.interactions},
            )
            .getSingle();
        final authoredSeverity = authored.read<String>('severity');
        expect(
          Severity.values.map((severity) => severity.name),
          contains(authoredSeverity),
          reason: '${fixture.expectedInteractionId} must author a valid enum',
        );
        final expectedSeverity = Severity.values.byName(authoredSeverity);
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
          results.map((r) => r.id),
          contains(fixture.expectedInteractionId),
          reason:
              '${fixture.canonicalId} should fire ${fixture.expectedInteractionId}',
        );
        final result = results.singleWhere(
          (r) => r.id == fixture.expectedInteractionId,
        );
        expect(
          result.severity,
          expectedSeverity,
          reason:
              '${fixture.canonicalId} must retain its exact authored severity',
        );
      }

      final suppressedPpiMagnesium = await runQuickCheckPair(
        QuickCheckItem.supplement(
          await _productForCanonicalId(coreDb, 'magnesium'),
        ),
        QuickCheckItem.medication(
          name: 'Omeprazole',
          rxcui: '7646',
          drugClasses: const ['class:proton_pump_inhibitors'],
        ),
        interactionDb,
      );
      expect(
        suppressedPpiMagnesium,
        isEmpty,
        reason:
            'PPI → magnesium is a suppressed medication-depletion record, '
            'not an active pairwise Quick Check interaction',
      );
    },
  );

  test(
    'bundled CBD interaction remains available without a catalog product',
    () async {
      // Catalog membership is not the interaction-rule contract. The current
      // catalog has no CBD product; a retained stack item must still be checked.
      final tmpDir = await Directory.systemTemp.createTemp('quick-check-cbd');
      addTearDown(() => tmpDir.delete(recursive: true));
      final interactionFile = await _materializeAsset(
        'assets/db/interaction_db.sqlite',
        tmpDir,
      );
      final interactionDb = InteractionDatabase.open(interactionFile.path);
      addTearDown(interactionDb.close);
      final results = await runQuickCheckPair(
        QuickCheckItem.supplement(
          const ProductsCoreData(
            dsldId: 'test-retained-cbd',
            productName: 'Retained CBD test item',
            keyIngredientTags: '["cbd"]',
            exportVersion: 'test',
            exportedAt: '2026-09-12T00:00:00Z',
          ),
        ),
        QuickCheckItem.medication(
          name: 'Warfarin',
          rxcui: '11289',
          drugClasses: const ['class:anticoagulants'],
        ),
        interactionDb,
      );
      expect(
        results
            .singleWhere((result) => result.id == 'DSI_ANTICOAG_CBD')
            .severity,
        Severity.caution,
      );
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
