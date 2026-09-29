// A row can declare several forms. 12012 / 331488 ship
// "Vitamin A (as Beta-Carotene, Retinyl Acetate)" with matched_forms
// [beta-carotene from mixed carotenoids, retinyl acetate]. The vitamin A
// pregnancy gate excludes beta_carotene / mixed_carotenoids; reading only the
// first form hid the warning even though retinyl acetate is declared. The
// exclusion must hold only when EVERY declared form is excluded (mirrors
// dsld_clean/scripts/profile_gate_evaluator.py and the shared fixture).

import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/core/constants/severity.dart';
import 'package:pharmaguide/services/warnings/interaction_warning.dart';
import 'package:pharmaguide/services/warnings/profile_gate_summary_filter.dart';

Map<String, dynamic> _row(List<Map<String, String>> forms) => {
  'name': 'Vitamin A',
  'standard_name': 'Vitamin A',
  'canonical_id': 'vitamin_a',
  'matched_form': forms.first['form_key'],
  'matched_forms': forms,
};

InteractionWarning _vitaminAPregnancy() => InteractionWarning(
  severity: Severity.caution,
  evidenceLevel: EvidenceLevel.established,
  title: 'Vitamin A in pregnancy',
  mechanism: 'preformed vitamin A',
  management: 'talk to your doctor',
  ingredientName: 'Vitamin A',
  conditionIds: const ['pregnancy'],
  profileGate: {
    'gate_type': 'profile_flag',
    'requires': {
      'conditions_any': <String>[],
      'drug_classes_any': <String>[],
      'profile_flags_any': ['pregnant'],
    },
    'excludes': {
      'conditions_any': <String>[],
      'drug_classes_any': <String>[],
      'profile_flags_any': <String>[],
      'product_forms_any': <String>[],
      'nutrient_forms_any': ['beta_carotene', 'mixed_carotenoids'],
    },
    'dose': null,
  },
);

bool _fires(Map<String, dynamic> row) {
  final warning = _vitaminAPregnancy();
  final context = resolveProfileGateProductContext(
    detailBlob: {
      'ingredients': [row],
      // UL rows come first and carry no matched_forms; forms are the union.
      'rda_ul_data': {
        'analyzed_ingredients': [
          {'name': 'Vitamin A', 'standard_name': 'Vitamin A'},
        ],
      },
    },
    warning: warning,
  );
  return warning.matchesProfile(
    userConditions: const {},
    userDrugClasses: const {},
    userProfileFlags: const {'pregnant'},
    productForm: context.productForm,
    nutrientForm: context.nutrientForm,
    nutrientForms: context.nutrientForms,
    dosePerDay: context.dosePerDay,
  );
}

void main() {
  test(
    '12012 beta-carotene + retinyl acetate row keeps the pregnancy warning',
    () {
      expect(
        _fires(
          _row([
            {
              'form_key': 'beta-carotene from mixed carotenoids',
              'raw_form_text': 'Beta-Carotene',
            },
            {
              'form_key': 'retinyl acetate',
              'raw_form_text': 'Vitamin A Acetate',
            },
          ]),
        ),
        isTrue,
      );
    },
  );

  test('form order does not matter', () {
    expect(
      _fires(
        _row([
          {'form_key': 'retinyl acetate', 'raw_form_text': 'Retinyl Acetate'},
          {
            'form_key': 'beta-carotene from mixed carotenoids',
            'raw_form_text': 'Beta-Carotene',
          },
        ]),
      ),
      isTrue,
    );
  });

  test('a row declaring only excluded carotenoid forms stays suppressed', () {
    expect(
      _fires(
        _row([
          {
            'form_key': 'beta-carotene from mixed carotenoids',
            'raw_form_text': 'Beta-Carotene',
          },
        ]),
      ),
      isFalse,
    );
  });
}
