import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/services/warnings/warning_rule_ref_resolver.dart';

const _gate = <String, dynamic>{
  'gate_type': 'condition',
  'requires': <String, dynamic>{
    'conditions_any': <String>['diabetes'],
    'drug_classes_any': <String>[],
    'profile_flags_any': <String>[],
  },
  'excludes': <String, dynamic>{
    'conditions_any': <String>[],
    'drug_classes_any': <String>[],
    'profile_flags_any': <String>[],
    'product_forms_any': <String>[],
    'nutrient_forms_any': <String>[],
  },
  'dose': null,
};

const _rule = <String, dynamic>{
  'id': 'RULE_TEST_MAGNESIUM_DIABETES',
  'subject_ref': <String, dynamic>{
    'db': 'ingredient_quality_map',
    'canonical_id': 'magnesium',
  },
  'condition_rules': <Map<String, dynamic>>[
    <String, dynamic>{
      'condition_id': 'diabetes',
      'severity': 'caution',
      'evidence_level': 'probable',
      'mechanism': 'Magnesium may affect glucose control.',
      'action': 'Monitor glucose with your clinician.',
      'sources': <String>[
        'https://ods.od.nih.gov/factsheets/Magnesium-HealthProfessional/',
      ],
      'alert_headline': 'May affect glucose control',
      'alert_body':
          'If you have diabetes, discuss magnesium use with your clinician.',
      'informational_note':
          'Magnesium and glucose control may be relevant for diabetes.',
      'profile_gate': _gate,
      'direction': 'harmful',
      'materiality': 'presence',
    },
  ],
  'drug_class_rules': <Map<String, dynamic>>[],
};

const _fullWarning = <String, dynamic>{
  'type': 'interaction',
  'severity': 'caution',
  'severity_contextual': 'informational',
  'display_mode_default': 'suppress',
  'title': 'Magnesium / diabetes',
  'detail': 'Magnesium may affect glucose control.',
  'action': 'Monitor glucose with your clinician.',
  'alert_headline': 'May affect glucose control',
  'alert_body':
      'If you have diabetes, discuss magnesium use with your clinician.',
  'informational_note':
      'Magnesium and glucose control may be relevant for diabetes.',
  'condition_ids': <String>['diabetes'],
  'drug_class_ids': <String>[],
  'ingredient_name': 'Magnesium',
  'ingredient_canonical_id': 'magnesium',
  'evidence_level': 'probable',
  'sources': <String>[
    'https://ods.od.nih.gov/factsheets/Magnesium-HealthProfessional/',
  ],
  'dose_threshold_evaluation': null,
  'dose_decision': <String, dynamic>{
    'clinical_severity': 'caution',
    'evaluation_status': 'evaluated',
    'consumer_disposition': 'review',
  },
  'direction': 'harmful',
  'materiality': 'presence',
  'min_effective_dose': null,
  'dose_floor_status': null,
  'source': 'interaction_rules',
  'source_rule_id': 'RULE_TEST_MAGNESIUM_DIABETES',
  'profile_gate': _gate,
};

void main() {
  test('schema 3 compact ref rehydrates schema 2.4 warning exactly', () {
    const blob = <String, dynamic>{
      'warning_rule_refs': <Map<String, dynamic>>[
        <String, dynamic>{
          'rule_id': 'RULE_TEST_MAGNESIUM_DIABETES',
          'copy_fingerprint':
              '27d0bb0fd10e809a279f2b4763413856917e7e975dfec304282d506a12fc4529',
          'type': 'interaction',
          'severity': 'caution',
          'severity_contextual': 'informational',
          'display_mode_default': 'suppress',
          'condition_ids': <String>['diabetes'],
          'drug_class_ids': <String>[],
          'ingredient_name': 'Magnesium',
          'ingredient_canonical_id': 'magnesium',
          'dose_decision': <String, dynamic>{
            'clinical_severity': 'caution',
            'evaluation_status': 'evaluated',
            'consumer_disposition': 'review',
          },
          'direction': 'harmful',
          'materiality': 'presence',
          'min_effective_dose': null,
          'dose_floor_status': null,
          'profile_gate': _gate,
        },
      ],
    };

    final resolved = resolveWarningRuleRefs(
      blob,
      const <String, Map<String, dynamic>>{
        'RULE_TEST_MAGNESIUM_DIABETES': _rule,
      },
    );

    expect(resolved, <Map<String, dynamic>>[_fullWarning]);
  });

  test('missing local rule fails closed instead of deleting a warning', () {
    const blob = <String, dynamic>{
      'warning_rule_refs': <Map<String, dynamic>>[
        <String, dynamic>{'rule_id': 'RULE_MISSING'},
      ],
    };

    expect(
      () =>
          resolveWarningRuleRefs(blob, const <String, Map<String, dynamic>>{}),
      throwsFormatException,
    );
  });

  test(
    'copy fingerprint selects reviewed pregnancy aggregate and keeps provenance',
    () {
      const pregnancyRule = <String, dynamic>{
        'id': 'RULE_TEST_PREGNANCY',
        'condition_rules': <Map<String, dynamic>>[
          <String, dynamic>{
            'condition_id': 'pregnancy',
            'severity': 'caution',
            'evidence_level': 'established',
            'mechanism': 'Different explicit condition copy.',
            'action': 'Do not select this condition copy.',
            'sources': <String>['https://example.com/condition'],
            'alert_headline': 'Different condition headline',
            'alert_body': 'Different condition body.',
            'informational_note': null,
          },
        ],
        'drug_class_rules': <Map<String, dynamic>>[],
        'pregnancy_lactation': <String, dynamic>{
          'pregnancy_category': 'no_data',
          'lactation_category': 'no_data',
          'evidence_level': 'no_data',
          'notes': 'Discuss use during pregnancy with your clinician.',
          'alert_headline': 'Pregnancy guidance',
          'alert_body': 'Use the aggregate pregnancy guidance.',
          'informational_note': 'Pregnancy-specific guidance applies.',
          'sources': <String>['https://example.com/aggregate'],
        },
      };
      const blob = <String, dynamic>{
        'warning_rule_refs': <Map<String, dynamic>>[
          <String, dynamic>{
            'rule_id': 'RULE_TEST_PREGNANCY',
            'copy_fingerprint':
                '12fc8ac3b7294524903be10f3e5b89b0428b8a729d3ec7f72cee4be9d8d0d965',
            'type': 'interaction',
            'severity': 'no_data',
            'condition_ids': <String>['pregnancy'],
            'drug_class_ids': <String>[],
            'ingredient_name': 'Magnesium',
            'ingredient_canonical_id': 'magnesium',
            'evidence_level': 'reviewed_no_data',
            'sources': <String>['https://example.com/reviewed-warning'],
            'source_producers': <String>['pregnancy_lactation'],
          },
        ],
      };

      final resolved = resolveWarningRuleRefs(
        blob,
        const <String, Map<String, dynamic>>{
          'RULE_TEST_PREGNANCY': pregnancyRule,
        },
      ).single;

      expect(resolved['detail'], '');
      expect(
        resolved['action'],
        'Discuss use during pregnancy with your clinician.',
      );
      expect(resolved['alert_headline'], 'Pregnancy guidance');
      expect(resolved['evidence_level'], 'reviewed_no_data');
      expect(resolved['sources'], <String>[
        'https://example.com/reviewed-warning',
      ]);
      expect(resolved['source_producers'], <String>['pregnancy_lactation']);
    },
  );

  test('copy drift fails closed instead of silently changing warning text', () {
    const blob = <String, dynamic>{
      'warning_rule_refs': <Map<String, dynamic>>[
        <String, dynamic>{
          'rule_id': 'RULE_TEST_MAGNESIUM_DIABETES',
          'copy_fingerprint': 'reviewed-copy-no-longer-matches',
          'condition_ids': <String>['diabetes'],
          'drug_class_ids': <String>[],
        },
      ],
    };

    expect(
      () => resolveWarningRuleRefs(blob, const <String, Map<String, dynamic>>{
        'RULE_TEST_MAGNESIUM_DIABETES': _rule,
      }),
      throwsFormatException,
    );
  });
}
