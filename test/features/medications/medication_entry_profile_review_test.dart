import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/data/database/interaction_database.dart';
import 'package:pharmaguide/data/providers/database_providers.dart';
import 'package:pharmaguide/features/medications/v2/medication_entry_v2_screen.dart';
import 'package:pharmaguide/features/profile/profile_provider.dart';
import 'package:pharmaguide/services/medications/rxnorm_api_service.dart';
import 'package:pharmaguide/services/medications/rxnorm_providers.dart';

class _FakeRxNormHttp {
  final Map<String, String> responses = const {
    '/REST/approximateTerm.json': '''
      {
        "approximateGroup": {
          "candidate": [
            {"rxcui": "202488", "name": "Motrin", "score": "100"}
          ]
        }
      }
    ''',
  };

  Future<String> call(Uri url) async {
    return responses['${url.path}?${url.query}'] ??
        responses[url.path] ??
        (throw StateError('No fake RxNorm response for $url'));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'pregnant profile plus Motrin shows pre-save profile review card',
    (tester) async {
      final interactionDb = InteractionDatabase.memory();
      addTearDown(interactionDb.close);
      await interactionDb
          .into(interactionDb.drugClassMap)
          .insert(
            DrugClassMapCompanion.insert(
              classId: 'class:nsaids',
              className: 'NSAIDs',
              drugRxcuisJson: '["5640"]',
              source: 'fixture',
              lastUpdated: '2026-06-27',
            ),
          );

      final fakeRx = _FakeRxNormHttp();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            interactionDatabaseProvider.overrideWithValue(interactionDb),
            loadedProfileProvider.overrideWith(
              (ref) async => const ProfileState(conditions: ['pregnancy']),
            ),
            rxNormApiServiceProvider.overrideWithValue(
              RxNormApiService(httpGet: fakeRx.call, offlineDb: interactionDb),
            ),
          ],
          child: const MaterialApp(home: MedicationEntryV2Screen()),
        ),
      );

      await tester.enterText(
        find.byKey(const Key('med-entry-search')),
        'motrin',
      );
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('med-entry-suggestion-202488')));
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.byKey(const Key('med-entry-profile-review-card')),
        160,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('med-entry-profile-review-card')),
        findsOneWidget,
      );
      expect(find.text('Review NSAID use in pregnancy'), findsOneWidget);
      expect(
        find.textContaining('generally avoided from 20 weeks'),
        findsOneWidget,
      );
    },
  );
}
