// The cards Sean approved on 2026-11-04, from real pipeline output, through the
// real profile, taxonomy, gate and fit.

import 'dart:convert';
import 'dart:io';

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

const _dsldId = 'dsld-held-rule-cards';
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

Map<String, dynamic> _fixture(String path) =>
    jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;

final _caffeine = _fixture(
  'test/fixtures/pipeline/caffeine_estimate_249741.json',
);
final _ageWarnings = _fixture(
  'test/fixtures/age_outcomes/real_warnings_211459_4340.json',
);

Future<void> _pumpPage(
  WidgetTester tester, {
  required List<String> conditions,
  required Map<String, dynamic> warning,
  String? ageBracket,
}) async {
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
          productName: 'Held Rule Product',
          exportVersion: 'test',
          exportedAt: '2026-11-04T00:00:00Z',
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
          (ref, id) async => {
            'warnings': [warning],
          },
        ),
        profileProvider.overrideWith(
          (ref) => ProfileNotifier()
            ..setAgeBracket(ageBracket)
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

void main() {
  group('249741, an upper figure resting on the estimate', () {
    testWidgets('a pregnant viewer reads the approved card', (tester) async {
      await _pumpPage(
        tester,
        conditions: const ['pregnancy'],
        warning: _caffeine,
        ageBracket: '31-50',
      );
      expect(find.text(_caffeine['alert_headline'] as String), findsOneWidget);
      expect(
        find.textContaining(_caffeine['alert_body'] as String),
        findsOneWidget,
      );
      expect(find.text('Not recommended for your profile'), findsOneWidget);
      expect(find.text(_allClear), findsNothing);
    });

    testWidgets('a viewer it does not name reads nothing', (tester) async {
      await _pumpPage(
        tester,
        conditions: const ['diabetes'],
        warning: _caffeine,
        ageBracket: '31-50',
      );
      expect(
        find.textContaining(_caffeine['alert_body'] as String),
        findsNothing,
      );
    });
  });

  group('age card', () {
    const headline = 'Limit depends on age';

    for (final age in const [null, 'teen', 'Prefer not to say']) {
      testWidgets('$age reads the review, not an adult answer', (tester) async {
        await _pumpPage(
          tester,
          conditions: const ['pregnancy'],
          warning: _ageWarnings['4340'] as Map<String, dynamic>,
          ageBracket: age,
        );
        expect(find.text(headline), findsOneWidget);
        expect(find.textContaining('Add your age range'), findsOneWidget);
        expect(find.text(_allClear), findsNothing);
      });
    }

    testWidgets('an adult within the limit reads no age card', (tester) async {
      await _pumpPage(
        tester,
        conditions: const ['pregnancy'],
        warning: _ageWarnings['4340'] as Map<String, dynamic>,
        ageBracket: '31-50',
      );
      expect(find.text(headline), findsNothing);
    });

    testWidgets('a teenager reads the over-limit card', (tester) async {
      await _pumpPage(
        tester,
        conditions: const ['pregnancy'],
        warning: _ageWarnings['4340'] as Map<String, dynamic>,
        ageBracket: '14-18',
      );
      expect(find.text(headline), findsNothing);
      expect(find.text(_allClear), findsNothing);
    });
  });
}
