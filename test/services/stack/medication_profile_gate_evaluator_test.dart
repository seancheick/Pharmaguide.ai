import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/services/stack/medication_profile_gate_evaluator.dart';

void main() {
  const rawRules = <String, dynamic>{
    'medication_profile_gate_rules': <Map<String, dynamic>>[
      <String, dynamic>{
        'id': 'MCR_PREGNANCY_NSAIDS',
        'severity': 'caution',
        'evidence_level': 'established',
        'headline': 'Review NSAID use in pregnancy',
        'body':
            'NSAIDs such as ibuprofen and naproxen are generally avoided '
            'from 20 weeks of pregnancy; after about 30 weeks they should '
            'not be used unless your clinician specifically directs.',
        'management':
            'Check with your OB/clinician before using NSAIDs during '
            'pregnancy. Acetaminophen may be discussed as an option, but '
            'use should still follow clinician guidance.',
        'sources': <String>[
          'https://www.fda.gov/drugs/drug-safety-and-availability/fda-recommends-avoiding-use-nsaids-pregnancy-20-weeks-or-later-because-they-can-result-low-amniotic',
        ],
        'profile_gate': <String, dynamic>{
          'gate_type': 'combination',
          'requires': <String, dynamic>{
            'conditions_any': <String>[],
            'drug_classes_any': <String>['nsaids'],
            'profile_flags_any': <String>['pregnant'],
          },
          'excludes': <String, dynamic>{
            'conditions_any': <String>[],
            'drug_classes_any': <String>[],
            'profile_flags_any': <String>[],
            'product_forms_any': <String>[],
            'nutrient_forms_any': <String>[],
          },
        },
      },
    ],
  };

  final rules = MedicationProfileGateRule.listFromJson(rawRules);
  const evaluator = MedicationProfileGateEvaluator();

  test('pregnant plus ibuprofen NSAID class fires warning', () {
    final warnings = evaluator.evaluate(
      rules: rules,
      medicationName: 'Motrin',
      medicationProfileGateClassIds: const {'nsaids'},
      userProfileFlags: const {'pregnant'},
    );

    expect(warnings, hasLength(1));
    expect(warnings.single.ruleId, 'MCR_PREGNANCY_NSAIDS');
    expect(warnings.single.medicationName, 'Motrin');
    expect(warnings.single.headline, 'Review NSAID use in pregnancy');
  });

  test('not pregnant plus ibuprofen does not fire', () {
    final warnings = evaluator.evaluate(
      rules: rules,
      medicationName: 'Motrin',
      medicationProfileGateClassIds: const {'nsaids'},
      userProfileFlags: const {},
    );

    expect(warnings, isEmpty);
  });

  test('pregnant plus acetaminophen does not fire and makes no safe claim', () {
    final warnings = evaluator.evaluate(
      rules: rules,
      medicationName: 'Tylenol',
      medicationProfileGateClassIds: const {},
      userProfileFlags: const {'pregnant'},
    );

    expect(warnings, isEmpty);
    expect(rules.single.management.toLowerCase(), isNot(contains('safe')));
  });

  test('pregnant plus aspirin antiplatelet class does not fire in v1', () {
    final warnings = evaluator.evaluate(
      rules: rules,
      medicationName: 'Aspirin',
      medicationProfileGateClassIds: const {'antiplatelet_agents'},
      userProfileFlags: const {'pregnant'},
    );

    expect(warnings, isEmpty);
  });
}
