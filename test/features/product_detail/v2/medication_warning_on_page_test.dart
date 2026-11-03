// A medication interaction found by the real check has to reach the product
// page. The check tags its warning with the medication's classes, and the page
// filters warnings against the same medication's classes, so the two have to
// use one vocabulary or the warning is silently dropped.

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/core/models/fit_score_result.dart';
import 'package:pharmaguide/data/database/core_database.dart';
import 'package:pharmaguide/data/database/interaction_database.dart';
import 'package:pharmaguide/data/database/user_database.dart';
import 'package:pharmaguide/data/providers/database_providers.dart';
import 'package:pharmaguide/data/providers/reference_data_provider.dart';
import 'package:pharmaguide/features/product_detail/providers/detail_blob_provider.dart';
import 'package:pharmaguide/features/product_detail/providers/fit_score_provider.dart';
import 'package:pharmaguide/features/product_detail/v2/product_detail_v2_connected.dart';
import 'package:pharmaguide/features/safety_alerts/providers/safety_alert_providers.dart';
import 'package:pharmaguide/features/profile/profile_provider.dart';
import 'package:pharmaguide/features/stack/providers/stack_providers.dart';
import 'package:pharmaguide/services/safety_alerts/safety_alert.dart';
import 'package:pharmaguide/services/safety_alerts/safety_alert_repository.dart';

const _dsldId = 'dsld-warfarin-page';
const _title = "Because you're taking Warfarin";

UserStacksLocalData _warfarin({
  String classes = '["class:vitamin_k_antagonists"]',
}) {
  final ts = DateTime.utc(2026, 11, 3, 12);
  return UserStacksLocalData(
    id: 'med-warfarin',
    type: 'medication',
    name: 'Warfarin',
    dsldId: null,
    rxcui: '11289',
    ingredientKeys: null,
    drugClassesCol: classes,
    genericRxcui: '11289',
    ingredientRxcuisCol: null,
    dosage: null,
    frequency: null,
    addedAt: ts,
    clientUpdatedAt: ts,
    deletedAt: null,
    syncedAt: null,
  );
}

Future<void> _seedVitaminKProduct(CoreDatabase db) async {
  await db
      .into(db.productsCore)
      .insert(
        ProductsCoreCompanion.insert(
          dsldId: _dsldId,
          productName: 'Calcium K/D',
          exportVersion: 'test',
          exportedAt: '2026-11-03T00:00:00Z',
          keyIngredientTags: const Value('["vitamin_k"]'),
          mappedCoverage: const Value(1),
        ),
      );
}

Future<void> _seedWarfarinVitaminK(InteractionDatabase db) async {
  await db
      .into(db.interactions)
      .insert(
        InteractionsCompanion.insert(
          id: 'DSI_WAR_VITK',
          agent1Type: 'drug',
          agent1Name: 'Warfarin',
          agent1Id: '11289',
          agent1CanonicalId: const Value(null),
          agent2Type: 'supplement',
          agent2Name: 'Vitamin K',
          agent2Id: 'C0042878',
          agent2CanonicalId: const Value('vitamin_k'),
          severity: 'caution',
          effectType: const Value('inhibitor'),
          mechanism: 'Sudden vitamin K changes can alter warfarin effect.',
          management: 'Keep vitamin K intake consistent.',
          evidenceLevel: const Value('established'),
          sourceUrlsJson:
              '["https://ods.od.nih.gov/factsheets/VitaminK-HealthProfessional/"]',
          sourcePmidsJson: '[]',
          doseDependent: const Value(0),
          direction: const Value('harmful'),
          materiality: const Value('presence'),
          typeAuthored: 'Med-Sup',
          source: 'curated',
          provenance: 'nih_ods',
          versionAdded: 'test',
          versionLastModified: 'test',
          lastUpdated: '2026-07-28',
        ),
      );
}

Future<void> _pumpPage(
  WidgetTester tester,
  UserStacksLocalData medication,
) async {
  final coreDb = CoreDatabase.memory();
  final userDb = UserDatabase.memory();
  final interactionDb = InteractionDatabase.memory();
  await _seedVitaminKProduct(coreDb);
  await _seedWarfarinVitaminK(interactionDb);
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
        safetyAlertRepositoryProvider.overrideWithValue(_VerifiedNoAlerts()),
        activeStackProvider.overrideWith((ref) async => [medication]),
        // No blob warning, so nothing else can stand in for the real check.
        detailBlobProvider.overrideWith(
          (ref, dsldId) async => <String, dynamic>{
            'ingredients': const <Map<String, dynamic>>[],
          },
        ),
        profileProvider.overrideWith(
          (ref) => ProfileNotifier()..setAgeBracket('31-50'),
        ),
        // The real fit check reads blob warnings only, so with no blob warning
        // it comes back clean. It can't resolve its assets in a widget test.
        fitScoreForProductProvider.overrideWith(
          (ref, dsldId) async => const FitScoreResult(
            missingFields: [],
            state: FitAssessmentState.limitedFit,
            reasons: [],
            mappedCoverage: 1,
          ),
        ),
        evaluatorProfileFlagsProvider.overrideWith(
          (ref) async => const <String>{},
        ),
        rdaOptimalUlsProvider.overrideWith((ref) async => const {}),
      ],
      child: const MaterialApp(
        home: ProductDetailV2ConnectedScreen(dsldId: _dsldId),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'a warfarin user sees the warning on a vitamin K product, and no all-clear',
    (tester) async {
      await _pumpPage(tester, _warfarin());

      expect(find.textContaining(_title), findsWidgets);
      expect(find.text('No known concerns'), findsNothing);
    },
  );

  testWidgets('a class the bridge renames still reaches the page', (
    tester,
  ) async {
    await _pumpPage(
      tester,
      _warfarin(classes: '["class:antiplatelet_agents"]'),
    );

    expect(find.textContaining(_title), findsWidgets);
    expect(find.text('No known concerns'), findsNothing);
  });
}

/// A feed that loaded and has nothing to say.
class _VerifiedNoAlerts implements SafetyAlertRepository {
  @override
  Future<SafetyAlertRelease> loadCurrent() async => const SafetyAlertRelease(
    alerts: [],
    baselineRevisions: {},
    isComplete: true,
  );

  @override
  Future<List<SafetyAlert>> loadCachedAlerts() async => const [];
}
