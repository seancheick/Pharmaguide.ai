import 'dart:async';
import 'dart:convert';
import 'package:drift/drift.dart' as drift;
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
    if (url.path == '/REST/approximateTerm.json' &&
        url.queryParameters['term'] == 'unknown medication') {
      return '{}';
    }
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

class _DelayedRxNormHttp {
  final aspirinClasses = Completer<String>();
  Future<String> call(Uri url) async {
    if (url.path == '/REST/approximateTerm.json') {
      final aspirin = url.queryParameters['term'] == 'aspirin';
      return jsonEncode({
        'approximateGroup': {
          'candidate': [
            {
              'rxcui': aspirin ? '1191' : '5640',
              'name': aspirin ? 'Aspirin' : 'Ibuprofen',
              'score': '100',
            },
          ],
        },
      });
    }
    if (url.path == '/REST/rxclass/class/byRxcui.json') {
      if (url.queryParameters['rxcui'] == '1191') return aspirinClasses.future;
      return '{}';
    }
    if (url.path.endsWith('/related.json')) {
      final id = url.path.contains('/1191/') ? '1191' : '5640';
      return jsonEncode({
        'relatedGroup': {
          'conceptGroup': [
            {
              'tty': 'IN',
              'conceptProperties': [
                {'rxcui': id},
              ],
            },
          ],
        },
      });
    }
    return '{}';
  }
}

class _FakeReferenceDataRepository extends ReferenceDataRepository {
  @override
  Future<Map<String, dynamic>> loadMedicationProfileGateRules() async {
    return const {
      'medication_profile_gate_rules': [
        {
          'id': 'MCR_PREGNANCY_NSAIDS',
          'medication_exceptions': [
            {'route': 'ophthalmic'},
          ],
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
  testWidgets(
    'pairwise confirmation is visible and invalidated by saved dose and schedule edits',
    (tester) async {
      final db = InteractionDatabase.memory();
      addTearDown(db.close);
      await db
          .into(db.drugClassMap)
          .insert(
            DrugClassMapCompanion.insert(
              classId: 'class:maois',
              className: 'MAOIs',
              drugRxcuisJson: '["9639"]',
              source: 'fixture',
              lastUpdated: '2026-10-13',
            ),
          );
      const criteria =
          'Confirm delivered 6 mg per 24 hours transdermal and no 9 or 12 mg patches within the previous 14 days.';
      await db
          .into(db.interactions)
          .insert(
            InteractionsCompanion.insert(
              id: 'DSI_MAOI_TYRAMINE',
              agent1Type: 'drug_class',
              agent1Id: 'class:maois',
              agent1Name: 'MAOI',
              agent1DrugClass: const drift.Value('class:maois'),
              agent2Type: 'food',
              agent2Id: 'C0041471',
              agent2Name: 'Tyramine foods',
              severity: 'avoid',
              mechanism: 'Diet review',
              management: 'Review with prescriber',
              sourceUrlsJson: '[]',
              sourcePmidsJson: '[]',
              typeAuthored: 'Med-Food',
              source: 'curated',
              provenance: 'dailymed',
              versionAdded: 'audit',
              versionLastModified: 'audit',
              lastUpdated: '2026-10-13',
              alertStyle: const drift.Value('food_advisory_note'),
              medicationExceptionsJson: drift.Value(
                jsonEncode([
                  {
                    'ingredient_rxcuis': ['9639'],
                    'dose_mg_exact': 6,
                    'route': 'transdermal',
                    'use_context': 'current_food_context',
                    'notes': criteria,
                  },
                ]),
              ),
            ),
          );
      Future<String> http(Uri url) async =>
          url.path == '/REST/approximateTerm.json'
          ? '{"approximateGroup":{"candidate":[{"rxcui":"9639","name":"Selegiline","score":"100"}]}}'
          : '{}';
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            interactionDatabaseProvider.overrideWithValue(db),
            referenceDataRepositoryProvider.overrideWith(
              (ref) => _FakeReferenceDataRepository(),
            ),
            loadedProfileProvider.overrideWith(
              (ref) async => const ProfileState(),
            ),
            clinicalProfileSchemaProvider.overrideWith(
              (ref) async => _testClinicalProfileSchema,
            ),
            rxNormApiServiceProvider.overrideWithValue(
              RxNormApiService(httpGet: http, offlineDb: db),
            ),
          ],
          child: const MaterialApp(home: MedicationEntryV2Screen()),
        ),
      );
      await tester.enterText(
        find.byKey(const Key('med-entry-search')),
        'selegiline',
      );
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('med-entry-suggestion-9639')));
      await tester.pumpAndSettle();
      final choice = find.byKey(
        const ValueKey('pairwise_confirmation_current_food_context'),
      );
      await tester.scrollUntilVisible(
        choice,
        120,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(find.text(criteria), findsOneWidget);
      await tester.tap(choice);
      await tester.pumpAndSettle();
      expect(tester.widget<CheckboxListTile>(choice).value, isTrue);
      await tester.scrollUntilVisible(
        find.byKey(const Key('med-entry-dose')),
        120,
        scrollable: find.byType(Scrollable).first,
      );
      tester
          .widget<TextField>(find.byKey(const Key('med-entry-dose')))
          .controller!
          .selection = const TextSelection.collapsed(
        offset: 0,
      );
      await tester.pumpAndSettle();
      expect(tester.widget<CheckboxListTile>(choice).value, isTrue);
      await tester.enterText(
        find.byKey(const Key('med-entry-dose')),
        '9 mg/24h',
      );
      await tester.pumpAndSettle();
      expect(tester.widget<CheckboxListTile>(choice).value, isFalse);
      await tester.ensureVisible(choice);
      await tester.tap(choice);
      await tester.pumpAndSettle();
      expect(tester.widget<CheckboxListTile>(choice).value, isTrue);
      await tester.scrollUntilVisible(
        find.text('Once daily'),
        120,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Once daily'));
      await tester.pumpAndSettle();
      expect(tester.widget<CheckboxListTile>(choice).value, isFalse);
    },
  );

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
        find.byWidgetPredicate(
          (w) =>
              w is DropdownButtonFormField<String> &&
              (w.key as ValueKey?)?.value.toString().startsWith(
                    'medication_route_',
                  ) ==
                  true,
        ),
        findsOneWidget,
      );
      expect(
        find.byWidgetPredicate(
          (w) =>
              w is DropdownButtonFormField<String> &&
              (w.key as ValueKey?)?.value.toString().startsWith(
                    'medication_use_confirmation_',
                  ) ==
                  true,
        ),
        findsOneWidget,
      );
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('medication_daily_dose')),
        120,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.enterText(
        find.byKey(const ValueKey('medication_daily_dose')),
        '81',
      );
      await tester.pumpAndSettle();
      // A numeric aspirin dose cannot turn ibuprofen into the exempt molecule.
      expect(
        find.text('Review NSAID use in pregnancy', skipOffstage: false),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await tester.scrollUntilVisible(
        find.byKey(const Key('med-entry-profile-review-card')),
        -160,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();

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

  // "Your medication list stays on this device" was true of the saved list,
  // but the name search sends what you type to the U.S. National Library of
  // Medicine (RxNorm). The row now says both.
  testWidgets('privacy row discloses the RxNorm name lookup', (tester) async {
    final interactionDb = InteractionDatabase.memory();
    addTearDown(interactionDb.close);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          interactionDatabaseProvider.overrideWithValue(interactionDb),
          referenceDataRepositoryProvider.overrideWith(
            (ref) => _FakeReferenceDataRepository(),
          ),
          rxNormApiServiceProvider.overrideWithValue(
            RxNormApiService(
              httpGet: _FakeRxNormHttp().call,
              offlineDb: interactionDb,
            ),
          ),
        ],
        child: const MaterialApp(home: MedicationEntryV2Screen()),
      ),
    );
    await tester.pumpAndSettle();

    final note = find.textContaining('National Library of Medicine');
    await tester.scrollUntilVisible(
      note,
      160,
      scrollable: find.byType(Scrollable).first,
    );
    expect(note, findsOneWidget);
    expect(find.textContaining('saved on this device only'), findsOneWidget);
    expect(
      find.textContaining(
        'unless you choose to share a snapshot with a '
        'connected AI assistant',
      ),
      findsOneWidget,
    );
  });
  testWidgets('new medication query resets confirmed dose route and purpose', (
    tester,
  ) async {
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

    await tester.enterText(find.byKey(const Key('med-entry-search')), 'motrin');
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
      find.byWidgetPredicate(
        (w) =>
            w is DropdownButtonFormField<String> &&
            (w.key as ValueKey?)?.value.toString().startsWith(
                  'medication_route_',
                ) ==
                true,
      ),
      160,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -220));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byWidgetPredicate(
        (w) =>
            w is DropdownButtonFormField<String> &&
            (w.key as ValueKey?)?.value.toString().startsWith(
                  'medication_route_',
                ) ==
                true,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Directly in the eye').last);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('medication_daily_dose')),
      '81',
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('med-entry-search')),
      -160,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.enterText(
      find.byKey(const Key('med-entry-search')),
      'unknown medication',
    );
    await tester.pumpAndSettle();
    final routeFinder = find.byWidgetPredicate(
      (w) =>
          w is DropdownButtonFormField<String> &&
          (w.key as ValueKey?)?.value.toString().startsWith(
                'medication_route_',
              ) ==
              true,
    );
    expect(tester.state<FormFieldState<String>>(routeFinder).value, isNull);
    expect(
      tester
          .widget<TextField>(
            find.byKey(const ValueKey('medication_daily_dose')),
          )
          .controller!
          .text,
      isEmpty,
    );
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'late aspirin hydration cannot replace newly selected ibuprofen identity',
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

      final fakeRx = _DelayedRxNormHttp();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            interactionDatabaseProvider.overrideWithValue(interactionDb),
            referenceDataRepositoryProvider.overrideWith(
              (ref) => ReferenceDataRepository(),
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
        'aspirin',
      );
      final searchField = tester.widget<TextField>(
        find.byKey(const Key('med-entry-search')),
      );
      expect(searchField.autocorrect, isFalse);
      expect(searchField.enableSuggestions, isFalse);
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('med-entry-suggestion-1191')));
      await tester.pump(const Duration(milliseconds: 100));

      await tester.enterText(
        find.byKey(const Key('med-entry-search')),
        'ibuprofen',
      );
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('med-entry-suggestion-5640')));
      await tester.pumpAndSettle();
      fakeRx.aspirinClasses.complete('{}');
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byKey(const Key('med-entry-profile-review-card')),
        160,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Review NSAID use in pregnancy'), findsOneWidget);
      expect(
        find.textContaining('Used to check: NSAIDs', skipOffstage: false),
        findsOneWidget,
      );
      expect(
        find.textContaining('Antiplatelet', skipOffstage: false),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
