import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/core/constants/severity.dart';
import 'package:pharmaguide/core/models/fit_score_result.dart';
import 'package:pharmaguide/features/product_detail/v2/sections/review_before_use_section.dart';
import 'package:pharmaguide/features/product_detail/v2/warnings_pipeline.dart';
import 'package:pharmaguide/services/stack/stack_nutrient_aggregator.dart';
import 'package:pharmaguide/services/stack/stack_nutrient_models.dart';
import 'package:pharmaguide/services/warnings/interaction_warning.dart';

const _fixturePath =
    'test/fixtures/pipeline/prebeta_real_products_20261021.json';

Map<String, dynamic> _product(
  Map<String, Map<String, dynamic>> products,
  String dsldId,
) {
  final product = products[dsldId];
  expect(product, isNotNull, reason: 'Missing frozen DSLD product $dsldId');
  return product!;
}

Map<String, dynamic> _blob(
  Map<String, Map<String, dynamic>> products,
  String dsldId,
) => Map<String, dynamic>.from(_product(products, dsldId)['blob'] as Map);

List<InteractionWarning> _profileWarnings({
  required Map<String, Map<String, dynamic>> products,
  required String dsldId,
  Set<String> conditions = const {},
  Set<String> drugClasses = const {},
  Set<String> flags = const {},
}) {
  final blob = _blob(products, dsldId);
  final guarded = composeGuardedWarnings(
    detailBlob: blob,
    productStatus: blob['product_status']?.toString(),
    personalizedWarnings: const [],
    userConditions: conditions,
    userDrugClasses: drugClasses,
    userProfileFlags: flags,
  );
  return partitionProfileWarnings(
    warnings: guarded,
    userConditions: conditions,
    userDrugClasses: drugClasses,
    userProfileFlags: flags,
  ).profile;
}

InteractionWarning _onlyLifeStageWarning(
  List<InteractionWarning> warnings,
  String condition,
) {
  final matches = warnings
      .where((warning) => warning.conditionIds.contains(condition))
      .toList(growable: false);
  expect(matches, hasLength(1));
  return matches.single;
}

void main() {
  late Map<String, Map<String, dynamic>> products;

  setUpAll(() {
    final fixture =
        jsonDecode(File(_fixturePath).readAsStringSync())
            as Map<String, dynamic>;
    products = {
      for (final raw in fixture['products'] as List<dynamic>)
        (raw as Map<String, dynamic>)['dsld_id'].toString(): raw,
    };
  });

  group('real-product profile warnings', () {
    test("pregnant St. John's wort shows the reason and source", () {
      final warning = _onlyLifeStageWarning(
        _profileWarnings(
          products: products,
          dsldId: '18219',
          conditions: const {'pregnancy'},
          flags: const {'pregnant'},
        ),
        'pregnancy',
      );

      expect(warning.severity, Severity.avoid);
      expect(warning.displayBody.toLowerCase(), contains('birth-defect'));
      expect(
        warning.sourceUrls,
        contains('https://www.nccih.nih.gov/health/st-johns-wort'),
      );
    });

    test("breastfeeding St. John's wort uses lactation-specific evidence", () {
      final warning = _onlyLifeStageWarning(
        _profileWarnings(
          products: products,
          dsldId: '18219',
          conditions: const {'lactation'},
          flags: const {'breastfeeding'},
        ),
        'lactation',
      );

      expect(warning.severity, Severity.caution);
      expect(warning.displayBody.toLowerCase(), contains('colic'));
      expect(warning.displayBody.toLowerCase(), contains('drowsiness'));
      expect(warning.displayBody.toLowerCase(), isNot(contains('fetal')));
      expect(
        warning.sourceUrls,
        contains('https://www.ncbi.nlm.nih.gov/books/NBK501770/'),
      );
    });

    test('pregnant sage explains the thujone concern and cites it', () {
      final warning = _onlyLifeStageWarning(
        _profileWarnings(
          products: products,
          dsldId: '252725',
          conditions: const {'pregnancy'},
          flags: const {'pregnant'},
        ),
        'pregnancy',
      );

      expect(warning.severity, Severity.avoid);
      expect(warning.displayBody.toLowerCase(), contains('thujone'));
      expect(
        warning.sourceUrls,
        contains('https://www.nccih.nih.gov/health/sage/'),
      );
    });

    test('kidney disease surfaces the real magnesium accumulation warning', () {
      final warnings = _profileWarnings(
        products: products,
        dsldId: '205309',
        conditions: const {'kidney_disease'},
      );
      final warning = warnings.singleWhere(
        (candidate) => candidate.conditionIds.contains('kidney_disease'),
      );

      expect(warning.severity, Severity.avoid);
      expect(warning.displayBody.toLowerCase(), contains('accumulate'));
      expect(warning.sourceUrls, isNotEmpty);
    });

    test('the same magnesium product does not invent a kidney warning', () {
      final warnings = _profileWarnings(products: products, dsldId: '205309');

      expect(
        warnings.where(
          (warning) => warning.conditionIds.contains('kidney_disease'),
        ),
        isEmpty,
      );
    });

    test(
      'no-data life-stage rows stay out of warnings without false reassurance',
      () {
        final warnings = _profileWarnings(
          products: products,
          dsldId: '33684',
          conditions: const {'pregnancy'},
          flags: const {'pregnant'},
        );
        expect(warnings, isEmpty);

        final summary = buildProfileRelevanceSummary(
          fitResult: const FitScoreResult(missingFields: [], mappedCoverage: 1),
          topGoalLabel: null,
          warnings: warnings,
          interactionHint: '',
          matchedAllergens: const [],
          freeFromConflicts: const [],
          hasInteractionProfile: false,
          hasPregnancyOrBreastfeeding: true,
        );
        expect(summary.headline, kNoProfileConcernsHeadline);
        expect(summary.footnote, kLifeStageClinicianNote);
      },
    );
  });

  test('real magnesium products sum through the production stack owner', () {
    List<Map<String, dynamic>> ingredients(String dsldId) =>
        (_blob(products, dsldId)['ingredients'] as List<dynamic>)
            .map((row) => Map<String, dynamic>.from(row as Map))
            .toList(growable: false);

    final totals = const StackNutrientAggregator().aggregate([
      StackItemNutrients(
        stackEntryId: '205309',
        productName: _product(products, '205309')['product_name'].toString(),
        ingredients: ingredients('205309'),
      ),
      StackItemNutrients(
        stackEntryId: '299065',
        productName: _product(products, '299065')['product_name'].toString(),
        ingredients: ingredients('299065'),
      ),
    ]);

    final magnesium = totals['magnesium'];
    expect(magnesium, isNotNull);
    expect(magnesium!.totalAmount, 240);
    expect(magnesium.unit, 'mg');
    expect(magnesium.contributions, hasLength(2));
    expect(magnesium.hasUnitConflict, isFalse);
  });
}
