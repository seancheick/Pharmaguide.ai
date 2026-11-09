import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/core/models/fit_score_result.dart';
import 'package:pharmaguide/services/crash_reporting_service.dart';
import 'package:pharmaguide/data/database/core_database.dart';
import 'package:pharmaguide/data/database/user_database.dart';
import 'package:pharmaguide/data/supabase/detail_blob_service.dart';
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
import 'package:pharmaguide/services/stack/stack_nutrient_models.dart';

const _dsldId = 'fit-provider-test';

FitScoreService _service() => FitScoreService(
  e1: E1DosageCalculator(const {'nutrient_recommendations': <Object>[]}),
  e2a: E2aGoalCalculator(const {'user_goal_mappings': <Object>[]}),
  e2b: E2bAgeCalculator(const {'nutrient_recommendations': <Object>[]}),
);

class _OfflineBlobService extends DetailBlobService {
  @override
  Future<Map<String, dynamic>?> fetchDetailBlobByHash(String sha256) =>
      throw StateError('offline: the network must not be needed');
}

class _DelayedCoreDatabase extends CoreDatabase {
  _DelayedCoreDatabase() : super.memory();
  final entered = Completer<void>();
  final resume = Completer<void>();
  @override
  Future<ProductsCoreData?> findById(String dsldId) async {
    entered.complete();
    await resume.future;
    return super.findById(dsldId);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'leaving detail during a catalog read does not use a disposed ref',
    () async {
      final coreDb = _DelayedCoreDatabase();
      addTearDown(coreDb.close);
      await coreDb
          .into(coreDb.productsCore)
          .insert(
            ProductsCoreCompanion.insert(
              dsldId: _dsldId,
              productName: 'Delayed product',
              exportVersion: 'test',
              exportedAt: '2026-11-08T00:00:00Z',
            ),
          );
      final container = ProviderContainer(
        overrides: [
          coreDatabaseProvider.overrideWithValue(coreDb),
          fitScoreServiceProvider.overrideWith((ref) async => _service()),
          loadedProfileProvider.overrideWith(
            (ref) async => const ProfileState(),
          ),
          evaluatorProfileFlagsProvider.overrideWith(
            (ref) async => const <String>{},
          ),
          currentStackMedicationClassIdsProvider.overrideWith(
            (ref) async => const <String>{},
          ),
          detailBlobProvider.overrideWith((ref, id) async => null),
        ],
      );
      addTearDown(container.dispose);
      final subscription = container.listen(
        fitScoreForProductProvider(_dsldId),
        (_, _) {},
      );
      await coreDb.entered.future;
      subscription.close();
      await container.pump();
      CrashReportingService().clearBuffersForTest();
      coreDb.resume.complete();
      await pumpEventQueue();
      expect(CrashReportingService().recordedErrors, isEmpty);
    },
  );
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
  group('a verdict moves only for a real reason', () {
    Map<String, dynamic> vitaminEBlob() => {
      'rda_ul_data': {
        'analyzed_ingredients': [
          {
            'canonical_id': 'vitamin_e',
            'standard_name': 'Vitamin E',
            'quantity': 900,
            'per_day_min': 900,
            'per_day_max': 900,
            'unit': 'mg alpha-tocopherol',
            'converted_unit': 'mg alpha-tocopherol',
            'safety_exposure': {'per_day': 900, 'unit': 'mg alpha-tocopherol'},
            'over_ul': false,
            'ul': 1000,
            'pct_ul': 90,
            'ul_gate_eligible': true,
            'skip_ul_check': false,
          },
        ],
      },
    };

    FitScoreService realService() {
      final rda =
          jsonDecode(
                File(
                  'assets/reference_data/rda_optimal_uls.json',
                ).readAsStringSync(),
              )
              as Map<String, dynamic>;
      return FitScoreService(
        e1: E1DosageCalculator(rda),
        e2a: E2aGoalCalculator(const {'user_goal_mappings': <Object>[]}),
        e2b: E2bAgeCalculator(rda),
      );
    }

    Future<CoreDatabase> seededCore({String? sha}) async {
      final coreDb = CoreDatabase.memory();
      addTearDown(coreDb.close);
      await coreDb
          .into(coreDb.productsCore)
          .insert(
            ProductsCoreCompanion.insert(
              dsldId: _dsldId,
              productName: 'Vitamin E',
              exportVersion: 'test',
              exportedAt: '2026-10-28T00:00:00Z',
              mappedCoverage: const Value(1),
              detailBlobSha256: Value(sha),
            ),
          );
      return coreDb;
    }

    const adolescentPregnancy = ProfileState(
      ageBracket: '14-18',
      sex: 'Female',
      conditions: ['pregnancy'],
    );

    test('a new catalog hash offline keeps the old blob on disk but never '
        'scores with it', () async {
      final coreDb = await seededCore(sha: 'new-sha');
      final userDb = UserDatabase.memory();
      addTearDown(userDb.close);
      await userDb.cacheDetail(_dsldId, jsonEncode(vitaminEBlob()), 'old-sha');
      final container = ProviderContainer(
        overrides: [
          coreDatabaseProvider.overrideWithValue(coreDb),
          userDatabaseProvider.overrideWithValue(userDb),
          detailBlobServiceProvider.overrideWithValue(_OfflineBlobService()),
          fitScoreServiceProvider.overrideWith((ref) async => realService()),
          loadedProfileProvider.overrideWith(
            (ref) async => adolescentPregnancy,
          ),
          evaluatorProfileFlagsProvider.overrideWith(
            (ref) async => const <String>{},
          ),
          currentStackMedicationClassIdsProvider.overrideWith(
            (ref) async => const <String>{},
          ),
          profileWarningRuleWarningsProvider.overrideWith(
            (ref, id) async => const [],
          ),
        ],
      );
      addTearDown(container.dispose);

      await expectLater(
        container.read(fitScoreForProductProvider(_dsldId).future),
        throwsA(anything),
        reason:
            'the product page reads this as "checks failed", never as no '
            'known concerns',
      );
      expect((await userDb.getCachedDetail(_dsldId))?.sha256, 'old-sha');
    });

    test('30 days offline gives the same result as today', () async {
      final coreDb = await seededCore(sha: 'same-sha');
      final userDb = UserDatabase.memory();
      addTearDown(userDb.close);
      final blob = jsonEncode(vitaminEBlob());

      Future<FitScoreResult?> resultWithCacheAged(Duration age) async {
        await userDb
            .into(userDb.detailCache)
            .insertOnConflictUpdate(
              DetailCacheCompanion(
                dsldId: const Value(_dsldId),
                blobJson: Value(blob),
                sha256: const Value('same-sha'),
                cachedAt: Value(DateTime.now().subtract(age)),
              ),
            );
        final container = ProviderContainer(
          overrides: [
            coreDatabaseProvider.overrideWithValue(coreDb),
            userDatabaseProvider.overrideWithValue(userDb),
            detailBlobServiceProvider.overrideWithValue(_OfflineBlobService()),
            fitScoreServiceProvider.overrideWith((ref) async => realService()),
            loadedProfileProvider.overrideWith(
              (ref) async => adolescentPregnancy,
            ),
            evaluatorProfileFlagsProvider.overrideWith(
              (ref) async => const <String>{},
            ),
            currentStackMedicationClassIdsProvider.overrideWith(
              (ref) async => const <String>{},
            ),
            profileWarningRuleWarningsProvider.overrideWith(
              (ref, id) async => const [],
            ),
          ],
        );
        addTearDown(container.dispose);
        return container.read(fitScoreForProductProvider(_dsldId).future);
      }

      final today = await resultWithCacheAged(Duration.zero);
      final later = await resultWithCacheAged(const Duration(days: 30));

      expect(today, isNotNull);
      expect(later, isNotNull);
      expect(later!.state, today!.state);
      expect(later.reasons, today.reasons);
      expect(
        later.nutrientStatuses.map((s) => (s.tier, s.ul)),
        today.nutrientStatuses.map((s) => (s.tier, s.ul)),
      );
      expect(later.nutrientStatuses.single.tier, NutrientTier.exceedsUl);
    });

    test(
      'a profile change during a scan wins over the check in flight',
      () async {
        final coreDb = await seededCore();
        final profile = StateProvider<ProfileState>(
          (ref) => const ProfileState(ageBracket: '31-50', sex: 'Female'),
        );
        final blobGate = Completer<void>();
        final container = ProviderContainer(
          overrides: [
            coreDatabaseProvider.overrideWithValue(coreDb),
            fitScoreServiceProvider.overrideWith((ref) async => realService()),
            loadedProfileProvider.overrideWith(
              (ref) async => ref.watch(profile),
            ),
            evaluatorProfileFlagsProvider.overrideWith(
              (ref) async => const <String>{},
            ),
            currentStackMedicationClassIdsProvider.overrideWith(
              (ref) async => const <String>{},
            ),
            profileWarningRuleWarningsProvider.overrideWith(
              (ref, id) async => const [],
            ),
            detailBlobProvider.overrideWith((ref, dsldId) async {
              await blobGate.future;
              return vitaminEBlob();
            }),
          ],
        );
        addTearDown(container.dispose);

        final seen = <FitScoreResult>[];
        final subscription = container.listen(
          fitScoreForProductProvider(_dsldId),
          (_, next) {
            final value = next.asData?.value;
            if (value != null && !next.isLoading) seen.add(value);
          },
          fireImmediately: true,
        );
        addTearDown(subscription.close);
        await pumpEventQueue();

        // The user edits their profile while the scan is still fetching data.
        container.read(profile.notifier).state = adolescentPregnancy;
        await pumpEventQueue();
        blobGate.complete();

        final fit = await container.read(
          fitScoreForProductProvider(_dsldId).future,
        );
        await pumpEventQueue();

        expect(fit!.nutrientStatuses.single.tier, NutrientTier.exceedsUl);
        expect(
          seen.map((f) => f.nutrientStatuses.single.tier),
          everyElement(NutrientTier.exceedsUl),
          reason: 'the result for the old profile must never reach the screen',
        );
      },
    );
  });

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
