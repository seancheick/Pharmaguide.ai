import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/data/database/core_database.dart';
import 'package:pharmaguide/data/providers/database_providers.dart';
import 'package:pharmaguide/data/providers/detail_blob_provider.dart';
import 'package:pharmaguide/features/product_detail/providers/fit_score_provider.dart';
import 'package:pharmaguide/features/profile/profile_provider.dart';
import 'package:pharmaguide/features/stack/providers/stack_safety_providers.dart';
import 'package:pharmaguide/services/fit_score/e1_dosage_calculator.dart';
import 'package:pharmaguide/services/fit_score/e2a_goal_calculator.dart';
import 'package:pharmaguide/services/fit_score/e2b_age_calculator.dart';
import 'package:pharmaguide/services/fit_score/e2c_medical_calculator.dart';
import 'package:pharmaguide/services/fit_score/fit_score_service.dart';

const _dsldId = 'fit-provider-test';

FitScoreService _service() => FitScoreService(
  e1: E1DosageCalculator(const {'nutrient_recommendations': <Object>[]}),
  e2a: E2aGoalCalculator(const {'user_goal_mappings': <Object>[]}),
  e2b: E2bAgeCalculator(const {'nutrient_recommendations': <Object>[]}),
  e2c: E2cMedicalCalculator(),
);

void main() {
  test('catalog failure surfaces instead of becoming an absent Fit result', () async {
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
        loadedProfileProvider.overrideWith((ref) async => const ProfileState()),
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
  });

  test('declared detail failure surfaces instead of becoming an absent Fit result', () async {
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
        loadedProfileProvider.overrideWith((ref) async => const ProfileState()),
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
  });
}
