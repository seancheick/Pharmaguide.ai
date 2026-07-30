import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/core/data/clinical_profile_schema.dart';
import 'package:pharmaguide/data/database/interaction_database.dart';
import 'package:pharmaguide/data/providers/database_providers.dart';
import 'package:pharmaguide/data/providers/reference_data_provider.dart';
import 'package:pharmaguide/data/repositories/reference_data_repository.dart';
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
            {"rxcui": "202488", "name": "Motrin Pill", "score": "100"}
          ]
        }
      }
    ''',
  };

  Future<String> call(Uri url) async {
    if (url.path == '/REST/rxclass/class/byRxcui.json') {
      if (url.queryParameters['relaSource'] == 'ATC') return '{}';
      return '''
        {
          "rxclassDrugInfoList": {
            "rxclassDrugInfo": [
              {
                "rela": "has_moa",
                "rxclassMinConceptItem": {
                  "className": "Cyclooxygenase Inhibitors",
                  "classType": "MOA"
                }
              },
              {
                "rela": "has_pe",
                "rxclassMinConceptItem": {
                  "className": "Decreased Prostaglandin Production",
                  "classType": "PE"
                }
              }
            ]
          }
        }
      ''';
    }
    return responses['${url.path}?${url.query}'] ??
        responses[url.path] ??
        (throw StateError('No fake RxNorm response for $url'));
  }
}

class _FakeReferenceDataRepository extends ReferenceDataRepository {
  @override
  Future<Map<String, dynamic>> loadMedicationProfileGateRules() async {
    return const {
      'medication_profile_gate_rules': [
        {
          'id': 'MCR_PREGNANCY_NSAIDS',
          'severity': 'caution',
          'evidence_level': 'established',
          'headline': 'Review NSAID use in pregnancy',
          'body':
              'NSAIDs such as ibuprofen and naproxen are generally avoided from 20 weeks of pregnancy.',
          'management': 'Check with your OB/clinician before using NSAIDs.',
          'sources': [
            'https://www.fda.gov/drugs/drug-safety-and-availability/fda-recommends-avoiding-use-nsaids-pregnancy-20-weeks-or-later-because-they-can-result-low-amniotic',
          ],
          'profile_gate': {
            'gate_type': 'combination',
            'requires': {
              'conditions_any': <String>[],
              'drug_classes_any': <String>['nsaids'],
              'profile_flags_any': <String>['pregnant'],
            },
            'excludes': {
              'conditions_any': <String>[],
              'drug_classes_any': <String>[],
              'profile_flags_any': <String>[],
              'product_forms_any': <String>[],
              'nutrient_forms_any': <String>[],
            },
          },
        },
        {
          'id': 'MCR_KIDNEY_DISEASE_NSAIDS',
          'severity': 'avoid',
          'evidence_level': 'established',
          'headline': 'NSAIDs are not recommended with kidney disease',
          'body':
              'NSAIDs such as ibuprofen and naproxen can reduce kidney blood flow and may worsen kidney function.',
          'management':
              'Avoid NSAID use unless your kidney clinician or prescriber specifically directs it.',
          'sources': [
            'https://www.niddk.nih.gov/health-information/kidney-disease/keeping-kidneys-safe',
          ],
          'profile_gate': {
            'gate_type': 'combination',
            'requires': {
              'conditions_any': <String>['kidney_disease'],
              'drug_classes_any': <String>['nsaids'],
              'profile_flags_any': <String>[],
            },
            'excludes': {
              'conditions_any': <String>[],
              'drug_classes_any': <String>[],
              'profile_flags_any': <String>[],
              'product_forms_any': <String>[],
              'nutrient_forms_any': <String>[],
            },
          },
        },
      ],
    };
  }
}

const _testClinicalProfileSchema = ClinicalProfileSchema(
  selectableConditions: [],
  userSelectableFlags: [],
  derivedFlagByCondition: {'pregnancy': 'pregnant'},
);

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
            referenceDataRepositoryProvider.overrideWith(
              (ref) => _FakeReferenceDataRepository(),
            ),
            loadedProfileProvider.overrideWith(
              (ref) async => const ProfileState(conditions: ['pregnancy']),
            ),
            clinicalProfileSchemaProvider.overrideWith(
              (ref) async => _testClinicalProfileSchema,
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
      final searchField = tester.widget<TextField>(
        find.byKey(const Key('med-entry-search')),
      );
      expect(searchField.autocorrect, isFalse);
      expect(searchField.enableSuggestions, isFalse);
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
      for (var i = 0; i < 30; i++) {
        if (find.text('Review NSAID use in pregnancy').evaluate().isNotEmpty) {
          break;
        }
        await tester.pump(const Duration(milliseconds: 100));
      }

      expect(
        find.byKey(const Key('med-entry-profile-review-card')),
        findsOneWidget,
      );
      expect(find.text('Review NSAID use in pregnancy'), findsOneWidget);
      expect(
        find.textContaining('generally avoided from 20 weeks'),
        findsOneWidget,
      );
      expect(find.text('Motrin Pill', skipOffstage: false), findsNothing);
      expect(find.text('Motrin', skipOffstage: false), findsWidgets);
      expect(
        find.text(
          'Used to check: NSAIDs (Ibuprofen, Aspirin regularly)',
          skipOffstage: false,
        ),
        findsOneWidget,
      );
      expect(
        find.textContaining('Cyclooxygenase', skipOffstage: false),
        findsNothing,
      );
      expect(
        find.textContaining('Prostaglandin', skipOffstage: false),
        findsNothing,
      );
    },
  );

  testWidgets(
    'kidney disease profile plus Motrin shows pre-save profile review card',
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
            referenceDataRepositoryProvider.overrideWith(
              (ref) => _FakeReferenceDataRepository(),
            ),
            loadedProfileProvider.overrideWith(
              (ref) async => const ProfileState(conditions: ['kidney_disease']),
            ),
            clinicalProfileSchemaProvider.overrideWith(
              (ref) async => _testClinicalProfileSchema,
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
      for (var i = 0; i < 30; i++) {
        if (find
            .text('NSAIDs are not recommended with kidney disease')
            .evaluate()
            .isNotEmpty) {
          break;
        }
        await tester.pump(const Duration(milliseconds: 100));
      }

      expect(
        find.byKey(const Key('med-entry-profile-review-card')),
        findsOneWidget,
      );
      expect(
        find.text('NSAIDs are not recommended with kidney disease'),
        findsOneWidget,
      );
      expect(find.textContaining('kidney function'), findsOneWidget);
    },
  );

  testWidgets(
    'clinical taxonomy failure is visible and cannot look like an all-clear',
    (tester) async {
      final interactionDb = InteractionDatabase.memory();
      addTearDown(interactionDb.close);

      final fakeRx = _FakeRxNormHttp();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            interactionDatabaseProvider.overrideWithValue(interactionDb),
            referenceDataRepositoryProvider.overrideWith(
              (ref) => _FakeReferenceDataRepository(),
            ),
            loadedProfileProvider.overrideWith(
              (ref) async => const ProfileState(conditions: ['pregnancy']),
            ),
            clinicalProfileSchemaProvider.overrideWith(
              (ref) async => throw StateError('taxonomy unavailable'),
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

      expect(find.text('Profile review unavailable'), findsOneWidget);
      expect(find.textContaining('not an all-clear'), findsOneWidget);
    },
  );
}
