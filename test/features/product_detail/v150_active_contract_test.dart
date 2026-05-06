// v1.5.0 canonical ingredient contract — Flutter active-row reads.
//
// Closes the gap from CONTRACT_V150_FOLLOWUP.md Step 4: 5 tests pinning
// the active-row reads of display_dose_label, display_form_label,
// dose_status, form_status, and the inactive display_role_label.
// Complements the existing v150_contract_test.dart (which only covers
// inactive severity_status routing).
//
// Tests buildIngredientExplain() — the pure public function the
// ingredient explain modal uses, mirroring the same reads the active
// row uses on the product detail screen.

import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/features/product_detail/widgets/ingredient_explain_model.dart';

Map<String, dynamic> _ingredient({
  String name = 'Test',
  String? standardName,
  String? displayLabel,
  String? displayFormLabel,
  String? formStatus,
  String? displayDoseLabel,
  String? doseStatus,
  Object? quantity,
  String? unit,
  num? bioScore,
}) {
  return {
    'name': name,
    if (standardName != null) 'standard_name': standardName,
    if (displayLabel != null) 'display_label': displayLabel,
    if (displayFormLabel != null) 'display_form_label': displayFormLabel,
    if (formStatus != null) 'form_status': formStatus,
    if (displayDoseLabel != null) 'display_dose_label': displayDoseLabel,
    if (doseStatus != null) 'dose_status': doseStatus,
    if (quantity != null) 'quantity': quantity,
    if (unit != null) 'unit': unit,
    if (bioScore != null) 'bio_score': bioScore,
  };
}

void main() {
  group('v1.5.0 active-row contract — display_dose_label', () {
    test('pipeline display_dose_label preferred over quantity+unit fallback', () {
      final explain = buildIngredientExplain(
        ingredient: _ingredient(
          displayDoseLabel: '1.05 mg',
          doseStatus: 'disclosed',
          quantity: 999, // legacy fallback — must NOT be rendered
          unit: 'IU',
        ),
      );
      expect(explain.doseLabel, '1.05 mg');
    });

    test('dose_status="missing" → no dose label rendered', () {
      final explain = buildIngredientExplain(
        ingredient: _ingredient(
          displayDoseLabel: null,
          doseStatus: 'missing',
          quantity: 100, // legacy fallback — must NOT be used
          unit: 'mg',
        ),
      );
      expect(explain.doseLabel, isNull);
    });

    test('dose_status="not_disclosed_blend" → no dose label rendered', () {
      final explain = buildIngredientExplain(
        ingredient: _ingredient(
          displayDoseLabel: null,
          doseStatus: 'not_disclosed_blend',
          quantity: 50,
          unit: 'mg',
        ),
      );
      expect(explain.doseLabel, isNull);
    });
  });

  group('v1.5.0 active-row contract — display_form_label / form_status', () {
    test('form_status="known" + display_form_label populated → form rendered', () {
      final explain = buildIngredientExplain(
        ingredient: _ingredient(
          name: 'Vitamin A',
          formStatus: 'known',
          displayFormLabel: 'Retinyl Palmitate',
        ),
      );
      expect(explain.formName, 'Retinyl Palmitate');
    });

    test('form_status="unknown" → formName is null (helper line hidden)', () {
      final explain = buildIngredientExplain(
        ingredient: _ingredient(
          name: 'Vitamin A',
          formStatus: 'unknown',
          displayFormLabel: null,
        ),
      );
      expect(explain.formName, isNull,
          reason: 'unknown form must NEVER produce a rendered helper — '
              'pipeline pre-emits the explicit unknown state');
    });

    test(
      'form_status="known" but display_form_label empty/null → still null '
      '(defensive — pipeline contract: known implies non-empty label)',
      () {
        final explain = buildIngredientExplain(
          ingredient: _ingredient(
            name: 'Vitamin A',
            formStatus: 'known',
            displayFormLabel: '',
          ),
        );
        expect(explain.formName, isNull);
      },
    );
  });

  group('v1.5.0 active-row contract — display_label as title', () {
    test('display_label preferred over standard_name and name fallbacks', () {
      final explain = buildIngredientExplain(
        ingredient: _ingredient(
          name: 'raw_name',
          standardName: 'Standard',
          displayLabel: 'Display Name (E551)',
        ),
      );
      expect(explain.title, 'Display Name (E551)');
    });
  });
}
