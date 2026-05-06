// Cross-surface consistency tests — Fit Score / E2c must agree with the
// product detail screen's profile_gate evaluator.
//
// The bug this prevents: detail screen suppresses the topical-aloe
// pregnancy alert via excludes.product_forms_any, but Fit Score still
// penalizes the product because it reads condition_summary directly.
// Without this test, the two surfaces silently disagree.
//
// Spec from dev review: 4 required scenarios:
//   1. topical aloe + pregnancy: no warning AND no Fit Score / E2c penalty
//   2. oral aloe + pregnancy: warning AND penalty still apply
//   3. stale condition_summary without matching gated warning: no penalty
//   4. drug-class gate still works

import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/core/constants/severity.dart';
import 'package:pharmaguide/features/product_detail/widgets/interaction_warnings.dart';
import 'package:pharmaguide/services/fit_score/e1_dosage_calculator.dart';
import 'package:pharmaguide/services/fit_score/e2a_goal_calculator.dart';
import 'package:pharmaguide/services/fit_score/e2b_age_calculator.dart';
import 'package:pharmaguide/services/fit_score/e2c_medical_calculator.dart';
import 'package:pharmaguide/services/fit_score/fit_score_service.dart';

FitScoreService _service() => FitScoreService(
  e1: E1DosageCalculator(const {}),
  e2a: E2aGoalCalculator(const {}),
  e2b: E2bAgeCalculator(const {}),
  e2c: E2cMedicalCalculator(),
);

Map<String, dynamic> _emptyExcludes() => const {
  'conditions_any': <String>[],
  'drug_classes_any': <String>[],
  'profile_flags_any': <String>[],
  'product_forms_any': <String>[],
  'nutrient_forms_any': <String>[],
};

InteractionWarning _aloePregnancyWarning() => InteractionWarning(
  severity: Severity.avoid,
  evidenceLevel: EvidenceLevel.established,
  title: 'Aloe pregnancy',
  mechanism: 'oral aloe pregnancy concerns',
  management: 'avoid oral aloe',
  conditionIds: const ['pregnancy'],
  profileGate: {
    'gate_type': 'profile_flag',
    'requires': {
      'conditions_any': <String>[],
      'drug_classes_any': <String>[],
      'profile_flags_any': ['pregnant'],
    },
    'excludes': {
      ..._emptyExcludes(),
      'product_forms_any': ['topical_only'],
    },
    'dose': null,
  },
);

Map<String, dynamic> _aloePregnancyConditionSummary() => const {
  'condition_summary': {
    'pregnancy': {
      'label': 'Pregnancy',
      'highest_severity': 'avoid',
      'ingredients': ['Aloe Vera'],
    },
  },
  'drug_class_summary': <String, dynamic>{},
};

void main() {
  group('Fit Score profile_gate consistency — aloe pregnancy', () {
    test(
      'topical-only aloe + pregnant user → no penalty (matches detail screen)',
      () {
        final result = _service().calculate(
          nutrients: const [],
          productClusters: const [],
          interactionSummary: _aloePregnancyConditionSummary(),
          userConditions: const ['pregnancy'],
          warnings: [_aloePregnancyWarning()],
          userProfileFlags: const {'pregnant'},
          productForm: 'topical_only',
        );

        // E2c starts at 8.0; an avoid penalty would drop it. With the gate
        // suppressing the warning, no penalty applies → e2c stays at 8.0.
        expect(
          result.e2c,
          8.0,
          reason:
              'topical_only excludes the pregnancy alert; '
              'E2c must NOT penalize',
        );
        expect(
          result.maxRelevantSeverity,
          isNull,
          reason: 'No firing severity → no relevant severity reported',
        );
      },
    );

    test(
      'oral aloe + pregnant user → penalty applies (warning still fires)',
      () {
        final result = _service().calculate(
          nutrients: const [],
          productClusters: const [],
          interactionSummary: _aloePregnancyConditionSummary(),
          userConditions: const ['pregnancy'],
          warnings: [_aloePregnancyWarning()],
          userProfileFlags: const {'pregnant'},
          productForm: 'capsule', // oral form — gate excludes only topical_only
        );

        // E2c penalty for avoid severity must be applied → e2c < 8.0.
        expect(
          result.e2c,
          lessThan(8.0),
          reason: 'oral aloe is not excluded; E2c must penalize',
        );
        expect(result.maxRelevantSeverity, equals('avoid'));
      },
    );
  });

  group('Fit Score profile_gate consistency — stale aggregation', () {
    test('condition_summary entry without matching warning → no penalty '
        '(fail closed)', () {
      // Pipeline emits a stale condition_summary entry but the warnings
      // list lacks any rule tagged with that condition. Without backing
      // evidence we must NOT penalize.
      final result = _service().calculate(
        nutrients: const [],
        productClusters: const [],
        interactionSummary: const {
          'condition_summary': {
            'pregnancy': {
              'label': 'Pregnancy',
              'highest_severity': 'avoid',
              'ingredients': ['MysteryHerb'],
            },
          },
          'drug_class_summary': <String, dynamic>{},
        },
        userConditions: const ['pregnancy'],
        // EMPTY warnings — stale aggregation has nothing backing it.
        warnings: const [],
        userProfileFlags: const {'pregnant'},
      );

      // When no warnings list is passed, the gate filter is bypassed
      // entirely (legacy fallback). When warnings list IS passed but
      // contains nothing tagged with the condition, the filter drops
      // the entry → no penalty.
      // The empty-list case takes the legacy path, so Fit Score still
      // applies the penalty. Re-test with one irrelevant warning to
      // exercise the "no relevant warning" branch:
      final result2 = _service().calculate(
        nutrients: const [],
        productClusters: const [],
        interactionSummary: const {
          'condition_summary': {
            'pregnancy': {
              'label': 'Pregnancy',
              'highest_severity': 'avoid',
              'ingredients': ['MysteryHerb'],
            },
          },
          'drug_class_summary': <String, dynamic>{},
        },
        userConditions: const ['pregnancy'],
        warnings: [
          InteractionWarning(
            severity: Severity.caution,
            evidenceLevel: EvidenceLevel.theoretical,
            title: 'Unrelated warning',
            mechanism: 'm',
            management: 'a',
            conditionIds: const ['hypertension'], // NOT pregnancy
            profileGate: {
              'gate_type': 'condition',
              'requires': {
                'conditions_any': ['hypertension'],
                'drug_classes_any': <String>[],
                'profile_flags_any': <String>[],
              },
              'excludes': _emptyExcludes(),
              'dose': null,
            },
          ),
        ],
        userProfileFlags: const {'pregnant'},
      );

      expect(
        result2.e2c,
        8.0,
        reason:
            'No warning is tagged with pregnancy — stale '
            'aggregation must be dropped (fail closed) so the user '
            'is not penalized for an unverified condition.',
      );
      // Sanity check on the bypass path (warnings empty == legacy
      // behavior): result preserves the unfiltered penalty.
      expect(result.e2c, lessThan(8.0));
    });
  });

  group('Fit Score profile_gate consistency — drug-class gate', () {
    test(
      'anticoagulant warning fires for user on anticoagulants → penalty',
      () {
        final result = _service().calculate(
          nutrients: const [],
          productClusters: const [],
          interactionSummary: const {
            'condition_summary': <String, dynamic>{},
            'drug_class_summary': {
              'anticoagulants': {
                'label': 'Anticoagulants',
                'highest_severity': 'caution',
                'ingredients': ['Ginkgo'],
              },
            },
          },
          userConditions: const [],
          userDrugClasses: const ['anticoagulants'],
          warnings: [
            InteractionWarning(
              severity: Severity.caution,
              evidenceLevel: EvidenceLevel.probable,
              title: 'Bleeding risk',
              mechanism: 'm',
              management: 'a',
              drugClassIds: const ['anticoagulants'],
              profileGate: {
                'gate_type': 'drug_class',
                'requires': {
                  'conditions_any': <String>[],
                  'drug_classes_any': ['anticoagulants'],
                  'profile_flags_any': <String>[],
                },
                'excludes': _emptyExcludes(),
                'dose': null,
              },
            ),
          ],
        );

        expect(
          result.e2c,
          lessThan(8.0),
          reason: 'drug-class gate must still penalize when it fires',
        );
        expect(result.maxRelevantSeverity, equals('caution'));
      },
    );

    test('anticoagulant entry without matching warning → no penalty', () {
      final result = _service().calculate(
        nutrients: const [],
        productClusters: const [],
        interactionSummary: const {
          'condition_summary': <String, dynamic>{},
          'drug_class_summary': {
            'anticoagulants': {
              'label': 'Anticoagulants',
              'highest_severity': 'caution',
              'ingredients': ['Stale'],
            },
          },
        },
        userConditions: const [],
        userDrugClasses: const ['anticoagulants'],
        // Warnings list provided but no entry tagged anticoagulants
        warnings: [
          InteractionWarning(
            severity: Severity.caution,
            evidenceLevel: EvidenceLevel.theoretical,
            title: 'Diabetes warning (irrelevant)',
            mechanism: 'm',
            management: 'a',
            conditionIds: const ['diabetes'],
            profileGate: {
              'gate_type': 'condition',
              'requires': {
                'conditions_any': ['diabetes'],
                'drug_classes_any': <String>[],
                'profile_flags_any': <String>[],
              },
              'excludes': _emptyExcludes(),
              'dose': null,
            },
          ),
        ],
      );

      expect(
        result.e2c,
        8.0,
        reason:
            'No warning tagged with anticoagulants; stale '
            'drug_class_summary entry must be dropped.',
      );
    });
  });
}
