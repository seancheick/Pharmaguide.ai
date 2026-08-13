import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/services/ingredients/ingredient_row_fields.dart';

void main() {
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
}
