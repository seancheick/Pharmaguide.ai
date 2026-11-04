// A label's own firm pregnancy or nursing statement has to reach the viewer it
// names, word for word, through the real profile: the condition the picker
// writes, the bundled taxonomy, the real gate and the real fit.

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/data/database/core_database.dart';
import 'package:pharmaguide/data/database/interaction_database.dart';
import 'package:pharmaguide/data/database/user_database.dart';
import 'package:pharmaguide/data/providers/database_providers.dart';
import 'package:pharmaguide/data/providers/reference_data_provider.dart'
    as reference_data;
import 'package:pharmaguide/data/repositories/reference_data_repository.dart';
import 'package:pharmaguide/features/product_detail/providers/detail_blob_provider.dart';
import 'package:pharmaguide/features/product_detail/v2/product_detail_v2_connected.dart';
import 'package:pharmaguide/features/profile/profile_provider.dart';
import 'package:pharmaguide/features/safety_alerts/providers/safety_alert_providers.dart';
import 'package:pharmaguide/features/stack/providers/stack_providers.dart';
import 'package:pharmaguide/services/safety_alerts/safety_alert.dart';
import 'package:pharmaguide/services/safety_alerts/safety_alert_repository.dart';

const _dsldId = 'dsld-label-statement';
const _text = 'Do not use if you are pregnant or nursing.';
const _pregnancy = ['pregnancy'];
const _lactation = ['lactation'];
const _ttc = ['ttc'];
const _allClear = 'No known concerns';

class _NoAlerts implements SafetyAlertRepository {
  @override
  Future<SafetyAlertRelease> loadCurrent() async => const SafetyAlertRelease(
    alerts: [],
    baselineRevisions: {},
    isComplete: true,
  );
  @override
  Future<List<SafetyAlert>> loadCachedAlerts() async => const [];
}

Map<String, dynamic> _statement({
  required String severity,
  List<String> flags = const ['pregnant', 'breastfeeding'],
  List<String> conditionIds = const ['pregnancy', 'lactation'],
}) => {
  'type': 'label_statement',
  'source': 'label_statements',
  'severity': severity,
  'display_mode_default': 'suppress',
  'evidence_level': 'ungraded',
  'title': 'Label warning',
  'detail': _text,
  'alert_body': _text,
  'sources': <String>[],
  'condition_ids': conditionIds,
  'drug_class_ids': <String>[],
  'profile_gate': {
    'gate_type': 'profile_flag',
    'requires': {
      'conditions_any': <String>[],
      'drug_classes_any': <String>[],
      'profile_flags_any': flags,
    },
    'excludes': {
      'conditions_any': <String>[],
      'drug_classes_any': <String>[],
      'profile_flags_any': <String>[],
      'product_forms_any': <String>[],
      'nutrient_forms_any': <String>[],
    },
    'dose': null,
  },
};

Future<void> _pumpPage(
  WidgetTester tester, {
  required List<String> conditions,
  required List<Map<String, dynamic>> warnings,
}) async {
  // A widget test's clock can't wait on the asset bundle, so the real taxonomy
  // is read first and the real providers derive from it.
  final repository = ReferenceDataRepository();
  await tester.runAsync(() async {
    await repository.loadClinicalProfileSchema();
    await repository.loadRdaOptimalUls();
    await repository.loadGoalMappings();
    await repository.loadMedicationProfileGateRules();
  });
  tester.view.physicalSize = const Size(1320, 12000);
  addTearDown(tester.view.reset);

  final coreDb = CoreDatabase.memory();
  final userDb = UserDatabase.memory();
  final interactionDb = InteractionDatabase.memory();
  await coreDb
      .into(coreDb.productsCore)
      .insert(
        ProductsCoreCompanion.insert(
          dsldId: _dsldId,
          productName: 'Label Statement Product',
          exportVersion: 'test',
          exportedAt: '2026-11-03T00:00:00Z',
          mappedCoverage: const Value(1),
        ),
      );
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await coreDb.close();
    await userDb.close();
    await interactionDb.close();
  });

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        coreDatabaseProvider.overrideWithValue(coreDb),
        userDatabaseProvider.overrideWithValue(userDb),
        interactionDatabaseProvider.overrideWithValue(interactionDb),
        safetyAlertRepositoryProvider.overrideWithValue(_NoAlerts()),
        activeStackProvider.overrideWith((ref) async => const []),
        detailBlobProvider.overrideWith(
          (ref, id) async => {'warnings': warnings},
        ),
        profileProvider.overrideWith(
          (ref) => ProfileNotifier()
            ..setAgeBracket('31-50')
            ..setConditions(conditions),
        ),
        reference_data.referenceDataRepositoryProvider.overrideWithValue(
          repository,
        ),
      ],
      child: const MaterialApp(
        home: ProductDetailV2ConnectedScreen(dsldId: _dsldId),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void _expectCard(String line) {
  expect(find.text('Label warning'), findsOneWidget);
  expect(find.text(line), findsOneWidget);
  expect(find.text(_allClear), findsNothing);
}

void _expectUnchanged() {
  expect(find.text('Label warning'), findsNothing);
  expect(find.textContaining(_text), findsNothing);
  expect(find.text(_allClear), findsOneWidget);
}

void main() {
  const notRecommended = 'Not recommended · $_text · Evidence not graded';
  const useCaution = 'Use caution · $_text · Evidence not graded';

  testWidgets('a statement the pipeline has not emitted leaves the all-clear', (
    tester,
  ) async {
    await _pumpPage(tester, conditions: _pregnancy, warnings: const []);
    _expectUnchanged();
  });

  group('avoid', () {
    final warnings = [_statement(severity: 'avoid')];

    testWidgets('reaches a pregnant viewer', (tester) async {
      await _pumpPage(tester, conditions: _pregnancy, warnings: warnings);
      _expectCard(notRecommended);
      expect(find.text('Not recommended for your profile'), findsOneWidget);
    });

    testWidgets('reaches a nursing viewer', (tester) async {
      await _pumpPage(tester, conditions: _lactation, warnings: warnings);
      _expectCard(notRecommended);
    });

    testWidgets('no profile sees nothing new', (tester) async {
      await _pumpPage(tester, conditions: const [], warnings: warnings);
      _expectUnchanged();
    });

    testWidgets('another condition sees nothing new', (tester) async {
      await _pumpPage(
        tester,
        conditions: const ['hypertension'],
        warnings: warnings,
      );
      _expectUnchanged();
    });

    testWidgets('trying to conceive sees nothing the label did not name', (
      tester,
    ) async {
      await _pumpPage(tester, conditions: _ttc, warnings: warnings);
      _expectUnchanged();
    });
  });

  group('caution', () {
    final warnings = [_statement(severity: 'caution')];

    testWidgets('removes the all-clear for a pregnant viewer', (tester) async {
      await _pumpPage(tester, conditions: _pregnancy, warnings: warnings);
      _expectCard(useCaution);
      expect(find.text('Review before use'), findsOneWidget);
    });

    testWidgets('removes the all-clear for a nursing viewer', (tester) async {
      await _pumpPage(tester, conditions: _lactation, warnings: warnings);
      _expectCard(useCaution);
    });

    testWidgets('no profile sees nothing new', (tester) async {
      await _pumpPage(tester, conditions: const [], warnings: warnings);
      _expectUnchanged();
    });
  });

  testWidgets('a pregnancy-only statement stays from a nursing viewer', (
    tester,
  ) async {
    await _pumpPage(
      tester,
      conditions: _lactation,
      warnings: [
        _statement(
          severity: 'avoid',
          flags: const ['pregnant'],
          conditionIds: const ['pregnancy'],
        ),
      ],
    );
    _expectUnchanged();
  });

  testWidgets('a statement naming conception reaches that viewer', (
    tester,
  ) async {
    await _pumpPage(
      tester,
      conditions: _ttc,
      warnings: [
        _statement(
          severity: 'avoid',
          flags: const ['pregnant', 'trying_to_conceive'],
          conditionIds: const ['pregnancy', 'ttc'],
        ),
      ],
    );
    _expectCard(notRecommended);
  });

  // The page keeps an untagged hard warning visible as a safety default, so the
  // pipeline has to tag every statement or an avoid would reach everyone.
  testWidgets('without condition ids an avoid would reach everyone', (
    tester,
  ) async {
    await _pumpPage(
      tester,
      conditions: const [],
      warnings: [_statement(severity: 'avoid', conditionIds: const [])],
    );
    expect(find.text(notRecommended), findsOneWidget);
  });
}
