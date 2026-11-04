import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/services/ingredients/ingredient_row_fields.dart';

void main() {
  test('canonical magnesium range reaches app adequacy and safety readers', () {
    final fixtures =
        jsonDecode(
              File(
                'test/fixtures/serving_basis_magnesium.json',
              ).readAsStringSync(),
            )
            as Map<String, dynamic>;
    for (final entry in {'201495': 150.0, '184671': 120.0}.entries) {
      final product = fixtures[entry.key] as Map<String, dynamic>;
      final row = product['dose_row'] as Map<String, dynamic>;
      expect(product['serving_info']['basis_count'], 1);
      expect(product['dosing_summary'], 'Take 1-4 capsules daily');
      expect(readAdequacyDoseAmount(row), entry.value);
      expect(readDoseAmount(row), entry.value * 4);
      expect(readUlDoseAmount(row), entry.value * 4);
      expect(readUlDoseUnit(row), 'mg');
    }
  });
  test('reviewed unit conflict blocks every numerical dose fallback', () {
    final row = <String, dynamic>{
      'quantity': 75,
      'unit': 'mg',
      'per_day_min': 75,
      'per_day_max': 75,
      'normalized_amount': 75000,
      'safety_exposure': {'per_day': 75000, 'unit': 'mcg'},
      'adequacy_exposure': {'per_day': 75000, 'unit': 'mcg'},
      'dose_data_quality': {
        'status': 'unresolved_unit',
        'reason': 'label_unit_conflict',
      },
    };
    expect(readDoseAmount(row), isNull);
    expect(readAdequacyDoseAmount(row), isNull);
    expect(readUlDoseAmount(row), isNull);
    expect(readDoseUnit(row), 'mg');
    row['dose_data_quality'] = {'status': 'corrected'};
    expect(readDoseAmount(row), 75);
  });
  group('pipeline UL exposure contract', () {
    test('uses safety mass without changing activity or adequacy readers', () {
      final row = <String, dynamic>{
        'per_day_min': 450,
        'per_day_max': 900,
        'converted_unit': 'mg',
        'safety_exposure': {'per_day': '1800', 'unit': 'MG'},
      };
      expect(readUlDoseAmount(row), 1800);
      expect(readUlDoseUnit(row), 'mg');
      expect(readDoseAmount(row), 900);
      expect(readAdequacyDoseAmount(row), 450);
    });
    test('older rows retain dose fallback, malformed contracts do not', () {
      expect(readUlDoseAmount({'per_day_max': 15, 'unit': 'mg'}), 15);
      expect(readUlDoseUnit({'unit': 'mcg'}), 'mcg');
      for (final exposure in [
        null,
        <String, dynamic>{},
        {'per_day': 1800},
        {'per_day': 'NaN', 'unit': 'mg'},
        {'per_day': 1800, 'unit': 3},
      ]) {
        expect(
          readUlDoseAmount({
            'quantity': 900,
            'unit': 'mg',
            'safety_exposure': exposure,
          }),
          isNull,
        );
      }
    });
  });

  group('readDoseAmount — per-day-first priority (B#1)', () {
    test('per-day fields win over raw per-serving quantity', () {
      // The bug: stack_dose_summer read `quantity` (raw per-serving) before
      // `converted_quantity`/`per_day_max` (per-day), so a "2 caps/day" row
      // undercounted vs the UL checker. Thresholds are per-day → per-day wins.
      expect(
        readDoseAmount({'quantity': 500, 'converted_quantity': 1000}),
        1000,
      );
      expect(readDoseAmount({'quantity': 500, 'per_day_max': 1000}), 1000);
    });

    test('falls through to raw quantity when no per-day field present', () {
      expect(readDoseAmount({'quantity': 500}), 500);
      expect(readDoseAmount({'amount': 250}), 250);
      expect(readDoseAmount({'dose_amount': 37.5}), 37.5);
    });

    test('parses numeric strings, rejects non-finite and non-numeric', () {
      expect(readDoseAmount({'quantity': '350'}), 350);
      expect(readDoseAmount({'quantity': 'Infinity'}), isNull);
      expect(readDoseAmount({'quantity': 'NaN'}), isNull);
      expect(readDoseAmount({'quantity': double.infinity}), isNull);
      expect(readDoseAmount({'quantity': 'not a number'}), isNull);
      expect(readDoseAmount(const {}), isNull);
    });
  });

  group('readAdequacyDoseAmount — minimum/recommended exposure', () {
    test('prefers per_day_min while safety reader keeps per_day_max', () {
      final row = {
        'quantity': 100,
        'converted_quantity': 100,
        'per_day_min': 100,
        'per_day_max': 300,
      };

      expect(readAdequacyDoseAmount(row), 100);
      expect(readDoseAmount(row), 300);
    });

    test('falls back to the regular dose when no minimum is emitted', () {
      expect(readAdequacyDoseAmount({'converted_quantity': 50}), 50);
    });
  });

  group('readDoseUnit — canonical normalization', () {
    test('folds spelling and lowercases (parallels amount priority)', () {
      expect(readDoseUnit({'unit': 'IU'}), 'iu');
      expect(readDoseUnit({'unit': 'µg'}), 'mcg');
      expect(readDoseUnit({'unit': 'ug'}), 'mcg');
      expect(readDoseUnit({'converted_unit': 'MG', 'unit': 'iu'}), 'mg');
      expect(readDoseUnit(const {}), '');
    });
  });

  group('isUsableDoseRow — shared filter (B#2)', () {
    test('drops blend containers and parent-total roll-ups', () {
      expect(isUsableDoseRow({'is_proprietary_blend': true}), isFalse);
      expect(isUsableDoseRow({'is_parent_total': true}), isFalse);
      expect(isUsableDoseRow({'dose_role': 'form_component'}), isFalse);
      expect(isUsableDoseRow({'dose_role': 'ul_scoped_component'}), isFalse);
      expect(isUsableDoseRow({'is_active': false}), isFalse);
      expect(isUsableDoseRow({'is_label_descriptor': true}), isFalse);
    });

    test('keeps ordinary rows and missing/false flags (opt-out semantics)', () {
      expect(isUsableDoseRow(const {}), isTrue);
      expect(
        isUsableDoseRow({
          'is_proprietary_blend': false,
          'is_parent_total': false,
        }),
        isTrue,
      );
    });
  });

  group('readDoseNameKeys / readCanonicalId', () {
    test('name keys canonicalize every present name field', () {
      final keys = readDoseNameKeys({
        'standard_name': 'Vitamin-D3',
        'mapped_name': 'vitamin_d3',
      });
      expect(keys, contains('vitamin_d3'));
    });

    test('canonical id prefers the nutrient_group_id roll-up', () {
      expect(
        readCanonicalId({
          'nutrient_group_id': 'vitamin_k',
          'canonical_id': 'vitamin_k1',
        }),
        'vitamin_k',
      );
    });

    test('legacy form ids roll up when nutrient_group_id is absent', () {
      expect(readCanonicalId({'canonical_id': 'vitamin_k1'}), 'vitamin_k');
      expect(readCanonicalId({'canonical_id': 'vitamin_k2'}), 'vitamin_k');
      expect(readCanonicalId({'canonical_id': 'vitamin_d2'}), 'vitamin_d');
      expect(readCanonicalId({'canonical_id': 'vitamin_d3'}), 'vitamin_d');
      expect(readCanonicalId({'canonical_id': 'vitamin_b9_folate'}), 'folate');
      expect(readCanonicalId({'canonical_id': 'folic_acid'}), 'folate');
    });
  });

  group('pipelineBlocksDoseRead', () {
    const readable = <String, dynamic>{
      'skip_ul_check': true,
      'ul_assessment_status': 'not_applicable',
      'dose_role': 'declared_total',
      'per_day_min': 400.0,
      'per_day_max': 400.0,
      'converted_unit': 'mg',
    };

    test('a declared total with no applicable UL can be read', () {
      expect(pipelineBlocksDoseRead(readable), isFalse);
      expect(readDoseAmount(readable), 400);
      expect(readDoseUnit(readable), 'mg');
    });

    test('a total assessed within its limit can be read', () {
      expect(
        pipelineBlocksDoseRead({
          ...readable,
          'ul_assessment_status': 'assessed_within_limit',
        }),
        isFalse,
      );
    });

    test('a row with no skip is never blocked here', () {
      expect(
        pipelineBlocksDoseRead(const {'quantity': 5, 'unit': 'mg'}),
        isFalse,
      );
    });

    test('indeterminate, missing and unknown statuses stay blocked', () {
      for (final status in ['indeterminate', 'evaluated', 'future_status']) {
        expect(
          pipelineBlocksDoseRead({...readable, 'ul_assessment_status': status}),
          isTrue,
          reason: status,
        );
      }
      expect(
        pipelineBlocksDoseRead({...readable}..remove('ul_assessment_status')),
        isTrue,
      );
    });

    test('a component or an unroled row stays blocked', () {
      for (final role in ['form_component', 'ul_scoped_component', null]) {
        expect(
          pipelineBlocksDoseRead({...readable, 'dose_role': role}),
          isTrue,
          reason: '$role',
        );
      }
    });

    test('a compound duplicate stays blocked', () {
      expect(
        pipelineBlocksDoseRead({
          ...readable,
          'skip_ul_reason': 'compound_duplicate_row',
        }),
        isTrue,
      );
    });

    test('a missing daily figure stays blocked', () {
      for (final field in ['per_day_min', 'per_day_max', 'converted_unit']) {
        expect(
          pipelineBlocksDoseRead({...readable}..remove(field)),
          isTrue,
          reason: field,
        );
      }
      expect(
        pipelineBlocksDoseRead({...readable, 'converted_unit': ' '}),
        isTrue,
      );
    });

    test('an older catalog row with a skip stays blocked', () {
      expect(
        pipelineBlocksDoseRead(const {
          'standard_name': 'Vitamin A',
          'quantity': 2000,
          'daily_amount_unit': 'IU',
          'skip_ul_check': true,
        }),
        isTrue,
      );
    });
  });

  group('readUlDoseRange', () {
    Map<String, dynamic> row(Map<String, dynamic> exposure) => {
      'canonical_id': 'vitamin_e',
      'per_day_max': 60.3,
      'converted_unit': 'mg',
      'safety_exposure': {'per_day': 60.3, 'unit': 'mg', ...exposure},
    };

    test('reads both bounds, with per_day kept for existing readers', () {
      final range = row({'low_per_day': 80.0, 'high_per_day': '176.3'});

      expect(readUlDoseRange(range)?.low, 80);
      expect(readUlDoseRange(range)?.high, 176.3);
      expect(readUlDoseAmount(range), 60.3);
    });

    test('an exact row has no range', () {
      expect(hasUlDoseRange(row({})), isFalse);
      expect(readUlDoseRange(row({})), isNull);
      expect(readUlDoseAmount(row({})), 60.3);
    });

    test('a malformed range does not fall back to per_day', () {
      for (final exposure in [
        {'low_per_day': 80.0},
        {'high_per_day': 176.3},
        {'low_per_day': 'bad', 'high_per_day': 176.3},
        {'low_per_day': 200.0, 'high_per_day': 176.3},
      ]) {
        expect(hasUlDoseRange(row(exposure)), isTrue, reason: '$exposure');
        expect(readUlDoseRange(row(exposure)), isNull, reason: '$exposure');
        expect(readUlDoseAmount(row(exposure)), isNull, reason: '$exposure');
      }
    });
  });
}
