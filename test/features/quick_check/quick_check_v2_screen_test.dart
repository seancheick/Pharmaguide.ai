import 'package:drift/drift.dart' as drift;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/data/database/core_database.dart';
import 'package:pharmaguide/data/database/interaction_database.dart';
import 'package:pharmaguide/data/providers/database_providers.dart';
import 'package:pharmaguide/features/quick_check/v2/quick_check_v2_screen.dart';
import 'package:pharmaguide/services/medications/rxnorm_api_service.dart';
import 'package:pharmaguide/services/medications/rxnorm_providers.dart';

void main() {
  testWidgets('checks RxNorm medication against supplement result', (
    tester,
  ) async {
    final coreDb = CoreDatabase.memory();
    final interactionDb = InteractionDatabase.memory();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await coreDb.close();
      await interactionDb.close();
    });

    await coreDb
        .into(coreDb.productsCore)
        .insert(
          ProductsCoreCompanion.insert(
            dsldId: 'potassium-1',
            productName: 'Potassium Complex',
            brandName: const drift.Value('Test Brand'),
            ingredientFingerprint: const drift.Value('["potassium"]'),
            // `canonicalIdsForProduct` reads `key_ingredient_tags`
            // first (Phase 11.11.B canonical resolver unification).
            keyIngredientTags: const drift.Value('["potassium"]'),
            qualityScoreV4100: const drift.Value(82),
            mappedCoverage: const drift.Value(0.9),
            productSafetyStatus: const drift.Value('no_known_catalog_concern'),
            qualityAssessmentStatus: const drift.Value('complete'),
            qualityScoreStatus: const drift.Value('scored'),
            v4Confidence: const drift.Value('moderate'),
            exportVersion: 'test',
            exportedAt: '2026-05-17T00:00:00Z',
          ),
        );
    await interactionDb
        .into(interactionDb.interactions)
        .insert(
          InteractionsCompanion.insert(
            id: 'DSI_ACEI_POTASSIUM',
            agent1Type: 'drug_class',
            agent1Name: 'ACE Inhibitors (class)',
            agent1Id: 'class:ace_inhibitors',
            agent2Type: 'supplement',
            agent2Name: 'Potassium',
            agent2Id: 'C0032821',
            agent2CanonicalId: const drift.Value('potassium'),
            severity: 'avoid',
            mechanism: 'ACE inhibitors can increase potassium retention.',
            management: 'Check with your clinician before combining.',
            evidenceLevel: const drift.Value('established'),
            sourceUrlsJson: '[]',
            sourcePmidsJson: '[]',
            typeAuthored: 'curated',
            source: 'curated',
            provenance: 'test',
            versionAdded: '1.0.0',
            versionLastModified: '1.0.0',
            lastUpdated: '2026-05-17T00:00:00Z',
          ),
        );

    final rxNorm = RxNormApiService(httpGet: _fakeRxNormHttpGet);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          coreDatabaseProvider.overrideWithValue(coreDb),
          interactionDatabaseProvider.overrideWithValue(interactionDb),
          rxNormApiServiceProvider.overrideWithValue(rxNorm),
        ],
        child: const MaterialApp(home: QuickCheckV2Screen()),
      ),
    );

    await tester.enterText(find.byType(TextField).first, 'lisinopril');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Lisinopril'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, 'potassium');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();

    expect(find.text('82 · Moderate'), findsOneWidget);
    await tester.tap(find.text('Potassium Complex'));
    await tester.pumpAndSettle();

    final checkButton = find.text('Check interactions');
    await tester.ensureVisible(checkButton);
    await tester.tap(checkButton);
    await tester.pumpAndSettle();

    expect(find.text('1 INTERACTION FOUND'), findsOneWidget);
    expect(find.text('NOT RECOMMENDED'), findsOneWidget);
    expect(find.text('Lisinopril'), findsWidgets);
    expect(find.text('Potassium Complex'), findsWidgets);
    expect(
      find.text('ACE inhibitors can increase potassium retention.'),
      findsOneWidget,
    );
  });
}

Future<String> _fakeRxNormHttpGet(Uri url) async {
  if (url.path == '/REST/approximateTerm.json') {
    final term = url.queryParameters['term']?.toLowerCase() ?? '';
    if (term.contains('lisinopril')) {
      return '''
      {
        "approximateGroup": {
          "candidate": [
            {"rxcui": "29046", "name": "Lisinopril", "score": "100"}
          ]
        }
      }
      ''';
    }
    return '{"approximateGroup":{"candidate":[]}}';
  }

  if (url.path == '/REST/rxclass/class/byRxcui.json') {
    return '''
    {
      "rxclassDrugInfoList": {
        "rxclassDrugInfo": [
          {
            "rxclassMinConceptItem": {
              "className": "ACE Inhibitors"
            }
          }
        ]
      }
    }
    ''';
  }

  if (url.path == '/REST/rxcui/29046/related.json') {
    return '{"relatedGroup":{"conceptGroup":[]}}';
  }

  throw StateError('Unexpected RxNorm URL: $url');
}
