// What someone taking the medication sees once an interaction rule reaches the
// device through the alert feed, and what everyone else does not. Fixture
// content is fictional; see test/fixtures/safety_alerts/README.md.

import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/core/constants/severity.dart';
import 'package:pharmaguide/core/models/fit_score_result.dart';
import 'package:pharmaguide/data/database/core_database.dart';
import 'package:pharmaguide/data/database/interaction_database.dart';
import 'package:pharmaguide/data/database/user_database.dart';
import 'package:pharmaguide/data/providers/database_providers.dart';
import 'package:pharmaguide/features/product_detail/providers/detail_blob_provider.dart';
import 'package:pharmaguide/features/product_detail/providers/personalized_warnings_provider.dart';
import 'package:pharmaguide/features/product_detail/v2/sections/live_safety_alert_section.dart';
import 'package:pharmaguide/features/product_detail/v2/sections/review_before_use_section.dart';
import 'package:pharmaguide/features/product_detail/v2/warnings_pipeline.dart';
import 'package:pharmaguide/features/safety_alerts/providers/safety_alert_providers.dart';
import 'package:pharmaguide/features/scanner/scanner_logic.dart';
import 'package:pharmaguide/features/stack/providers/medication_identity_providers.dart';
import 'package:pharmaguide/features/stack/providers/stack_providers.dart';
import 'package:pharmaguide/services/safety_alerts/safety_alert.dart';
import 'package:pharmaguide/services/safety_alerts/safety_alert_repository.dart';
import 'package:pharmaguide/services/signals/clinical_signal_envelope.dart';
import 'package:pharmaguide/services/signals/stack_signal_aggregator.dart';
import 'package:pharmaguide/services/warnings/interaction_warning.dart';
import 'package:pharmaguide/features/profile/profile_provider.dart';

const _dsldId = '9990001';
const _classId = 'class:fake_test_medications';
const _rxcui = '0000001';
const _ruleId = 'DSI_FAKE_TESTOPRILEX_FAKEROOT';

const _product = ProductsCoreData(
  dsldId: _dsldId,
  productName: 'Fakeroot capsules',
  keyIngredientTags: '["fake_fakeroot"]',
  productSafetyStatus: 'no_known_catalog_concern',
  exportVersion: 'test',
  exportedAt: '2026-11-03T00:00:00Z',
);

SafetyAlert _rule({String severity = 'contraindicated'}) {
  final feed =
      jsonDecode(
            File(
              'test/fixtures/safety_alerts/interaction_rule_feed.json',
            ).readAsStringSync(),
          )
          as Map<String, dynamic>;
  final row = (feed['alerts'] as List).cast<Map<String, dynamic>>().firstWhere(
    (alert) => alert['event_type'] == 'interaction_rule',
  );
  return SafetyAlert.fromJson({
    ...row,
    'consumer_disposition': severity == 'contraindicated' ? 'block' : 'review',
    'interaction': {...(row['interaction'] as Map), 'severity': severity},
  });
}

SafetyAlert _pregnancyRule() {
  final feed =
      jsonDecode(
            File(
              'test/fixtures/safety_alerts/interaction_rule_feed.json',
            ).readAsStringSync(),
          )
          as Map<String, dynamic>;
  return SafetyAlert.fromJson(
    (feed['alerts'] as List).cast<Map<String, dynamic>>().firstWhere(
      (alert) => alert['alert_id'] == 'SA_9999_0003',
    ),
  );
}

const _pregnant = ProfileState(conditions: ['pregnancy']);

class _FakeRepository implements SafetyAlertRepository {
  _FakeRepository(this.alerts);
  final List<SafetyAlert> alerts;

  @override
  Future<SafetyAlertRelease> loadCurrent() async => SafetyAlertRelease(
    alerts: alerts,
    baselineRevisions: const {},
    isComplete: true,
  );

  @override
  Future<List<SafetyAlert>> loadCachedAlerts() async => alerts;
}

Future<void> _pumpSection(
  WidgetTester tester,
  Set<String> medicationIds,
) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        safetyAlertRepositoryProvider.overrideWithValue(
          _FakeRepository([_rule()]),
        ),
        localMedicationIdentityProvider.overrideWith(
          (ref) async => medicationIds,
        ),
        loadedProfileProvider.overrideWith((ref) async => const ProfileState()),
        evaluatorProfileFlagsProvider.overrideWith((ref) async => const {}),
      ],
      child: const MaterialApp(
        home: Scaffold(body: LiveSafetyAlertSection(product: _product)),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

UserStacksLocalData _medication() {
  final ts = DateTime.utc(2026, 11, 3, 12);
  return UserStacksLocalData(
    id: 'med-fake',
    type: 'medication',
    name: 'Testoprilex',
    rxcui: _rxcui,
    addedAt: ts,
    clientUpdatedAt: ts,
  );
}

Future<void> _seedBundledRow(InteractionDatabase db, String severity) => db
    .into(db.interactions)
    .insert(
      InteractionsCompanion.insert(
        id: _ruleId,
        agent1Type: 'drug',
        agent1Name: 'Testoprilex',
        agent1Id: _rxcui,
        agent1CanonicalId: const Value(null),
        agent2Type: 'supplement',
        agent2Name: 'Fakeroot',
        agent2Id: 'C0000000',
        agent2CanonicalId: const Value('fake_fakeroot'),
        severity: severity,
        effectType: const Value('inhibitor'),
        mechanism: 'Bundled fictional mechanism.',
        management: 'Bundled fictional management.',
        evidenceLevel: const Value('established'),
        sourceUrlsJson: '["https://example.org/fake-bundled-source"]',
        sourcePmidsJson: '[]',
        doseDependent: const Value(0),
        direction: const Value('harmful'),
        materiality: const Value('presence'),
        typeAuthored: 'Med-Sup',
        source: 'curated',
        provenance: 'test',
        versionAdded: 'test',
        versionLastModified: 'test',
        lastUpdated: '2026-11-03',
      ),
    );

/// Runs the real provider against in-memory databases.
Future<List<InteractionWarning>> _warnings({
  required List<SafetyAlert> alerts,
  required Set<String> medicationIds,
  List<UserStacksLocalData> stack = const [],
  String? bundledSeverity,
  ProfileState profile = const ProfileState(),
  bool profileFails = false,
  bool flagsFail = false,
}) async {
  final coreDb = CoreDatabase.memory();
  final interactionDb = InteractionDatabase.memory();
  addTearDown(coreDb.close);
  addTearDown(interactionDb.close);
  await coreDb
      .into(coreDb.productsCore)
      .insert(
        ProductsCoreCompanion.insert(
          dsldId: _dsldId,
          productName: _product.productName,
          exportVersion: 'test',
          exportedAt: '2026-11-03T00:00:00Z',
          keyIngredientTags: const Value('["fake_fakeroot"]'),
        ),
      );
  if (bundledSeverity != null) {
    await _seedBundledRow(interactionDb, bundledSeverity);
  }
  final container = ProviderContainer(
    overrides: [
      coreDatabaseProvider.overrideWithValue(coreDb),
      interactionDatabaseProvider.overrideWithValue(interactionDb),
      activeStackProvider.overrideWith((ref) async => stack),
      detailBlobProvider.overrideWith((ref, dsldId) async => null),
      safetyAlertRepositoryProvider.overrideWithValue(_FakeRepository(alerts)),
      localMedicationIdentityProvider.overrideWith(
        (ref) async => medicationIds,
      ),
      loadedProfileProvider.overrideWith((ref) async => profile),
      evaluatorProfileFlagsProvider.overrideWith(
        (ref) async => flagsFail
            ? throw StateError('no taxonomy')
            : {if (profile.conditions.contains('pregnancy')) 'pregnant'},
      ),
      if (profileFails)
        localMedicationIdentityProvider.overrideWith(
          (ref) async => throw StateError('unreadable'),
        ),
    ],
  );
  addTearDown(container.dispose);
  return container.read(
    personalizedInteractionWarningsProvider(_dsldId).future,
  );
}

/// The product page's verdict headline, reached the way the page reaches it.
String _headline(List<InteractionWarning> warnings) {
  final composed = composeGuardedWarnings(
    detailBlob: null,
    personalizedWarnings: warnings,
    userConditions: const {},
    userDrugClasses: const {},
    userProfileFlags: const {},
  );
  final partition = partitionProfileWarnings(
    warnings: composed,
    userConditions: const {},
    userDrugClasses: const {},
    userProfileFlags: const {},
  );
  return buildProfileRelevanceSummary(
    fitResult: const FitScoreResult(
      missingFields: [],
      state: FitAssessmentState.limitedFit,
      reasons: [],
      mappedCoverage: 1,
    ),
    topGoalLabel: null,
    warnings: partition.profile,
    interactionHint: '',
    matchedAllergens: const [],
    freeFromConflicts: const [],
    hasInteractionProfile: true,
  ).headline;
}

void main() {
  group('the notice on the product page', () {
    testWidgets('names the ingredient, medication, reason and source', (
      tester,
    ) async {
      await _pumpSection(tester, {_classId});

      expect(
        find.text('Fictional test notice: Fakeroot and Testoprilex'),
        findsOneWidget,
      );
      for (final part in [
        'Fakeroot (fictional)',
        'Testoprilex (fictional)',
        'can raise Testoprilex levels',
        'Worth a conversation with your doctor',
        EvidenceLevel.established.label,
      ]) {
        expect(find.textContaining(part), findsOneWidget, reason: part);
      }
      expect(find.text('View source'), findsOneWidget);
    });

    testWidgets('shows nothing to someone not taking the medication', (
      tester,
    ) async {
      await _pumpSection(tester, const {});

      expect(
        find.byKey(const Key('live-safety-alert-SA_9999_0001')),
        findsNothing,
      );
      expect(find.textContaining('Testoprilex'), findsNothing);
    });
  });

  group('the personal verdict', () {
    test(
      'a hard rule replaces the all-clear, even with an empty stack',
      () async {
        final warnings = await _warnings(
          alerts: [_rule()],
          medicationIds: {_classId},
        );

        expect(warnings, hasLength(1));
        expect(warnings.single.severity, Severity.contraindicated);
        expect(warnings.single.evidenceLevel, EvidenceLevel.established);
        expect(warnings.single.ingredientName, 'Fakeroot (fictional)');
        expect(warnings.single.sourceUrls, [
          'https://example.org/fake-interaction-source',
        ]);
        expect(_headline(warnings), 'Not recommended for your profile');
      },
    );

    test('someone not taking the medication keeps the all-clear', () async {
      final warnings = await _warnings(
        alerts: [_rule()],
        medicationIds: const {},
      );

      expect(warnings, isEmpty);
      expect(_headline(warnings), kNoProfileConcernsHeadline);
    });

    test('a match on an RxCUI alone still counts as personal', () async {
      // RxCUIs are not drug classes, so the class-based profile gate alone
      // would file this under general notes.
      final warnings = await _warnings(
        alerts: [_rule(severity: 'caution')],
        medicationIds: {_rxcui},
      );

      expect(warnings.single.severity, Severity.caution);
      expect(_headline(warnings), 'Review before use');
    });

    test('the rule replaces the bundled row it corrects', () async {
      final warnings = await _warnings(
        alerts: [_rule()],
        medicationIds: {_rxcui},
        stack: [_medication()],
        bundledSeverity: 'caution',
      );

      expect(warnings, hasLength(1));
      expect(warnings.single.severity, Severity.contraindicated);
      expect(warnings.single.mechanism, contains('Test fixture only'));
    });

    test('a weaker rule never hides a stricter bundled warning', () async {
      final warnings = await _warnings(
        alerts: [_rule(severity: 'caution')],
        medicationIds: {_rxcui},
        stack: [_medication()],
        bundledSeverity: 'contraindicated',
      );

      expect(
        warnings.map((warning) => warning.severity),
        contains(Severity.contraindicated),
      );
    });
  });

  group('a rule for pregnancy', () {
    test(
      'the verdict leads with it, with no stack and no medication',
      () async {
        final warnings = await _warnings(
          alerts: [_pregnancyRule()],
          medicationIds: const {},
          profile: _pregnant,
        );

        final warning = warnings.single;
        expect(warning.title, 'Fictional test notice: Fakeroot in pregnancy');
        expect(warning.mechanism, contains('not for use during pregnancy'));
        expect(warning.evidenceLevel, EvidenceLevel.established);
        expect(warning.sourceUrls, isNotEmpty);
        expect(warning.title, isNot(contains('taking')));
        expect(_headline(warnings), 'Not recommended for your profile');
      },
    );

    test('an unreadable device profile surfaces, never as nothing to '
        'report', () async {
      await expectLater(
        _warnings(
          alerts: [_pregnancyRule()],
          medicationIds: const {},
          profileFails: true,
        ),
        throwsA(anything),
      );
    });

    test('a failed taxonomy surfaces for someone whose profile is on file, '
        'with products in the stack too', () async {
      final ts = DateTime.utc(2026, 11, 3, 12);
      for (final stack in [
        const <UserStacksLocalData>[],
        [
          UserStacksLocalData(
            id: 'supp-other',
            type: 'supplement',
            name: 'Other',
            addedAt: ts,
            clientUpdatedAt: ts,
          ),
        ],
      ]) {
        await expectLater(
          _warnings(
            alerts: [_pregnancyRule()],
            medicationIds: const {},
            profile: _pregnant,
            flagsFail: true,
            stack: stack,
          ),
          throwsA(anything),
        );
      }
    });

    test('nobody else sees it', () async {
      expect(
        await _warnings(alerts: [_pregnancyRule()], medicationIds: const {}),
        isEmpty,
      );
      expect(
        await _warnings(
          alerts: [_pregnancyRule()],
          medicationIds: const {},
          profile: const ProfileState(conditions: ['diabetes']),
        ),
        isEmpty,
      );
    });
  });

  group('other surfaces', () {
    // No page open: someone with the product and the medication in their stack
    // still gets the signal the Stack tab and health history read.
    Future<SafetyAlertMatchSet> matchesFor(
      Set<String> medicationIds, {
      List<SafetyAlert>? alerts,
      ProfileState profile = const ProfileState(),
      bool flagsFail = false,
    }) {
      final ts = DateTime.utc(2026, 11, 3, 12);
      final container = ProviderContainer(
        overrides: [
          activeStackProvider.overrideWith(
            (ref) async => [
              UserStacksLocalData(
                id: 'supp-fake',
                type: 'supplement',
                name: _product.productName,
                dsldId: _dsldId,
                ingredientKeys: '["fake_fakeroot"]',
                addedAt: ts,
                clientUpdatedAt: ts,
              ),
            ],
          ),
          safetyAlertRepositoryProvider.overrideWithValue(
            _FakeRepository(alerts ?? [_rule()]),
          ),
          localMedicationIdentityProvider.overrideWith(
            (ref) async => medicationIds,
          ),
          loadedProfileProvider.overrideWith((ref) async => profile),
          evaluatorProfileFlagsProvider.overrideWith(
            (ref) async => flagsFail
                ? throw StateError('no taxonomy')
                : {if (profile.conditions.contains('pregnancy')) 'pregnant'},
          ),
        ],
      );
      addTearDown(container.dispose);
      return container.read(safetyAlertMatchesProvider.future);
    }

    test('a stack product matches without opening its page', () async {
      final matches = await matchesFor({_classId});
      expect(matches.matches.single.alert.interaction?.ruleId, _ruleId);
      expect((await matchesFor(const {})).matches, isEmpty);
    });

    test('the Stack signal carries severity, evidence and the notice', () {
      final signal = ClinicalSignal.fromRegulatorySafety(
        _rule(),
        dsldId: _dsldId,
      );

      expect(signal.clinicalSeverity, Severity.contraindicated);
      expect(
        clinicalSignalContextLabel(signal),
        'Supplement interaction · ${EvidenceLevel.established.label}',
      );
      expect(signal.body, contains('Fakeroot (fictional)'));
      expect(signal.body, contains('Testoprilex (fictional)'));
    });

    test('a scan is critical only for someone taking the medication', () {
      expect(
        scanResultIsSafetyCritical(
          _product,
          alerts: [_rule()],
          device: const DeviceSafetyProfile(medicationIds: {_classId}),
        ),
        isTrue,
      );
      expect(scanResultIsSafetyCritical(_product, alerts: [_rule()]), isFalse);
    });

    test('a stack product matches a pregnancy rule on this device', () async {
      final matches = await matchesFor(
        const {},
        alerts: [_pregnancyRule()],
        profile: _pregnant,
      );
      expect(matches.matches.single.alert.alertId, 'SA_9999_0003');
      expect(matches.isComplete, isTrue);
      expect(
        (await matchesFor(const {}, alerts: [_pregnancyRule()])).matches,
        isEmpty,
      );
    });

    test('an unreadable profile is an incomplete check, not an all-clear, '
        'and a ban still shows', () async {
      final matches = await matchesFor(
        const {},
        alerts: [_pregnancyRule()],
        profile: _pregnant,
        flagsFail: true,
      );
      expect(matches.isComplete, isFalse);
    });

    test('a scan is critical for a pregnancy rule only if pregnant', () {
      final rule = _pregnancyRule();
      expect(
        scanResultIsSafetyCritical(
          _product,
          alerts: [rule],
          device: const DeviceSafetyProfile(profileFlags: {'pregnant'}),
        ),
        isTrue,
      );
      expect(scanResultIsSafetyCritical(_product, alerts: [rule]), isFalse);
    });
  });
}
