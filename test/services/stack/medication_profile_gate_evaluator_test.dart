import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/core/constants/severity.dart';
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
      <String, dynamic>{
        'id': 'MCR_KIDNEY_DISEASE_NSAIDS',
        'severity': 'avoid',
        'evidence_level': 'established',
        'headline': 'NSAIDs are not recommended with kidney disease',
        'body':
            'NSAIDs such as ibuprofen and naproxen can reduce kidney blood '
            'flow and may worsen kidney function.',
        'management':
            'Avoid NSAID use unless your kidney clinician or prescriber '
            'specifically directs it.',
        'sources': <String>[
          'https://www.niddk.nih.gov/health-information/kidney-disease/keeping-kidneys-safe',
        ],
        'profile_gate': <String, dynamic>{
          'gate_type': 'combination',
          'requires': <String, dynamic>{
            'conditions_any': <String>['kidney_disease'],
            'drug_classes_any': <String>['nsaids'],
            'profile_flags_any': <String>[],
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

  test('missing medication profile-gate evidence hydrates as ungraded', () {
    final rule = MedicationProfileGateRule.fromJson({
      'id': 'MCR_TEST',
      'severity': 'caution',
      'headline': 'Review medication use',
      'body': 'Review before use.',
      'management': 'Ask your clinician.',
      'profile_gate': <String, dynamic>{},
    });

    expect(rule.evidenceLevel, EvidenceLevel.ungraded);
  });

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
    final pregnancyRule = rules.firstWhere(
      (rule) => rule.id == 'MCR_PREGNANCY_NSAIDS',
    );
    expect(pregnancyRule.management.toLowerCase(), isNot(contains('safe')));
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

  test('kidney disease plus ibuprofen NSAID class fires warning', () {
    final warnings = evaluator.evaluate(
      rules: rules,
      medicationName: 'ibuprofen',
      medicationProfileGateClassIds: const {'nsaids'},
      userProfileFlags: const {},
      userConditions: const {'kidney_disease'},
    );

    expect(warnings, hasLength(1));
    expect(warnings.single.ruleId, 'MCR_KIDNEY_DISEASE_NSAIDS');
    expect(warnings.single.medicationName, 'ibuprofen');
    expect(
      warnings.single.headline,
      'NSAIDs are not recommended with kidney disease',
    );
  });

  test('kidney disease without NSAID class does not fire', () {
    final warnings = evaluator.evaluate(
      rules: rules,
      medicationName: 'Tylenol',
      medicationProfileGateClassIds: const {},
      userProfileFlags: const {},
      userConditions: const {'kidney_disease'},
    );

    expect(warnings, isEmpty);
  });
}
