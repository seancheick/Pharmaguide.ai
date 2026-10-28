import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/core/models/fit_score_result.dart';
import 'package:pharmaguide/data/database/core_database.dart';
import 'package:pharmaguide/data/providers/database_providers.dart';
import 'package:pharmaguide/data/providers/detail_blob_provider.dart';
import 'package:pharmaguide/features/product_detail/providers/fit_score_provider.dart';
import 'package:pharmaguide/features/profile/profile_provider.dart';
import 'package:pharmaguide/features/product_detail/providers/profile_warning_rule_provider.dart';
import 'package:pharmaguide/features/product_detail/v2/sections/review_before_use_section.dart';
import 'package:pharmaguide/features/stack/providers/stack_safety_providers.dart';
import 'package:pharmaguide/services/fit_score/e1_dosage_calculator.dart';
import 'package:pharmaguide/services/fit_score/e2a_goal_calculator.dart';
import 'package:pharmaguide/services/fit_score/e2b_age_calculator.dart';
import 'package:pharmaguide/services/fit_score/fit_score_service.dart';

const _dsldId = 'fit-provider-test';

FitScoreService _service() => FitScoreService(
  e1: E1DosageCalculator(const {'nutrient_recommendations': <Object>[]}),
  e2a: E2aGoalCalculator(const {'user_goal_mappings': <Object>[]}),
  e2b: E2bAgeCalculator(const {'nutrient_recommendations': <Object>[]}),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final (id, name, amount, unit, adultUl, personalUl) in [
    ('vitamin_e', 'Vitamin E', 900, 'mg alpha-tocopherol', 1000, 800),
    ('vitamin_a', 'Vitamin A', 2900, 'mcg RAE', 3000, 2800),
  ]) {
    test(
      '$name real adolescent pregnancy profile reaches personal summary',
      () async {
        final rda =
            jsonDecode(
                  File(
                    'assets/reference_data/rda_optimal_uls.json',
                  ).readAsStringSync(),
                )
                as Map<String, dynamic>;
        final service = FitScoreService(
          e1: E1DosageCalculator(rda),
          e2a: E2aGoalCalculator(const {'user_goal_mappings': <Object>[]}),
          e2b: E2bAgeCalculator(rda),
        );
        final coreDb = CoreDatabase.memory();
        addTearDown(coreDb.close);
        await coreDb
            .into(coreDb.productsCore)
            .insert(
              ProductsCoreCompanion.insert(
                dsldId: _dsldId,
                productName: name,
                exportVersion: 'test',
                exportedAt: '2026-10-28T00:00:00Z',
                mappedCoverage: const Value(1),
                goalMatches: const Value('["GOAL_PRENATAL_PREGNANCY"]'),
                goalMatchConfidence: const Value(1),
              ),
            );
        final container = ProviderContainer(
          overrides: [
            coreDatabaseProvider.overrideWithValue(coreDb),
            fitScoreServiceProvider.overrideWith((ref) async => service),
            loadedProfileProvider.overrideWith(
              (ref) async => const ProfileState(
                ageBracket: '14-18',
                sex: 'Female',
                conditions: ['pregnancy'],
                goals: ['GOAL_PRENATAL_PREGNANCY'],
              ),
            ),
            currentStackMedicationClassIdsProvider.overrideWith(
              (ref) async => const <String>{},
            ),
            profileWarningRuleWarningsProvider.overrideWith(
              (ref, id) async => const [],
            ),
            detailBlobProvider.overrideWith(
              (ref, dsldId) async => {
                'rda_ul_data': {
                  'analyzed_ingredients': [
                    {
                      'canonical_id': id,
                      'standard_name': name,
                      'quantity': amount,
                      'per_day_min': amount,
                      'per_day_max': amount,
                      'unit': unit,
                      'converted_unit': unit,
                      'safety_exposure': {'per_day': amount, 'unit': unit},
                      'over_ul': false,
                      'ul': adultUl,
                      'pct_ul': amount / adultUl * 100,
                      'ul_gate_eligible': true,
                      'skip_ul_check': false,
                    },
                  ],
                },
              },
            ),
          ],
        );
        addTearDown(container.dispose);
        final fit = await container.read(
          fitScoreForProductProvider(_dsldId).future,
        );
        expect(fit, isNotNull);
        expect(fit!.state, isNot(FitAssessmentState.strongMatch));
        expect(fit.nutrientStatuses.single.ul, personalUl);
        expect(fit.nutrientStatuses.single.ulIsFallback, isFalse);
        final summary = buildProfileRelevanceSummary(
          fitResult: fit,
          topGoalLabel: null,
          warnings: const [],
          interactionHint: '',
          matchedAllergens: const [],
          freeFromConflicts: const [],
          hasInteractionProfile: true,
          hasPregnancyOrBreastfeeding: true,
        );
        expect(summary.headline, 'Review before use');
        expect(summary.rows.single.headline, '$name above the upper limit');
      },
    );
  }
  test(
    'catalog failure surfaces instead of becoming an absent Fit result',
    () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'pharmaguide-fit-corrupt-core-',
      );
      addTearDown(() => tempDir.delete(recursive: true));
      final dbFile = File('${tempDir.path}/pharmaguide_core.db');
      await dbFile.writeAsString('not a sqlite database');
      final coreDb = CoreDatabase.open(dbFile.path);
      addTearDown(coreDb.close);
      final container = ProviderContainer(
        overrides: [
          coreDatabaseProvider.overrideWithValue(coreDb),
          fitScoreServiceProvider.overrideWith((ref) async => _service()),
          loadedProfileProvider.overrideWith(
            (ref) async => const ProfileState(),
          ),
          currentStackMedicationClassIdsProvider.overrideWith(
            (ref) async => const <String>{},
          ),
        ],
      );
      addTearDown(container.dispose);

      await expectLater(
        container.read(fitScoreForProductProvider(_dsldId).future),
        throwsA(anything),
      );
    },
  );

  test(
    'declared detail failure surfaces instead of becoming an absent Fit result',
    () async {
      final coreDb = CoreDatabase.memory();
      addTearDown(coreDb.close);
      await coreDb
          .into(coreDb.productsCore)
          .insert(
            ProductsCoreCompanion.insert(
              dsldId: _dsldId,
              productName: 'Fit Provider Product',
              exportVersion: 'test',
              exportedAt: '2026-07-29T00:00:00Z',
              mappedCoverage: const Value(1),
            ),
          );

      final container = ProviderContainer(
        overrides: [
          coreDatabaseProvider.overrideWithValue(coreDb),
          fitScoreServiceProvider.overrideWith((ref) async => _service()),
          loadedProfileProvider.overrideWith(
            (ref) async => const ProfileState(),
          ),
          currentStackMedicationClassIdsProvider.overrideWith(
            (ref) async => const <String>{},
          ),
          detailBlobProvider.overrideWith(
            (ref, dsldId) async => throw Exception('detail unavailable'),
          ),
        ],
      );
      addTearDown(container.dispose);

      await expectLater(
        container.read(fitScoreForProductProvider(_dsldId).future),
        throwsA(anything),
      );
    },
  );
}
